#import "SCIAutofillInternalDevMode.h"
#import "../../Utils.h"
#import <objc/runtime.h>

static NSString *const kAutofillDebugFooterToggleKey = @"sci_dev_autofill_debug_footer";
static NSString *const kAutofillBloksModeToggleKey  = @"sci_dev_autofill_force_bloks";
static NSString *const kAutofillBloksPrefetchToggleKey = @"sci_dev_autofill_bloks_prefetch";

static NSString *const kIGAutofillDebugFooterDefaultsKey = @"autofill_internal_settings_debug_footer_enabled";
static NSString *const kIGAutofillForceBloksDefaultsKey = @"autofill_internal_settings_force_bloks_experience";
static NSString *const kIGAutofillBloksPrefetchDefaultsKey = @"autofill_internal_settings_bloks_prefetch_enabled";
static NSString *const kIGAutofillHideBloksIndicatorDefaultsKey = @"autofill_internal_settings_hide_bloks_view_indicator";

@implementation SCIAutofillInternalDevMode

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kAutofillDebugFooterToggleKey: @(NO),
        kAutofillBloksModeToggleKey: @(NO),
        kAutofillBloksPrefetchToggleKey: @(NO),
    }];
}

+ (Class)autofillSettingsClass {
    return NSClassFromString(@"AutofillInternalSettingsInstagram.IGAutofillInternalSettings");
}

+ (NSString *)returnTypeForMethod:(Method)m {
    if (!m) return @"missing";
    char rt[128] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return @(rt);
}

+ (NSString *)availabilityForSelectorName:(NSString *)selectorName {
    Class cls = [self autofillSettingsClass];
    if (!cls) return @"class-missing";

    SEL sel = NSSelectorFromString(selectorName);
    Method classMethod = class_getClassMethod(cls, sel);
    if (classMethod) {
        return [NSString stringWithFormat:@"class · args=%u · ret=%@",
                method_getNumberOfArguments(classMethod),
                [self returnTypeForMethod:classMethod]];
    }

    Method instanceMethod = class_getInstanceMethod(cls, sel);
    if (instanceMethod) {
        return [NSString stringWithFormat:@"instance · args=%u · ret=%@",
                method_getNumberOfArguments(instanceMethod),
                [self returnTypeForMethod:instanceMethod]];
    }

    return @"missing";
}

+ (NSString *)valueDescriptionForDefaultsKey:(NSString *)key {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id obj = [ud objectForKey:key];
    if (!obj) return @"unset";
    return [obj description] ?: @"?";
}

+ (void)applyEnabledToggles {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    if ([SCIUtils getBoolPref:kAutofillDebugFooterToggleKey]) {
        [ud setBool:YES forKey:kIGAutofillDebugFooterDefaultsKey];
    }

    if ([SCIUtils getBoolPref:kAutofillBloksModeToggleKey]) {
        // The app exposes setForceBloksExperienceOn / Off / clear around this key.
        // Avoid calling the Swift instance directly here; writing the backing key
        // is safer for sideloaded runtime testing.
        [ud setInteger:1 forKey:kIGAutofillForceBloksDefaultsKey];
    }

    if ([SCIUtils getBoolPref:kAutofillBloksPrefetchToggleKey]) {
        [ud setBool:YES forKey:kIGAutofillBloksPrefetchDefaultsKey];
    }

    [ud synchronize];
}

+ (NSDictionary<NSString *, id> *)statusSnapshot {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    Class cls = [self autofillSettingsClass];
    d[@"class"] = cls ? NSStringFromClass(cls) : @"missing";
    d[@"mode"] = @"safe-defaults-only";

    NSArray<NSString *> *selectors = @[
        @"setDebugFooterEnabledWithEnabled:",
        @"getDebugFooterEnabled",
        @"setForceBloksExperienceOn",
        @"setForceBloksExperienceOff",
        @"clearForceBloksExperience",
        @"getForceBloksExperience",
        @"isForceBloksExperienceOn",
        @"isForceBloksExperienceOff",
        @"shouldForceBloksExperienceOnOrOff",
        @"setBloksPrefetchEnabledWithEnabled:",
        @"isBloksPrefetchEnabled"
    ];

    for (NSString *selectorName in selectors) {
        d[[@"has_" stringByAppendingString:selectorName]] = [self availabilityForSelectorName:selectorName];
    }

    d[@"debugFooter"] = [self valueDescriptionForDefaultsKey:kIGAutofillDebugFooterDefaultsKey];
    d[@"forceBloks"] = [self valueDescriptionForDefaultsKey:kIGAutofillForceBloksDefaultsKey];
    d[@"bloksPrefetch"] = [self valueDescriptionForDefaultsKey:kIGAutofillBloksPrefetchDefaultsKey];
    d[@"hideBloksIndicator"] = [self valueDescriptionForDefaultsKey:kIGAutofillHideBloksIndicatorDefaultsKey];

    return d;
}

+ (NSString *)statusText {
    NSDictionary *d = [self statusSnapshot];
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"class: %@", d[@"class"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"mode: %@", d[@"mode"] ?: @"unknown"]];
    [lines addObject:[NSString stringWithFormat:@"debugFooter defaults: %@", d[@"debugFooter"] ?: @"unset"]];
    [lines addObject:[NSString stringWithFormat:@"forceBloks defaults: %@", d[@"forceBloks"] ?: @"unset"]];
    [lines addObject:[NSString stringWithFormat:@"bloksPrefetch defaults: %@", d[@"bloksPrefetch"] ?: @"unset"]];
    [lines addObject:[NSString stringWithFormat:@"hideBloksIndicator defaults: %@", d[@"hideBloksIndicator"] ?: @"unset"]];
    [lines addObject:@""];
    [lines addObject:@"selector availability (no calls):"];
    [lines addObject:[NSString stringWithFormat:@"setDebugFooterEnabledWithEnabled: %@", d[@"has_setDebugFooterEnabledWithEnabled:"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"getDebugFooterEnabled: %@", d[@"has_getDebugFooterEnabled"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"setForceBloksExperienceOn: %@", d[@"has_setForceBloksExperienceOn"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"setForceBloksExperienceOff: %@", d[@"has_setForceBloksExperienceOff"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"clearForceBloksExperience: %@", d[@"has_clearForceBloksExperience"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"getForceBloksExperience: %@", d[@"has_getForceBloksExperience"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"isForceBloksExperienceOn: %@", d[@"has_isForceBloksExperienceOn"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"isForceBloksExperienceOff: %@", d[@"has_isForceBloksExperienceOff"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"shouldForceBloksExperienceOnOrOff: %@", d[@"has_shouldForceBloksExperienceOnOrOff"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"setBloksPrefetchEnabledWithEnabled: %@", d[@"has_setBloksPrefetchEnabledWithEnabled:"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"isBloksPrefetchEnabled: %@", d[@"has_isBloksPrefetchEnabled"] ?: @"missing"]];
    return [lines componentsJoinedByString:@"\n"];
}

@end
