#import "SCIMobileConfigBrokerStore.h"
#import "SCIDexKitNameResolver.h"
#import <dispatch/dispatch.h>

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
static NSString * const kMCBRMigrationDoneKey = @"mcbr.migration.v2.done";

static NSString *SCIMCBrokerString(id obj) { return [obj isKindOfClass:NSString.class] ? (NSString *)obj : @""; }
static BOOL SCIMCBrokerBool(id obj) { return [obj respondsToSelector:@selector(boolValue)] ? [obj boolValue] : NO; }
static BOOL SCIMCBrokerObservedObjectIsPresent(id obj) { return obj && obj != (id)NSNull.null; }

static NSObject *SCIMCBrokerCacheLock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSMutableDictionary<NSString *, NSDictionary *> *SCIMCBrokerResolvedCache(void) {
    static NSMutableDictionary<NSString *, NSDictionary *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

static NSMutableDictionary<NSString *, NSNumber *> *SCIMCBrokerHitCache(void) {
    static NSMutableDictionary<NSString *, NSNumber *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

static NSMutableDictionary<NSString *, NSNumber *> *SCIMCBrokerForcedHitCache(void) {
    static NSMutableDictionary<NSString *, NSNumber *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

static NSMutableSet<NSString *> *SCIMCBrokerDirtyHitKeys(void) {
    static NSMutableSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ keys = [NSMutableSet set]; });
    return keys;
}

static NSDictionary *gSCIMCBrokerSnapshotCache = nil;

static void SCIMCBrokerInvalidateCaches(void) {
    @synchronized (SCIMCBrokerCacheLock()) {
        [SCIMCBrokerResolvedCache() removeAllObjects];
        gSCIMCBrokerSnapshotCache = nil;
    }
}

static NSDictionary *SCIMCBrokerSnapshotCacheCopy(void) {
    @synchronized (SCIMCBrokerCacheLock()) {
        return gSCIMCBrokerSnapshotCache ? [gSCIMCBrokerSnapshotCache copy] : nil;
    }
}

static void SCIMCBrokerSetSnapshotCache(NSDictionary *snapshot) {
    @synchronized (SCIMCBrokerCacheLock()) {
        gSCIMCBrokerSnapshotCache = snapshot ? [snapshot copy] : nil;
    }
}

static void SCIMCBrokerPostStoreChange(NSDictionary *userInfo) {
    static BOOL scheduled = NO;
    static NSMutableDictionary *pending = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ pending = [NSMutableDictionary dictionary]; });

    SCIMCBrokerInvalidateCaches();

    @synchronized (SCIMCBrokerCacheLock()) {
        if (userInfo.count) [pending addEntriesFromDictionary:userInfo];
        if (scheduled) return;
        scheduled = YES;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *info = nil;
        @synchronized (SCIMCBrokerCacheLock()) {
            info = [pending copy];
            [pending removeAllObjects];
            scheduled = NO;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIMCBrokerStoreDidChangeNotification object:nil userInfo:info ?: @{}];
    });
}

static NSNumber *SCIMCBrokerCachedCountForKey(NSMutableDictionary<NSString *, NSNumber *> *cache, NSString *defaultsKey) {
    if (!defaultsKey.length) return @0;
    @synchronized (SCIMCBrokerCacheLock()) {
        NSNumber *cached = cache[defaultsKey];
        if (cached) return cached;
    }
    NSNumber *loaded = @((NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:defaultsKey]);
    @synchronized (SCIMCBrokerCacheLock()) { cache[defaultsKey] = loaded; }
    return loaded;
}

