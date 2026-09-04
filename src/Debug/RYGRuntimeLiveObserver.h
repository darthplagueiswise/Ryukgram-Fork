#import <Foundation/Foundation.h>
@class RYGRuntimeBoolMethod;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const RYGRuntimeNativeValueDidChangeNotification;
FOUNDATION_EXPORT NSString *const RYGRuntimeNativeValueKeyUserInfoKey;

/// Installs pass-through hooks for the supplied methods. These hooks never
/// alter the return value; they record the value produced by the implementation
/// that was active at installation time. This is how the browser can show live
/// values without invoking arbitrary private selectors just to populate cells.
FOUNDATION_EXPORT void RYGRuntimeBeginLiveObservation(NSArray<RYGRuntimeBoolMethod *> *methods);
FOUNDATION_EXPORT NSNumber * _Nullable RYGRuntimeObservedNativeValue(NSString *overrideKey);

NS_ASSUME_NONNULL_END
