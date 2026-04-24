#import "../../Utils.h"
#import "SCIExpFlags.h"
#include "../../../modules/fishhook/fishhook.h"

static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL; // ig_is_employee_or_test_user

static BOOL rgEmployeeMasterEnabled(void) { return [SCIUtils getBoolPref:@"igt_employee"]; }
static BOOL rgEmployeeMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_mc"]; }
static BOOL rgEmployeeOrTestUserMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"]; }
static BOOL rgInternalObserverEnabled(void) { return [SCIUtils getBoolPref:@"igt_internaluse_observer"]; }

static BOOL rgHasManualInternalUseOverrides(void) { return [SCIExpFlags allOverriddenInternalUseSpecifiers].count > 0; }

static BOOL rgShouldInstallInternalModeHooks(void) {
    return rgEmployeeMasterEnabled() ||
           rgEmployeeMCEnabled() ||
           rgEmployeeOrTestUserMCEnabled() ||
           [SCIUtils getBoolPref:@"igt_internal_apps_gate"] ||
           rgInternalObserverEnabled() ||
           rgHasManualInternalUseOverrides();
}

static BOOL specifierMatchesEmployee(unsigned long long specifier) {
    if (specifier == kIGMCEmployeeSpecifierA || specifier == kIGMCEmployeeSpecifierB) return rgEmployeeMCEnabled();
    if (specifier == kIGMCEmployeeOrTestUserSpecifier) return rgEmployeeOrTestUserMCEnabled();
    return NO;
}

static NSString *specifierName(unsigned long long specifier) {
    if (specifier == kIGMCEmployeeSpecifierA || specifier == kIGMCEmployeeSpecifierB) return @"ig_is_employee";
    if (specifier == kIGMCEmployeeOrTestUserSpecifier) return @"ig_is_employee_or_test_user";
    return @"unknown";
}

static BOOL applyInternalUseOverride(unsigned long long specifier, BOOL original) {
    SCIExpFlagOverride manual = [SCIExpFlags internalUseOverrideForSpecifier:specifier];
    if (manual == SCIExpFlagOverrideTrue) return YES;
    if (manual == SCIExpFlagOverrideFalse) return NO;
    if (specifierMatchesEmployee(specifier)) return YES;
    return original;
}

static void recordInternalUseSpecifier(NSString *funcName, unsigned long long specifier, BOOL defaultValue, BOOL originalValue, BOOL returnedValue) {
    BOOL forced = (returnedValue != originalValue);
    BOOL shouldRecord = rgInternalObserverEnabled() || forced || specifierMatchesEmployee(specifier) || [SCIExpFlags internalUseOverrideForSpecifier:specifier] != SCIExpFlagOverrideOff;
    if (!shouldRecord) return;

    NSString *name = specifierName(specifier);
    [SCIExpFlags recordInternalUseSpecifier:specifier
                               functionName:funcName
                              specifierName:name
                               defaultValue:defaultValue
                                resultValue:returnedValue
                                forcedValue:forced];

    if (rgInternalObserverEnabled()) {
        NSLog(@"[RyukGram][MC][%@] spec=0x%016llx (%@) default=%d original=%d returned=%d forced=%d employeeMatch=%d manual=%ld",
              funcName,
              specifier,
              name,
              defaultValue,
              originalValue,
              returnedValue,
              forced,
              specifierMatchesEmployee(specifier),
              (long)[SCIExpFlags internalUseOverrideForSpecifier:specifier]);
    }
}

typedef BOOL (*IGMCBoolInternalFn)(id, BOOL, unsigned long long);
static IGMCBoolInternalFn orig_IGMobileConfigBooleanValueForInternalUse = NULL;
static BOOL hook_IGMobileConfigBooleanValueForInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    BOOL original = orig_IGMobileConfigBooleanValueForInternalUse ?
        orig_IGMobileConfigBooleanValueForInternalUse(ctx, defaultValue, specifier) : defaultValue;
    BOOL returned = applyInternalUseOverride(specifier, original);
    recordInternalUseSpecifier(@"IGMobileConfigBooleanValueForInternalUse", specifier, defaultValue, original, returned);
    return returned;
}

static IGMCBoolInternalFn orig_IGMobileConfigSessionlessBooleanValueForInternalUse = NULL;
static BOOL hook_IGMobileConfigSessionlessBooleanValueForInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    BOOL original = orig_IGMobileConfigSessionlessBooleanValueForInternalUse ?
        orig_IGMobileConfigSessionlessBooleanValueForInternalUse(ctx, defaultValue, specifier) : defaultValue;
    BOOL returned = applyInternalUseOverride(specifier, original);
    recordInternalUseSpecifier(@"IGMobileConfigSessionlessBooleanValueForInternalUse", specifier, defaultValue, original, returned);
    return returned;
}

static BOOL (*orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18)(void) = NULL;
static BOOL hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18(void) {
    if ([SCIUtils getBoolPref:@"igt_internal_apps_gate"]) return YES;
    return orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 ?
        orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18() : NO;
}

%ctor {
    if (!rgShouldInstallInternalModeHooks()) return;

    struct rebinding rebindings[] = {
        {"IGMobileConfigBooleanValueForInternalUse", (void *)hook_IGMobileConfigBooleanValueForInternalUse, (void **)&orig_IGMobileConfigBooleanValueForInternalUse},
        {"IGMobileConfigSessionlessBooleanValueForInternalUse", (void *)hook_IGMobileConfigSessionlessBooleanValueForInternalUse, (void **)&orig_IGMobileConfigSessionlessBooleanValueForInternalUse},
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18, (void **)&orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][MC] internal-mode fishhook rc=%d bool=%p sessionless=%p internalApps=%p manualOverrides=%lu",
          rc,
          orig_IGMobileConfigBooleanValueForInternalUse,
          orig_IGMobileConfigSessionlessBooleanValueForInternalUse,
          orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18,
          (unsigned long)[SCIExpFlags allOverriddenInternalUseSpecifiers].count);
}
