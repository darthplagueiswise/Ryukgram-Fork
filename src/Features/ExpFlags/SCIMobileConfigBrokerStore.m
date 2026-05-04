#import "SCIMobileConfigBrokerStore.h"

NSString * const SCIMCBrokerIndexKey = @"dexkit.cbool.__index";
NSString * const SCIMCBrokerHookIndexKey = @"dexkit.cbool.hooks";
static NSString * const kSCIMCBrokerObservedPrefix = @"dexkit.observed.cbool:";

@implementation SCIMobileConfigBrokerStore

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        SCIMCBrokerIndexKey: @[],
        SCIMCBrokerHookIndexKey: @[],
    }];
}

+ (NSString *)overrideKeyForBroker:(SCIMobileConfigBrokerDescriptor *)broker value:(uint64_t)value {
    NSString *symbol = [broker namespaceSymbol] ?: @"";
    NSString *kind = [broker kindLabel] ?: @"specifier";
    return [NSString stringWithFormat:@"dexkit.cbool:%@:%@:%@:%016llx",
            broker.imageName ?: @"FBSharedFramework",
            symbol,
            kind,
            (unsigned long long)value];
}

+ (NSString *)observedKeyForOverrideKey:(NSString *)overrideKey {
    if (![overrideKey hasPrefix:@"dexkit.cbool:"]) return @"";
    return [kSCIMCBrokerObservedPrefix stringByAppendingString:[overrideKey substringFromIndex:@"dexkit.cbool:".length]];
}

+ (NSString *)hookEnabledKeyForBrokerID:(NSString *)brokerID {
    return [@"dexkit.cbool.hook:" stringByAppendingString:brokerID ?: @""];
}

+ (NSString *)errorKeyForBrokerID:(NSString *)brokerID {
    return [@"dexkit.cbool.err:" stringByAppendingString:brokerID ?: @""];
}

+ (NSArray *)arrayForKey:(NSString *)key {
    NSArray *arr = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
    return [arr isKindOfClass:NSArray.class] ? arr : @[];
}

+ (void)setIndexedKey:(NSString *)item enabled:(BOOL)enabled indexKey:(NSString *)indexKey {
    if (!item.length || !indexKey.length) return;
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:[self arrayForKey:indexKey]];
    if (enabled) [set addObject:item];
    else [set removeObject:item];
    [[NSUserDefaults standardUserDefaults] setObject:set.array forKey:indexKey];
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
        [self setIndexedKey:key enabled:YES indexKey:SCIMCBrokerIndexKey];
    } else {
        [ud removeObjectForKey:key];
        [self setIndexedKey:key enabled:NO indexKey:SCIMCBrokerIndexKey];
    }
}

+ (BOOL)hookEnabledForBrokerID:(NSString *)brokerID {
    if (!brokerID.length) return NO;
    return [[NSUserDefaults standardUserDefaults] boolForKey:[self hookEnabledKeyForBrokerID:brokerID]] || [[self enabledHookBrokerIDs] containsObject:brokerID];
}

+ (void)setHookEnabled:(BOOL)enabled forBrokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    NSString *key = [self hookEnabledKeyForBrokerID:brokerID];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:key];
    [self setIndexedKey:brokerID enabled:enabled indexKey:SCIMCBrokerHookIndexKey];
}

+ (void)noteObservedValue:(BOOL)value forOverrideKey:(NSString *)overrideKey {
    NSString *key = [self observedKeyForOverrideKey:overrideKey];
    if (!key.length) return;
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
}

+ (nullable NSNumber *)observedValueForOverrideKey:(NSString *)overrideKey {
    NSString *key = [self observedKeyForOverrideKey:overrideKey];
    if (!key.length) return nil;
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

+ (void)setLastError:(nullable NSString *)error forBrokerID:(NSString *)brokerID {
    if (!brokerID.length) return;
    NSString *key = [self errorKeyForBrokerID:brokerID];
    if (error.length) [[NSUserDefaults standardUserDefaults] setObject:error forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

+ (nullable NSString *)lastErrorForBrokerID:(NSString *)brokerID {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:[self errorKeyForBrokerID:brokerID]];
    return [v isKindOfClass:NSString.class] ? v : nil;
}

+ (NSArray<NSString *> *)activeOverrideKeys {
    NSMutableArray *out = [NSMutableArray array];
    for (id obj in [self arrayForKey:SCIMCBrokerIndexKey]) {
        if (![obj isKindOfClass:NSString.class]) continue;
        if ([self overrideValueForKey:obj]) [out addObject:obj];
    }
    return out;
}

+ (NSArray<NSString *> *)enabledHookBrokerIDs {
    NSMutableArray *out = [NSMutableArray array];
    for (id obj in [self arrayForKey:SCIMCBrokerHookIndexKey]) {
        if ([obj isKindOfClass:NSString.class]) [out addObject:obj];
    }
    return out;
}

+ (NSArray<NSString *> *)observedOverrideKeys {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in all.allKeys) {
        if (![key hasPrefix:kSCIMCBrokerObservedPrefix]) continue;
        NSString *overrideKey = [@"dexkit.cbool:" stringByAppendingString:[key substringFromIndex:kSCIMCBrokerObservedPrefix.length]];
        [out addObject:overrideKey];
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

+ (BOOL)parseOverrideKey:(NSString *)key
                brokerID:(NSString * _Nullable * _Nullable)brokerID
                   image:(NSString * _Nullable * _Nullable)image
                  symbol:(NSString * _Nullable * _Nullable)symbol
                    kind:(NSString * _Nullable * _Nullable)kind
                   value:(uint64_t * _Nullable)value {
    if (![key hasPrefix:@"dexkit.cbool:"]) return NO;
    NSString *body = [key substringFromIndex:@"dexkit.cbool:".length];
    NSArray<NSString *> *parts = [body componentsSeparatedByString:@":"];
    if (parts.count < 4) return NO;
    NSString *img = parts[0];
    NSString *sym = parts[1];
    NSString *k = parts[2];
    NSString *hex = parts[3];
    uint64_t parsed = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexLongLong:&parsed]) return NO;
    SCIMobileConfigBrokerDescriptor *d = [SCIMobileConfigBrokerDescriptor descriptorForSymbol:[@"_" stringByAppendingString:sym]] ?: [SCIMobileConfigBrokerDescriptor descriptorForSymbol:sym];
    if (brokerID) *brokerID = d.brokerID ?: @"";
    if (image) *image = img;
    if (symbol) *symbol = sym;
    if (kind) *kind = k;
    if (value) *value = parsed;
    return YES;
}

@end
