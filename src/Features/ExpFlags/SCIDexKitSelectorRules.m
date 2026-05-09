#import "SCIDexKitSelectorRules.h"

@implementation SCIDexKitSelectorRules

+ (NSArray<NSString *> *)ownerTokens {
    return @[@"experiment", @"feature", @"config", @"configuration", @"provider", @"gating", @"gate", @"rollout", @"settings", @"internal", @"dogfood", @"mobileconfig", @"launcher", @"autofill", @"prism", @"directnotes", @"directnote", @"quicksnap", @"homecoming", @"liquidglass", @"tabbar", @"friendmap", @"notes", @"identityswitcher", @"cta"];
}
+ (NSArray<NSString *> *)strongOwnerTokens {
    return @[@"experiment", @"experimentation", @"gating", @"gate", @"config", @"configuration", @"provider", @"mobileconfig", @"autofill", @"prism", @"directnotes", @"directnote", @"quicksnap", @"homecoming", @"liquidglass", @"dogfood"];
}
+ (NSArray<NSString *> *)selectorTokens {
    return @[@"enabled", @"enable", @"eligible", @"available", @"availability", @"shouldshow", @"shouldenable", @"shoulduse", @"isprism", @"isliquidglass", @"homecoming", @"quicksnap", @"friendmap", @"dogfood"];
}
+ (NSArray<NSString *> *)rootGateTokens {
    return @[@"enabled", @"isenabled", @"shouldenable", @"shouldshow", @"eligible", @"iseligible", @"available", @"isavailable", @"supported", @"issupported", @"allowed", @"isallowed"];
}
+ (NSArray<NSString *> *)configOptionTokens {
    return @[@"enable", @"disable", @"default", @"defaulton", @"defaultoff", @"toggle", @"sound", @"caption", @"scrubber", @"ufi", @"preview", @"spinner", @"positioning", @"bottomsheet", @"global", @"sticky"];
}
+ (NSArray<NSString *> *)variantTokens {
    return @[@"variant", @"treatment", @"bucket", @"firstswipe", @"preview", @"defaulton", @"defaultoff", @"recap", @"up leveling", @"upleveling"];
}
+ (NSArray<NSString *> *)uiStateTokens {
    return @[@"selected", @"highlighted", @"visible", @"hidden", @"loading", @"refreshing", @"animating", @"presented", @"dismissed", @"dragging", @"scrolling", @"decelerating", @"tracking", @"editing", @"focused", @"expanded", @"collapsed", @"mounted", @"appearing", @"disappearing", @"window", @"superview", @"layout", @"firstresponder", @"accessibility", @"playing"];
}
+ (NSSet<NSString *> *)excludedSelectors {
    return [NSSet setWithArray:@[@"isEmpty", @"empty", @"isVisible", @"visible", @"isHidden", @"hidden", @"isSelected", @"selected", @"isHighlighted", @"highlighted", @"isLoading", @"loading", @"isRefreshing", @"refreshing", @"isAnimating", @"animating", @"isAccessibilityElement", @"supportsSecureCoding", @"prefersNavigationBarHidden", @"prefersStatusBarHidden", @"becomeFirstResponder", @"resignFirstResponder", @"scrollEnabled", @"isScrollEnabled", @"userInteractionEnabled", @"isUserInteractionEnabled", @"requiresPageWorld", @"isPlaying", @"playing"]];
}
+ (NSArray<NSString *> *)excludedClassPrefixes { return @[@"UI", @"NS", @"WK", @"AV", @"CA", @"NSURL", @"SwiftUI"]; }
+ (NSArray<NSString *> *)visualOwnerTokens { return @[@"view", @"cell", @"button", @"label", @"imageview", @"scroll", @"collection", @"table", @"gesture", @"layer", @"spinner", @"hud", @"controller"]; }

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
    NSInteger score = 0;
    BOOL excluded = [self isExcludedClassName:className selector:selector];
    if (excluded) score -= 80;
    if ([self containsAny:className tokens:[self ownerTokens]]) score += 10;
    if ([self containsAny:className tokens:[self strongOwnerTokens]]) score += 20;
    if ([self containsAny:selector tokens:[self selectorTokens]]) score += 8;
    NSString *ls = selector.lowercaseString ?: @"";
    if ([ls hasPrefix:@"should"] || [ls hasPrefix:@"is"] || [ls hasPrefix:@"has"] || [ls hasPrefix:@"can"]) score += 2;
    if ([self containsAny:selector tokens:[self uiStateTokens]]) score -= 35;
    if ([self containsAny:className tokens:[self visualOwnerTokens]] && [self containsAny:selector tokens:[self uiStateTokens]]) score -= 35;
    if ([ls isEqualToString:@"isenabled"] || [ls isEqualToString:@"enabled"]) score -= 15;
    if ([self containsAny:selector tokens:[self configOptionTokens]]) score += 4;
    if ([self containsAny:selector tokens:[self variantTokens]]) score -= 6;
    return score;
}
+ (BOOL)isCuratedClassName:(NSString *)className selector:(NSString *)selector {
    return [self curatedScoreForClassName:className selector:selector] >= 10;
}

