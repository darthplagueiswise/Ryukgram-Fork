#import "SCIAutofillInternalDevMode.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kAutofillDebugFooterKey = @"sci_dev_autofill_debug_footer";
static NSString *const kAutofillForceBloksKey  = @"sci_dev_autofill_force_bloks";
static NSString *const kAutofillBloksPrefetchKey = @"sci_dev_autofill_bloks_prefetch";

@implementation SCIAutofillInternalDevMode

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kAutofillDebugFooterKey: @(NO),
        kAutofillForceBloksKey: @(NO),
        kAutofillBloksPrefetchKey: @(NO),
    }];
}

+ (Class)autofillSettingsClass {
    return NSClassFromString(@"AutofillInternalSettingsInstagram.IGAutofillInternalSettings");
}

+ (BOOL)classResponds:(SEL)sel {
    Class cls = [self autofillSettingsClass];
    return cls && [cls respondsToSelector:sel];
}

+ (void)sendVoidSelector:(SEL)sel {
    Class cls = [self autofillSettingsClass];
    if (!cls || ![cls respondsToSelector:sel]) return;
    ((void (*)(Class, SEL))objc_msgSend)(cls, sel);
}

+ (void)sendBoolSelector:(SEL)sel value:(BOOL)value {
    Class cls = [self autofillSettingsClass];
    if (!cls || ![cls respondsToSelector:sel]) return;
    ((void (*)(Class, SEL, BOOL))objc_msgSend)(cls, sel, value);
}

+ (id)sendObjectGetter:(SEL)sel {
    Class cls = [self autofillSettingsClass];
    if (!cls || ![cls respondsToSelector:sel]) return nil;
    return ((id (*)(Class, SEL))objc_msgSend)(cls, sel);
}

+ (BOOL)sendBoolGetter:(SEL)sel fallback:(BOOL)fallback {
    Class cls = [self autofillSettingsClass];
    if (!cls || ![cls respondsToSelector:sel]) return fallback;
    return ((BOOL (*)(Class, SEL))objc_msgSend)(cls, sel);
}

+ (void)applyEnabledToggles {
    if (![self autofillSettingsClass]) return;

    if ([SCIUtils getBoolPref:kAutofillDebugFooterKey]) {
        [self sendBoolSelector:NSSelectorFromString(@"setDebugFooterEnabledWithEnabled:") value:YES];
    }

    if ([SCIUtils getBoolPref:kAutofillForceBloksKey]) {
        [self sendVoidSelector:NSSelectorFromString(@"setForceBloksExperienceOn")];
    }

    if ([SCIUtils getBoolPref:kAutofillBloksPrefetchKey]) {
        [self sendBoolSelector:NSSelectorFromString(@"setBloksPrefetchEnabledWithEnabled:") value:YES];
    }
}

+ (NSString *)stringForObject:(id)obj {
    if (!obj || obj == (id)kCFNull) return @"nil";
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj respondsToSelector:@selector(stringValue)]) return [obj stringValue];
    return [obj description] ?: @"?";
}

+ (NSDictionary<NSString *, id> *)statusSnapshot {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    Class cls = [self autofillSettingsClass];
    d[@"class"] = cls ? NSStringFromClass(cls) : @"missing";
    d[@"has_setDebugFooterEnabledWithEnabled"] = @([self classResponds:NSSelectorFromString(@"setDebugFooterEnabledWithEnabled:")]);
    d[@"has_getDebugFooterEnabled"] = @([self classResponds:NSSelectorFromString(@"getDebugFooterEnabled")]);
    d[@"has_setForceBloksExperienceOn"] = @([self classResponds:NSSelectorFromString(@"setForceBloksExperienceOn")]);
    d[@"has_setForceBloksExperienceOff"] = @([self classResponds:NSSelectorFromString(@"setForceBloksExperienceOff")]);
    d[@"has_getForceBloksExperience"] = @([self classResponds:NSSelectorFromString(@"getForceBloksExperience")]);
    d[@"has_isForceBloksExperienceOn"] = @([self classResponds:NSSelectorFromString(@"isForceBloksExperienceOn")]);
    d[@"has_isForceBloksExperienceOff"] = @([self classResponds:NSSelectorFromString(@"isForceBloksExperienceOff")]);
    d[@"has_shouldForceBloksExperienceOnOrOff"] = @([self classResponds:NSSelectorFromString(@"shouldForceBloksExperienceOnOrOff")]);
    d[@"has_setBloksPrefetchEnabledWithEnabled"] = @([self classResponds:NSSelectorFromString(@"setBloksPrefetchEnabledWithEnabled:")]);
    d[@"has_isBloksPrefetchEnabled"] = @([self classResponds:NSSelectorFromString(@"isBloksPrefetchEnabled")]);

    if (cls) {
        if ([self classResponds:NSSelectorFromString(@"getDebugFooterEnabled")]) {
            d[@"getDebugFooterEnabled"] = @([self sendBoolGetter:NSSelectorFromString(@"getDebugFooterEnabled") fallback:NO]);
        }
        if ([self classResponds:NSSelectorFromString(@"getForceBloksExperience")]) {
            d[@"getForceBloksExperience"] = [self stringForObject:[self sendObjectGetter:NSSelectorFromString(@"getForceBloksExperience")]];
        }
        if ([self classResponds:NSSelectorFromString(@"isForceBloksExperienceOn")]) {
            d[@"isForceBloksExperienceOn"] = @([self sendBoolGetter:NSSelectorFromString(@"isForceBloksExperienceOn") fallback:NO]);
        }
        if ([self classResponds:NSSelectorFromString(@"isForceBloksExperienceOff")]) {
            d[@"isForceBloksExperienceOff"] = @([self sendBoolGetter:NSSelectorFromString(@"isForceBloksExperienceOff") fallback:NO]);
        }
        if ([self classResponds:NSSelectorFromString(@"shouldForceBloksExperienceOnOrOff")]) {
            d[@"shouldForceBloksExperienceOnOrOff"] = @([self sendBoolGetter:NSSelectorFromString(@"shouldForceBloksExperienceOnOrOff") fallback:NO]);
        }
        if ([self classResponds:NSSelectorFromString(@"isBloksPrefetchEnabled")]) {
            d[@"isBloksPrefetchEnabled"] = @([self sendBoolGetter:NSSelectorFromString(@"isBloksPrefetchEnabled") fallback:NO]);
        }
    }
    return d;
}

+ (NSString *)statusText {
    NSDictionary *d = [self statusSnapshot];
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"class: %@", d[@"class"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"debugFooter: %@", d[@"getDebugFooterEnabled"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"forceBloks: %@", d[@"getForceBloksExperience"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"forceBloksOn: %@", d[@"isForceBloksExperienceOn"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"forceBloksOff: %@", d[@"isForceBloksExperienceOff"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"shouldForceOnOrOff: %@", d[@"shouldForceBloksExperienceOnOrOff"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"bloksPrefetch: %@", d[@"isBloksPrefetchEnabled"] ?: @"unavailable"]];
    return [lines componentsJoinedByString:@"\n"];
}

@end
