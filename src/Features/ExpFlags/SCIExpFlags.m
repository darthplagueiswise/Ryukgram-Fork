#import "SCIExpFlags.h"
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

// overrides

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

+ (NSArray<NSString *> *)allOverriddenNames { return [[self loadOverrides] allKeys]; }
+ (void)resetAllOverrides { [[NSUserDefaults standardUserDefaults] removeObjectForKey:kOverridesKey]; }

// meta observations

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

// MC observations (view-only)

static NSMutableDictionary<NSNumber *, SCIExpMCObservation *> *gMCObs = nil;
static dispatch_queue_t mcQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.expflags.mc", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

+ (void)recordMCParamID:(unsigned long long)pid type:(SCIExpMCType)t defaultValue:(NSString *)def {
    dispatch_barrier_async(mcQueue(), ^{
        if (!gMCObs) gMCObs = [NSMutableDictionary dictionary];
        NSNumber *k = @(pid);
        SCIExpMCObservation *o = gMCObs[k];
        if (!o) { o = [SCIExpMCObservation new]; o.paramID = pid; o.type = t; gMCObs[k] = o; }
        o.lastDefault = def ?: @"";
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

// InternalUse observations (live, view-only)

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

static NSString *SCIResolvedSpecifierName(NSString *specifierName, void *callerAddress) {
    if (specifierName.length && ![specifierName isEqualToString:@"unknown"]) return specifierName;
    NSString *caller = SCICallerDescription(callerAddress);
    if (caller.length) return [@"callsite " stringByAppendingString:caller];
    return @"unknown";
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
    NSString *resolvedName = SCIResolvedSpecifierName(specifierName, callerAddress);

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
                          o.functionName ?: @"InternalUse",
                          name,
                          o.specifier,
                          o.defaultValue,
                          o.resultValue,
                          changed,
                          forced,
                          (unsigned long)o.hitCount]];
    }
    return lines;
}

// crash-loop guard

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

+ (void)markLaunchStable { [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCrashCounterKey]; }

// binary scan — mmap executable, grep for flag-prefix strings, dedupe/sort

+ (void)scanExecutableNamesWithCompletion:(void (^)(NSArray<NSString *> *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *names = [self scanExecutable];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(names ?: @[]); });
    });
}

+ (NSArray<NSString *> *)scanExecutable {
    NSMutableSet *seen = [NSMutableSet set];
    NSString *path = [[NSBundle mainBundle] executablePath];
    if (path) {
        int fd = open(path.UTF8String, O_RDONLY);
        if (fd >= 0) {
            struct stat st;
            if (fstat(fd, &st) == 0 && st.st_size > 0) {
                size_t size = (size_t)st.st_size;
                const char *base = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
                if (base != MAP_FAILED) {
                    static const char *prefixes[] = {
                        "ig_ios_", "ig_android_", "ig_direct_", "ig_feed_", "ig_reels_",
                        "ig_stories_", "ig_explore_", "ig_camera_", "ig_growth_", "ig_privacy_",
                        "fbios_", "fb_ios_"
                    };
                    const size_t pc = sizeof(prefixes) / sizeof(prefixes[0]);
                    for (size_t i = 0; i < size; i++) {
                        char c = base[i];
                        if (c != 'i' && c != 'f') continue;
                        if (i > 0) {
                            char prev = base[i - 1];
                            if ((prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9') || prev == '_' || prev == '.') continue;
                        }
                        size_t matched = 0;
                        const char *rem = base + i;
                        size_t left = size - i;
                        for (size_t p = 0; p < pc; p++) {
                            size_t L = strlen(prefixes[p]);
                            if (left >= L && memcmp(rem, prefixes[p], L) == 0) { matched = L; break; }
                        }
                        if (!matched) continue;
                        size_t j = i + matched;
                        while (j < size) {
                            char ch = base[j];
                            if (!((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '.')) break;
                            j++;
                        }
                        size_t nl = j - i;
                        if (nl >= 16 && nl <= 160) {
                            NSString *s = [[NSString alloc] initWithBytes:(base + i) length:nl encoding:NSASCIIStringEncoding];
                            if (s) [seen addObject:s];
                        }
                        i = j;
                    }
                    munmap((void *)base, size);
                }
            }
            close(fd);
        }
    }

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSArray<NSString *> *internal = [self allInternalUseObservationLines];
    if (internal.count) [out addObjectsFromArray:internal];
    NSArray<NSString *> *scanned = [[seen allObjects] sortedArrayUsingSelector:@selector(compare:)];
    if (scanned.count) [out addObjectsFromArray:scanned];
    return out;
}

@end
