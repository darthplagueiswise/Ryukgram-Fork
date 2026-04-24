// Filtered dogfood/internal gates.
// Never forces all MobileConfig booleans. Only targets known employee/test-user specifiers.

#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <substrate.h>
#import <dlfcn.h>

static const unsigned long long kIGIsEmployeeA = 0x0081030f00000a95ULL;
static const unsigned long long kIGIsEmployeeB = 0x0081030f00010a96ULL;
static const unsigned long long kIGIsEmployeeOrTestUser = 0x008100b200000161ULL;

static BOOL RGEmployeeMCEnabled(void) { return [SCIUtils getBoolPref:@"igt_employee"]; }
static BOOL RGEmployeeOrTestUserMCEnabled(void) { return [SCIUtils getBoolPref:@"igt_employee_test_user"]; }
static BOOL RGInternalAppsGateEnabled(void) { return [SCIUtils getBoolPref:@"igt_internal"]; }
static BOOL RGObserveInternalUseEnabled(void) { return [SCIUtils getBoolPref:@"igt_internaluse_observer"]; }

static NSString *RGNameForKnownSpecifier(unsigned long long spec) {
    if (spec == kIGIsEmployeeA) return @"_ig_is_employee[0]";
    if (spec == kIGIsEmployeeB) return @"_ig_is_employee[1]";
    if (spec == kIGIsEmployeeOrTestUser) return @"_ig_is_employee_or_test_user";
    return nil;
}

static BOOL RGIsEmployeeSpecifier(unsigned long long spec) {
    return spec == kIGIsEmployeeA || spec == kIGIsEmployeeB;
}

static BOOL RGShouldForceSpecifier(unsigned long long spec) {
    if (RGEmployeeMCEnabled() && RGIsEmployeeSpecifier(spec)) return YES;
    if (RGEmployeeOrTestUserMCEnabled() && spec == kIGIsEmployeeOrTestUser) return YES;
    return NO;
}

static void RGRecordInternalBool(NSString *symbol, unsigned long long spec, BOOL original, BOOL forced) {
    NSString *known = RGNameForKnownSpecifier(spec);
    BOOL shouldRecord = RGObserveInternalUseEnabled() || known.length || forced;
    if (!shouldRecord) return;

    NSString *value = forced ? [NSString stringWithFormat:@"%@ -> FORCED YES", original ? @"YES" : @"NO"] : (original ? @"YES" : @"NO");
    NSString *selector = known.length ? [NSString stringWithFormat:@"%@ / %@", symbol, known] : symbol;
    [SCIExpFlags recordMCParamID:spec
                            type:SCIExpMCTypeBool
                    defaultValue:value
                     sourceClass:@"IGMobileConfigInternalUse"
                        selector:selector];
}

static void *RGFindSymbol(const char *machOSymbol) {
    if (!machOSymbol) return NULL;
    void *p = MSFindSymbol(NULL, machOSymbol);
    if (!p && machOSymbol[0] == '_') p = dlsym(RTLD_DEFAULT, machOSymbol + 1);
    if (!p) p = dlsym(RTLD_DEFAULT, machOSymbol);
    return p;
}

typedef BOOL (*RGMCBoolInternalFn)(id ctx, BOOL def, unsigned long long spec);
static RGMCBoolInternalFn orig_IGMCBoolInternal = NULL;
static RGMCBoolInternalFn orig_IGMCSessionlessBoolInternal = NULL;

static BOOL hook_IGMCBoolInternal(id ctx, BOOL def, unsigned long long spec) {
    BOOL original = orig_IGMCBoolInternal ? orig_IGMCBoolInternal(ctx, def, spec) : def;
    BOOL forced = RGShouldForceSpecifier(spec);
    RGRecordInternalBool(@"IGMobileConfigBooleanValueForInternalUse", spec, original, forced);
    return forced ? YES : original;
}

static BOOL hook_IGMCSessionlessBoolInternal(id ctx, BOOL def, unsigned long long spec) {
    BOOL original = orig_IGMCSessionlessBoolInternal ? orig_IGMCSessionlessBoolInternal(ctx, def, spec) : def;
    BOOL forced = RGShouldForceSpecifier(spec);
    RGRecordInternalBool(@"IGMobileConfigSessionlessBooleanValueForInternalUse", spec, original, forced);
    return forced ? YES : original;
}

typedef BOOL (*RGInternalAppsInstalledFn)(void);
static RGInternalAppsInstalledFn orig_InternalAppsInstalled = NULL;

static BOOL hook_InternalAppsInstalled(void) {
    if (RGInternalAppsGateEnabled()) {
        [SCIExpFlags recordMCParamID:0x1ULL
                                type:SCIExpMCTypeBool
                        defaultValue:@"FORCED YES"
                         sourceClass:@"IGInternalAppsGate"
                            selector:@"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18"];
        return YES;
    }
    return orig_InternalAppsInstalled ? orig_InternalAppsInstalled() : NO;
}

static void RGInstallFunction(const char *symbol, void *replacement, void **original) {
    void *target = RGFindSymbol(symbol);
    if (!target) {
        SCILog(@"Dogfood gate symbol not found: %s", symbol);
        return;
    }
    MSHookFunction(target, replacement, original);
    SCILog(@"Dogfood gate hook installed: %s", symbol);
}

// Manual actions exposed to the settings menu. These are intentionally not run at launch.
extern "C" void RGTryUpdateMobileConfigAction(void) {
    typedef void (*TryFn)(id completion);
    TryFn fn = (TryFn)RGFindSymbol("_IGMobileConfigTryUpdateConfigsWithCompletion");
    if (!fn) {
        [SCIUtils showErrorHUDWithDescription:@"IGMobileConfigTryUpdateConfigsWithCompletion not found"];
        return;
    }

    void (^completion)(id) = ^(id result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showToastForDuration:3.0 title:@"MobileConfig try update completed" subtitle:result ? [result description] : nil];
        });
    };
    fn(completion);
    [SCIUtils showToastForDuration:2.0 title:@"MobileConfig try update requested"];
}

extern "C" void RGForceUpdateMobileConfigAction(void) {
    typedef void (*ForceFn)(void);
    ForceFn fn = (ForceFn)RGFindSymbol("_IGMobileConfigForceUpdateConfigs");
    if (!fn) {
        [SCIUtils showErrorHUDWithDescription:@"IGMobileConfigForceUpdateConfigs not found"];
        return;
    }

    fn();
    [SCIUtils showToastForDuration:2.0 title:@"MobileConfig force update requested"];
}

%ctor {
    BOOL needsHooks = RGEmployeeMCEnabled() || RGEmployeeOrTestUserMCEnabled() || RGInternalAppsGateEnabled() || RGObserveInternalUseEnabled();
    if (!needsHooks) return;

    RGInstallFunction("_IGMobileConfigBooleanValueForInternalUse", (void *)hook_IGMCBoolInternal, (void **)&orig_IGMCBoolInternal);
    RGInstallFunction("_IGMobileConfigSessionlessBooleanValueForInternalUse", (void *)hook_IGMCSessionlessBoolInternal, (void **)&orig_IGMCSessionlessBoolInternal);
    RGInstallFunction("_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)hook_InternalAppsInstalled, (void **)&orig_InternalAppsInstalled);
}
