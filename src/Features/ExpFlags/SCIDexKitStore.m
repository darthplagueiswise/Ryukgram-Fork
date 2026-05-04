#import "SCIDexKitStore.h"
#import "../../Core/SCIBoolOverrideResolver.h"
#import "SCIExpFlags.h"

static NSString *const kSCIDexKitSchemaKey = @"dexkit.meta.schema";
static NSString *const kSCIDexKitObservedBuildKey = @"dexkit.meta.observedBuild";
static NSString *const kSCIDexKitBoolIndexKey = @"dexkit.bool.__index";
static NSString *const kSCIDexKitQuarantineKey = @"dexkit.meta.quarantinedOverrides";
static NSString *const kSCIDexKitBootInProgressKey = @"dexkit.meta.bootInProgress";
static NSString *const kSCIDexKitUnstableCountKey = @"dexkit.meta.unstableLaunchCount";
static NSString *const kSCIDexKitLastApplyingKey = @"dexkit.meta.lastApplyingOverride";
static NSInteger const kSCIDexKitSchemaVersion = 2;

@implementation SCIDexKitStore

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kSCIDexKitSchemaKey: @(kSCIDexKitSchemaVersion),
        kSCIDexKitBoolIndexKey: @[],
        kSCIDexKitQuarantineKey: @[],
        kSCIDexKitBootInProgressKey: @NO,
        kSCIDexKitUnstableCountKey: @0,
    }];
    [SCIBoolOverrideResolver registerDefaults];
}

