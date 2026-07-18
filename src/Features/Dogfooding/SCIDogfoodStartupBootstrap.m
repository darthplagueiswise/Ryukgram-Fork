#import "SCIInternalGatePrefs.h"
#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <os/log.h>

#define BOOTLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DogfoodBootstrap " fmt, ##__VA_ARGS__)

FOUNDATION_EXPORT void SCIInstallSessionlessMobileConfigEarlyCaptureHooks(void);
FOUNDATION_EXPORT void SCIBugMenuOEMActivationInstall(void);
FOUNDATION_EXPORT void SCIInstallBugMenuActionCellHooks(void);
FOUNDATION_EXPORT void SCIInstallLoggedOutMobileConfigActionHook(void);
FOUNDATION_EXPORT void SCIInstallEmployeeIdentityConsumerHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeePandoIdentityHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeeMobileConfigDescriptorHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeeTestDogfoodRuntimeHooks(void);
FOUNDATION_EXPORT void SCIInstallDogfoodObjectHooksIfNeeded(void);

static id sSCIDogfoodLaunchObserver;

static BOOL SCIDogfoodMasterEnabled(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static BOOL SCIInternalMenuFeatureEnabled(void) {
    return SCIDogfoodMasterEnabled() ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"];
}

static BOOL SCISessionlessCaptureEnabled(void) {
    return SCIDogfoodMasterEnabled() ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_loggedout"];
}

static dispatch_queue_t SCIDogfoodBootstrapWorker(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ryukgram.dogfood-bootstrap",
                                      DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue,
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static void SCIInstallPreMainDogfoodHooks(void) {
    // Pre-main is deliberately restricted to exact hooks that must observe
    // objects constructed during launch. Nothing runs when the associated
    // feature family is disabled, and no class/image enumeration occurs here.
    if (SCISessionlessCaptureEnabled()) {
        SCIInstallSessionlessMobileConfigEarlyCaptureHooks();
    }
    if (SCIDogfoodMasterEnabled()) {
        SCIInstallEmployeeIdentityConsumerHooks();
    }
}

static void SCIInstallPostLaunchExactHooks(void) {
    BOOL masterEnabled = SCIDogfoodMasterEnabled();
    BOOL menuEnabled = SCIInternalMenuFeatureEnabled();

    // Retry the two exact pre-main installers once because some Swift classes
    // are registered only after the initial image set has finished loading.
    if (SCISessionlessCaptureEnabled()) {
        SCIInstallSessionlessMobileConfigEarlyCaptureHooks();
    }
    if (masterEnabled) {
        SCIInstallEmployeeIdentityConsumerHooks();
    }

    if (menuEnabled) {
        SCIBugMenuOEMActivationInstall();
        SCIInstallBugMenuActionCellHooks();
        SCIInstallLoggedOutMobileConfigActionHook();
    }

    if (masterEnabled) {
        SCIInstallEmployeePandoIdentityHooks();
        SCIInstallDogfoodObjectHooksIfNeeded();
    }
}

static void SCIDogfoodPostLaunchBootstrap(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL masterEnabled = SCIDogfoodMasterEnabled();
        SCIInstallPostLaunchExactHooks();

        // The only broad class scans are employee/test-user utilities. Do not
        // even schedule their queue when the master is disabled.
        if (masterEnabled) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(2.0 * NSEC_PER_SEC)),
                           SCIDogfoodBootstrapWorker(), ^{
                SCIInstallEmployeeMobileConfigDescriptorHooks();
                SCIInstallEmployeeTestDogfoodRuntimeHooks();
                BOOTLOG("deferred employee utility hooks installed");
            });
        }
        BOOTLOG("post-launch exact hooks installed; master=%d menu=%d",
                masterEnabled, SCIInternalMenuFeatureEnabled());
    });
}

__attribute__((constructor))
static void SCIDogfoodStartupBootstrapCtor(void) {
    @autoreleasepool {
        BOOL masterEnabled = SCIDogfoodMasterEnabled();
        BOOL menuEnabled = SCIInternalMenuFeatureEnabled();
        BOOL sessionlessEnabled = SCISessionlessCaptureEnabled();

        // Zero bootstrap work for this feature family when every relevant
        // preference is off. A restart is already required after enabling the
        // internal feature group, so no always-on observer is necessary.
        if (!masterEnabled && !menuEnabled && !sessionlessEnabled) {
            return;
        }

        SCIInstallPreMainDogfoodHooks();

        sSCIDogfoodLaunchObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
            id observer = sSCIDogfoodLaunchObserver;
            sSCIDogfoodLaunchObserver = nil;
            if (observer) {
                [NSNotificationCenter.defaultCenter removeObserver:observer];
            }
            SCIDogfoodPostLaunchBootstrap();
        }];

        BOOTLOG("constructor armed; master=%d menu=%d sessionless=%d",
                masterEnabled, menuEnabled, sessionlessEnabled);
    }
}
