#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const SCIBoolOverrideResolverDidChangeNotification;

@interface SCIBoolOverrideResolver : NSObject
+ (void)registerDefaults;
+ (void)reloadSnapshotFromDefaults;
+ (nullable NSNumber *)overrideValueForKey:(NSString *)overrideKey;
+ (void)setOverrideValue:(nullable NSNumber *)value forKey:(NSString *)overrideKey;
+ (NSArray<NSString *> *)activeOverrideKeys;
+ (BOOL)hasOverrideForKey:(NSString *)overrideKey;
@end

FOUNDATION_EXPORT BOOL SCIResolvePersistedBoolOverride(NSString *key, BOOL originalValue);

NS_ASSUME_NONNULL_END
