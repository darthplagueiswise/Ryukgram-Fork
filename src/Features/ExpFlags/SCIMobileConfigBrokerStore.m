#import "SCIMobileConfigBrokerStore.h"
#import "SCIMobileConfigIDResolver.h"

NSString * const SCIMCBrokerStoreDidChangeNotification = @"SCIMCBrokerStoreDidChangeNotification";
NSString * const SCIMCBrokerIndexKey = @"mcbr.idx";
NSString * const SCIMCBrokerObservedIndexKey = @"mcob.idx";
NSString * const SCIMCBrokerHookIndexKey = @"mcbr.hooks";

static NSString * const kMCBROverridePrefix = @"mcbr:";
static NSString * const kMCBRObservedPrefix = @"mcob:";
static NSString * const kMCBRHookPrefix = @"mcbr.hook:";
static NSString * const kMCBRErrorPrefix = @"mcer:";
static NSString * const kMCBRHitPrefix = @"mcbr.hit:";
static NSString * const kMCBRForcedHitPrefix = @"mcbr.fhit:";

@implementation SCIMobileConfigBrokerStore

+ (void)registerDefaultsAndMigrate {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud registerDefaults:@{SCIMCBrokerIndexKey: @[], SCIMCBrokerObservedIndexKey: @[], SCIMCBrokerHookIndexKey: @[]}];

    // Conservative migration from the first long namespace and from early broker-wide mcbr:<id> values.
    NSDictionary *all = [ud dictionaryRepresentation];
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        NSString *longKey = [NSString stringWithFormat:@"dexkit.cbroker:%@:%@", d.imageName, d.symbol];
        id longValue = all[longKey];
        if ([longValue isKindOfClass:NSNumber.class]) {
            [ud setBool:[longValue boolValue] forKey:[self overrideKeyForBrokerID:d.brokerID value:0]];
            [self addIndexedKey:[self overrideKeyForBrokerID:d.brokerID value:0] indexKey:SCIMCBrokerIndexKey];
        }
        NSString *oldBrokerWide = [kMCBROverridePrefix stringByAppendingString:(d.brokerID ?: @"")];
        id oldValue = all[oldBrokerWide];
        if ([oldValue isKindOfClass:NSNumber.class]) {
            [ud setBool:[oldValue boolValue] forKey:[self overrideKeyForBrokerID:d.brokerID value:0]];
            [self addIndexedKey:[self overrideKeyForBrokerID:d.brokerID value:0] indexKey:SCIMCBrokerIndexKey];
            [ud removeObjectForKey:oldBrokerWide];
        }
    }
}

+ (NSArray *)arrayForKey:(NSString *)key {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:NSArray.class] ? obj : @[];
}

+ (void)addIndexedKey:(NSString *)item indexKey:(NSString *)indexKey {
    if (!item.length || !indexKey.length) return;
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:[self arrayForKey:indexKey]];
    [set addObject:item];
    [[NSUserDefaults standardUserDefaults] setObject:set.array forKey:indexKey];
}

+ (void)removeIndexedKey:(NSString *)item indexKey:(NSString *)indexKey {
    if (!item.length || !indexKey.length) return;
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:[self arrayForKey:indexKey]];
    [set removeObject:item];
    [[NSUserDefaults standardUserDefaults] setObject:set.array forKey:indexKey];
}

+ (NSString *)hexForValue:(uint64_t)value {
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)value];
}

+ (NSString *)overrideKeyForBroker:(SCIMobileConfigBrokerDescriptor *)broker value:(uint64_t)value {
    return [self overrideKeyForBrokerID:broker.brokerID value:value];
}

+ (NSString *)overrideKeyForBrokerID:(NSString *)brokerID value:(uint64_t)value {
    return [NSString stringWithFormat:@"%@%@:%@", kMCBROverridePrefix, brokerID ?: @"", [self hexForValue:value]];
}

+ (NSString *)observedKeyForOverrideKey:(NSString *)overrideKey {
    if (![overrideKey hasPrefix:kMCBROverridePrefix]) return @"";
    return [kMCBRObservedPrefix stringByAppendingString:[overrideKey substringFromIndex:kMCBROverridePrefix.length]];
}

