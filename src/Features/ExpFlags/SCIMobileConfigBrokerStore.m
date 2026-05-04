#import "SCIMobileConfigBrokerStore.h"

NSString * const SCIMCBrokerStoreDidChangeNotification = @"SCIMCBrokerStoreDidChangeNotification";

static NSString * const kMCBRIndexKey = @"mcbr.idx";
static NSString * const kMCBRHookPrefix = @"mcbr.hook:";
static NSString * const kMCBRHitPrefix = @"mcbr.hit:";
static NSString * const kMCBRForcedHitPrefix = @"mcbr.fhit:";

@implementation SCIMobileConfigBrokerStore

+ (void)registerDefaultsAndMigrate {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kMCBRIndexKey: @[]}];

    // Conservative migration from the initial long namespace, if it was ever used locally.
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray *idx = [[[NSUserDefaults standardUserDefaults] arrayForKey:kMCBRIndexKey] mutableCopy] ?: [NSMutableArray array];
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        NSString *longKey = [NSString stringWithFormat:@"dexkit.cbroker:%@:%@", d.imageName, d.symbol];
        id value = all[longKey];
        if ([value isKindOfClass:NSNumber.class]) {
            NSString *shortKey = [self overrideKeyForBrokerID:d.brokerID];
            [[NSUserDefaults standardUserDefaults] setBool:[value boolValue] forKey:shortKey];
            if (![idx containsObject:d.brokerID]) [idx addObject:d.brokerID];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:idx forKey:kMCBRIndexKey];
}

+ (NSString *)overrideKeyForBrokerID:(NSString *)brokerID { return [@"mcbr:" stringByAppendingString:brokerID ?: @""]; }
+ (NSString *)observedKeyForBrokerID:(NSString *)brokerID { return [@"mcob:" stringByAppendingString:brokerID ?: @""]; }
+ (NSString *)lastErrorKeyForBrokerID:(NSString *)brokerID { return [@"mcer:" stringByAppendingString:brokerID ?: @""]; }
+ (NSString *)hookEnabledKeyForBrokerID:(NSString *)brokerID { return [kMCBRHookPrefix stringByAppendingString:brokerID ?: @""]; }
+ (NSString *)hitKeyForBrokerID:(NSString *)brokerID { return [kMCBRHitPrefix stringByAppendingString:brokerID ?: @""]; }
+ (NSString *)forcedHitKeyForBrokerID:(NSString *)brokerID { return [kMCBRForcedHitPrefix stringByAppendingString:brokerID ?: @""]; }

+ (NSArray<NSString *> *)activeOverrideBrokerIDs {
    NSArray *idx = [[NSUserDefaults standardUserDefaults] arrayForKey:kMCBRIndexKey];
    NSMutableArray *out = [NSMutableArray array];
    for (id obj in idx ?: @[]) {
        if (![obj isKindOfClass:NSString.class]) continue;
        NSString *bid = obj;
        if ([self overrideValueForBrokerID:bid] != nil) [out addObject:bid];
    }
    return out;
}

+ (NSNumber *)overrideValueForBrokerID:(NSString *)brokerID {
    if (!brokerID.length) return nil;
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self overrideKeyForBrokerID:brokerID]];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

+ (void)setOverrideValue:(NSNumber *)value forBrokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableArray *idx = [[ud arrayForKey:kMCBRIndexKey] mutableCopy] ?: [NSMutableArray array];
    NSString *key = [self overrideKeyForBrokerID:brokerID];
    if (value) {
        [ud setBool:value.boolValue forKey:key];
        if (![idx containsObject:brokerID]) [idx addObject:brokerID];
    } else {
        [ud removeObjectForKey:key];
        [idx removeObject:brokerID];
    }
    [ud setObject:idx forKey:kMCBRIndexKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIMCBrokerStoreDidChangeNotification object:nil userInfo:@{@"brokerID": brokerID}];
}

+ (NSNumber *)observedValueForBrokerID:(NSString *)brokerID {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self observedKeyForBrokerID:brokerID]];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

+ (void)noteObservedValue:(BOOL)value brokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:[self observedKeyForBrokerID:brokerID]];
}

