// SCIInternalUseGateHook.x
// CRITICAL FIX: fishhook must be installed at %ctor UNCONDITIONALLY.
// The previous version checked prefs BEFORE calling rebind_symbols — if
// the crash guard disabled those prefs, the rebind was never installed and
// could never be activated later. Now: always rebind; check pref at call time.

#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"
#import <os/log.h>

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] MCGate " fmt,##__VA_ARGS__)

// --- Keys ---
static NSString *kAll        = @"sci_force_mc_internal_use_all";
static NSString *kBool       = @"sci_force_mc_internal_use_boolean";
static NSString *kSessionless= @"sci_force_mc_sessionless_internal_use_boolean";
static NSString *kInternalApp= @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString *kMinos      = @"sci_force_minos_dogfood_mek_encryption";
static NSString *kOverrides  = @"sci_force_mobileconfig_overrides";
static NSString *kTryUpdate  = @"sci_force_mobileconfig_try_update";
static NSString *kForceUpdate= @"sci_force_mobileconfig_force_update";

static inline BOOL gateOn(NSString *k) {
    return [SCIInternalGatePrefs mobileConfigBoolGateEnabledForKey:k];
}
static inline BOOL indivOn(NSString *k) {
    return [SCIInternalGatePrefs individualGateEnabledForKey:k];
}

// --- Typed originals (called when pref is OFF for passthrough) ---
typedef BOOL (*MCBoolFn_t)(id, BOOL, void *);
typedef BOOL (*MCSessionlessBoolFn_t)(BOOL, void *);
typedef BOOL (*InternalAppsFn_t)(void);
typedef BOOL (*MinosMekFn_t)(void);
typedef void (*SetOverridesFn_t)(id, NSDictionary *);
typedef void (*TryUpdateFn_t)(id, id, id);
typedef void (*ForceUpdateFn_t)(id);

static MCBoolFn_t        orig_MCBool      = NULL;
static MCSessionlessBoolFn_t orig_MCSessionless = NULL;
static InternalAppsFn_t  orig_InternalApps= NULL;
static MinosMekFn_t      orig_Minos       = NULL;
static SetOverridesFn_t  orig_SetOverrides= NULL;
static TryUpdateFn_t     orig_TryUpdate   = NULL;
static ForceUpdateFn_t   orig_ForceUpdate = NULL;

// --- Hooks: check pref at CALL TIME, not install time ---

static BOOL my_MCBool(id session, BOOL defaultVal, void *params) {
    if (gateOn(kBool)) return YES;
    return orig_MCBool ? orig_MCBool(session, defaultVal, params) : defaultVal;
}

static BOOL my_MCSessionless(BOOL defaultVal, void *params) {
    if (gateOn(kSessionless)) return YES;
    return orig_MCSessionless ? orig_MCSessionless(defaultVal, params) : defaultVal;
}

static BOOL my_InternalApps(void) {
    if (gateOn(kInternalApp)) return YES;
    return orig_InternalApps ? orig_InternalApps() : NO;
}

static BOOL my_Minos(void) {
    if (gateOn(kMinos)) return YES;
    return orig_Minos ? orig_Minos() : NO;
}

static void my_SetOverrides(id manager, NSDictionary *overrides) {
    if (indivOn(kOverrides)) {
        NSDictionary *custom = [SCIInternalGatePrefs mobileConfigCustomOverrides];
        if (custom.count) {
            NSMutableDictionary *m = [overrides mutableCopy] ?: [NSMutableDictionary dictionary];
            [m addEntriesFromDictionary:custom];
            if (orig_SetOverrides) orig_SetOverrides(manager, m);
            return;
        }
    }
    if (orig_SetOverrides) orig_SetOverrides(manager, overrides);
}

static void my_TryUpdate(id manager, id marker, id completion) {
    if (orig_TryUpdate) orig_TryUpdate(manager, marker, completion);
}

static void my_ForceUpdate(id manager) {
    if (orig_ForceUpdate) orig_ForceUpdate(manager);
}

// --- Install: ALWAYS rebind, no pref check at install time ---
void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;

    struct rebinding r[] = {
        {"IGMobileConfigBooleanValueForInternalUse",
         (void *)my_MCBool, (void **)&orig_MCBool},
        {"IGMobileConfigSessionlessBooleanValueForInternalUse",
         (void *)my_MCSessionless, (void **)&orig_MCSessionless},
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
         (void *)my_InternalApps, (void **)&orig_InternalApps},
        {"MEBIsMinosDogfoodMekEncryptionVersionEnabled",
         (void *)my_Minos, (void **)&orig_Minos},
        {"IGMobileConfigSetConfigOverrides",
         (void *)my_SetOverrides, (void **)&orig_SetOverrides},
        {"IGMobileConfigTryUpdateConfigsWithCompletion",
         (void *)my_TryUpdate, (void **)&orig_TryUpdate},
        {"IGMobileConfigForceUpdateConfigs",
         (void *)my_ForceUpdate, (void **)&orig_ForceUpdate},
    };
    int n = rebind_symbols(r, sizeof(r)/sizeof(r[0]));
    SCILOG("rebind_symbols returned %d (0=OK)", n);
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        SCIInstallMobileConfigInternalUseGateIfNeeded();
    }
}
