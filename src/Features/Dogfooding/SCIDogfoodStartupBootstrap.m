#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <os/log.h>

#define BOOTLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DogfoodBootstrap " fmt, ##__VA_ARGS__)

FOUNDATION_EXPORT void SCIInstallSessionlessMobileConfigEarlyCaptureHooks(void);
FOUNDATION_EXPORT void SCIInstallBugMenuOEMActivationHooks(void);
FOUNDATION_EXPORT void SCIInstallBugMenuActionCellHooks(void);
FOUNDATION_EXPORT void SCIInstallLoggedOutMobileConfigActionHook(void);
FOUNDATION_EXPORT void SCIInstallEmployeeIdentityConsumerHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeePandoIdentityHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeeMobileConfigDescriptorHooks(void);
FOUNDATION_EXPORT void SCIInstallEmployeeTestDogfoodRuntimeHooks(void);
FOUNDATION_EXPORT void SCIInstallDogfoodObjectHooksIfNeeded(void);

static id sSCIDogfoodLaunchObserver;

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
    // Only hooks that must exist before Instagram constructs early session and
    // MobileConfig objects belong here. Both installers perform a fixed number
    // of exact class/selector lookups; neither enumerates images or classes.
    SCIInstallSessionlessMobileConfigEarlyCaptureHooks();
    SCIInstallEmployeeIdentityConsumerHooks();
}

static void SCIInstallPostLaunchExactHooks(void) {
    // Debug-menu/action hooks are not needed in the launch-critical window.
    // Install them once after UIApplication has finished launching.
    SCIInstallSessionlessMobileConfigEarlyCaptureHooks();
    SCIInstallEmployeeIdentityConsumerHooks();
    SCIInstallBugMenuOEMActivationHooks();
    SCIInstallBugMenuActionCellHooks();
    SCIInstallLoggedOutMobileConfigActionHook();
    SCIInstallEmployeePandoIdentityHooks();
    SCIInstallDogfoodObjectHooksIfNeeded();
}

static void SCIDogfoodPostLaunchBootstrap(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIInstallPostLaunchExactHooks();

        // The only broad class scans run once, off the main thread, after the
        // launch-critical window has passed.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(2.0 * NSEC_PER_SEC)),
                       SCIDogfoodBootstrapWorker(), ^{
            SCIInstallEmployeeMobileConfigDescriptorHooks();
            SCIInstallEmployeeTestDogfoodRuntimeHooks();
            BOOTLOG("deferred utility hooks installed");
        });
        BOOTLOG("post-launch exact hooks installed; utility phase scheduled");
    });
}

__attribute__((constructor))
static void SCIDogfoodStartupBootstrapCtor(void) {
    @autoreleasepool {
        // One lightweight constructor owns this feature family's startup.
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
    }
}
