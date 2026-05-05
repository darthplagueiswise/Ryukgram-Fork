#import <Foundation/Foundation.h>
#import "SCIDexKitDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIDexKitStore : NSObject
+ (void)registerDefaults;
+ (void)migrateIfNeeded;
+ (void)invalidateObservedCacheIfBuildChanged;
+ (NSString *)currentAppBuildToken;

+ (NSString *)overrideKeyForImage:(NSString *)image sign:(NSString *)sign className:(NSString *)className selector:(NSString *)selector;
+ (NSString *)observedKeyForImage:(NSString *)image sign:(NSString *)sign className:(NSString *)className selector:(NSString *)selector;
+ (NSString *)observedKeyForOverrideKey:(NSString *)overrideKey;
+ (BOOL)parseBoolKey:(NSString *)key image:(NSString **)image sign:(NSString **)sign className:(NSString **)className selector:(NSString **)selector;

+ (NSArray<NSString *> *)activeOverrideKeys;
+ (nullable NSNumber *)overrideValueForKey:(NSString *)overrideKey;
+ (void)setOverrideValue:(nullable NSNumber *)value forKey:(NSString *)overrideKey;
+ (nullable NSNumber *)observedValueForKey:(NSString *)observedKey;
+ (void)noteObservedValue:(BOOL)value forKey:(NSString *)observedKey;
+ (SCIDexKitKnownBoolState)effectiveStateForOverrideKey:(NSString *)overrideKey observedKey:(NSString *)observedKey;

+ (void)beginBootGuard;
+ (void)markLaunchStable;
+ (void)noteApplyingOverrideKey:(NSString *)key;
+ (BOOL)isOverrideQuarantined:(NSString *)key;
+ (NSArray<NSString *> *)quarantinedOverrideKeys;
+ (void)clearQuarantineForKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
