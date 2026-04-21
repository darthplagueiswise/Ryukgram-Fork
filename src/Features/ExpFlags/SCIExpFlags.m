#import "SCIExpFlags.h"

static NSString *const kOverridesKey = @"sci_exp_overrides_by_name";
static NSString *const kMCOverridesKey = @"sci_exp_overrides_by_pid";
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

+ (NSMutableDictionary *)loadMCOverrides {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kMCOverridesKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)saveMCOverrides:(NSDictionary *)d {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (d.count == 0) {
        [ud removeObjectForKey:kMCOverridesKey];
    } else {
        [ud setObject:d forKey:kMCOverridesKey];
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

+ (nullable id)mcOverrideObjectForParamID:(unsigned long long)pid type:(SCIExpMCType)type {
    NSDictionary *entry = [self loadMCOverrides][@(pid).stringValue];
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;
    NSNumber *storedType = entry[@"type"];
    id value = entry[@"value"];
    if (![storedType isKindOfClass:[NSNumber class]]) return nil;
    if (storedType.integerValue != type) return nil;
    if (!value || value == [NSNull null]) return nil;
    return value;
}

+ (void)setMCOverrideObject:(nullable id)obj forParamID:(unsigned long long)pid type:(SCIExpMCType)type {
    NSMutableDictionary *d = [self loadMCOverrides];
    NSString *key = @(pid).stringValue;
    if (!obj) {
        [d removeObjectForKey:key];
    } else {
        d[key] = @{@"type": @(type), @"value": obj};
    }
    [self saveMCOverrides:d];
}

+ (NSArray<NSNumber *> *)allOverriddenMCParamIDs {
    NSArray<NSString *> *keys = [[self loadMCOverrides] allKeys];
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *k in keys) {
        unsigned long long v = strtoull(k.UTF8String, NULL, 10);
        [out addObject:@(v)];
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

+ (void)resetAllMCOverrides {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kMCOverridesKey];
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
    if (c >= kCrashThreshold && ([self loadOverrides].count > 0 || [self loadMCOverrides].count > 0)) {
        [self resetAllOverrides];
        [self resetAllMCOverrides];
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
