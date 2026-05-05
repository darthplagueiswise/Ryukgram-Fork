#import "SCIExpMobileConfigDebug.h"
#import "SCIExpFlags.h"
#import "SCIExpMobileConfigMapping.h"
#import <objc/runtime.h>
#import <objc/message.h>

static __weak id gSCILastMCContext = nil;
static NSString *gSCILastMCContextSource = nil;
static NSUInteger gSCIContextHitCount = 0;

static dispatch_queue_t SCIExpMCDebugQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("sci.expflags.mc.debug", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSString *SCISafeDescribeObject(id obj) {
    if (!obj) return @"nil";
    @try {
        NSString *cls = NSStringFromClass([obj class]);
        if ([obj isKindOfClass:[NSString class]]) {
            NSString *s = (NSString *)obj;
            NSString *preview = s.length > 240 ? [[s substringToIndex:240] stringByAppendingString:@"…"] : s;
            return [NSString stringWithFormat:@"%@ len=%lu %@", cls, (unsigned long)s.length, preview];
        }
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)obj;
            NSArray *keys = d.allKeys;
            NSArray *first = keys.count > 8 ? [keys subarrayWithRange:NSMakeRange(0, 8)] : keys;
            return [NSString stringWithFormat:@"%@ count=%lu keys=%@", cls, (unsigned long)d.count, first];
        }
        if ([obj isKindOfClass:[NSArray class]]) {
            NSArray *a = (NSArray *)obj;
            return [NSString stringWithFormat:@"%@ count=%lu first=%@", cls, (unsigned long)a.count, a.firstObject];
        }
        return [NSString stringWithFormat:@"%@ %@", cls, obj];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"<describe exception %@>", e.name ?: @"?"];
    }
}

static NSString *SCITypeEncodingForMethod(Method m) {
    const char *t = method_getTypeEncoding(m);
    return t ? [NSString stringWithUTF8String:t] : @"";
}

static BOOL SCIMethodLooksNoArgObject(Method m) {
    NSString *t = SCITypeEncodingForMethod(m);
    return [t hasPrefix:@"@16@0:8"] || [t hasPrefix:@"@16@0:8\""];
}

static NSArray<NSString *> *SCIDumpMethodsForClass(Class cls, BOOL meta) {
    if (!cls) return @[];
    Class target = meta ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"%@ %@ methods=%u", meta ? @"+" : @"-", NSStringFromClass(cls), count]];
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        IMP imp = method_getImplementation(methods[i]);
        NSString *name = sel ? NSStringFromSelector(sel) : @"?";
        NSString *types = SCITypeEncodingForMethod(methods[i]);
        [lines addObject:[NSString stringWithFormat:@"  %@ %@ imp=%p types=%@", meta ? @"+" : @"-", name, imp, types]];
    }
    if (methods) free(methods);
    return lines;
}

static id SCICallNoArgObject(id target, SEL sel) {
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
    id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return send(target, sel);
}

static NSArray<NSString *> *SCIProbeNoArgObjectMethodsForClass(Class cls) {
    if (!cls) return @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    id instance = nil;
    unsigned int classCount = 0;
    Method *classMethods = class_copyMethodList(object_getClass(cls), &classCount);
    for (unsigned int i = 0; i < classCount; i++) {
        Method m = classMethods[i];
        SEL sel = method_getName(m);
        NSString *name = sel ? NSStringFromSelector(sel) : @"?";
        NSString *types = SCITypeEncodingForMethod(m);
        if (!SCIMethodLooksNoArgObject(m)) continue;
        @try {
            id result = SCICallNoArgObject(cls, sel);
            [lines addObject:[NSString stringWithFormat:@"CALL +[%@ %@] -> %@", NSStringFromClass(cls), name, SCISafeDescribeObject(result)]];
            if (!instance && result && [result isKindOfClass:cls]) instance = result;
        } @catch (NSException *e) {
            [lines addObject:[NSString stringWithFormat:@"CALL +[%@ %@] EXCEPTION %@ %@ types=%@", NSStringFromClass(cls), name, e.name ?: @"?", e.reason ?: @"", types]];
        }
    }
    if (classMethods) free(classMethods);

    if (!instance) {
        @try { instance = [[cls alloc] init]; } @catch (__unused NSException *e) {}
        if (instance) [lines addObject:[NSString stringWithFormat:@"ALLOC %@ -> %@", NSStringFromClass(cls), SCISafeDescribeObject(instance)]];
    }

    if (instance) {
        unsigned int instCount = 0;
        Method *instMethods = class_copyMethodList(cls, &instCount);
        for (unsigned int i = 0; i < instCount; i++) {
            Method m = instMethods[i];
            SEL sel = method_getName(m);
            NSString *name = sel ? NSStringFromSelector(sel) : @"?";
            NSString *types = SCITypeEncodingForMethod(m);
            if (!SCIMethodLooksNoArgObject(m)) continue;
            @try {
                id result = SCICallNoArgObject(instance, sel);
                [lines addObject:[NSString stringWithFormat:@"CALL -[%@ %@] -> %@", NSStringFromClass(cls), name, SCISafeDescribeObject(result)]];
            } @catch (NSException *e) {
                [lines addObject:[NSString stringWithFormat:@"CALL -[%@ %@] EXCEPTION %@ %@ types=%@", NSStringFromClass(cls), name, e.name ?: @"?", e.reason ?: @"", types]];
            }
        }
        if (instMethods) free(instMethods);
    }

    return lines;
}

static BOOL SCINameLooksResolved(NSString *name) {
    if (!name.length) return NO;
    if ([name isEqualToString:@"unknown"]) return NO;
    if ([name hasPrefix:@"callsite "]) return NO;
    return YES;
}

