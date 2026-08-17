#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const RYGEasyGatingDidObserveNotification;
FOUNDATION_EXPORT NSString *const RYGEasyGatingGateIDUserInfoKey;

@interface RYGEasyGatingObservation : NSObject
@property (nonatomic, assign) uint32_t gateID;
@property (nonatomic, assign) uint32_t variant;
@property (nonatomic, assign) BOOL nativeValue;
@property (nonatomic, assign) NSUInteger callCount;
@property (nonatomic, strong) NSDate *lastSeen;
@property (nonatomic, readonly, nullable) NSNumber *overrideValue;
@end

@interface RYGEasyGatingRuntime : NSObject
+ (instancetype)shared;

/// Installs a fishhook rebinding for the exact C entry point imported by the
/// supplied Instagram executable: EasyGatingGetBoolean_Internal_DoNotUseOrMock.
/// It never changes a return value unless the user created an override for that
/// concrete gate ID.
- (void)installIfNeeded;

/// Process-live observations, sorted by numeric gate ID. No pointer/context
/// values are persisted.
- (NSArray<RYGEasyGatingObservation *> *)observations;

- (nullable NSNumber *)overrideForGateID:(uint32_t)gateID;
- (void)setOverride:(nullable NSNumber *)value forGateID:(uint32_t)gateID;
- (void)clearObservations;
@end

NS_ASSUME_NONNULL_END
