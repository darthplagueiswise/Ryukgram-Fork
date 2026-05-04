#import "SCIDexKitSelectorRules.h"

@implementation SCIDexKitSelectorRules

+ (NSArray<NSString *> *)ownerTokens {
    return @[@"experiment", @"feature", @"config", @"provider", @"gating", @"rollout", @"settings", @"internal", @"dogfood", @"mobileconfig", @"launcher", @"autofill", @"prism", @"directnotes", @"quicksnap", @"homecoming", @"liquidglass", @"tabbar", @"friendmap", @"notes", @"identityswitcher", @"cta"];
}
+ (NSArray<NSString *> *)strongOwnerTokens {
    return @[@"experiment", @"gating", @"config", @"provider", @"mobileconfig", @"autofill", @"prism", @"directnotes", @"quicksnap", @"homecoming", @"liquidglass", @"dogfood"];
}
+ (NSArray<NSString *> *)selectorTokens {
    return @[@"enabled", @"eligible", @"available", @"shouldshow", @"shouldenable", @"isprism", @"isliquidglass", @"homecoming", @"quicksnap"];
}
+ (NSSet<NSString *> *)excludedSelectors {
    return [NSSet setWithArray:@[@"isEmpty", @"isVisible", @"isHidden", @"isSelected", @"supportsSecureCoding", @"isAccessibilityElement", @"prefersNavigationBarHidden", @"prefersStatusBarHidden", @"becomeFirstResponder", @"resignFirstResponder", @"scrollEnabled", @"isScrollEnabled", @"userInteractionEnabled", @"isUserInteractionEnabled", @"requiresPageWorld", @"isPlaying", @"isHighlighted"]];
}
+ (NSArray<NSString *> *)excludedClassPrefixes { return @[@"UI", @"NS", @"WK", @"AV", @"CA", @"NSURL", @"SwiftUI"]; }

+ (BOOL)containsAny:(NSString *)s tokens:(NSArray<NSString *> *)tokens {
    NSString *l = s.lowercaseString ?: @"";
    for (NSString *t in tokens) if ([l containsString:t.lowercaseString]) return YES;
    return NO;
}
+ (BOOL)selectorLooksBoolLegacyC:(NSString *)selector {
    NSString *s = selector.lowercaseString ?: @"";
    return [s hasPrefix:@"is"] || [s hasPrefix:@"should"] || [s hasPrefix:@"has"] || [s hasPrefix:@"can"] || [s containsString:@"enabled"] || [s containsString:@"eligible"];
}
+ (BOOL)isExcludedClassName:(NSString *)className selector:(NSString *)selector {
    if ([[self excludedSelectors] containsObject:selector ?: @""]) return YES;
    for (NSString *p in [self excludedClassPrefixes]) if ([className hasPrefix:p]) return YES;
    return NO;
}
+ (NSInteger)curatedScoreForClassName:(NSString *)className selector:(NSString *)selector {
    if ([self isExcludedClassName:className selector:selector]) return NSIntegerMin;
    NSInteger score = 0;
    if ([self containsAny:className tokens:[self ownerTokens]]) score += 10;
    if ([self containsAny:className tokens:[self strongOwnerTokens]]) score += 20;
    if ([self containsAny:selector tokens:[self selectorTokens]]) score += 5;
    NSString *ls = selector.lowercaseString ?: @"";
    if ([ls isEqualToString:@"isenabled"] || [ls isEqualToString:@"enabled"]) score -= 15;
    if ([ls hasPrefix:@"should"] || [ls hasPrefix:@"is"] || [ls hasPrefix:@"has"]) score += 2;
    return score;
}
+ (BOOL)isCuratedClassName:(NSString *)className selector:(NSString *)selector {
    return [self curatedScoreForClassName:className selector:selector] >= 10;
}

@end