+ (NSString *)currentAppBuildToken {
    NSBundle *b = NSBundle.mainBundle;
    NSString *bid = [b objectForInfoDictionaryKey:@"CFBundleIdentifier"] ?: @"?";
    NSString *shortVersion = [b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [b objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    return [NSString stringWithFormat:@"%@:%@:%@", bid, shortVersion, build];
}

+ (void)invalidateObservedCacheIfBuildChanged {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *current = [self currentAppBuildToken];
    NSString *old = [ud stringForKey:kSCIDexKitObservedBuildKey];
    if (old.length && ![old isEqualToString:current]) {
        NSDictionary *dict = [ud dictionaryRepresentation];
        for (NSString *key in dict.allKeys) {
            if ([key hasPrefix:@"dexkit.observed.bool:"]) [ud removeObjectForKey:key];
        }
    }
    [ud setObject:current forKey:kSCIDexKitObservedBuildKey];
}

+ (NSString *)overrideKeyForImage:(NSString *)image sign:(NSString *)sign className:(NSString *)className selector:(NSString *)selector {
    return [NSString stringWithFormat:@"dexkit.bool:%@:%@:%@:%@", image ?: @"?", sign ?: @"-", className ?: @"", selector ?: @""];
}

+ (NSString *)observedKeyForImage:(NSString *)image sign:(NSString *)sign className:(NSString *)className selector:(NSString *)selector {
    return [NSString stringWithFormat:@"dexkit.observed.bool:%@:%@:%@:%@", image ?: @"?", sign ?: @"-", className ?: @"", selector ?: @""];
}

+ (NSString *)observedKeyForOverrideKey:(NSString *)overrideKey {
    if (![overrideKey hasPrefix:@"dexkit.bool:"]) return @"";
    return [@"dexkit.observed.bool:" stringByAppendingString:[overrideKey substringFromIndex:@"dexkit.bool:".length]];
}

+ (BOOL)parseBoolKey:(NSString *)key image:(NSString **)image sign:(NSString **)sign className:(NSString **)className selector:(NSString **)selector {
    NSString *prefix = nil;
    if ([key hasPrefix:@"dexkit.bool:"]) prefix = @"dexkit.bool:";
    else if ([key hasPrefix:@"dexkit.observed.bool:"]) prefix = @"dexkit.observed.bool:";
    else return NO;
    NSString *body = [key substringFromIndex:prefix.length];
    NSArray<NSString *> *parts = [body componentsSeparatedByString:@":"];
    if (parts.count < 4) return NO;
    if (image) *image = parts[0];
    if (sign) *sign = parts[1];
    if (className) *className = parts[2];
    if (selector) {
        NSArray *selParts = [parts subarrayWithRange:NSMakeRange(3, parts.count - 3)];
        *selector = [selParts componentsJoinedByString:@":"];
    }
    return YES;
}

+ (NSString *)modernKeyForLegacyObjCEnabledKey:(NSString *)legacy defaultImage:(NSString *)image {
    if (![legacy hasPrefix:@"objc-enabled:"]) return nil;
    NSString *body = [legacy substringFromIndex:@"objc-enabled:".length];
    if (body.length < 3) return nil;
    NSString *sign = [body substringToIndex:1];
    NSRange sp = [body rangeOfString:@" "];
    if (sp.location == NSNotFound || sp.location <= 1) return nil;
    NSString *cls = [body substringWithRange:NSMakeRange(1, sp.location - 1)];
    NSString *sel = [body substringFromIndex:sp.location + 1];
    return [self overrideKeyForImage:image ?: NSBundle.mainBundle.executablePath.lastPathComponent sign:sign className:cls selector:sel];
}

+ (void)migrateIfNeeded {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSInteger schema = [ud integerForKey:kSCIDexKitSchemaKey];
    if (schema >= kSCIDexKitSchemaVersion) { [SCIBoolOverrideResolver reloadSnapshotFromDefaults]; return; }

    NSMutableArray *index = [[ud arrayForKey:kSCIDexKitBoolIndexKey] ?: @[] mutableCopy];
    NSDictionary *legacyOverrides = [ud dictionaryForKey:@"sci_exp_overrides_by_name"];
    if ([legacyOverrides isKindOfClass:NSDictionary.class]) {
        for (NSString *legacyKey in legacyOverrides) {
            id value = legacyOverrides[legacyKey];
            if (![value respondsToSelector:@selector(integerValue)]) continue;
            NSInteger v = [value integerValue];
            if (v != 1 && v != 2) continue;
            NSString *newKey = [self modernKeyForLegacyObjCEnabledKey:legacyKey defaultImage:NSBundle.mainBundle.executablePath.lastPathComponent];
            if (!newKey.length) continue;
            [ud setBool:(v == 1) forKey:newKey];
            if (![index containsObject:newKey]) [index addObject:newKey];
        }
    }
    [ud setObject:index forKey:kSCIDexKitBoolIndexKey];

    NSDictionary *legacyObserved = [ud dictionaryForKey:@"sci_enabled_experiment_observed_defaults"];
    if ([legacyObserved isKindOfClass:NSDictionary.class]) {
        for (NSString *legacyKey in legacyObserved) {
            id value = legacyObserved[legacyKey];
            if (![value isKindOfClass:NSNumber.class]) continue;
            NSString *newOverride = [self modernKeyForLegacyObjCEnabledKey:legacyKey defaultImage:NSBundle.mainBundle.executablePath.lastPathComponent];
            if (!newOverride.length) continue;
            [ud setBool:[value boolValue] forKey:[self observedKeyForOverrideKey:newOverride]];
        }
    }

    NSDictionary *oldObserved = [ud dictionaryForKey:@"sci_dexkit_bool_getter_observed_values"];
    if ([oldObserved isKindOfClass:NSDictionary.class]) {
        for (NSString *key in oldObserved) {
            id value = oldObserved[key];
            if (![value isKindOfClass:NSNumber.class]) continue;
            if ([key hasPrefix:@"dexkit.observed.bool:"]) [ud setBool:[value boolValue] forKey:key];
        }
    }
    [ud setInteger:kSCIDexKitSchemaVersion forKey:kSCIDexKitSchemaKey];
    [SCIBoolOverrideResolver reloadSnapshotFromDefaults];
}

+ (NSArray<NSString *> *)activeOverrideKeys { return [SCIBoolOverrideResolver activeOverrideKeys]; }
+ (NSNumber *)overrideValueForKey:(NSString *)overrideKey {
    if ([self isOverrideQuarantined:overrideKey]) return nil;
    return [SCIBoolOverrideResolver overrideValueForKey:overrideKey];
}
+ (void)setOverrideValue:(NSNumber *)value forKey:(NSString *)overrideKey {
    [SCIBoolOverrideResolver setOverrideValue:value forKey:overrideKey];
    if (value) [self clearQuarantineForKey:overrideKey];
}
+ (NSNumber *)observedValueForKey:(NSString *)observedKey {
    id v = [NSUserDefaults.standardUserDefaults objectForKey:observedKey];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}
+ (void)noteObservedValue:(BOOL)value forKey:(NSString *)observedKey {
    if (!observedKey.length) return;
    NSNumber *old = [self observedValueForKey:observedKey];
    if (old && old.boolValue == value) return;
    [NSUserDefaults.standardUserDefaults setBool:value forKey:observedKey];
}
+ (SCIDexKitKnownBoolState)effectiveStateForOverrideKey:(NSString *)overrideKey observedKey:(NSString *)observedKey {
    NSNumber *forced = [self overrideValueForKey:overrideKey];
    if (forced) return forced.boolValue ? SCIDexKitKnownBoolStateOn : SCIDexKitKnownBoolStateOff;
    NSNumber *obs = [self observedValueForKey:observedKey];
    if (obs) return obs.boolValue ? SCIDexKitKnownBoolStateOn : SCIDexKitKnownBoolStateOff;
    return SCIDexKitKnownBoolStateUnknown;
}

+ (void)beginBootGuard {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    BOOL inProgress = [ud boolForKey:kSCIDexKitBootInProgressKey];
    NSInteger unstable = [ud integerForKey:kSCIDexKitUnstableCountKey];
    if (inProgress) {
        unstable++;
        [ud setInteger:unstable forKey:kSCIDexKitUnstableCountKey];
        NSString *last = [ud stringForKey:kSCIDexKitLastApplyingKey];
        if (last.length && unstable >= 2) {
            NSMutableArray *q = [[ud arrayForKey:kSCIDexKitQuarantineKey] ?: @[] mutableCopy];
            if (![q containsObject:last]) [q addObject:last];
            [ud setObject:q forKey:kSCIDexKitQuarantineKey];
            [SCIBoolOverrideResolver setOverrideValue:nil forKey:last];
        }
    }
    [ud setBool:YES forKey:kSCIDexKitBootInProgressKey];
}
+ (void)markLaunchStable {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setBool:NO forKey:kSCIDexKitBootInProgressKey];
    [ud setInteger:0 forKey:kSCIDexKitUnstableCountKey];
    [ud removeObjectForKey:kSCIDexKitLastApplyingKey];
}
+ (void)noteApplyingOverrideKey:(NSString *)key { if (key.length) [NSUserDefaults.standardUserDefaults setObject:key forKey:kSCIDexKitLastApplyingKey]; }
+ (NSArray<NSString *> *)quarantinedOverrideKeys { return [NSUserDefaults.standardUserDefaults arrayForKey:kSCIDexKitQuarantineKey] ?: @[]; }
+ (BOOL)isOverrideQuarantined:(NSString *)key { return key.length && [[self quarantinedOverrideKeys] containsObject:key]; }
+ (void)clearQuarantineForKey:(NSString *)key {
    if (!key.length) return;
    NSMutableArray *q = [[self quarantinedOverrideKeys] mutableCopy];
    if (!q) q = [NSMutableArray array];
    [q removeObject:key];
    [NSUserDefaults.standardUserDefaults setObject:q forKey:kSCIDexKitQuarantineKey];
}

@end
