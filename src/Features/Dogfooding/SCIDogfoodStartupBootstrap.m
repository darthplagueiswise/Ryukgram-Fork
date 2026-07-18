#import "SCIInternalGatePrefs.h"
#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <os/log.h>

#define BOOTLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DogfoodBootstrap " fmt, ##__VA_ARGS__)

FOUNDATION_EXPORT void SCIInstallEmployeeInternalHooksIfNeeded(void);
FOUNDATION_EXPORT void SCIBugMenuOEMActivationInstall(void);
FOUNDATION_EXPORT void SCIInstallBugMenuActionCellHooks(void);
FOUNDATION_EXPORT void SCIInstallLoggedOutMobileConfigActionHook(void);
FOUNDATION_EXPORT void SCIEmployeeIdentityConsumerHooksInstall(void);
FOUNDATION_EXPORT void SCIInstallEmployeePandoIdentityHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeeMobileConfigDescriptorHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeeTestDogfoodRuntimeHooks(void);
FOUNDATION_EXPORT void SCIInstallDogfoodObjectHooksIfNeeded(void);

static id sSCIDogfoodActivationObserver;

static BOOL SCIDogfoodMasterEnabled(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static BOOL SCIInternalMenuFeatureEnabled(void) {
    return SCIDogfoodMasterEnabled() ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"] ||
        [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"] ||
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

static void SCIInstallPostActivationExactHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        BOOL masterEnabled = SCIDogfoodMasterEnabled();
        BOOL menuEnabled = SCIInternalMenuFeatureEnabled();

        // The legacy employee/internal installer owns the initializers,
        // lifecycle state and the single table didSelect hook.
        SCIInstallEmployeeInternalHooksIfNeeded();

        if (menuEnabled) {
            // Cell presentation/highlight and exact IGBugReportActionCell button
            // routes only. No duplicate lifecycle or didSelect chain.
            SCIBugMenuOEMActivationInstall();
            SCIInstallBugMenuActionCellHooks();
            SCIInstallLoggedOutMobileConfigActionHook();
        }

        if (masterEnabled) {
            SCIEmployeeIdentityConsumerHooksInstall();
            SCIInstallEmployeePandoIdentityHooks();
            SCIInstallDogfoodObjectHooksIfNeeded();
        }

        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start;
        BOOTLOG("post-activation exact install %.3f ms master=%d menu=%d",
                elapsed * 1000.0, masterEnabled, menuEnabled);

        // The only full objc_getClassList passes run well after first frame and
        // only while Employee / Internal was already enabled at launch.
        if (masterEnabled) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(4.0 * NSEC_PER_SEC)),
                           SCIDogfoodBootstrapWorker(), ^{
                CFAbsoluteTime scanStart = CFAbsoluteTimeGetCurrent();
                SCIInstallEmployeeMobileConfigDescriptorHooks();
                SCIInstallEmployeeTestDogfoodRuntimeHooks();
                BOOTLOG("deferred utility scans %.3f ms",
                        (CFAbsoluteTimeGetCurrent() - scanStart) * 1000.0);
            });
        }
    });
}

static void SCIDogfoodApplicationBecameActive(void) {
    // Do not perform runtime probing in the notification callback itself. Give
    // the first active frame a short head start, then run one exact pass.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SCIInstallPostActivationExactHooks();
    });
}

__attribute__((constructor))
static void SCIDogfoodStartupBootstrapCtor(void) {
    @autoreleasepool {
        BOOL masterEnabled = SCIDogfoodMasterEnabled();
        BOOL menuEnabled = SCIInternalMenuFeatureEnabled();

        // Zero work and no observer when the feature family is entirely off.
        if (!masterEnabled && !menuEnabled) return;

        sSCIDogfoodActivationObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
            id observer = sSCIDogfoodActivationObserver;
            sSCIDogfoodActivationObserver = nil;
            if (observer) {
                [NSNotificationCenter.defaultCenter removeObserver:observer];
            }
            SCIDogfoodApplicationBecameActive();
        }];

        BOOTLOG("constructor armed only; master=%d menu=%d",
                masterEnabled, menuEnabled);
    }
}
