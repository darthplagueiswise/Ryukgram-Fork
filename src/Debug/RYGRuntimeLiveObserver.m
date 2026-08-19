#import "RYGRuntimeLiveObserver.h"
#import "RYGRuntimeBrowserEngine.h"

NSString *const RYGRuntimeNativeValueDidChangeNotification = @"RYGRuntimeNativeValueDidChangeNotification";
NSString *const RYGRuntimeNativeValueKeyUserInfoKey = @"overrideKey";

NSNumber *RYGRuntimeObservedNativeValue(NSString *overrideKey) {
    if (!overrideKey.length) return nil;
    return [RYGRuntimeBrowserEngine observedNativeValueForKey:overrideKey];
}

void RYGRuntimeBeginLiveObservation(NSArray<RYGRuntimeBoolMethod *> *methods) {
    if (!methods.count) return;
    NSArray<RYGRuntimeBoolMethod *> *rows = methods.copy;
    void (^install)(void) = ^{
        // Explicit observation only. The runtime browser never fans hooks over
        // an executable simply because a screen was opened. Observation and
        // Force True/False share the exact same engine/trampoline, so there is
        // only one original IMP chain per method.
        NSUInteger limit = MIN(rows.count, (NSUInteger)64);
        for (NSUInteger index = 0; index < limit; index++) {
            id candidate = rows[index];
            if ([candidate isKindOfClass:RYGRuntimeBoolMethod.class]) {
                [RYGRuntimeBrowserEngine observeMethod:(RYGRuntimeBoolMethod *)candidate];
            }
        }
    };
    if (NSThread.isMainThread) install();
    else dispatch_async(dispatch_get_main_queue(), install);
}
