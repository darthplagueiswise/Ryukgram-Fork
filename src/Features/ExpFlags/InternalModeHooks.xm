#import "../../Utils.h"
#include "../../../modules/fishhook/fishhook.h"

static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL; // ig_is_employee_or_test_user

static BOOL rgEmployeeMasterEnabled(void) { return [SCIUtils getBoolPref:@"igt_employee"]; }
static BOOL rgEmployeeMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_mc"]; }
static BOOL rgEmployeeOrTestUserMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"]; }

static BOOL rgShouldInstallInternalModeHooks(void) {
    return rgEmployeeMasterEnabled() ||
           rgEmployeeMCEnabled() ||
           rgEmployeeOrTestUserMCEnabled() ||
           [SCIUtils getBoolPref:@"igt_internal_apps_gate"] ||
           [SCIUtils getBoolPref:@"igt_internaluse_observer"];
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

static void logInternalUseSpecifier(const char *funcName, unsigned long long specifier, BOOL defaultValue, BOOL resultValue) {
    if (![SCIUtils getBoolPref:@"igt_internaluse_observer"]) return;
    NSString *name = specifierName(specifier);
    NSLog(@"[RyukGram][MC][%s] spec=0x%016llx (%@) default=%d result=%d employeeMatch=%d",
          funcName,
          specifier,
          name,
          defaultValue,
          resultValue,
          specifierMatchesEmployee(specifier));
}

typedef BOOL (*IGMCBoolInternalFn)(id, BOOL, unsigned long long);
static IGMCBoolInternalFn orig_IGMobileConfigBooleanValueForInternalUse = NULL;
static BOOL hook_IGMobileConfigBooleanValueForInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    BOOL original = orig_IGMobileConfigBooleanValueForInternalUse ?
        orig_IGMobileConfigBooleanValueForInternalUse(ctx, defaultValue, specifier) : defaultValue;
    logInternalUseSpecifier("internal", specifier, defaultValue, original);

    if (specifierMatchesEmployee(specifier)) {
        return YES;
    }
    return original;
}

static IGMCBoolInternalFn orig_IGMobileConfigSessionlessBooleanValueForInternalUse = NULL;
static BOOL hook_IGMobileConfigSessionlessBooleanValueForInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    BOOL original = orig_IGMobileConfigSessionlessBooleanValueForInternalUse ?
        orig_IGMobileConfigSessionlessBooleanValueForInternalUse(ctx, defaultValue, specifier) : defaultValue;
    logInternalUseSpecifier("sessionless", specifier, defaultValue, original);

    if (specifierMatchesEmployee(specifier)) {
        return YES;
    }
    return original;
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
    NSLog(@"[RyukGram][MC] internal-mode fishhook rc=%d bool=%p sessionless=%p internalApps=%p",
          rc,
          orig_IGMobileConfigBooleanValueForInternalUse,
          orig_IGMobileConfigSessionlessBooleanValueForInternalUse,
          orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18);
}
