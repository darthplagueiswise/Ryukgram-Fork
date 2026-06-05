// SCIInternalUseGateHook.x
// Safe MobileConfig/internal-use BOOL gates only.
//
// Run 226 crash analysis (Instagram-2026-06-05-153301): the process crashed in
// objc_retain inside +[IGTabBarButton profileButtonWithCustomOverlayView:badgeType:].
// The crashing registers had x0/x3/x19 = IGMobileConfigTryUpdateConfigsWithCompletion.
// That means a C function pointer ended up where Instagram expected an Objective-C
// object. The cause was unconditional fishhook rebinding of MobileConfig ACTION
// functions below. These are not BOOL gates and must not be globally rebound:
//   - IGMobileConfigSetConfigOverrides
//   - IGMobileConfigTryUpdateConfigsWithCompletion
//   - IGMobileConfigForceUpdateConfigs
//
// This file intentionally keeps only BOOL-returning imported gates. Use the Symbols
// Browser for inspection of action symbols; do not patch them here.

#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"
#import <os/log.h>

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] MCGate " fmt,##__VA_ARGS__)

static NSString *kBool        = @"sci_force_mc_internal_use_boolean";
static NSString *kSessionless = @"sci_force_mc_sessionless_internal_use_boolean";
static NSString *kInternalApp = @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString *kMinos       = @"sci_force_minos_dogfood_mek_encryption";

static inline BOOL gateOn(NSString *k)  { return [SCIInternalGatePrefs mobileConfigBoolGateEnabledForKey:k]; }

typedef BOOL (*MCBoolFn_t)(id, BOOL, void *);
typedef BOOL (*MCSessionlessFn_t)(BOOL, void *);
typedef BOOL (*SimpleBoolFn_t)(void);

static MCBoolFn_t        orig_MCBool        = NULL;
static MCSessionlessFn_t orig_MCSessionless = NULL;
static SimpleBoolFn_t    orig_InternalApps  = NULL;
static SimpleBoolFn_t    orig_Minos         = NULL;

static BOOL my_MCBool(id session, BOOL def, void *p) {
    if (gateOn(kBool)) return YES;
    return orig_MCBool ? orig_MCBool(session, def, p) : def;
}

static BOOL my_MCSessionless(BOOL def, void *p) {
    if (gateOn(kSessionless)) return YES;
    return orig_MCSessionless ? orig_MCSessionless(def, p) : def;
}

static BOOL my_InternalApps(void) {
    if (gateOn(kInternalApp)) return YES;
    return orig_InternalApps ? orig_InternalApps() : NO;
}

static BOOL my_Minos(void) {
    if (gateOn(kMinos)) return YES;
    return orig_Minos ? orig_Minos() : NO;
}

static void SCIRemoveUnsafeMobileConfigActionPrefs(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d removeObjectForKey:@"sci_force_mobileconfig_overrides"];
    [d removeObjectForKey:@"sci_force_mobileconfig_try_update"];
    [d removeObjectForKey:@"sci_force_mobileconfig_force_update"];
    [d synchronize];
}

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;

    SCIRemoveUnsafeMobileConfigActionPrefs();

    struct rebinding r[] = {
        {"IGMobileConfigBooleanValueForInternalUse",            (void *)my_MCBool,        (void **)&orig_MCBool},
        {"IGMobileConfigSessionlessBooleanValueForInternalUse", (void *)my_MCSessionless, (void **)&orig_MCSessionless},
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)my_InternalApps, (void **)&orig_InternalApps},
        {"MEBIsMinosDogfoodMekEncryptionVersionEnabled",        (void *)my_Minos,         (void **)&orig_Minos},
    };
    int rc = rebind_symbols(r, sizeof(r) / sizeof(r[0]));
    SCILOG("safe BOOL rebind_symbols=%d (0=ok)", rc);
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        SCIInstallMobileConfigInternalUseGateIfNeeded();
    }
}
