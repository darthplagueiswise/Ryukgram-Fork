#import "SCIExpFlags.h"
#import "SCIExpMobileConfigMapping.h"
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <dlfcn.h>

static NSString *const kOverridesKey    = @"sci_exp_overrides_by_name";
static NSString *const kCrashCounterKey = @"sci_exp_flags_unstable_launches";
static const NSInteger kCrashThreshold  = 3;

@implementation SCIExpObservation
@end
@implementation SCIExpMCObservation
@end
@implementation SCIExpInternalUseObservation
@end

@implementation SCIExpFlags

#pragma mark - Overrides

+ (NSMutableDictionary *)loadOverrides {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kOverridesKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)saveOverrides:(NSDictionary *)d {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (d.count == 0) [ud removeObjectForKey:kOverridesKey];
    else [ud setObject:d forKey:kOverridesKey];
}

+ (SCIExpFlagOverride)overrideForName:(NSString *)name {
    if (!name.length) return SCIExpFlagOverrideOff;
    NSNumber *n = [self loadOverrides][name];
    return n ? (SCIExpFlagOverride)n.integerValue : SCIExpFlagOverrideOff;
}

+ (void)setOverride:(SCIExpFlagOverride)o forName:(NSString *)name {
    if (!name.length) return;
    NSMutableDictionary *d = [self loadOverrides];
    if (o == SCIExpFlagOverrideOff) [d removeObjectForKey:name];
    else d[name] = @(o);
    [self saveOverrides:d];
}

+ (NSArray<NSString *> *)allOverriddenNames {
    return [[self loadOverrides] allKeys];
}

+ (void)resetAllOverrides {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kOverridesKey];
}

#pragma mark - Meta observations

static NSMutableDictionary<NSString *, SCIExpObservation *> *gMetaObs = nil;
static dispatch_queue_t metaQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.expflags.meta", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

+ (void)recordExperimentName:(NSString *)name group:(NSString *)group {
    if (!name.length) return;
    dispatch_barrier_async(metaQueue(), ^{
        if (!gMetaObs) gMetaObs = [NSMutableDictionary dictionary];
        SCIExpObservation *o = gMetaObs[name];
        if (!o) { o = [SCIExpObservation new]; o.experimentName = name; gMetaObs[name] = o; }
        o.lastGroup = group;
        o.hitCount++;
    });
}

+ (NSArray<SCIExpObservation *> *)allObservations {
    __block NSArray *snap = @[];
    dispatch_sync(metaQueue(), ^{ snap = gMetaObs ? [gMetaObs.allValues copy] : @[]; });
    return [snap sortedArrayUsingComparator:^NSComparisonResult(SCIExpObservation *a, SCIExpObservation *b) {
        return [a.experimentName caseInsensitiveCompare:b.experimentName];
    }];
}

#pragma mark - MC observations

static NSMutableDictionary<NSNumber *, SCIExpMCObservation *> *gMCObs = nil;
static dispatch_queue_t mcQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.expflags.mc", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

+ (void)recordMCParamID:(unsigned long long)pid type:(SCIExpMCType)t defaultValue:(NSString *)def {
    [self recordMCParamID:pid
                    type:t
            defaultValue:def
           originalValue:nil
            contextClass:nil
            selectorName:nil];
}

+ (void)recordMCParamID:(unsigned long long)pid
                   type:(SCIExpMCType)t
           defaultValue:(NSString *)def
          originalValue:(NSString *)original
           contextClass:(NSString *)contextClass
           selectorName:(NSString *)selectorName {

    dispatch_barrier_async(mcQueue(), ^{
        if (!gMCObs) gMCObs = [NSMutableDictionary dictionary];

        NSNumber *k = @(pid);
        SCIExpMCObservation *o = gMCObs[k];

        if (!o) {
            o = [SCIExpMCObservation new];
            o.paramID = pid;
            o.type = t;

            NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:pid];
            if (mapped.length) {
                o.resolvedName = mapped;
            }

            NSString *source = [SCIExpMobileConfigMapping mappingSourceDescription];
            if (source.length) {
                o.source = source;
            }

            gMCObs[k] = o;
        }

        o.type = t;
        o.lastDefault = def ?: @"";
        o.lastOriginalValue = original ?: @"";
        o.contextClass = contextClass ?: o.contextClass ?: @"";
        o.selectorName = selectorName ?: o.selectorName ?: @"";
        o.hitCount++;
    });
}