+ (NSString *)hookEnabledKeyForBrokerID:(NSString *)brokerID { return [kMCBRHookPrefix stringByAppendingString:(brokerID ?: @"")]; }
+ (NSString *)lastErrorKeyForBrokerID:(NSString *)brokerID { return [kMCBRErrorPrefix stringByAppendingString:(brokerID ?: @"")]; }
+ (NSString *)hitKeyForBrokerID:(NSString *)brokerID { return [kMCBRHitPrefix stringByAppendingString:(brokerID ?: @"")]; }
+ (NSString *)forcedHitKeyForBrokerID:(NSString *)brokerID { return [kMCBRForcedHitPrefix stringByAppendingString:(brokerID ?: @"")]; }

+ (BOOL)parseOverrideKey:(NSString *)key brokerID:(NSString * _Nullable * _Nullable)brokerID value:(uint64_t * _Nullable)value {
    if (![key hasPrefix:kMCBROverridePrefix]) return NO;
    NSString *body = [key substringFromIndex:kMCBROverridePrefix.length];
    NSArray<NSString *> *parts = [body componentsSeparatedByString:@":"];
    if (parts.count < 2) return NO;
    NSString *bid = parts[0];
    NSString *hex = parts[1];
    unsigned long long parsed = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexLongLong:&parsed]) return NO;
    if (brokerID) *brokerID = bid;
    if (value) *value = (uint64_t)parsed;
    return YES;
}

+ (nullable NSNumber *)overrideValueForKey:(NSString *)key {
    if (!key.length) return nil;
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

+ (void)setOverrideValue:(nullable NSNumber *)value forKey:(NSString *)key {
    if (!key.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (value) {
        [ud setBool:value.boolValue forKey:key];
        [self addIndexedKey:key indexKey:SCIMCBrokerIndexKey];
    } else {
        [ud removeObjectForKey:key];
        [self removeIndexedKey:key indexKey:SCIMCBrokerIndexKey];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIMCBrokerStoreDidChangeNotification object:nil userInfo:@{@"key": key}];
}

+ (nullable NSNumber *)observedValueForOverrideKey:(NSString *)overrideKey {
    NSString *key = [self observedKeyForOverrideKey:overrideKey];
    if (!key.length) return nil;
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

+ (void)noteObservedValue:(BOOL)value forOverrideKey:(NSString *)overrideKey {
    NSString *key = [self observedKeyForOverrideKey:overrideKey];
    if (!key.length) return;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [self addIndexedKey:overrideKey indexKey:SCIMCBrokerObservedIndexKey];
}

+ (NSArray<NSString *> *)activeOverrideKeys {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id obj in [self arrayForKey:SCIMCBrokerIndexKey]) {
        if (![obj isKindOfClass:NSString.class]) continue;
        if ([self overrideValueForKey:obj]) [out addObject:obj];
    }
    return out;
}

+ (NSArray<NSString *> *)activeOverrideKeysForBrokerID:(NSString *)brokerID {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSString *prefix = [NSString stringWithFormat:@"%@%@:", kMCBROverridePrefix, brokerID ?: @""];
    for (NSString *key in [self activeOverrideKeys]) if ([key hasPrefix:prefix]) [out addObject:key];
    return out;
}

+ (NSArray<NSString *> *)observedOverrideKeys {
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSetWithArray:[self arrayForKey:SCIMCBrokerObservedIndexKey]];
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in all.allKeys) {
        if (![key hasPrefix:kMCBRObservedPrefix]) continue;
        NSString *overrideKey = [kMCBROverridePrefix stringByAppendingString:[key substringFromIndex:kMCBRObservedPrefix.length]];
        [set addObject:overrideKey];
    }
    return set.array;
}

