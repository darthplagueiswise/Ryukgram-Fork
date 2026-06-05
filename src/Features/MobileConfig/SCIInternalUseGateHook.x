// SCIInternalUseGateHook.x
// CRITICAL FIX: fishhook installed UNCONDITIONALLY at %ctor.
// Previous version checked prefs before rebind_symbols — if crash guard
// disabled the prefs, the rebind never happened and could never activate.
// Now: always rebind; check pref inside the hook at call time.

#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"
#import <os/log.h>

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] MCGate " fmt,##__VA_ARGS__)

static NSString *kAll         = @"sci_force_mc_internal_use_all";
static NSString *kBool        = @"sci_force_mc_internal_use_boolean";
static NSString *kSessionless = @"sci_force_mc_sessionless_internal_use_boolean";
static NSString *kInternalApp = @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString *kMinos       = @"sci_force_minos_dogfood_mek_encryption";
static NSString *kOverrides   = @"sci_force_mobileconfig_overrides";
static NSString *kTryUpdate   = @"sci_force_mobileconfig_try_update";
static NSString *kForceUpdate = @"sci_force_mobileconfig_force_update";

static inline BOOL gateOn(NSString *k)  { return [SCIInternalGatePrefs mobileConfigBoolGateEnabledForKey:k]; }
static inline BOOL indivOn(NSString *k) { return [SCIInternalGatePrefs individualGateEnabledForKey:k]; }

typedef BOOL (*MCBoolFn_t)(id, BOOL, void *);
typedef BOOL (*MCSessionlessFn_t)(BOOL, void *);
typedef BOOL (*SimpleBoolFn_t)(void);
typedef void (*SetOverridesFn_t)(id, NSDictionary *);
typedef void (*TryUpdateFn_t)(id, id, id);
typedef void (*ForceUpdateFn_t)(id);

static MCBoolFn_t       orig_MCBool       = NULL;
static MCSessionlessFn_t orig_MCSessionless = NULL;
static SimpleBoolFn_t   orig_InternalApps  = NULL;
static SimpleBoolFn_t   orig_Minos         = NULL;
static SetOverridesFn_t orig_SetOverrides  = NULL;
static TryUpdateFn_t    orig_TryUpdate     = NULL;
static ForceUpdateFn_t  orig_ForceUpdate   = NULL;

static BOOL my_MCBool(id session, BOOL def, void *p)      { if (gateOn(kBool)) return YES; return orig_MCBool ? orig_MCBool(session,def,p) : def; }
static BOOL my_MCSessionless(BOOL def, void *p)           { if (gateOn(kSessionless)) return YES; return orig_MCSessionless ? orig_MCSessionless(def,p) : def; }
static BOOL my_InternalApps(void)                         { if (gateOn(kInternalApp)) return YES; return orig_InternalApps ? orig_InternalApps() : NO; }
static BOOL my_Minos(void)                                { if (gateOn(kMinos)) return YES; return orig_Minos ? orig_Minos() : NO; }
static void my_ForceUpdate(id m)                          { if (orig_ForceUpdate) orig_ForceUpdate(m); }
static void my_TryUpdate(id m, id mk, id cb)              { if (orig_TryUpdate) orig_TryUpdate(m,mk,cb); }
static void my_SetOverrides(id m, NSDictionary *ov) {
    if (indivOn(kOverrides)) {
        NSDictionary *custom = [SCIInternalGatePrefs mobileConfigCustomOverrides];
        if (custom.count) {
            NSMutableDictionary *mo = [ov mutableCopy] ?: [NSMutableDictionary dictionary];
            [mo addEntriesFromDictionary:custom];
            if (orig_SetOverrides) orig_SetOverrides(m, mo);
            return;
        }
    }
    if (orig_SetOverrides) orig_SetOverrides(m, ov);
}

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
    static BOOL done = NO; if (done) return; done = YES;
    struct rebinding r[] = {
        {"IGMobileConfigBooleanValueForInternalUse",           (void*)my_MCBool,        (void**)&orig_MCBool},
        {"IGMobileConfigSessionlessBooleanValueForInternalUse",(void*)my_MCSessionless, (void**)&orig_MCSessionless},
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",(void*)my_InternalApps,(void**)&orig_InternalApps},
        {"MEBIsMinosDogfoodMekEncryptionVersionEnabled",       (void*)my_Minos,         (void**)&orig_Minos},
        {"IGMobileConfigSetConfigOverrides",                   (void*)my_SetOverrides,  (void**)&orig_SetOverrides},
        {"IGMobileConfigTryUpdateConfigsWithCompletion",       (void*)my_TryUpdate,     (void**)&orig_TryUpdate},
        {"IGMobileConfigForceUpdateConfigs",                   (void*)my_ForceUpdate,   (void**)&orig_ForceUpdate},
    };
    int rc = rebind_symbols(r, sizeof(r)/sizeof(r[0]));
    SCILOG("rebind_symbols=%d (0=ok)", rc);
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        SCIInstallMobileConfigInternalUseGateIfNeeded();
    }
}
