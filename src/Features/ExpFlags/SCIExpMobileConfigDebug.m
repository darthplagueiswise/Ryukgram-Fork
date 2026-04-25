#import "SCIExpMobileConfigDebug.h"
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
    [lines addObject:[SCIExpMobileConfigMapping mappingDebugDescription] ?: @"Mapping: unavailable"];
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