static void SCIMCBrokerScheduleHitFlush(void) {
    static BOOL scheduled = NO;
    @synchronized (SCIMCBrokerCacheLock()) {
        if (scheduled) return;
        scheduled = YES;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *hits = nil;
        NSDictionary *forcedHits = nil;
        NSSet *dirty = nil;

        @synchronized (SCIMCBrokerCacheLock()) {
            hits = [SCIMCBrokerHitCache() copy];
            forcedHits = [SCIMCBrokerForcedHitCache() copy];
            dirty = [SCIMCBrokerDirtyHitKeys() copy];
            [SCIMCBrokerDirtyHitKeys() removeAllObjects];
            scheduled = NO;
        }

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        for (NSString *key in dirty) {
            NSNumber *value = hits[key] ?: forcedHits[key];
            if (value) [ud setInteger:value.integerValue forKey:key];
        }
    });
}

static void SCIMCBrokerIncrementCachedCountBy(NSMutableDictionary<NSString *, NSNumber *> *cache, NSString *defaultsKey, NSUInteger delta) {
    if (!defaultsKey.length || delta == 0) return;
    @synchronized (SCIMCBrokerCacheLock()) {
        NSNumber *current = cache[defaultsKey];
        if (!current) current = @((NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:defaultsKey]);
        cache[defaultsKey] = @(current.unsignedIntegerValue + delta);
        [SCIMCBrokerDirtyHitKeys() addObject:defaultsKey];
    }
    SCIMCBrokerScheduleHitFlush();
}

static void SCIMCBrokerIncrementCachedCount(NSMutableDictionary<NSString *, NSNumber *> *cache, NSString *defaultsKey) {
    SCIMCBrokerIncrementCachedCountBy(cache, defaultsKey, 1);
}

static void SCIMCBrokerEnsureResolverObserver(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:SCIDexKitNameResolverDidUpdateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            SCIMCBrokerPostStoreChange(@{@"source": @"resolver"});
        }];
        [nc addObserverForName:SCIDexKitNameResolverRuntimeFeedDidUpdateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            SCIMCBrokerPostStoreChange(@{@"source": @"runtime-feed"});
        }];
    });
}

static NSComparisonResult SCIMCBrokerCompareMetadataItems(NSDictionary *a, NSDictionary *b) {
    BOOL ar = SCIMCBrokerBool(a[@"runtimeObserved"]);
    BOOL br = SCIMCBrokerBool(b[@"runtimeObserved"]);
    if (ar != br) return ar ? NSOrderedAscending : NSOrderedDescending;

    BOOL aResolved = SCIMCBrokerBool(a[@"resolved"]);
    BOOL bResolved = SCIMCBrokerBool(b[@"resolved"]);
    if (aResolved != bResolved) return aResolved ? NSOrderedAscending : NSOrderedDescending;

    BOOL aObserved = SCIMCBrokerObservedObjectIsPresent(a[@"observed"]);
    BOOL bObserved = SCIMCBrokerObservedObjectIsPresent(b[@"observed"]);
    if (aObserved != bObserved) return aObserved ? NSOrderedAscending : NSOrderedDescending;

    NSString *at = SCIMCBrokerString(a[@"title"]);
    NSString *bt = SCIMCBrokerString(b[@"title"]);
    NSComparisonResult r = [at localizedCaseInsensitiveCompare:bt];
    if (r != NSOrderedSame) return r;

    return [SCIMCBrokerString(a[@"key"]) compare:SCIMCBrokerString(b[@"key"])] ;
}

@implementation SCIMobileConfigBrokerStore

+ (void)registerDefaultsAndMigrate {
    SCIMCBrokerEnsureResolverObserver();

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud registerDefaults:@{SCIMCBrokerIndexKey: @[], SCIMCBrokerObservedIndexKey: @[], SCIMCBrokerHookIndexKey: @[]}];

    if ([ud boolForKey:kMCBRMigrationDoneKey]) return;

    NSDictionary *all = [ud dictionaryRepresentation];
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        NSString *longKey = [NSString stringWithFormat:@"dexkit.cbroker:%@:%@", d.imageName, d.symbol];
        id longValue = all[longKey];
        if ([longValue isKindOfClass:NSNumber.class]) {
            NSString *key = [self overrideKeyForBrokerID:d.brokerID value:0];
            [ud setBool:[longValue boolValue] forKey:key];
            [self addIndexedKey:key indexKey:SCIMCBrokerIndexKey];
        }

        NSString *oldBrokerWide = [kMCBROverridePrefix stringByAppendingString:(d.brokerID ?: @"")];
        id oldValue = all[oldBrokerWide];
        if ([oldValue isKindOfClass:NSNumber.class]) {
            NSString *key = [self overrideKeyForBrokerID:d.brokerID value:0];
            [ud setBool:[oldValue boolValue] forKey:key];
            [self addIndexedKey:key indexKey:SCIMCBrokerIndexKey];
            [ud removeObjectForKey:oldBrokerWide];
        }
    }
    [ud setBool:YES forKey:kMCBRMigrationDoneKey];
}

