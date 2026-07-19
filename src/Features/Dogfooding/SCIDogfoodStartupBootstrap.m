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
FOUNDATION_EXPORT void SCIInstallValidatedOEMResolvers(void);
FOUNDATION_EXPORT void SCIInstallEmployeeIdentityConsumerHooks(void);
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

static void SCIInstallPostActivationExactHooks(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIInstallPostActivationExactHooks();
        });
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        BOOL masterEnabled = SCIDogfoodMasterEnabled();
        BOOL menuEnabled = SCIInternalMenuFeatureEnabled();

        // Every Objective-C method replacement is mounted from the main thread
        // after the first active frame.  No dyld callback, class-list scan or
        // delayed background MSHookMessageEx pass is allowed here.
        SCIInstallEmployeeInternalHooksIfNeeded();

        if (menuEnabled) {
            SCIBugMenuOEMActivationInstall();
            SCIInstallBugMenuActionCellHooks();
            SCIInstallLoggedOutMobileConfigActionHook();
            SCIInstallValidatedOEMResolvers();
        }

        if (masterEnabled) {
            SCIInstallEmployeeIdentityConsumerHooks();
            SCIInstallEmployeePandoIdentityHooks();
            SCIInstallDogfoodObjectHooksIfNeeded();

            // These installers are now bounded to exact, ABI-validated classes
            // and selectors.  They run in the same main-thread transaction so
            // the app never observes a partially installed hook chain.
            SCIInstallEmployeeMobileConfigDescriptorHooks();
            SCIInstallEmployeeTestDogfoodRuntimeHooks();
        }

        BOOTLOG("main-thread bounded install %.3f ms master=%d menu=%d",
                (CFAbsoluteTimeGetCurrent() - start) * 1000.0,
                masterEnabled, menuEnabled);
    });
}

static void SCIDogfoodApplicationBecameActive(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(0.50 * NSEC_PER_SEC)),
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

        BOOTLOG("main-thread bounded bootstrap armed; master=%d menu=%d",
                masterEnabled, menuEnabled);
    }
}
