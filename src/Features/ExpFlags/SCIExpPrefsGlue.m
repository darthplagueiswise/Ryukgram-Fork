#import "SCIExpFlags.h"

@implementation SCIExpFlags (InternalUseOverrides)

+ (SCIExpFlagOverride)internalUseOverrideForSpecifier:(unsigned long long)specifier {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"sci_exp_internaluse_prefs"] ?: @{};
    NSNumber *n = d[[NSString stringWithFormat:@"%llu", specifier]];
    return n ? (SCIExpFlagOverride)n.integerValue : SCIExpFlagOverrideOff;
}

+ (void)setInternalUseOverride:(SCIExpFlagOverride)o forSpecifier:(unsigned long long)specifier {
    NSMutableDictionary *d = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"sci_exp_internaluse_prefs"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *k = [NSString stringWithFormat:@"%llu", specifier];
    if (o == SCIExpFlagOverrideOff) [d removeObjectForKey:k];
    else d[k] = @(o);
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"sci_exp_internaluse_prefs"];
}

+ (NSArray<NSNumber *> *)allOverriddenInternalUseSpecifiers {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"sci_exp_internaluse_prefs"] ?: @{};
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *k in d) {
        unsigned long long v = strtoull(k.UTF8String, NULL, 10);
        if (v) [out addObject:@(v)];
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

+ (void)resetAllInternalUseOverrides {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"sci_exp_internaluse_prefs"];
}

@end
