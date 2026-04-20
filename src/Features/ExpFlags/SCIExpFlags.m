#import "SCIExpFlags.h"

static NSString *const kOverridesKey = @"sci_exp_overrides_by_name";
static NSString *const kCrashCounterKey = @"sci_exp_flags_unstable_launches";
static const NSInteger kCrashThreshold = 3;

@implementation SCIExpObservation
@end

@implementation SCIExpMCObservation
@end

@implementation SCIExpFlags

static NSMutableDictionary<NSString *, SCIExpObservation *> *gMetaObs = nil;
static NSMutableDictionary<NSNumber *, SCIExpMCObservation *> *gMCObs = nil;

+ (NSMutableDictionary *)loadOverrides {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kOverridesKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)saveOverrides:(NSDictionary *)d {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (d.count == 0) {
        [ud removeObjectForKey:kOverridesKey];
    } else {
        [ud setObject:d forKey:kOverridesKey];
    }
}

+ (SCIExpFlagOverride)overrideForName:(NSString *)name {
    if (!name.length) return SCIExpFlagOverrideOff;
    NSNumber *n = [self loadOverrides][name];
    return n ? (SCIExpFlagOverride)n.integerValue : SCIExpFlagOverrideOff;
}

+ (void)setOverride:(SCIExpFlagOverride)o forName:(NSString *)name {
    if (!name.length) return;
    NSMutableDictionary *d = [self loadOverrides];
    if (o == SCIExpFlagOverrideOff) {
        [d removeObjectForKey:name];
    } else {
        d[name] = @(o);
    }
    [self saveOverrides:d];
}

+ (NSArray<NSString *> *)allOverriddenNames {
    return [[[self loadOverrides] allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

+ (void)resetAllOverrides {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kOverridesKey];
}

+ (void)recordExperimentName:(NSString *)name group:(NSString *)group {
    if (!name.length) return;
    if (!gMetaObs) gMetaObs = [NSMutableDictionary dictionary];
    SCIExpObservation *o = gMetaObs[name];
    if (!o) {
        o = [SCIExpObservation new];
        o.experimentName = name;
        gMetaObs[name] = o;
    }
    o.lastGroup = group;
    o.hitCount += 1;
}

+ (NSArray<SCIExpObservation *> *)allObservations {
    NSArray *values = gMetaObs ? [gMetaObs allValues] : @[];
    return [values sortedArrayUsingComparator:^NSComparisonResult(SCIExpObservation *a, SCIExpObservation *b) {
        return [a.experimentName caseInsensitiveCompare:b.experimentName];
    }];
}

+ (void)recordMCParamID:(unsigned long long)pid type:(SCIExpMCType)t defaultValue:(NSString *)def {
    if (!gMCObs) gMCObs = [NSMutableDictionary dictionary];
    NSNumber *key = @(pid);
    SCIExpMCObservation *o = gMCObs[key];
    if (!o) {
        o = [SCIExpMCObservation new];
        o.paramID = pid;
        o.type = t;
        gMCObs[key] = o;
    }
    o.lastDefault = def ?: @"";
    o.hitCount += 1;
}

+ (NSArray<SCIExpMCObservation *> *)allMCObservations {
    NSArray *values = gMCObs ? [gMCObs allValues] : @[];
    return [values sortedArrayUsingComparator:^NSComparisonResult(SCIExpMCObservation *a, SCIExpMCObservation *b) {
        if (a.hitCount != b.hitCount) return a.hitCount > b.hitCount ? NSOrderedAscending : NSOrderedDescending;
        if (a.paramID < b.paramID) return NSOrderedAscending;
        if (a.paramID > b.paramID) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

+ (void)scanExecutableNamesWithCompletion:(void (^)(NSArray<NSString *> *))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(@[]);
    });
}

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

@end