+ (NSArray<NSString *> *)observedOverrideKeysForBrokerID:(NSString *)brokerID {
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    NSString *prefix = [NSString stringWithFormat:@"%@%@:", kMCBROverridePrefix, brokerID ?: @""];
    for (NSString *key in [self observedOverrideKeys]) if ([key hasPrefix:prefix]) [set addObject:key];
    for (NSString *key in [self activeOverrideKeysForBrokerID:brokerID]) [set addObject:key];
    return set.array;
}

+ (NSArray<NSString *> *)enabledHookBrokerIDs {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id obj in [self arrayForKey:SCIMCBrokerHookIndexKey]) if ([obj isKindOfClass:NSString.class]) [out addObject:obj];
    return out;
}

+ (BOOL)isBrokerHookEnabledForID:(NSString *)brokerID {
    if (!brokerID.length) return NO;
    return [[NSUserDefaults standardUserDefaults] boolForKey:[self hookEnabledKeyForBrokerID:brokerID]] || [[self enabledHookBrokerIDs] containsObject:brokerID];
}

+ (void)setBrokerHookEnabled:(BOOL)enabled brokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:enabled forKey:[self hookEnabledKeyForBrokerID:brokerID]];
    if (enabled) [self addIndexedKey:brokerID indexKey:SCIMCBrokerHookIndexKey];
    else [self removeIndexedKey:brokerID indexKey:SCIMCBrokerHookIndexKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIMCBrokerStoreDidChangeNotification object:nil userInfo:@{@"brokerID": brokerID}];
}

+ (BOOL)hasAnyActiveOverridesOrHooks {
    return [self activeOverrideKeys].count > 0 || [self enabledHookBrokerIDs].count > 0;
}

+ (BOOL)shouldInstallBrokerID:(NSString *)brokerID {
    return [self isBrokerHookEnabledForID:brokerID] || [self activeOverrideKeysForBrokerID:brokerID].count > 0;
}

+ (void)noteLastError:(nullable NSString *)error brokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    NSString *key = [self lastErrorKeyForBrokerID:brokerID];
    if (error.length) [[NSUserDefaults standardUserDefaults] setObject:error forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

+ (nullable NSString *)lastErrorForBrokerID:(NSString *)brokerID {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self lastErrorKeyForBrokerID:brokerID]];
    return [v isKindOfClass:NSString.class] ? v : nil;
}

+ (void)noteHitForBrokerID:(NSString *)brokerID value:(uint64_t)value forced:(BOOL)forced {
    if (!brokerID.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *hitKey = [self hitKeyForBrokerID:brokerID];
    [ud setInteger:([ud integerForKey:hitKey] + 1) forKey:hitKey];
    if (forced) {
        NSString *fKey = [self forcedHitKeyForBrokerID:brokerID];
        [ud setInteger:([ud integerForKey:fKey] + 1) forKey:fKey];
    }
    (void)value;
}

+ (NSUInteger)hitCountForBrokerID:(NSString *)brokerID { return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:[self hitKeyForBrokerID:brokerID]]; }
+ (NSUInteger)forcedHitCountForBrokerID:(NSString *)brokerID { return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:[self forcedHitKeyForBrokerID:brokerID]]; }

+ (SCIMCBrokerBoolState)effectiveStateForOverrideKey:(NSString *)overrideKey {
    NSNumber *forced = [self overrideValueForKey:overrideKey];
    if (forced) return forced.boolValue ? SCIMCBrokerBoolStateOn : SCIMCBrokerBoolStateOff;
    NSNumber *observed = [self observedValueForOverrideKey:overrideKey];
    if (observed) return observed.boolValue ? SCIMCBrokerBoolStateOn : SCIMCBrokerBoolStateOff;
    return SCIMCBrokerBoolStateSystem;
}

+ (NSString *)stateLabelForOverrideKey:(NSString *)overrideKey {
    SCIMCBrokerBoolState s = [self effectiveStateForOverrideKey:overrideKey];
    if (s == SCIMCBrokerBoolStateOn) return @"ON";
    if (s == SCIMCBrokerBoolStateOff) return @"OFF";
    return @"Unknown";
}

+ (NSString *)systemLabelForOverrideKey:(NSString *)overrideKey {
    NSNumber *observed = [self observedValueForOverrideKey:overrideKey];
    if (!observed) return @"Unknown";
    return observed.boolValue ? @"ON" : @"OFF";
}