+ (void)noteLastError:(NSString *)error brokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    NSString *key = [self lastErrorKeyForBrokerID:brokerID];
    if (error.length) [[NSUserDefaults standardUserDefaults] setObject:error forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

+ (NSString *)lastErrorForBrokerID:(NSString *)brokerID {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self lastErrorKeyForBrokerID:brokerID]];
    return [v isKindOfClass:NSString.class] ? v : nil;
}

+ (BOOL)isBrokerHookEnabledForID:(NSString *)brokerID {
    return [[NSUserDefaults standardUserDefaults] boolForKey:[self hookEnabledKeyForBrokerID:brokerID]];
}

+ (void)setBrokerHookEnabled:(BOOL)enabled brokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:[self hookEnabledKeyForBrokerID:brokerID]];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIMCBrokerStoreDidChangeNotification object:nil userInfo:@{@"brokerID": brokerID}];
}

+ (SCIMCBrokerBoolState)effectiveStateForBrokerID:(NSString *)brokerID {
    NSNumber *forced = [self overrideValueForBrokerID:brokerID];
    if (forced) return forced.boolValue ? SCIMCBrokerBoolStateOn : SCIMCBrokerBoolStateOff;
    NSNumber *observed = [self observedValueForBrokerID:brokerID];
    if (observed) return observed.boolValue ? SCIMCBrokerBoolStateOn : SCIMCBrokerBoolStateOff;
    return SCIMCBrokerBoolStateSystem;
}

+ (NSString *)stateLabelForBrokerID:(NSString *)brokerID {
    SCIMCBrokerBoolState s = [self effectiveStateForBrokerID:brokerID];
    if (s == SCIMCBrokerBoolStateOn) return @"ON";
    if (s == SCIMCBrokerBoolStateOff) return @"OFF";
    return @"Unknown";
}

+ (NSString *)systemLabelForBrokerID:(NSString *)brokerID {
    NSNumber *observed = [self observedValueForBrokerID:brokerID];
    if (!observed) return @"Unknown";
    return observed.boolValue ? @"ON" : @"OFF";
}

+ (NSString *)overrideLabelForBrokerID:(NSString *)brokerID {
    NSNumber *forced = [self overrideValueForBrokerID:brokerID];
    if (!forced) return @"System";
    return forced.boolValue ? @"Forced ON" : @"Forced OFF";
}

+ (void)noteHitForBrokerID:(NSString *)brokerID forced:(BOOL)forced {
    if (!brokerID.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *hitKey = [self hitKeyForBrokerID:brokerID];
    [ud setInteger:([ud integerForKey:hitKey] + 1) forKey:hitKey];
    if (forced) {
        NSString *fKey = [self forcedHitKeyForBrokerID:brokerID];
        [ud setInteger:([ud integerForKey:fKey] + 1) forKey:fKey];
    }
}

+ (NSUInteger)hitCountForBrokerID:(NSString *)brokerID { return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:[self hitKeyForBrokerID:brokerID]]; }
+ (NSUInteger)forcedHitCountForBrokerID:(NSString *)brokerID { return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:[self forcedHitKeyForBrokerID:brokerID]]; }

+ (NSDictionary *)snapshotDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (SCIMobileConfigBrokerDescriptor *desc in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        d[desc.brokerID] = @{
            @"key": [self overrideKeyForBrokerID:desc.brokerID],
            @"symbol": desc.symbol ?: @"",
            @"override": [self overrideValueForBrokerID:desc.brokerID] ?: [NSNull null],
            @"observed": [self observedValueForBrokerID:desc.brokerID] ?: [NSNull null],
            @"hookEnabled": @([self isBrokerHookEnabledForID:desc.brokerID]),
            @"hits": @([self hitCountForBrokerID:desc.brokerID]),
            @"forcedHits": @([self forcedHitCountForBrokerID:desc.brokerID]),
            @"lastError": [self lastErrorForBrokerID:desc.brokerID] ?: @""
        };
    }
    return d;
}

+ (void)resetAllBrokerOverrides {
    NSArray *ids = [self activeOverrideBrokerIDs];
    for (NSString *bid in ids) [self setOverrideValue:nil forBrokerID:bid];
}

@end
