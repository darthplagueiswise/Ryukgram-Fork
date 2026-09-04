#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const RYGEasyGatingDidObserveNotification;
FOUNDATION_EXPORT NSString *const RYGEasyGatingGateIDUserInfoKey;

@interface RYGEasyGatingObservation : NSObject
@property (nonatomic, assign) uint32_t gateID;
@property (nonatomic, assign) BOOL defaultValue;
@property (nonatomic, assign) BOOL exposureEnabled;
@property (nonatomic, assign) BOOL nativeValue;
@property (nonatomic, assign) NSUInteger callCount;
@property (nonatomic, strong) NSDate *lastSeen;
@property (nonatomic, readonly, nullable) NSNumber *overrideValue;
@end

@interface RYGEasyGatingRuntime : NSObject
+ (instancetype)shared;

/// Registers a fishhook rebinding for imported references to the final mapped
/// EasyGatingPlatformGetBoolean entry point. This deliberately does not inline
/// patch FBSharedFramework.__TEXT: sideload code-signing kills processes that
/// later execute a modified signed page. Direct same-image branches that do not
/// use an import slot are therefore left untouched rather than patched unsafely.
- (void)installIfNeeded;

- (NSArray<RYGEasyGatingObservation *> *)observations;
- (nullable NSNumber *)overrideForGateID:(uint32_t)gateID;
- (void)setOverride:(nullable NSNumber *)value forGateID:(uint32_t)gateID;
- (void)clearObservations;
@end

NS_ASSUME_NONNULL_END
