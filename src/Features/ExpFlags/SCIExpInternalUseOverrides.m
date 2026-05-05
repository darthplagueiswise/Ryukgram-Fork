#import "SCIExpFlags.h"

static NSString *const kInternalUseOverridesKey = @"sci_exp_internaluse_overrides_by_specifier";

@implementation SCIExpFlags (InternalUseOverrides)

+ (NSMutableDictionary *)rg_loadInternalUseOverrides {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kInternalUseOverridesKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)rg_saveInternalUseOverrides:(NSDictionary *)d {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (d.count == 0) [ud removeObjectForKey:kInternalUseOverridesKey];
    else [ud setObject:d forKey:kInternalUseOverridesKey];
}

+ (NSString *)rg_keyForInternalUseSpecifier:(unsigned long long)specifier {
    return [NSString stringWithFormat:@"0x%016llx", specifier];
}

+ (SCIExpFlagOverride)internalUseOverrideForSpecifier:(unsigned long long)specifier {
    NSNumber *n = [self rg_loadInternalUseOverrides][[self rg_keyForInternalUseSpecifier:specifier]];
    return n ? (SCIExpFlagOverride)n.integerValue : SCIExpFlagOverrideOff;
}

+ (void)setInternalUseOverride:(SCIExpFlagOverride)o forSpecifier:(unsigned long long)specifier {
    NSMutableDictionary *d = [self rg_loadInternalUseOverrides];
    NSString *key = [self rg_keyForInternalUseSpecifier:specifier];
    if (o == SCIExpFlagOverrideOff) [d removeObjectForKey:key];
    else d[key] = @(o);
    [self rg_saveInternalUseOverrides:d];
}

+ (NSArray<NSNumber *> *)allOverriddenInternalUseSpecifiers {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in [self rg_loadInternalUseOverrides].allKeys) {
        unsigned long long value = 0;
        if ([key hasPrefix:@"0x"]) value = strtoull(key.UTF8String + 2, NULL, 16);
        else value = strtoull(key.UTF8String, NULL, 10);
        if (value) [out addObject:@(value)];
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        unsigned long long av = a.unsignedLongLongValue;
        unsigned long long bv = b.unsignedLongLongValue;
        if (av < bv) return NSOrderedAscending;
        if (av > bv) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

+ (void)resetAllInternalUseOverrides {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kInternalUseOverridesKey];
}

@end
