#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const RYGEasyGatingDidObserveNotification;
FOUNDATION_EXPORT NSString *const RYGEasyGatingGateIDUserInfoKey;

@interface RYGEasyGatingObservation : NSObject
/// Final mapped Easy Gating ID received by EasyGatingPlatformGetBoolean.
@property (nonatomic, assign) uint32_t gateID;
/// Native/default Boolean passed in w2/x2 to EasyGatingPlatformGetBoolean.
@property (nonatomic, assign) BOOL defaultValue;
/// Booleanized exposure/logging flag passed in w3/x3 by the internal wrapper.
@property (nonatomic, assign) BOOL exposureEnabled;
/// Actual result returned by the unmodified platform function before an override.
@property (nonatomic, assign) BOOL nativeValue;
@property (nonatomic, assign) NSUInteger callCount;
@property (nonatomic, strong) NSDate *lastSeen;
@property (nonatomic, readonly, nullable) NSNumber *overrideValue;
@end

@interface RYGEasyGatingRuntime : NSObject
+ (instancetype)shared;

/// Hooks the final platform-level Boolean entry point. The supplied
/// FBSharedFramework maps EasyGatingGetBoolean_Internal_DoNotUseOrMock's w1
/// selector/index to the concrete gate ID before tail-calling
/// EasyGatingPlatformGetBoolean with x0=context, w1=gate ID, w2=default Boolean,
/// w3=exposure flag. Hooking this level avoids mistaking the pre-map selector for
/// the concrete gate ID and leaves the original result untouched unless the user
/// explicitly overrides that mapped gate.
- (void)installIfNeeded;

/// Process-live observations, sorted by final mapped gate ID. No context pointer
/// is retained or persisted.
- (NSArray<RYGEasyGatingObservation *> *)observations;

- (nullable NSNumber *)overrideForGateID:(uint32_t)gateID;
- (void)setOverride:(nullable NSNumber *)value forGateID:(uint32_t)gateID;
- (void)clearObservations;
@end

NS_ASSUME_NONNULL_END
