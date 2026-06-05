// SCIInternalUseGateHook.x
// Safe internal-use gates only.
//
// This file intentionally hooks only pure boolean C gates. It does NOT rebind
// IGMobileConfigSetConfigOverrides, IGMobileConfigTryUpdateConfigsWithCompletion,
// or IGMobileConfigForceUpdateConfigs: those are action/update functions, not BOOL
// accessors, and the 2026-06-05 crash showed IGMobileConfigTryUpdateConfigsWithCompletion
// being retained as if it were an ObjC object during IGTabBarButton construction.

#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"
#import <os/log.h>

#define SCILOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] " fmt, ##__VA_ARGS__)

static NSString *const kSCIMCInternalUseBooleanKey = @"sci_force_mc_internal_use_boolean";
static NSString *const kSCIMCSessionlessInternalUseKey = @"sci_force_mc_sessionless_internal_use_boolean";
static NSString *const kSCIIGInternalAppsInstalledKey = @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString *const kSCIMinosDogfoodMekKey = @"sci_force_minos_dogfood_mek_encryption";

static BOOL sciGateEnabled(NSString *key) {
    return [SCIInternalGatePrefs mobileConfigBoolGateEnabledForKey:key];
}

static BOOL sci_yes_boolean(void) { return YES; }
static BOOL sci_yes_sessionless(void) { return YES; }
static BOOL sci_yes_internal_apps(void) { return YES; }
static BOOL sci_yes_minos_mek(void) { return YES; }

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
    struct rebinding rebinds[4];
    size_t n = 0;

    if (sciGateEnabled(kSCIMCInternalUseBooleanKey)) {
        rebinds[n++] = (struct rebinding){
            "IGMobileConfigBooleanValueForInternalUse",
            (void *)sci_yes_boolean,
            NULL
        };
    }

    if (sciGateEnabled(kSCIMCSessionlessInternalUseKey)) {
        rebinds[n++] = (struct rebinding){
            "IGMobileConfigSessionlessBooleanValueForInternalUse",
            (void *)sci_yes_sessionless,
            NULL
        };
    }

    if (sciGateEnabled(kSCIIGInternalAppsInstalledKey)) {
        rebinds[n++] = (struct rebinding){
            "IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
            (void *)sci_yes_internal_apps,
            NULL
        };
    }

    if (sciGateEnabled(kSCIMinosDogfoodMekKey)) {
        rebinds[n++] = (struct rebinding){
            "MEBIsMinosDogfoodMekEncryptionVersionEnabled",
            (void *)sci_yes_minos_mek,
            NULL
        };
    }

    if (n) {
        rebind_symbols(rebinds, n);
        SCILOG("Safe MobileConfig/internal-use BOOL rebinds installed: %zu", n);
    } else {
        SCILOG("Safe MobileConfig/internal-use BOOL rebinds skipped");
    }
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        SCIInstallMobileConfigInternalUseGateIfNeeded();
    }
}