static NSArray<NSString *> *SCIRuntimeResolvedObservationLines(void) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSArray<SCIExpInternalUseObservation *> *observations = [SCIExpFlags allInternalUseObservations];
    NSUInteger resolved = 0;
    NSUInteger callsites = 0;
    NSUInteger unknown = 0;

    for (SCIExpInternalUseObservation *o in observations) {
        if (SCINameLooksResolved(o.specifierName)) resolved++;
        else if ([o.specifierName hasPrefix:@"callsite "]) callsites++;
        else unknown++;
    }

    [lines addObject:[NSString stringWithFormat:@"Runtime observed InternalUse rows: total=%lu resolved=%lu callsite=%lu unknown=%lu",
                      (unsigned long)observations.count,
                      (unsigned long)resolved,
                      (unsigned long)callsites,
                      (unsigned long)unknown]];

    NSUInteger emitted = 0;
    for (SCIExpInternalUseObservation *o in observations) {
        if (!SCINameLooksResolved(o.specifierName)) continue;
        [lines addObject:[NSString stringWithFormat:@"  0x%016llx %@ · %@ · default=%d result=%d hits=%lu recent=%lu",
                          o.specifier,
                          o.specifierName ?: @"?",
                          o.functionName ?: @"InternalUse",
                          o.defaultValue,
                          o.resultValue,
                          (unsigned long)o.hitCount,
                          (unsigned long)o.lastSeenOrder]];
        if (++emitted >= 16) break;
    }
    if (!emitted) [lines addObject:@"  no resolved runtime names yet"];
    return lines;
}

static NSArray<NSString *> *SCIImportantMappingSummaryLines(void) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"Mapping/runtime summary: %@", [SCIExpMobileConfigMapping mappingSourceDescription] ?: @"none"]];

    NSArray<NSString *> *found = [SCIExpMobileConfigMapping foundMappingPaths];
    if (found.count) {
        [lines addObject:@"JSON candidates found (not necessarily MobileConfig ID maps):"];
        NSUInteger limit = MIN((NSUInteger)8, found.count);
        for (NSUInteger i = 0; i < limit; i++) [lines addObject:[NSString stringWithFormat:@"  + %@", found[i]]];
        if (found.count > limit) [lines addObject:[NSString stringWithFormat:@"  ... %lu more", (unsigned long)(found.count - limit)]];
    } else {
        [lines addObject:@"JSON candidates found: none"];
    }

    [lines addObject:@"Known employee anchors through convertSpecifierToParamName:"];
    NSDictionary<NSNumber *, NSString *> *employeeSamples = @{
        @(0x008100b200000161ULL): @"ig_is_employee_or_test_user",
        @(0x0081030f00000a95ULL): @"ig_is_employee[0]",
        @(0x0081030f00010a96ULL): @"ig_is_employee[1]"
    };
    for (NSNumber *n in [[employeeSamples allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *resolved = [SCIExpMobileConfigMapping resolvedNameForSpecifier:n.unsignedLongLongValue];
        [lines addObject:[NSString stringWithFormat:@"  0x%016llx %@ -> %@", n.unsignedLongLongValue, employeeSamples[n], resolved.length ? resolved : @"nil"]];
    }

    return lines;
}

@implementation SCIExpMobileConfigDebug

+ (void)noteContext:(id)context source:(NSString *)source {
    if (!context) return;
    dispatch_async(SCIExpMCDebugQueue(), ^{
        gSCILastMCContext = context;
        gSCILastMCContextSource = [source copy] ?: @"unknown";
        gSCIContextHitCount++;
    });
}

+ (NSString *)debugState {
    __block id ctx = nil;
    __block NSString *src = nil;
    __block NSUInteger hits = 0;
    dispatch_sync(SCIExpMCDebugQueue(), ^{
        ctx = gSCILastMCContext;
        src = gSCILastMCContextSource;
        hits = gSCIContextHitCount;
    });
    return [NSString stringWithFormat:@"context=%@ source=%@ hits=%lu",
            ctx ? NSStringFromClass([ctx class]) : @"nil",
            src ?: @"nil",
            (unsigned long)hits];
}

+ (NSString *)runDebugDumps {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"MobileConfig debug context tracker is active. %@", [self debugState]]];
    [lines addObject:@""];
    [lines addObjectsFromArray:SCIImportantMappingSummaryLines()];
    [lines addObject:@""];
    [lines addObjectsFromArray:SCIRuntimeResolvedObservationLines()];
    [lines addObject:@""];

    NSArray<NSString *> *classes = @[
        @"FBMobileConfigStartupConfigs",
        @"FBMobileConfigStartupConfigsDeprecated",
        @"FBMobileConfigParameterDescription",
        @"FBMobileConfigContextManager",
        @"IGMobileConfigContextManager",
        @"FBMobileConfigsSessionlessContextManager",
        @"IGMobileConfigSessionlessContextManager"
    ];

    for (NSString *className in classes) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            [lines addObject:[NSString stringWithFormat:@"CLASS %@ missing", className]];
            continue;
        }
        [lines addObjectsFromArray:SCIDumpMethodsForClass(cls, YES)];
        [lines addObjectsFromArray:SCIDumpMethodsForClass(cls, NO)];
        if ([className containsString:@"StartupConfigs"]) {
            [lines addObjectsFromArray:SCIProbeNoArgObjectMethodsForClass(cls)];
        }
    }

    NSString *message = [lines componentsJoinedByString:@"\n"];
    NSLog(@"[RyukGram][MCDebug]\n%@", message);
    return message;
}

@end