+ (NSArray *)arrayForKey:(NSString *)key {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [obj isKindOfClass:NSArray.class] ? obj : @[];
}

+ (void)addIndexedKey:(NSString *)item indexKey:(NSString *)indexKey {
    if (!item.length || !indexKey.length) return;
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:[self arrayForKey:indexKey]];
    if ([set containsObject:item]) return;
    [set addObject:item];
    [[NSUserDefaults standardUserDefaults] setObject:set.array forKey:indexKey];
}

+ (void)removeIndexedKey:(NSString *)item indexKey:(NSString *)indexKey {
    if (!item.length || !indexKey.length) return;
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:[self arrayForKey:indexKey]];
    if (![set containsObject:item]) return;
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
    if (![key isKindOfClass:NSString.class] || ![key hasPrefix:kMCBROverridePrefix]) return NO;
    NSString *body = [key substringFromIndex:kMCBROverridePrefix.length];
    NSArray<NSString *> *parts = [body componentsSeparatedByString:@":"];
    if (parts.count < 2) return NO;
    unsigned long long parsed = 0;
    if (![[NSScanner scannerWithString:parts[1]] scanHexLongLong:&parsed]) return NO;
    if (brokerID) *brokerID = parts[0];
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
    NSNumber *existing = [self overrideValueForKey:key];
    if (value && existing && existing.boolValue == value.boolValue) return;
    if (!value && !existing) return;

    if (value) {
        [ud setBool:value.boolValue forKey:key];
        [self addIndexedKey:key indexKey:SCIMCBrokerIndexKey];
    } else {
        [ud removeObjectForKey:key];
        [self removeIndexedKey:key indexKey:SCIMCBrokerIndexKey];
    }
    SCIMCBrokerPostStoreChange(@{@"key": key});
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

    NSNumber *existing = [self observedValueForOverrideKey:overrideKey];
    BOOL alreadyIndexed = [[self arrayForKey:SCIMCBrokerObservedIndexKey] containsObject:overrideKey];
    if (existing && existing.boolValue == value && alreadyIndexed) return;

    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [self addIndexedKey:overrideKey indexKey:SCIMCBrokerObservedIndexKey];
    SCIMCBrokerPostStoreChange(@{@"key": overrideKey, @"observed": @(value)});
}

+ (NSArray<NSString *> *)activeOverrideKeys {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id obj in [self arrayForKey:SCIMCBrokerIndexKey]) {
        if ([obj isKindOfClass:NSString.class] && [self overrideValueForKey:obj]) [out addObject:obj];
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
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id obj in [self arrayForKey:SCIMCBrokerObservedIndexKey]) {
        if (![obj isKindOfClass:NSString.class]) continue;
        NSString *key = (NSString *)obj;
        if ([key hasPrefix:kMCBROverridePrefix]) [out addObject:key];
    }
    return out;
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
    BOOL old = [self isBrokerHookEnabledForID:brokerID];
    if (old == enabled) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:enabled forKey:[self hookEnabledKeyForBrokerID:brokerID]];
    if (enabled) [self addIndexedKey:brokerID indexKey:SCIMCBrokerHookIndexKey];
    else [self removeIndexedKey:brokerID indexKey:SCIMCBrokerHookIndexKey];
    SCIMCBrokerPostStoreChange(@{@"brokerID": brokerID});
}

