#import "RYGMobileConfig.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdatomic.h>

static atomic_bool gRYGMCStartupSyncReady = false;

static void RYGMCArmNativeSync(void) {
    atomic_store_explicit(&gRYGMCStartupSyncReady, true, memory_order_release);
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    if (mobileConfig.overrideCount) [mobileConfig reapplyOverridesToNativeTable];
}

@implementation RYGMobileConfig (RYGMobileConfigStartupSyncGate)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod(self, @selector(reapplyOverridesToNativeTable));
        Method guarded = class_getInstanceMethod(self, @selector(ryg_launchSafe_reapplyOverridesToNativeTable));
        if (original && guarded) method_exchangeImplementations(original, guarded);
    });
}

- (void)ryg_launchSafe_reapplyOverridesToNativeTable {
    if (!atomic_load_explicit(&gRYGMCStartupSyncReady, memory_order_acquire)) return;
    [self ryg_launchSafe_reapplyOverridesToNativeTable];
}

@end

__attribute__((constructor)) static void RYGInstallMobileConfigStartupSyncGate(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) { RYGMCArmNativeSync(); }];
        [center addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) { RYGMCArmNativeSync(); }];
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) RYGMCArmNativeSync();
    });
}
