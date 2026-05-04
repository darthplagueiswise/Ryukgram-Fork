#import "SCIBoolOverrideResolver.h"

NSString *const SCIBoolOverrideResolverDidChangeNotification = @"SCIBoolOverrideResolverDidChangeNotification";
static NSString *const kSCIDexKitBoolIndexKey = @"dexkit.bool.__index";
static NSDictionary<NSString *, NSNumber *> *gSCIBoolOverrideSnapshot = nil;

@implementation SCIBoolOverrideResolver

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kSCIDexKitBoolIndexKey: @[],
    }];
    [self reloadSnapshotFromDefaults];
}

+ (void)reloadSnapshotFromDefaults {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *index = [ud arrayForKey:kSCIDexKitBoolIndexKey] ?: @[];
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (id obj in index) {
        if (![obj isKindOfClass:NSString.class]) continue;
        id v = [ud objectForKey:(NSString *)obj];
        if ([v isKindOfClass:NSNumber.class]) snapshot[(NSString *)obj] = v;
    }
    @synchronized(self) { gSCIBoolOverrideSnapshot = [snapshot copy]; }
}

+ (nullable NSNumber *)overrideValueForKey:(NSString *)overrideKey {
    if (!overrideKey.length) return nil;
    @synchronized(self) {
        if (!gSCIBoolOverrideSnapshot) [self reloadSnapshotFromDefaults];
        id v = gSCIBoolOverrideSnapshot[overrideKey];
        return [v isKindOfClass:NSNumber.class] ? v : nil;
    }
}

+ (void)setOverrideValue:(nullable NSNumber *)value forKey:(NSString *)overrideKey {
    if (!overrideKey.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableArray *index = [[ud arrayForKey:kSCIDexKitBoolIndexKey] ?: @[] mutableCopy];
    if (value) {
        if (![index containsObject:overrideKey]) [index addObject:overrideKey];
        [ud setBool:value.boolValue forKey:overrideKey];
    } else {
        [ud removeObjectForKey:overrideKey];
        [index removeObject:overrideKey];
    }
    [ud setObject:index forKey:kSCIDexKitBoolIndexKey];
    [self reloadSnapshotFromDefaults];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIBoolOverrideResolverDidChangeNotification object:nil];
}

+ (NSArray<NSString *> *)activeOverrideKeys {
    @synchronized(self) {
        if (!gSCIBoolOverrideSnapshot) [self reloadSnapshotFromDefaults];
        return [[gSCIBoolOverrideSnapshot allKeys] sortedArrayUsingSelector:@selector(compare:)];
    }
}

+ (BOOL)hasOverrideForKey:(NSString *)overrideKey {
    return [self overrideValueForKey:overrideKey] != nil;
}

@end

BOOL SCIResolvePersistedBoolOverride(NSString *key, BOOL originalValue) {
    NSNumber *forced = [SCIBoolOverrideResolver overrideValueForKey:key];
    return forced ? forced.boolValue : originalValue;
}
