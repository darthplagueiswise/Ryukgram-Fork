#import <Foundation/Foundation.h>
#import "SCIMobileConfigBrokerDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SCIMCBrokerIndexKey;
FOUNDATION_EXPORT NSString * const SCIMCBrokerHookIndexKey;

@interface SCIMobileConfigBrokerStore : NSObject
+ (void)registerDefaults;
+ (NSString *)overrideKeyForBroker:(SCIMobileConfigBrokerDescriptor *)broker value:(uint64_t)value;
+ (NSString *)observedKeyForOverrideKey:(NSString *)overrideKey;
+ (NSString *)hookEnabledKeyForBrokerID:(NSString *)brokerID;
+ (NSString *)errorKeyForBrokerID:(NSString *)brokerID;
+ (nullable NSNumber *)overrideValueForKey:(NSString *)key;
+ (void)setOverrideValue:(nullable NSNumber *)value forKey:(NSString *)key;
+ (BOOL)hookEnabledForBrokerID:(NSString *)brokerID;
+ (void)setHookEnabled:(BOOL)enabled forBrokerID:(NSString *)brokerID;
+ (void)noteObservedValue:(BOOL)value forOverrideKey:(NSString *)overrideKey;
+ (nullable NSNumber *)observedValueForOverrideKey:(NSString *)overrideKey;
+ (void)setLastError:(nullable NSString *)error forBrokerID:(NSString *)brokerID;
+ (nullable NSString *)lastErrorForBrokerID:(NSString *)brokerID;
+ (NSArray<NSString *> *)activeOverrideKeys;
+ (NSArray<NSString *> *)enabledHookBrokerIDs;
+ (NSArray<NSString *> *)observedOverrideKeys;
+ (BOOL)parseOverrideKey:(NSString *)key brokerID:(NSString **)brokerID image:(NSString **)image symbol:(NSString **)symbol kind:(NSString **)kind value:(uint64_t *)value;
@end

NS_ASSUME_NONNULL_END
