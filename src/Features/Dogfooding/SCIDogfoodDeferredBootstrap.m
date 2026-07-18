#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <os/log.h>

#define DFBOOTLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] DogfoodBootstrap " fmt, ##__VA_ARGS__)

void SCIBugMenuOEMActivationInstall(void);
void SCIEmployeeIdentityConsumerHooksInstall(void);

static void SCIDogfoodInstallDeferredHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        SCIBugMenuOEMActivationInstall();
        SCIEmployeeIdentityConsumerHooksInstall();
        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start;
        DFBOOTLOG("one-shot post-activation install %.3f ms", elapsed * 1000.0);
    });
}

__attribute__((constructor))
static void SCIDogfoodDeferredBootstrapCtor(void) {
    @autoreleasepool {
        // Keep Objective-C runtime probing out of the cold-launch constructor.
        // One observer replaces the previous global dyld add-image callbacks.
        __block id token = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            SCIDogfoodInstallDeferredHooks();
            id strongToken = token;
            token = nil;
            if (strongToken) {
                [[NSNotificationCenter defaultCenter] removeObserver:strongToken];
            }
        }];
    }
}
