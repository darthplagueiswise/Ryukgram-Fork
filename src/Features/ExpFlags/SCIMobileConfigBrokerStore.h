#import <Foundation/Foundation.h>
#import "SCIMobileConfigBrokerDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SCIMCBrokerStoreDidChangeNotification;
FOUNDATION_EXPORT NSString * const SCIMCBrokerIndexKey;
FOUNDATION_EXPORT NSString * const SCIMCBrokerObservedIndexKey;
FOUNDATION_EXPORT NSString * const SCIMCBrokerHookIndexKey;

typedef NS_ENUM(NSInteger, SCIMCBrokerBoolState) {
    SCIMCBrokerBoolStateSystem = -1,
    SCIMCBrokerBoolStateOff = 0,
    SCIMCBrokerBoolStateOn = 1,
};

@interface SCIMobileConfigBrokerStore : NSObject
+ (void)registerDefaultsAndMigrate;

// Short per-value namespace: mcbr:<brokerID>:<hex64>. This is the compact form of dexkit.cbool.
+ (NSString *)overrideKeyForBroker:(SCIMobileConfigBrokerDescriptor *)broker value:(uint64_t)value;
+ (NSString *)overrideKeyForBrokerID:(NSString *)brokerID value:(uint64_t)value;
+ (NSString *)observedKeyForOverrideKey:(NSString *)overrideKey;
+ (NSString *)hookEnabledKeyForBrokerID:(NSString *)brokerID;
+ (NSString *)lastErrorKeyForBrokerID:(NSString *)brokerID;

+ (BOOL)parseOverrideKey:(NSString *)key brokerID:(NSString * _Nullable * _Nullable)brokerID value:(uint64_t * _Nullable)value;
+ (nullable NSNumber *)overrideValueForKey:(NSString *)key;
+ (void)setOverrideValue:(nullable NSNumber *)value forKey:(NSString *)key;
+ (nullable NSNumber *)observedValueForOverrideKey:(NSString *)overrideKey;
+ (void)noteObservedValue:(BOOL)value forOverrideKey:(NSString *)overrideKey;

+ (NSArray<NSString *> *)activeOverrideKeys;
+ (NSArray<NSString *> *)activeOverrideKeysForBrokerID:(NSString *)brokerID;
+ (NSArray<NSString *> *)observedOverrideKeys;
+ (NSArray<NSString *> *)observedOverrideKeysForBrokerID:(NSString *)brokerID;
+ (NSArray<NSString *> *)enabledHookBrokerIDs;

+ (BOOL)isBrokerHookEnabledForID:(NSString *)brokerID;
+ (void)setBrokerHookEnabled:(BOOL)enabled brokerID:(NSString *)brokerID;
+ (BOOL)hasAnyActiveOverridesOrHooks;
+ (BOOL)shouldInstallBrokerID:(NSString *)brokerID;

+ (void)noteLastError:(nullable NSString *)error brokerID:(NSString *)brokerID;
+ (nullable NSString *)lastErrorForBrokerID:(NSString *)brokerID;
+ (void)noteHitForBrokerID:(NSString *)brokerID value:(uint64_t)value forced:(BOOL)forced;
+ (NSUInteger)hitCountForBrokerID:(NSString *)brokerID;
+ (NSUInteger)forcedHitCountForBrokerID:(NSString *)brokerID;

+ (SCIMCBrokerBoolState)effectiveStateForOverrideKey:(NSString *)overrideKey;
+ (NSString *)stateLabelForOverrideKey:(NSString *)overrideKey;
+ (NSString *)systemLabelForOverrideKey:(NSString *)overrideKey;
+ (NSString *)overrideLabelForOverrideKey:(NSString *)overrideKey;
+ (NSDictionary *)resolvedMetadataForOverrideKey:(NSString *)overrideKey;
+ (NSDictionary *)snapshotDictionary;
+ (void)resetAllBrokerOverrides;

// Compatibility for older menu code. These keys are broker-wide lab keys and are not used by the v2 router.
+ (NSString *)overrideKeyForBrokerID:(NSString *)brokerID;
+ (NSString *)observedKeyForBrokerID:(NSString *)brokerID;
+ (nullable NSNumber *)overrideValueForBrokerID:(NSString *)brokerID;
+ (void)setOverrideValue:(nullable NSNumber *)value forBrokerID:(NSString *)brokerID;
+ (nullable NSNumber *)observedValueForBrokerID:(NSString *)brokerID;
+ (void)noteObservedValue:(BOOL)value brokerID:(NSString *)brokerID;
+ (SCIMCBrokerBoolState)effectiveStateForBrokerID:(NSString *)brokerID;
+ (NSString *)stateLabelForBrokerID:(NSString *)brokerID;
+ (NSString *)systemLabelForBrokerID:(NSString *)brokerID;
+ (NSString *)overrideLabelForBrokerID:(NSString *)brokerID;
+ (NSArray<NSString *> *)activeOverrideBrokerIDs;
+ (void)noteHitForBrokerID:(NSString *)brokerID forced:(BOOL)forced;
@end

NS_ASSUME_NONNULL_END