+ (NSString *)familyKeyForClassName:(NSString *)className selector:(NSString *)selector {
    NSString *ls = selector.lowercaseString ?: @"";
    NSString *family = @"misc";
    if ([ls containsString:@"firstswipepreview"]) family = @"first-swipe-preview";
    else if ([ls containsString:@"preview"]) family = @"preview";
    else if ([ls containsString:@"bottomsheet"]) family = @"bottomsheet";
    else if ([ls containsString:@"globalsound"] || [ls containsString:@"sound"]) family = @"sound";
    else if ([ls containsString:@"caption"]) family = @"caption";
    else if ([ls containsString:@"scrubber"]) family = @"scrubber";
    else if ([ls containsString:@"spinner"]) family = @"spinner";
    else if ([ls containsString:@"homecoming"]) family = @"homecoming";
    else if ([ls containsString:@"quicksnap"]) family = @"quicksnap";
    else if ([ls containsString:@"friendmap"]) family = @"friendmap";
    else if ([ls containsString:@"liquidglass"]) family = @"liquidglass";
    else if ([ls containsString:@"prism"]) family = @"prism";
    return [NSString stringWithFormat:@"%@|%@", className ?: @"?", family];
}

+ (BOOL)isHiddenNoiseClassification:(NSDictionary<NSString *, id> *)classification {
    if (![classification isKindOfClass:NSDictionary.class]) return NO;
    NSString *category = [classification[@"semanticCategory"] isKindOfClass:NSString.class] ? [classification[@"semanticCategory"] lowercaseString] : @"";
    NSInteger risk = [classification[@"riskLevel"] respondsToSelector:@selector(integerValue)] ? [classification[@"riskLevel"] integerValue] : 0;
    BOOL observe = [classification[@"observeRecommended"] respondsToSelector:@selector(boolValue)] ? [classification[@"observeRecommended"] boolValue] : YES;
    if (risk >= 4) return YES;
    if (!observe) return YES;
    if ([category isEqualToString:@"ui-state"] ||
        [category isEqualToString:@"lifecycle-state"] ||
        [category isEqualToString:@"loading-state"] ||
        [category isEqualToString:@"selection-state"]) return YES;
    return NO;
}

+ (BOOL)shouldHideNoisyClassName:(NSString *)className selector:(NSString *)selector imageBasename:(NSString *)imageBasename typeEncoding:(NSString *)typeEncoding {
    NSDictionary *c = [self classificationForClassName:className selector:selector imageBasename:imageBasename typeEncoding:typeEncoding];
    return [self isHiddenNoiseClassification:c];
}

+ (NSDictionary<NSString *, id> *)classificationForClassName:(NSString *)className selector:(NSString *)selector imageBasename:(NSString *)imageBasename typeEncoding:(NSString *)typeEncoding {
    NSString *lc = className.lowercaseString ?: @"";
    NSString *ls = selector.lowercaseString ?: @"";
    NSInteger score = [self curatedScoreForClassName:className selector:selector];
    NSString *category = @"unknown-bool";
    NSInteger risk = 2;
    BOOL observe = YES;
    BOOL force = NO;
    BOOL batch = NO;
    NSMutableArray<NSString *> *reasons = [NSMutableArray array];

    BOOL strongOwner = [self containsAny:className tokens:[self strongOwnerTokens]];
    BOOL rootGate = [self containsAny:selector tokens:[self rootGateTokens]];
    BOOL uiState = [self containsAny:selector tokens:[self uiStateTokens]] || ([self containsAny:className tokens:[self visualOwnerTokens]] && [self containsAny:selector tokens:[self uiStateTokens]]);
    BOOL config = [self containsAny:selector tokens:[self configOptionTokens]] || [lc containsString:@"configuration"] || [lc containsString:@"config"];
    BOOL variant = [self containsAny:selector tokens:[self variantTokens]];
    BOOL debugInternal = [lc containsString:@"debug"] || [lc containsString:@"dogfood"] || [lc containsString:@"internal"] || [ls containsString:@"debug"] || [ls containsString:@"internal"];

    if (uiState || [self isExcludedClassName:className selector:selector]) {
        category = @"ui-state";
        risk = 4;
        observe = NO;
        force = NO;
        batch = NO;
        [reasons addObject:@"selector/class looks like transient UI or lifecycle state"];
    } else if (debugInternal) {
        category = @"debug-internal";
        risk = 2;
        observe = YES;
        force = rootGate;
        batch = NO;
        [reasons addObject:@"debug/internal/dogfood owner or selector"];
    } else if (strongOwner && rootGate && !variant) {
        category = @"feature-gate";
        risk = 1;
        observe = YES;
        force = YES;
        batch = YES;
        [reasons addObject:@"strong feature/config owner with root gate selector"];
    } else if (rootGate && strongOwner) {
        category = @"experiment-gate";
        risk = 1;
        observe = YES;
        force = YES;
        batch = YES;
        [reasons addObject:@"experiment-like root gate"];
    } else if (variant) {
        category = @"variant-option";
        risk = 3;
        observe = YES;
        force = NO;
        batch = NO;
        [reasons addObject:@"selector looks like variant/default/preview option"];
    } else if (config) {
        category = @"config-option";
        risk = 2;
        observe = YES;
        force = NO;
        batch = NO;
        [reasons addObject:@"configuration option; observe first"];
    } else if (rootGate) {
        category = @"eligibility-gate";
        risk = 2;
        observe = YES;
        force = score >= 20;
        batch = NO;
        [reasons addObject:@"root gate wording without strong owner confidence"];
    } else {
        category = @"unknown-bool";
        risk = 3;
        observe = YES;
        force = NO;
        batch = NO;
        [reasons addObject:@"generic BOOL; discovery only"];
    }

    if ([imageBasename isEqualToString:@"FBSharedFramework"]) [reasons addObject:@"FBSharedFramework"];
    [reasons addObject:[NSString stringWithFormat:@"score=%ld", (long)score]];

    return @{
        @"semanticCategory": category,
        @"riskLevel": @(risk),
        @"batchForceAllowed": @(batch),
        @"observeRecommended": @(observe),
        @"forceRecommended": @(force),
        @"classificationReason": [reasons componentsJoinedByString:@" · "],
        @"familyKey": [self familyKeyForClassName:className selector:selector]
    };
}

@end
