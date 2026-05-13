#import <Foundation/Foundation.h>
#import "../SCIMobileConfigBrokerStore.h"
#import "../SCIMobileConfigBrokerRouter.h"

// beta2 stability fix:
// This file must not install MobileConfig ObjC getter observers from %ctor.
// The previous beta2 version called InstallPersistedIfNeeded() unconditionally,
// which scheduled immediate/main/1s/3s observer installation even when no UI
// toggle was enabled. That matches a delayed crash a few seconds after launch.
//
// Runtime MobileConfig observation is now manual/debug only. The exported
// symbols remain so existing menu code can link, but they are inert unless a
// future explicit UI path is rebuilt with a safe, user-triggered installer.

static NSString *const kStartupKey = @"sci_exp_mc_objc_startup_hooks_enabled";
static NSString *const kApplyKey = @"sci_exp_mc_objc_apply_overrides_enabled";
static NSString *const kAliasKey = @"sci_exp_mc_objc_alias_observer_enabled";

static void SCIObjCMCRegisterSafeDefaults(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud registerDefaults:@{
        kStartupKey: @NO,
        kApplyKey: @NO,
        kAliasKey: @NO,
        @"sci_exp_mc_c_hooks_enabled": @NO,
        @"sci_exp_mc_hooks_enabled": @NO,
        @"sci_exp_mc_legacy_getter_hooks_enabled": @NO,
        @"sci_exp_mc_c_broker_body_hooks_enabled": @NO,
        @"sci_exp_mc_allow_install_enabled_brokers": @NO
    }];
}

static void SCIObjCMCDisableLegacyAutoObserversOnce(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:@"sci_exp_default_observers_v11_beta2_startup_inert_done"]) return;

    for (NSString *k in @[
        @"sci_exp_mc_hooks_enabled",
        @"sci_exp_mc_c_hooks_enabled",
        @"sci_exp_mc_c_broker_body_hooks_enabled",
        @"sci_exp_mc_legacy_getter_hooks_enabled",
        @"sci_exp_mc_objc_startup_hooks_enabled",
        @"sci_exp_mc_objc_alias_observer_enabled",
        @"sci_exp_mc_allow_install_enabled_brokers"
    ]) {
        [ud setBool:NO forKey:k];
    }
    [ud setBool:YES forKey:@"sci_exp_default_observers_v11_beta2_startup_inert_done"];
    [ud synchronize];
}

static void SCIObjCMCNoteNoop(NSString *brokerID, NSString *reason) {
    NSString *bid = brokerID.length ? brokerID : @"unknown";
    NSString *msg = reason ?: @"ObjC MobileConfig getter observer disabled for beta2 launch stability";
    [SCIMobileConfigBrokerStore noteLastError:msg brokerID:bid];
    NSLog(@"[RyukGram][MCObjC] %@ broker=%@", msg, bid);
}

#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("default"))) void SCIInstallObjCMobileConfigGetterObserverForBrokerID(NSString *brokerID) {
    SCIObjCMCNoteNoop(brokerID, @"ObjC getter observer install is manual-disabled in beta2 stability build");
}

__attribute__((visibility("default"))) void SCIInstallObjCMobileConfigAliasResolverObserverForBrokerID(NSString *brokerID) {
    SCIObjCMCNoteNoop(brokerID, @"ObjC alias observer install is manual-disabled in beta2 stability build");
}

__attribute__((visibility("default"))) void SCIInstallFocusedObjCGetterObserver(void) {
    SCIObjCMCNoteNoop(@"focused", @"Focused ObjC getter observer disabled for beta2 launch stability");
}

__attribute__((visibility("default"))) void SCIInstallObjCMobileConfigGetterObserver(void) {
    SCIObjCMCNoteNoop(@"all", @"Global ObjC getter observer disabled for beta2 launch stability");
}

__attribute__((visibility("default"))) BOOL SCIObjCMobileConfigObserverIsInstalledForBrokerID(NSString *brokerID) {
    (void)brokerID;
    return NO;
}

__attribute__((visibility("default"))) NSUInteger SCIObjCMobileConfigObserverInstalledCount(void) {
    return 0;
}

__attribute__((visibility("default"))) void SCIObjCMobileConfigObserverInstallEnabled(void) {
    SCIObjCMCNoteNoop(@"enabled", @"Install enabled ObjC observers disabled for beta2 launch stability");
}
#ifdef __cplusplus
}
#endif

%ctor {
    @autoreleasepool {
        SCIObjCMCRegisterSafeDefaults();
        SCIObjCMCDisableLegacyAutoObserversOnce();
        NSLog(@"[RyukGram][MCObjC] startup inert; no MobileConfig ObjC getter hooks scheduled");
    }
}
