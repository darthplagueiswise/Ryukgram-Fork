#import "SCIMobileConfigBrokerStore.h"
#import "SCIDexKitNameResolver.h"

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

static NSString *SCIMCBrokerString(id obj) { return [obj isKindOfClass:NSString.class] ? (NSString *)obj : @""; }
static BOOL SCIMCBrokerBool(id obj) { return [obj respondsToSelector:@selector(boolValue)] ? [obj boolValue] : NO; }

@implementation SCIMobileConfigBrokerStore

+ (void)registerDefaultsAndMigrate {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud registerDefaults:@{SCIMCBrokerIndexKey: @[], SCIMCBrokerObservedIndexKey: @[], SCIMCBrokerHookIndexKey: @[]}];

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
+ (NSString *)hexForValue:(uint64_t)value { return [NSString stringWithFormat:@"%016llx", (unsigned long long)value]; }
+ (NSString *)overrideKeyForBroker:(SCIMobileConfigBrokerDescriptor *)broker value:(uint64_t)value { return [self overrideKeyForBrokerID:broker.brokerID value:value]; }
+ (NSString *)overrideKeyForBrokerID:(NSString *)brokerID value:(uint64_t)value { return [NSString stringWithFormat:@"%@%@:%@", kMCBROverridePrefix, brokerID ?: @"", [self hexForValue:value]]; }
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
    if (value) { [ud setBool:value.boolValue forKey:key]; [self addIndexedKey:key indexKey:SCIMCBrokerIndexKey]; }
    else { [ud removeObjectForKey:key]; [self removeIndexedKey:key indexKey:SCIMCBrokerIndexKey]; }
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

    NSArray<NSString *> *keys = set.array;
    return [keys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDictionary *ma = [self resolvedMetadataForOverrideKey:a];
        NSDictionary *mb = [self resolvedMetadataForOverrideKey:b];
        BOOL aRuntime = SCIMCBrokerBool(ma[@"runtimeObserved"]);
        BOOL bRuntime = SCIMCBrokerBool(mb[@"runtimeObserved"]);
        if (aRuntime != bRuntime) return aRuntime ? NSOrderedAscending : NSOrderedDescending;
        BOOL aResolved = SCIMCBrokerBool(ma[@"resolved"]);
        BOOL bResolved = SCIMCBrokerBool(mb[@"resolved"]);
        if (aResolved != bResolved) return aResolved ? NSOrderedAscending : NSOrderedDescending;
        BOOL aObserved = [self observedValueForOverrideKey:a] != nil;
        BOOL bObserved = [self observedValueForOverrideKey:b] != nil;
        if (aObserved != bObserved) return aObserved ? NSOrderedAscending : NSOrderedDescending;
        NSString *ta = SCIMCBrokerString(ma[@"title"]);
        NSString *tb = SCIMCBrokerString(mb[@"title"]);
        return [ta compare:tb options:NSCaseInsensitiveSearch];
    }];
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
+ (BOOL)hasAnyActiveOverridesOrHooks { return [self activeOverrideKeys].count > 0 || [self enabledHookBrokerIDs].count > 0; }
+ (BOOL)shouldInstallBrokerID:(NSString *)brokerID { return [self isBrokerHookEnabledForID:brokerID] || [self activeOverrideKeysForBrokerID:brokerID].count > 0; }
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

+ (NSDictionary *)resolvedMetadataForOverrideKey:(NSString *)overrideKey {
    NSString *bid = nil;
    uint64_t value = 0;
    if (![self parseOverrideKey:overrideKey brokerID:&bid value:&value]) return @{};

    SCIDexKitResolvedName *resolved = [SCIDexKitNameResolver resolveBrokerID:bid value:value];
    NSDictionary *base = [resolved dictionaryRepresentation] ?: @{};

    NSString *name = SCIMCBrokerString(base[@"name"]);
    NSString *title = SCIMCBrokerString(base[@"title"]);
    NSString *detail = SCIMCBrokerString(base[@"detail"]);
    NSString *source = SCIMCBrokerString(base[@"source"]);
    NSString *normalized = SCIMCBrokerString(base[@"normalizedKey"]);
    NSString *family = SCIMCBrokerString(base[@"family"]);
    NSString *param = SCIMCBrokerString(base[@"param"]);
    NSString *tag = SCIMCBrokerString(base[@"tag"]);
    NSString *callerImage = SCIMCBrokerString(base[@"callerImage"]);
    NSString *callerSymbol = SCIMCBrokerString(base[@"callerSymbol"]);
    NSString *callerAddress = SCIMCBrokerString(base[@"callerAddress"]);

    NSNumber *observedValue = [self observedValueForOverrideKey:overrideKey];
    BOOL runtimeObserved = SCIMCBrokerBool(base[@"runtimeObserved"]) || observedValue != nil || [SCIDexKitNameResolver sourceRepresentsRuntimeObservation:source];
    BOOL exactName = name.length > 0 && [SCIDexKitNameResolver sourceRepresentsExactName:source];

    uint64_t normalizedValue = [SCIDexKitNameResolver normalizedSpecifierValue:value];
    if (!normalized.length) normalized = [SCIDexKitNameResolver hexForValue:normalizedValue];
    if (!title.length) title = exactName ? name : [SCIDexKitNameResolver hexForValue:normalizedValue];
    if (!source.length) source = @"decoded-id";

    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:base];
    out[@"name"] = name ?: @"";
    out[@"resolvedName"] = exactName ? name : @"";
    out[@"title"] = title ?: @"";
    out[@"resolvedDetail"] = detail ?: @"";
    out[@"detail"] = detail ?: @"";
    out[@"source"] = source ?: @"";
    out[@"runtimeObserved"] = @(runtimeObserved);
    out[@"resolved"] = @(exactName);
    out[@"rawValue"] = [self hexForValue:value];
    out[@"rawValuePrefixed"] = [SCIDexKitNameResolver hexForValue:value];
    out[@"normalizedValue"] = normalized ?: @"";
    out[@"family"] = family ?: @"";
    out[@"param"] = param ?: @"";
    out[@"tag"] = tag ?: @"";
    out[@"callerImage"] = callerImage ?: @"";
    out[@"callerSymbol"] = callerSymbol ?: @"";
    out[@"callerAddress"] = callerAddress ?: @"";
    out[@"brokerID"] = bid ?: @"";
    out[@"identityCandidates"] = [SCIDexKitNameResolver identityCandidatesForBrokerID:bid value:value] ?: @[];
    return out;
}

+ (NSDictionary *)snapshotDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (SCIMobileConfigBrokerDescriptor *desc in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSString *key in [self observedOverrideKeysForBrokerID:desc.brokerID]) {
            NSString *bid = nil; uint64_t value = 0;
            [self parseOverrideKey:key brokerID:&bid value:&value];
            NSMutableDictionary *item = [[self resolvedMetadataForOverrideKey:key] mutableCopy];
            item[@"key"] = key ?: @"";
            item[@"value"] = [self hexForValue:value];
            item[@"override"] = [self overrideValueForKey:key] ?: [NSNull null];
            item[@"observed"] = [self observedValueForOverrideKey:key] ?: [NSNull null];
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
+ (void)resetAllBrokerOverrides { for (NSString *key in [self activeOverrideKeys]) [self setOverrideValue:nil forKey:key]; }

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
