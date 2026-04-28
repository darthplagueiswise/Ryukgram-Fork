#import "SCIExpFlags.h"
#import "SCIMachODexKitResolver.h"
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

// Internal
