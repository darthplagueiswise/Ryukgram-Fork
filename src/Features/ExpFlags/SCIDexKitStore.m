#import "SCIDexKitStore.h"

static NSString *const kSCIDexKitBoolGetterPrefix = @"dexkit.bool:";
static NSString *const kSCIDexKitLegacyBoolGetterPrefix = @"objc-enabled:";
static NSString *const kSCIDexKitObservedBoolGetterValuesKey = @"sci_dexkit_bool_getter_observed_values";
static NSString *const kSCIDexKitLegacyObservedValuesKey = @"sci_enabled_experiment_observed_defaults";

@implementation SCIDexKitStore

+ (NSString *)boolGetterKeyWithClassName:(NSString *)className methodName:(NSString *)methodName classMethod:(BOOL)classMethod {
    return [NSString stringWithFormat:@"%@%@%@ %@",
            kSCIDexKitBoolGetterPrefix,
            classMethod ? @"+" : @"-",
            className ?: @"",
            methodName ?: @""];
}

+ (BOOL)parseBoolGetterKey:(NSString *)key className:(NSString **)className methodName:(NSString **)methodName classMethod:(BOOL *)classMethod {
    if (![key hasPrefix:kSCIDexKitBoolGetterPrefix] && ![key hasPrefix:kSCIDexKitLegacyBoolGetterPrefix]) return NO;
    NSString *prefix = [key hasPrefix:kSCIDexKitBoolGetterPrefix] ? kSCIDexKitBoolGetterPrefix : kSCIDexKitLegacyBoolGetterPrefix;
    NSString *body = [key substringFromIndex:prefix.length];
    if (body.length < 3) return NO;
    unichar kind = [body characterAtIndex:0];
    if (kind != '+' && kind != '-') return NO;
    NSRange space = [body rangeOfString:@" "];
    if (space.location == NSNotFound || space.location <= 1 || space.location + 1 >= body.length) return NO;
    if (classMethod) *classMethod = (kind == '+');
    if (className) *className = [body substringWithRange:NSMakeRange(1, space.location - 1)];
    if (methodName) *methodName = [body substringFromIndex:space.location + 1];
    return YES;
}

+ (SCIExpFlagOverride)overrideForKey:(NSString *)key {
    if (!key.length) return SCIExpFlagOverrideOff;
    SCIExpFlagOverride override = [SCIExpFlags overrideForName:key];
    if (override != SCIExpFlagOverrideOff) return override;

    // Backward compatibility with keys saved before DexKit got a unified namespace.
    if ([key hasPrefix:kSCIDexKitBoolGetterPrefix]) {
        NSString *legacy = [kSCIDexKitLegacyBoolGetterPrefix stringByAppendingString:[key substringFromIndex:kSCIDexKitBoolGetterPrefix.length]];
        return [SCIExpFlags overrideForName:legacy];
    }
    return SCIExpFlagOverrideOff;
}

+ (void)setOverride:(SCIExpFlagOverride)override forKey:(NSString *)key {
    if (!key.length) return;
    [SCIExpFlags setOverride:override forName:key];

    if ([key hasPrefix:kSCIDexKitBoolGetterPrefix]) {
        NSString *legacy = [kSCIDexKitLegacyBoolGetterPrefix stringByAppendingString:[key substringFromIndex:kSCIDexKitBoolGetterPrefix.length]];
        [SCIExpFlags setOverride:SCIExpFlagOverrideOff forName:legacy];
    }
}

+ (NSArray<NSString *> *)allOverrideKeys {
    return [SCIExpFlags allOverriddenNames];
}

+ (NSArray<NSString *> *)allBoolGetterOverrideKeys {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in [self allOverrideKeys]) {
        if ([key hasPrefix:kSCIDexKitBoolGetterPrefix] || [key hasPrefix:kSCIDexKitLegacyBoolGetterPrefix]) [out addObject:key];
    }
    return out;
}

+ (NSDictionary<NSString *, NSNumber *> *)observedBoolGetterValues {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *modern = [ud dictionaryForKey:kSCIDexKitObservedBoolGetterValuesKey];
    NSMutableDictionary *merged = modern ? [modern mutableCopy] : [NSMutableDictionary dictionary];

    // Migration/read-through from the previous DexKit observed-defaults key.
    NSDictionary *legacy = [ud dictionaryForKey:kSCIDexKitLegacyObservedValuesKey];
    if ([legacy isKindOfClass:NSDictionary.class]) {
        for (NSString *legacyKey in legacy) {
            id value = legacy[legacyKey];
            if (![value isKindOfClass:NSNumber.class]) continue;
            if ([legacyKey hasPrefix:kSCIDexKitLegacyBoolGetterPrefix]) {
                NSString *modernKey = [kSCIDexKitBoolGetterPrefix stringByAppendingString:[legacyKey substringFromIndex:kSCIDexKitLegacyBoolGetterPrefix.length]];
                if (!merged[modernKey]) merged[modernKey] = value;
            } else if (!merged[legacyKey]) {
                merged[legacyKey] = value;
            }
        }
    }
    return merged;
}

+ (NSNumber *)observedBoolGetterValueForKey:(NSString *)key {
    if (!key.length) return nil;
    NSNumber *value = [self observedBoolGetterValues][key];
    if (value) return value;
    if ([key hasPrefix:kSCIDexKitBoolGetterPrefix]) {
        NSString *legacy = [kSCIDexKitLegacyBoolGetterPrefix stringByAppendingString:[key substringFromIndex:kSCIDexKitBoolGetterPrefix.length]];
        return [self observedBoolGetterValues][legacy];
    }
    return nil;
}

+ (void)setObservedBoolGetterValue:(BOOL)value forKey:(NSString *)key {
    if (!key.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *dict = [[self observedBoolGetterValues] mutableCopy];
    NSNumber *old = dict[key];
    if (old && old.boolValue == value) return;
    dict[key] = @(value);
    [ud setObject:dict forKey:kSCIDexKitObservedBoolGetterValuesKey];
}

+ (BOOL)effectiveBoolValueForKey:(NSString *)key defaultKnown:(BOOL)defaultKnown defaultValue:(BOOL)defaultValue {
    SCIExpFlagOverride override = [self overrideForKey:key];
    if (override == SCIExpFlagOverrideTrue) return YES;
    if (override == SCIExpFlagOverrideFalse) return NO;
    return defaultKnown ? defaultValue : NO;
}

+ (NSString *)systemLabelForKnown:(BOOL)known value:(BOOL)value {
    if (!known) return @"unknown";
    return value ? @"ON" : @"OFF";
}

+ (NSString *)overrideLabelForKey:(NSString *)key {
    SCIExpFlagOverride override = [self overrideForKey:key];
    if (override == SCIExpFlagOverrideTrue) return @"OVERRIDE ON";
    if (override == SCIExpFlagOverrideFalse) return @"OVERRIDE OFF";
    return @"SYSTEM";
}

@end
