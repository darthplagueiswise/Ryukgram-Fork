#import <Foundation/Foundation.h>

@class RYGRuntimeBoolMethod;

NS_ASSUME_NONNULL_BEGIN

/// Single owner for Runtime Browser method overrides.
/// Discovery belongs to the browser; this manager only installs/replays exact
/// persisted {class, selector, meta, ABI} specs and keeps hot-path values in RAM.
@interface RYGRuntimeHookManager : NSObject
+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method;
+ (nullable NSNumber *)observedNativeValueForKey:(NSString *)overrideKey;
+ (nullable NSNumber *)overrideForKey:(NSString *)overrideKey;
+ (BOOL)setOverride:(nullable NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method;
+ (void)restorePersistedOverrides;
+ (NSUInteger)persistedOverrideCount;
@end

NS_ASSUME_NONNULL_END
