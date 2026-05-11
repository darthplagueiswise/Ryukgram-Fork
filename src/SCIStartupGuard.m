#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Features/ExpFlags/SCIMobileConfigBrokerStore.h"
#import "Features/ExpFlags/SCIMobileConfigBrokerRouter.h"

// This file intentionally no longer implements the old StartupGuard.
// The previous version ran from a constructor, scanned broker state, listened to
// global NSUserDefaults changes, showed alerts, and disabled prefs/overrides by
// itself. That made launch/login fragile and could make the tweak appear before
// Instagram had a stable session/UI.
//
// The only responsibilities left here are:
// 1. register/migrate the MobileConfig broker store;
// 2. erase stale StartupGuard bookkeeping keys so old crash-loop state cannot
//    affect new builds;
// 3. optionally install previously enabled broker observers, but only after the
//    app is active and a non-login root UI has had time to settle.

static NSString * const kSCIStartupObserverDidRunKey = @"sci.startupobserver.did_run_once";
static NSString * const kSCIStartupObserverLastRunKey = @"sci.startupobserver.last_run";

static NSArray<NSString *> *SCIStartupGuardLegacyKeys(void) {
    return @[
        @"sci.startupguard.pending",
        @"sci.startupguard.signature",
        @"sci.startupguard.started_at",
        @"sci.startupguard.count",
        @"sci.startupguard.last_report",
        @"sci.startupguard.last_report_id",
        @"sci.startupguard.shown_report_id",
        @"sci.startupguard.last_disabled",
        @"sci.startupguard.event_log"
    ];
}

static NSUserDefaults *SCIStartupDefaults(void) {
    return [NSUserDefaults standardUserDefaults];
}

static void SCIClearLegacyStartupGuardState(void) {
    NSUserDefaults *ud = SCIStartupDefaults();
    BOOL changed = NO;
    for (NSString *key in SCIStartupGuardLegacyKeys()) {
        if ([ud objectForKey:key] != nil) {
            [ud removeObjectForKey:key];
            changed = YES;
        }
    }
    if (changed) {
        [ud synchronize];
        NSLog(@"[RyukGram][StartupObserver] cleared legacy StartupGuard state");
    }
}

static UIViewController *SCITopViewController(UIViewController *vc) {
    UIViewController *cur = vc;
    while (cur.presentedViewController) cur = cur.presentedViewController;
    if ([cur isKindOfClass:UINavigationController.class]) {
        return SCITopViewController(((UINavigationController *)cur).visibleViewController);
    }
    if ([cur isKindOfClass:UITabBarController.class]) {
        return SCITopViewController(((UITabBarController *)cur).selectedViewController);
    }
    return cur;
}

static UIViewController *SCIRootViewController(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow && w.rootViewController) return w.rootViewController;
        }
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.rootViewController) return w.rootViewController;
        }
    }
    return nil;
}

static BOOL SCIClassNameLooksLikeLoginOrPreAuth(NSString *name) {
    if (!name.length) return YES;
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *badTokens = @[
        @"login",
        @"logout",
        @"signin",
        @"signup",
        @"registration",
        @"accountswitch",
        @"authentication",
        @"twofactor",
        @"checkpoint",
        @"challenge",
        @"consent",
        @"privacyflow",
        @"splash",
        @"landing"
    ];
    for (NSString *token in badTokens) {
        if ([lower containsString:token]) return YES;
    }
    return NO;
}

static BOOL SCIAppLooksReadyForRuntimeObservers(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState != UIApplicationStateActive) return NO;

    UIViewController *root = SCIRootViewController();
    UIViewController *top = SCITopViewController(root);
    if (!root || !top) return NO;

    NSString *rootName = NSStringFromClass(root.class) ?: @"";
    NSString *topName = NSStringFromClass(top.class) ?: @"";
    if (SCIClassNameLooksLikeLoginOrPreAuth(rootName) || SCIClassNameLooksLikeLoginOrPreAuth(topName)) {
        NSLog(@"[RyukGram][StartupObserver] delaying observers; root=%@ top=%@", rootName, topName);
        return NO;
    }
    return YES;
}

static void SCIInstallObserversIfSafe(void) {
    static BOOL installed = NO;
    if (installed) return;

    NSUserDefaults *ud = SCIStartupDefaults();
    if (![ud boolForKey:@"sci_exp_mc_allow_install_enabled_brokers"]) {
        NSLog(@"[RyukGram][StartupObserver] broker observer install disabled; manual/debug only");
        return;
    }

    if (![SCIMobileConfigBrokerStore hasAnyActiveOverridesOrHooks]) {
        NSLog(@"[RyukGram][StartupObserver] no active broker overrides/hooks; observer remains inert");
        return;
    }

    if (!SCIAppLooksReadyForRuntimeObservers()) return;

    installed = YES;
    [ud setBool:YES forKey:kSCIStartupObserverDidRunKey];
    [ud setDouble:NSDate.date.timeIntervalSince1970 forKey:kSCIStartupObserverLastRunKey];
    [ud synchronize];

    NSLog(@"[RyukGram][StartupObserver] installing enabled broker observers after active non-login UI");
    [SCIMobileConfigBrokerRouter installEnabledBrokers];
}

static void SCIScheduleSafeObserverChecks(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCIInstallObserversIfSafe();
            });
        }];

        // Give Instagram time to move past cold-start/login routing. These checks
        // are cheap and do not scan broker keys unless explicit install is allowed.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIInstallObserversIfSafe();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIInstallObserversIfSafe();
        });
    });
}

__attribute__((constructor))
static void SCIStartupObserverInit(void) {
    @autoreleasepool {
        NSUserDefaults *ud = SCIStartupDefaults();
        [ud registerDefaults:@{
            @"sci_exp_mc_allow_install_enabled_brokers": @NO,
            @"sci_exp_mc_c_hooks_enabled": @NO,
            @"sci_exp_mc_c_broker_body_hooks_enabled": @NO,
            kSCIStartupObserverDidRunKey: @NO
        }];

        SCIClearLegacyStartupGuardState();
        [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
        SCIScheduleSafeObserverChecks();

        NSLog(@"[RyukGram][StartupObserver] loaded inert; no safeguard, no auto-disable, delayed observer only");
    }
}
