#import "SCIAutofillInternalDevMode.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kAutofillDebugFooterKey = @"sci_dev_autofill_debug_footer";
static NSString *const kAutofillBloksModeKey  = @"sci_dev_autofill_force_bloks";
static NSString *const kAutofillBloksPrefetchKey = @"sci_dev_autofill_bloks_prefetch";

static id gAutofillSettingsInstance = nil;

@implementation SCIAutofillInternalDevMode

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kAutofillDebugFooterKey: @(NO),
        kAutofillBloksModeKey: @(NO),
        kAutofillBloksPrefetchKey: @(NO),
    }];
}

+ (Class)autofillSettingsClass {
    return NSClassFromString(@"AutofillInternalSettingsInstagram.IGAutofillInternalSettings");
}

+ (id)autofillSettingsInstance {
    if (gAutofillSettingsInstance) return gAutofillSettingsInstance;
    Class cls = [self autofillSettingsClass];
    if (!cls) return nil;
    @try {
        id obj = ((id (*)(Class, SEL))objc_msgSend)(cls, @selector(alloc));
        if (obj && [obj respondsToSelector:@selector(init)]) {
            obj = ((id (*)(id, SEL))objc_msgSend)(obj, @selector(init));
        }
        gAutofillSettingsInstance = obj;
    } @catch (__unused NSException *e) {
        gAutofillSettingsInstance = nil;
    }
    return gAutofillSettingsInstance;
}

+ (Method)methodForSelector:(SEL)sel isClassMethod:(BOOL *)isClassMethod {
    Class cls = [self autofillSettingsClass];
    if (!cls || !sel) return NULL;
    Method m = class_getClassMethod(cls, sel);
    if (m) {
        if (isClassMethod) *isClassMethod = YES;
        return m;
    }
    m = class_getInstanceMethod(cls, sel);
    if (m) {
        if (isClassMethod) *isClassMethod = NO;
        return m;
    }
    return NULL;
}

+ (id)targetForSelector:(SEL)sel method:(Method *)outMethod isClassMethod:(BOOL *)outIsClassMethod {
    BOOL isClassMethod = NO;
    Method m = [self methodForSelector:sel isClassMethod:&isClassMethod];
    if (!m) return nil;
    if (outMethod) *outMethod = m;
    if (outIsClassMethod) *outIsClassMethod = isClassMethod;
    if (isClassMethod) return [self autofillSettingsClass];
    id instance = [self autofillSettingsInstance];
    return (instance && [instance respondsToSelector:sel]) ? instance : nil;
}

+ (NSString *)returnTypeForMethod:(Method)m {
    if (!m) return @"missing";
    char rt[128] = {0};
    method_getReturnType(m, rt, sizeof(rt));
    return @(rt);
}

+ (NSString *)availabilityForSelectorName:(NSString *)selectorName {
    SEL sel = NSSelectorFromString(selectorName);
    BOOL isClassMethod = NO;
    Method m = [self methodForSelector:sel isClassMethod:&isClassMethod];
    if (!m) return @"missing";
    return [NSString stringWithFormat:@"%@ · args=%u · ret=%@", isClassMethod ? @"class" : @"instance", method_getNumberOfArguments(m), [self returnTypeForMethod:m]];
}

+ (BOOL)sendVoidSelector:(SEL)sel {
    Method m = NULL;
    id target = [self targetForSelector:sel method:&m isClassMethod:NULL];
    if (!target || !m || method_getNumberOfArguments(m) != 2) return NO;
    ((void (*)(id, SEL))objc_msgSend)(target, sel);
    return YES;
}

+ (BOOL)sendBoolSelector:(SEL)sel value:(BOOL)value {
    Method m = NULL;
    id target = [self targetForSelector:sel method:&m isClassMethod:NULL];
    if (!target || !m || method_getNumberOfArguments(m) != 3) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(target, sel, value);
    return YES;
}

+ (NSString *)stringForObject:(id)obj {
    if (!obj || obj == (id)kCFNull) return @"nil";
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj respondsToSelector:@selector(stringValue)]) return [obj stringValue];
    return [obj description] ?: @"?";
}

+ (NSString *)callNoArgSelectorName:(NSString *)selectorName {
    SEL sel = NSSelectorFromString(selectorName);
    Method m = NULL;
    id target = [self targetForSelector:sel method:&m isClassMethod:NULL];
    if (!target || !m) return @"unavailable";
    unsigned int argc = method_getNumberOfArguments(m);
    NSString *ret = [self returnTypeForMethod:m];
    if (argc != 2) return [NSString stringWithFormat:@"available(args=%u ret=%@)", argc, ret];
    const char *r = ret.UTF8String;
    if (!r || !r[0]) return @"available(ret=?)";
    @try {
        if (r[0] == 'B' || r[0] == 'c') {
            BOOL v = ((BOOL (*)(id, SEL))objc_msgSend)(target, sel);
            return v ? @"YES" : @"NO";
        }
        if (r[0] == '@') {
            id v = ((id (*)(id, SEL))objc_msgSend)(target, sel);
            return [self stringForObject:v];
        }
        if (r[0] == 'q' || r[0] == 'i' || r[0] == 's' || r[0] == 'l' || r[0] == 'Q' || r[0] == 'I' || r[0] == 'S' || r[0] == 'L') {
            long long v = ((long long (*)(id, SEL))objc_msgSend)(target, sel);
            return [NSString stringWithFormat:@"%lld", v];
        }
        return [NSString stringWithFormat:@"available(ret=%@)", ret];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"exception:%@", e.name ?: @"unknown"];
    }
}

