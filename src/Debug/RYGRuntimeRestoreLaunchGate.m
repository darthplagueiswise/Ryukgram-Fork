#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>

// Generic Runtime Browser persistence must never hold up cold launch.
//
// RYGRuntimeHookManager owns exact persisted identities, but its legacy
// constructor invokes +reinstallPersistedOverrides synchronously and schedules
// another replay shortly afterwards.  Some persisted selectors are extremely
// hot during Instagram startup, so installing the generic trampolines before
// the first active frame can multiply launch cost dramatically.
//
// This gate is installed from an earlier constructor.  Dedicated Developer
// owners (Prism, Story, Bug Report, MobileConfig, EasyGating) are unaffected.
// Only generic Runtime Browser replay is deferred until UIApplication is active.

static atomic_bool gRYGRuntimeLaunchGateActive = false;
static atomic_bool gRYGRuntimeLaunchGateDeferred = false;
static atomic_bool gRYGRuntimeLaunchGateRunning = false;
static BOOL gRYGRuntimeLaunchGateInstalled = NO;

@interface RYGRuntimeBrowserEngine (RYGRuntimeRestoreLaunchGate)
+ (void)ryg_launchGate_reinstallPersistedOverrides;
@end

static void RYGRuntimeLaunchGateRunDeferred(void) {
    if (!atomic_load_explicit(&gRYGRuntimeLaunchGateActive, memory_order_acquire)) return;
    if (!atomic_exchange_explicit(&gRYGRuntimeLaunchGateDeferred, false, memory_order_acq_rel)) return;
    [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
}

@implementation RYGRuntimeBrowserEngine (RYGRuntimeRestoreLaunchGate)

+ (void)ryg_launchGate_reinstallPersistedOverrides {
    // After method exchange this selector points to the manager's real replay.
    if (!atomic_load_explicit(&gRYGRuntimeLaunchGateActive, memory_order_acquire)) {
        atomic_store_explicit(&gRYGRuntimeLaunchGateDeferred, true, memory_order_release);
        return;
    }

    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(&gRYGRuntimeLaunchGateRunning,
                                                  &expected,
                                                  true,
                                                  memory_order_acq_rel,
                                                  memory_order_acquire)) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self ryg_launchGate_reinstallPersistedOverrides];
        atomic_store_explicit(&gRYGRuntimeLaunchGateRunning, false, memory_order_release);
        // If another replay request arrived while one was running, coalesce it
        // into one additional pass instead of recursively replaying every event.
        if (atomic_load_explicit(&gRYGRuntimeLaunchGateDeferred, memory_order_acquire) &&
            atomic_load_explicit(&gRYGRuntimeLaunchGateActive, memory_order_acquire)) {
            dispatch_async(dispatch_get_main_queue(), ^{ RYGRuntimeLaunchGateRunDeferred(); });
        }
    });
}

@end

__attribute__((constructor(101))) static void RYGInstallRuntimeRestoreLaunchGate(void) {
    Class cls = object_getClass(RYGRuntimeBrowserEngine.class);
    Method original = class_getInstanceMethod(cls, @selector(reinstallPersistedOverrides));
    Method gated = class_getInstanceMethod(cls, @selector(ryg_launchGate_reinstallPersistedOverrides));
    if (original && gated) {
        method_exchangeImplementations(original, gated);
        gRYGRuntimeLaunchGateInstalled = YES;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
            atomic_store_explicit(&gRYGRuntimeLaunchGateActive, true, memory_order_release);
            if (gRYGRuntimeLaunchGateInstalled) RYGRuntimeLaunchGateRunDeferred();
        }];
        [center addObserverForName:UIApplicationWillResignActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(__unused NSNotification *note) {
            atomic_store_explicit(&gRYGRuntimeLaunchGateActive, false, memory_order_release);
        }];
        if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            atomic_store_explicit(&gRYGRuntimeLaunchGateActive, true, memory_order_release);
            if (gRYGRuntimeLaunchGateInstalled) RYGRuntimeLaunchGateRunDeferred();
        }
    });
}