+ (NSArray<SCIExpMCObservation *> *)allMCObservations {
    __block NSArray *snap = @[];
    dispatch_sync(mcQueue(), ^{ snap = gMCObs ? [gMCObs.allValues copy] : @[]; });
    return [snap sortedArrayUsingComparator:^NSComparisonResult(SCIExpMCObservation *a, SCIExpMCObservation *b) {
        if (a.hitCount != b.hitCount) return a.hitCount > b.hitCount ? NSOrderedAscending : NSOrderedDescending;
        if (a.paramID < b.paramID) return NSOrderedAscending;
        if (a.paramID > b.paramID) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

#pragma mark - InternalUse observations (lightweight mapping integration)

static NSMutableDictionary<NSString *, SCIExpInternalUseObservation *> *gInternalUseObs = nil;
static NSUInteger gInternalUseOrder = 0;
static dispatch_queue_t internalUseQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.expflags.internaluse", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

static NSString *SCIImageBasename(const char *path) {
    if (!path) return @"?";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"?";
}

static NSString *SCICallerDescription(void *callerAddress) {
    if (!callerAddress) return @"";
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr(callerAddress, &info) == 0) {
        return [NSString stringWithFormat:@"caller=%p", callerAddress];
    }
    NSString *image = SCIImageBasename(info.dli_fname);
    uintptr_t caller = (uintptr_t)callerAddress;
    uintptr_t base = (uintptr_t)info.dli_fbase;
    uintptr_t imageOffset = base ? (caller - base) : 0;

    if (info.dli_sname && info.dli_saddr) {
        NSString *symbol = [NSString stringWithUTF8String:info.dli_sname] ?: @"?";
        uintptr_t symbolOffset = caller - (uintptr_t)info.dli_saddr;
        return [NSString stringWithFormat:@"%@:%@+0x%lx image+0x%lx", image, symbol, (unsigned long)symbolOffset, (unsigned long)imageOffset];
    }
    return [NSString stringWithFormat:@"%@+0x%lx", image, (unsigned long)imageOffset];
}

static NSString *SCIResolvedSpecifierName(NSString *specifierName,
                                          unsigned long long specifier,
                                          NSString *functionName,
                                          void *callerAddress) {
    if (specifierName.length && ![specifierName isEqualToString:@"unknown"] && ![specifierName hasPrefix:@"spec_0x"]) {
        return specifierName;
    }

    NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:specifier];
    if (mapped.length) {
        return mapped;
    }

    NSString *caller = SCICallerDescription(callerAddress);
    if (caller.length) {
        return [NSString stringWithFormat:@"callsite %@ · 0x%016llx", caller, specifier];
    }

    return [NSString stringWithFormat:@"unknown 0x%016llx", specifier];
}

+ (void)recordInternalUseSpecifier:(unsigned long long)specifier
                      functionName:(NSString *)functionName
                     specifierName:(NSString *)specifierName
                      defaultValue:(BOOL)defaultValue
                       resultValue:(BOOL)resultValue
                       forcedValue:(BOOL)forcedValue
                     callerAddress:(void *)callerAddress {

    if (!functionName.length) functionName = @"InternalUse";
    NSString *key = [NSString stringWithFormat:@"%@:%016llx", functionName, specifier];
    NSString *caller = SCICallerDescription(callerAddress);
    NSString *resolvedName = SCIResolvedSpecifierName(specifierName, specifier, functionName, callerAddress);

    dispatch_barrier_async(internalUseQueue(), ^{
        if (!gInternalUseObs) gInternalUseObs = [NSMutableDictionary dictionary];
        SCIExpInternalUseObservation *o = gInternalUseObs[key];
        if (!o) {
            o = [SCIExpInternalUseObservation new];
            o.functionName = functionName;
            o.specifier = specifier;
            gInternalUseObs[key] = o;
        }
        o.specifierName = resolvedName.length ? resolvedName : @"unknown";
        o.callerDescription = caller;
        o.defaultValue = defaultValue;
        o.resultValue = resultValue;
        o.forcedValue = forcedValue;
        o.lastSeenOrder = ++gInternalUseOrder;
        o.hitCount++;
    });
}

+ (NSArray<SCIExpInternalUseObservation *> *)allInternalUseObservations {
    __block NSArray *snap = @[];
    dispatch_sync(internalUseQueue(), ^{ snap = gInternalUseObs ? [gInternalUseObs.allValues copy] : @[]; });
    return [snap sortedArrayUsingComparator:^NSComparisonResult(SCIExpInternalUseObservation *a, SCIExpInternalUseObservation *b) {
        if (a.hitCount != b.hitCount) return a.hitCount > b.hitCount ? NSOrderedAscending : NSOrderedDescending;
        if (a.specifier < b.specifier) return NSOrderedAscending;
        if (a.specifier > b.specifier) return NSOrderedDescending;
        return [a.functionName compare:b.functionName];
    }];
}

+ (NSArray<NSString *> *)allInternalUseObservationLines {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (SCIExpInternalUseObservation *o in [self allInternalUseObservations]) {
        NSString *forced = o.forcedValue ? @" forced=YES" : @"";
        NSString *name = o.specifierName.length ? o.specifierName : @"unknown";
        NSString *changed = o.defaultValue != o.resultValue ? @" changed" : @"";
        [lines addObject:[NSString stringWithFormat:@"[InternalUse] %@ %@ spec=0x%016llx default=%d result=%d%@%@ ×%lu",
                          o.functionName ?: @"InternalUse", name, o.specifier,
                          o.defaultValue, o.resultValue, changed, forced, (unsigned long)o.hitCount]];
    }
    return lines;
}

#pragma mark - Crash loop guard

+ (BOOL)checkAndHandleCrashLoop {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger c = [ud integerForKey:kCrashCounterKey] + 1;
    if (c >= kCrashThreshold && [self loadOverrides].count > 0) {
        [self resetAllOverrides];
        [ud removeObjectForKey:kCrashCounterKey];
        return YES;
    }
    [ud setInteger:c forKey:kCrashCounterKey];
    return NO;
}

+ (void)markLaunchStable {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCrashCounterKey];
}

