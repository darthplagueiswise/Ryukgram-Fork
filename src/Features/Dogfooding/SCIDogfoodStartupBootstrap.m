#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
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

static void SCIInstallExactDogfoodHooks(void) {
    // Each installer is idempotent and performs only direct class/selector
    // lookups. No full Objective-C class scan is allowed in this phase.
    SCIInstallSessionlessMobileConfigEarlyCaptureHooks();
    SCIInstallBugMenuOEMActivationHooks();
    SCIInstallBugMenuActionCellHooks();
    SCIInstallLoggedOutMobileConfigActionHook();
    SCIInstallEmployeeIdentityConsumerHooks();
    SCIInstallEmployeePandoIdentityHooks();
}

static void SCIInstallDeferredDogfoodHooks(void) {
    dispatch_async(SCIDogfoodBootstrapWorker(), ^{
        // These are the only broad runtime scans. They run once after launch at
        // utility QoS, never in a constructor, on the main queue, or per image.
        SCIInstallEmployeeMobileConfigDescriptorHooks();
        SCIInstallEmployeeTestDogfoodRuntimeHooks();
        BOOTLOG("deferred utility hooks installed");
    });
}

static void SCIDogfoodPostLaunchBootstrap(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Retry direct lookups once because some Swift metadata is registered
        // after the tweak constructor. This remains O(fixed selectors), not an
        // image callback or class-list scan.
        SCIInstallExactDogfoodHooks();
        SCIInstallDogfoodObjectHooksIfNeeded();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(1.0 * NSEC_PER_SEC)),
                       SCIDogfoodBootstrapWorker(), ^{
            SCIInstallDeferredDogfoodHooks();
        });
        BOOTLOG("post-launch exact hooks installed; deferred phase scheduled");
    });
}

__attribute__((constructor))
static void SCIDogfoodStartupBootstrapCtor(void) {
    @autoreleasepool {
        // One lightweight constructor owns this feature family's startup.
        SCIInstallExactDogfoodHooks();

        __block id token = nil;
        token = [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
            if (token) {
                [NSNotificationCenter.defaultCenter removeObserver:token];
                token = nil;
            }
            SCIDogfoodPostLaunchBootstrap();
        }];
    }
}