+ (BOOL)hasAnyActiveOverridesOrHooks { return [self activeOverrideKeys].count > 0 || [self enabledHookBrokerIDs].count > 0; }
+ (BOOL)shouldInstallBrokerID:(NSString *)brokerID { return [self isBrokerHookEnabledForID:brokerID] || [self activeOverrideKeysForBrokerID:brokerID].count > 0; }

+ (void)noteLastError:(nullable NSString *)error brokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    NSString *key = [self lastErrorKeyForBrokerID:brokerID];
    NSString *old = [[NSUserDefaults standardUserDefaults] stringForKey:key] ?: @"";
    if ((error ?: @"").length && [old isEqualToString:error ?: @""]) return;
    if (!(error ?: @"").length && !old.length) return;

    if (error.length) [[NSUserDefaults standardUserDefaults] setObject:error forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    SCIMCBrokerPostStoreChange(@{@"brokerID": brokerID, @"error": error ?: @""});
}
+ (nullable NSString *)lastErrorForBrokerID:(NSString *)brokerID {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self lastErrorKeyForBrokerID:brokerID]];
    return [v isKindOfClass:NSString.class] ? v : nil;
}

+ (void)noteHitForBrokerID:(NSString *)brokerID value:(uint64_t)value forced:(BOOL)forced {
    [self noteHitCountForBrokerID:brokerID value:value forced:forced count:1];
}
+ (void)noteHitCountForBrokerID:(NSString *)brokerID value:(uint64_t)value forced:(BOOL)forced count:(NSUInteger)count {
    if (!brokerID.length) return;
    if (count == 0) return;
    SCIMCBrokerIncrementCachedCountBy(SCIMCBrokerHitCache(), [self hitKeyForBrokerID:brokerID], count);
    if (forced) SCIMCBrokerIncrementCachedCountBy(SCIMCBrokerForcedHitCache(), [self forcedHitKeyForBrokerID:brokerID], count);
    (void)value;
}
+ (NSUInteger)hitCountForBrokerID:(NSString *)brokerID { return SCIMCBrokerCachedCountForKey(SCIMCBrokerHitCache(), [self hitKeyForBrokerID:brokerID]).unsignedIntegerValue; }
+ (NSUInteger)forcedHitCountForBrokerID:(NSString *)brokerID { return SCIMCBrokerCachedCountForKey(SCIMCBrokerForcedHitCache(), [self forcedHitKeyForBrokerID:brokerID]).unsignedIntegerValue; }

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
    SCIMCBrokerEnsureResolverObserver();

    if (!overrideKey.length) return @{};
    @synchronized (SCIMCBrokerCacheLock()) {
        NSDictionary *cached = SCIMCBrokerResolvedCache()[overrideKey];
        if (cached) return cached;
    }

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

    NSDictionary *immutable = [out copy];
    @synchronized (SCIMCBrokerCacheLock()) { SCIMCBrokerResolvedCache()[overrideKey] = immutable; }
    return immutable;
}

+ (NSDictionary *)snapshotDictionary {
    SCIMCBrokerEnsureResolverObserver();

    NSDictionary *cached = SCIMCBrokerSnapshotCacheCopy();
    if (cached) return cached;

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
        [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return SCIMCBrokerCompareMetadataItems(a, b);
        }];

        d[desc.brokerID] = @{
            @"symbol": desc.symbol ?: @"",
            @"hookEnabled": @([self isBrokerHookEnabledForID:desc.brokerID]),
            @"hits": @([self hitCountForBrokerID:desc.brokerID]),
            @"forcedHits": @([self forcedHitCountForBrokerID:desc.brokerID]),
            @"lastError": [self lastErrorForBrokerID:desc.brokerID] ?: @"",
            @"values": items
        };
    }

    NSDictionary *snapshot = [d copy];
    SCIMCBrokerSetSnapshotCache(snapshot);
    return snapshot;
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