#pragma mark - Binary scan helper

+ (void)scanExecutableNamesWithCompletion:(void (^)(NSArray<NSString *> *names))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *names = [self scanExecutable];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(names ?: @[]); });
    });
}

+ (NSArray<NSString *> *)scanExecutable {
    NSMutableSet *seen = [NSMutableSet set];
    NSString *path = [[NSBundle mainBundle] executablePath];
    if (!path) return @[];

    int fd = open(path.UTF8String, O_RDONLY);
    if (fd < 0) return @[];
    struct stat st;
    if (fstat(fd, &st) != 0) { close(fd); return @[]; }

    void *map = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (map == MAP_FAILED) { close(fd); return @[]; }

    const char *p = (const char *)map;
    for (size_t i = 0; i + 8 < (size_t)st.st_size; i++) {
        if (p[i] == 'i' && p[i+1] == 'g' && p[i+2] == '_') {
            NSUInteger len = 0;
            while (i + len < (size_t)st.st_size && len < 80) {
                unsigned char c = (unsigned char)p[i + len];
                if (c == 0 || c < 0x20 || c > 0x7e) break;
                len++;
            }
            if (len >= 6) {
                NSString *s = [[NSString alloc] initWithBytes:p + i length:len encoding:NSASCIIStringEncoding];
                if (s) [seen addObject:s];
            }
        }
    }
    munmap(map, st.st_size);
    close(fd);

    return [[seen allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

@end
