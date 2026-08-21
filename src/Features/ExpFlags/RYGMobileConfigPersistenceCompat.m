#import "RYGMobileConfig.h"
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

static BOOL gRYGMobileConfigRestoreScheduled;

static void RYGReapplyPersistedMobileConfig(void) {
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    if (!mobileConfig || mobileConfig.overrideCount == 0) return;
    [mobileConfig reapplyOverridesToNativeTable];
}

static void RYGScheduleMobileConfigRestoreAfter(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RYGReapplyPersistedMobileConfig();
    });
}

static void RYGScheduleMobileConfigRestore(void) {
    @synchronized(RYGMobileConfig.class) {
        if (gRYGMobileConfigRestoreScheduled) return;
        gRYGMobileConfigRestoreScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized(RYGMobileConfig.class) { gRYGMobileConfigRestoreScheduled = NO; }
        RYGReapplyPersistedMobileConfig();
    });
}

static void RYGMobileConfigPersistenceImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    RYGScheduleMobileConfigRestore();
}

__attribute__((constructor)) static void RYGInstallMobileConfigPersistenceCompat(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            RYGScheduleMobileConfigRestore();
        }];
        RYGScheduleMobileConfigRestoreAfter(0.25);
        RYGScheduleMobileConfigRestoreAfter(0.9);
        RYGScheduleMobileConfigRestoreAfter(2.2);
        RYGScheduleMobileConfigRestoreAfter(4.5);
    });
    _dyld_register_func_for_add_image(RYGMobileConfigPersistenceImageDidLoad);
}