+ (NSString *)overrideLabelForOverrideKey:(NSString *)overrideKey {
    NSNumber *forced = [self overrideValueForKey:overrideKey];
    if (!forced) return @"System";
    return forced.boolValue ? @"Forced ON" : @"Forced OFF";
}


+ (NSDictionary *)resolvedDictionaryForOverrideKey:(NSString *)overrideKey {
    NSString *bid = nil; uint64_t value = 0;
    if (![self parseOverrideKey:overrideKey brokerID:&bid value:&value]) return @{};
    return [SCIMobileConfigIDResolver resolvedDictionaryForBrokerID:bid value:value];
}

+ (NSDictionary *)snapshotDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (SCIMobileConfigBrokerDescriptor *desc in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *key in [self observedOverrideKeysForBrokerID:desc.brokerID]) {
            NSString *bid = nil; uint64_t value = 0;
            [self parseOverrideKey:key brokerID:&bid value:&value];
            NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{
                @"key": key ?: @"",
                @"value": [self hexForValue:value],
                @"override": [self overrideValueForKey:key] ?: [NSNull null],
                @"observed": [self observedValueForOverrideKey:key] ?: [NSNull null]
            }];
            NSDictionary *resolved = [SCIMobileConfigIDResolver resolvedDictionaryForBrokerID:(bid ?: desc.brokerID) value:value];
            if (resolved.count) [item addEntriesFromDictionary:resolved];
            [items addObject:item];
        }
        d[desc.brokerID] = @{
            @"symbol": desc.symbol ?: @"",
            @"hookEnabled": @([self isBrokerHookEnabledForID:desc.brokerID]),
            @"hits": @([self hitCountForBrokerID:desc.brokerID]),
            @"forcedHits": @([self forcedHitCountForBrokerID:desc.brokerID]),
            @"lastError": [self lastErrorForBrokerID:desc.brokerID] ?: @"",
            @"values": items
        };
    }
    return d;
}

+ (void)resetAllBrokerOverrides {
    for (NSString *key in [self activeOverrideKeys]) [self setOverrideValue:nil forKey:key];
}

#pragma mark - Compatibility broker-wide API

+ (NSString *)overrideKeyForBrokerID:(NSString *)brokerID { return [self overrideKeyForBrokerID:brokerID value:0]; }
+ (NSString *)observedKeyForBrokerID:(NSString *)brokerID { return [self observedKeyForOverrideKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (nullable NSNumber *)overrideValueForBrokerID:(NSString *)brokerID { return [self overrideValueForKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (void)setOverrideValue:(nullable NSNumber *)value forBrokerID:(NSString *)brokerID { [self setOverrideValue:value forKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (nullable NSNumber *)observedValueForBrokerID:(NSString *)brokerID { return [self observedValueForOverrideKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (void)noteObservedValue:(BOOL)value brokerID:(NSString *)brokerID { [self noteObservedValue:value forOverrideKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (SCIMCBrokerBoolState)effectiveStateForBrokerID:(NSString *)brokerID { return [self effectiveStateForOverrideKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (NSString *)stateLabelForBrokerID:(NSString *)brokerID { return [self stateLabelForOverrideKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (NSString *)systemLabelForBrokerID:(NSString *)brokerID { return [self systemLabelForOverrideKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (NSString *)overrideLabelForBrokerID:(NSString *)brokerID { return [self overrideLabelForOverrideKey:[self overrideKeyForBrokerID:brokerID value:0]]; }
+ (NSArray<NSString *> *)activeOverrideBrokerIDs {
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
    for (NSString *key in [self activeOverrideKeys]) {
        NSString *bid = nil;
        if ([self parseOverrideKey:key brokerID:&bid value:NULL] && bid.length) [set addObject:bid];
    }
    return set.array;
}
+ (void)noteHitForBrokerID:(NSString *)brokerID forced:(BOOL)forced { [self noteHitForBrokerID:brokerID value:0 forced:forced]; }

@end