+ (void)applyEnabledToggles {
    if (![self autofillSettingsClass]) return;
    if ([SCIUtils getBoolPref:kAutofillDebugFooterKey]) {
        [self sendBoolSelector:NSSelectorFromString(@"setDebugFooterEnabledWithEnabled:") value:YES];
    }
    if ([SCIUtils getBoolPref:kAutofillBloksModeKey]) {
        [self sendVoidSelector:NSSelectorFromString(@"setForceBloksExperienceOn")];
    }
    if ([SCIUtils getBoolPref:kAutofillBloksPrefetchKey]) {
        [self sendBoolSelector:NSSelectorFromString(@"setBloksPrefetchEnabledWithEnabled:") value:YES];
    }
}

+ (NSDictionary<NSString *, id> *)statusSnapshot {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    Class cls = [self autofillSettingsClass];
    id instance = [self autofillSettingsInstance];
    d[@"class"] = cls ? NSStringFromClass(cls) : @"missing";
    d[@"instance"] = instance ? [NSString stringWithFormat:@"%@", instance] : @"missing";
    NSArray<NSString *> *selectors = @[
        @"setDebugFooterEnabledWithEnabled:", @"getDebugFooterEnabled",
        @"setForceBloksExperienceOn", @"setForceBloksExperienceOff", @"clearForceBloksExperience",
        @"getForceBloksExperience", @"isForceBloksExperienceOn", @"isForceBloksExperienceOff", @"shouldForceBloksExperienceOnOrOff",
        @"setBloksPrefetchEnabledWithEnabled:", @"isBloksPrefetchEnabled"
    ];
    for (NSString *selectorName in selectors) {
        d[[@"has_" stringByAppendingString:selectorName]] = [self availabilityForSelectorName:selectorName];
    }
    d[@"getDebugFooterEnabled"] = [self callNoArgSelectorName:@"getDebugFooterEnabled"];
    d[@"getForceBloksExperience"] = [self callNoArgSelectorName:@"getForceBloksExperience"];
    d[@"isForceBloksExperienceOn"] = [self callNoArgSelectorName:@"isForceBloksExperienceOn"];
    d[@"isForceBloksExperienceOff"] = [self callNoArgSelectorName:@"isForceBloksExperienceOff"];
    d[@"shouldForceBloksExperienceOnOrOff"] = [self callNoArgSelectorName:@"shouldForceBloksExperienceOnOrOff"];
    d[@"isBloksPrefetchEnabled"] = [self callNoArgSelectorName:@"isBloksPrefetchEnabled"];
    return d;
}

+ (NSString *)statusText {
    NSDictionary *d = [self statusSnapshot];
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"class: %@", d[@"class"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"instance: %@", d[@"instance"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"debugFooter: %@", d[@"getDebugFooterEnabled"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"forceBloks: %@", d[@"getForceBloksExperience"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"forceBloksOn: %@", d[@"isForceBloksExperienceOn"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"forceBloksOff: %@", d[@"isForceBloksExperienceOff"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"shouldForceOnOrOff: %@", d[@"shouldForceBloksExperienceOnOrOff"] ?: @"unavailable"]];
    [lines addObject:[NSString stringWithFormat:@"bloksPrefetch: %@", d[@"isBloksPrefetchEnabled"] ?: @"unavailable"]];
    [lines addObject:@""];
    [lines addObject:@"selector availability:"];
    [lines addObject:[NSString stringWithFormat:@"setDebugFooterEnabledWithEnabled: %@", d[@"has_setDebugFooterEnabledWithEnabled:"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"getDebugFooterEnabled: %@", d[@"has_getDebugFooterEnabled"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"setForceBloksExperienceOn: %@", d[@"has_setForceBloksExperienceOn"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"getForceBloksExperience: %@", d[@"has_getForceBloksExperience"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"isForceBloksExperienceOn: %@", d[@"has_isForceBloksExperienceOn"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"isForceBloksExperienceOff: %@", d[@"has_isForceBloksExperienceOff"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"setBloksPrefetchEnabledWithEnabled: %@", d[@"has_setBloksPrefetchEnabledWithEnabled:"] ?: @"missing"]];
    [lines addObject:[NSString stringWithFormat:@"isBloksPrefetchEnabled: %@", d[@"has_isBloksPrefetchEnabled"] ?: @"missing"]];
    return [lines componentsJoinedByString:@"\n"];
}

@end
