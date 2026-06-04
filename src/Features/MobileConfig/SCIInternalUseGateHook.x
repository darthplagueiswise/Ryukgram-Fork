// SCIInternalUseGateHook.x
// ---------------------------------------------------------------------------
// fishhook redirects imported C symbols by name through the __got / lazy
// symbol pointers. Boolean "internal use" gates return YES; action functions
// are hooked as pass-through wrappers so they keep their original control flow
// and can be logged/extended behind dedicated toggles.
// ---------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"
#import <os/log.h>

#define SCILOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] " fmt, ##__VA_ARGS__)

static NSString *const kSCIMCAllInternalUseKey = @"sci_force_mc_internal_use_all";
static NSString *const kSCIMCInternalUseBooleanKey = @"sci_force_mc_internal_use_boolean";
static NSString *const kSCIMCSessionlessInternalUseKey = @"sci_force_mc_sessionless_internal_use_boolean";
static NSString *const kSCIIGInternalAppsInstalledKey = @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString *const kSCIMinosDogfoodMekKey = @"sci_force_minos_dogfood_mek_encryption";

static NSString *const kSCIMobileConfigOverridesKey = @"sci_force_mobileconfig_overrides";
static NSString *const kSCIMobileConfigTryUpdateKey = @"sci_force_mobileconfig_try_update";
static NSString *const kSCIMobileConfigForceUpdateKey = @"sci_force_mobileconfig_force_update";

static BOOL sciGateEnabled(NSString *key) {
    return [SCIInternalGatePrefs mobileConfigBoolGateEnabledForKey:key];
}

static BOOL sciIndividualGateEnabled(NSString *key) {
    return [SCIInternalGatePrefs individualGateEnabledForKey:key];
}

static BOOL sci_yes_boolean(void) { return YES; }
static BOOL sci_yes_sessionless(void) { return YES; }
static BOOL sci_yes_internal_apps(void) { return YES; }
static BOOL sci_yes_minos_mek(void) { return YES; }

typedef void (*IGMobileConfigSetConfigOverrides_t)(id manager, NSDictionary *overrides);
static IGMobileConfigSetConfigOverrides_t orig_IGMobileConfigSetConfigOverrides = NULL;

static void my_IGMobileConfigSetConfigOverrides(id manager, NSDictionary *overrides) {
    SCILOG("IGMobileConfigSetConfigOverrides called");

    if (sciIndividualGateEnabled(kSCIMobileConfigOverridesKey)) {
        NSDictionary *customOverrides = [SCIInternalGatePrefs mobileConfigCustomOverrides];
        NSMutableDictionary *mutableOverrides = [overrides mutableCopy];
        if (!mutableOverrides) mutableOverrides = [NSMutableDictionary dictionary];

        if (customOverrides) {
            [mutableOverrides addEntriesFromDictionary:customOverrides];
            SCILOG("Applying custom MobileConfig overrides: %{public}@", customOverrides);
        }

        if (orig_IGMobileConfigSetConfigOverrides) {
            orig_IGMobileConfigSetConfigOverrides(manager, mutableOverrides);
        }
        return;
    }

    if (orig_IGMobileConfigSetConfigOverrides) {
        orig_IGMobileConfigSetConfigOverrides(manager, overrides);
    }
}

typedef void (^IGMobileConfigCompletionBlock)(BOOL success, NSError *error);
typedef void (*IGMobileConfigTryUpdateConfigsWithCompletion_t)(id manager, id perfMarker, IGMobileConfigCompletionBlock completionBlock);
static IGMobileConfigTryUpdateConfigsWithCompletion_t orig_IGMobileConfigTryUpdateConfigsWithCompletion = NULL;

static void my_IGMobileConfigTryUpdateConfigsWithCompletion(id manager, id perfMarker, IGMobileConfigCompletionBlock completionBlock) {
    SCILOG("IGMobileConfigTryUpdateConfigsWithCompletion called");
    if (sciIndividualGateEnabled(kSCIMobileConfigTryUpdateKey)) {
        SCILOG("IGMobileConfigTryUpdateConfigsWithCompletion hook toggle is ON.");
        IGMobileConfigCompletionBlock wrappedCompletionBlock = [^(BOOL success, NSError *error) {
            SCILOG("IGMobileConfigTryUpdateConfigsWithCompletion completion success=%d", success);
            if (completionBlock) completionBlock(success, error);
        } copy];
        if (orig_IGMobileConfigTryUpdateConfigsWithCompletion) {
            orig_IGMobileConfigTryUpdateConfigsWithCompletion(manager, perfMarker, wrappedCompletionBlock);
        }
        return;
    }
    if (orig_IGMobileConfigTryUpdateConfigsWithCompletion) {
        orig_IGMobileConfigTryUpdateConfigsWithCompletion(manager, perfMarker, completionBlock);
    }
}

typedef void (*IGMobileConfigForceUpdateConfigs_t)(id manager);
static IGMobileConfigForceUpdateConfigs_t orig_IGMobileConfigForceUpdateConfigs = NULL;

static void my_IGMobileConfigForceUpdateConfigs(id manager) {
    SCILOG("IGMobileConfigForceUpdateConfigs called");
    if (sciIndividualGateEnabled(kSCIMobileConfigForceUpdateKey)) {
        SCILOG("IGMobileConfigForceUpdateConfigs hook toggle is ON. Calling original.");
    }
    if (orig_IGMobileConfigForceUpdateConfigs) {
        orig_IGMobileConfigForceUpdateConfigs(manager);
    }
}

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
    struct rebinding rebinds[7];
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

    if (sciIndividualGateEnabled(kSCIMobileConfigOverridesKey)) {
        rebinds[n++] = (struct rebinding){
            "IGMobileConfigSetConfigOverrides",
            (void *)my_IGMobileConfigSetConfigOverrides,
            (void **)&orig_IGMobileConfigSetConfigOverrides
        };
    }
    if (sciIndividualGateEnabled(kSCIMobileConfigTryUpdateKey)) {
        rebinds[n++] = (struct rebinding){
            "IGMobileConfigTryUpdateConfigsWithCompletion",
            (void *)my_IGMobileConfigTryUpdateConfigsWithCompletion,
            (void **)&orig_IGMobileConfigTryUpdateConfigsWithCompletion
        };
    }
    if (sciIndividualGateEnabled(kSCIMobileConfigForceUpdateKey)) {
        rebinds[n++] = (struct rebinding){
            "IGMobileConfigForceUpdateConfigs",
            (void *)my_IGMobileConfigForceUpdateConfigs,
            (void **)&orig_IGMobileConfigForceUpdateConfigs
        };
    }

    if (n) {
        rebind_symbols(rebinds, n);
        SCILOG("MobileConfig rebinds installed: %zu", n);
    } else {
        SCILOG("MobileConfig rebinds skipped");
    }
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        SCIInstallMobileConfigInternalUseGateIfNeeded();
    }
}
