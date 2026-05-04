#import <Foundation/Foundation.h>
#import "SCIMobileConfigBrokerDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SCIMCBrokerStoreDidChangeNotification;

typedef NS_ENUM(NSInteger, SCIMCBrokerBoolState) {
    SCIMCBrokerBoolStateSystem = -1,
    SCIMCBrokerBoolStateOff = 0,
    SCIMCBrokerBoolStateOn = 1,
};

@interface SCIMobileConfigBrokerStore : NSObject
+ (void)registerDefaultsAndMigrate;
+ (NSString *)overrideKeyForBrokerID:(NSString *)brokerID;    // mcbr:<id>
+ (NSString *)observedKeyForBrokerID:(NSString *)brokerID;    // mcob:<id>
+ (NSString *)lastErrorKeyForBrokerID:(NSString *)brokerID;   // mcer:<id>
+ (NSArray<NSString *> *)activeOverrideBrokerIDs;
+ (nullable NSNumber *)overrideValueForBrokerID:(NSString *)brokerID;
+ (void)setOverrideValue:(nullable NSNumber *)value forBrokerID:(NSString *)brokerID;
+ (nullable NSNumber *)observedValueForBrokerID:(NSString *)brokerID;
+ (void)noteObservedValue:(BOOL)value brokerID:(NSString *)brokerID;
+ (void)noteLastError:(nullable NSString *)error brokerID:(NSString *)brokerID;
+ (nullable NSString *)lastErrorForBrokerID:(NSString *)brokerID;
+ (BOOL)isBrokerHookEnabledForID:(NSString *)brokerID;
+ (void)setBrokerHookEnabled:(BOOL)enabled brokerID:(NSString *)brokerID;
+ (SCIMCBrokerBoolState)effectiveStateForBrokerID:(NSString *)brokerID;
+ (NSString *)stateLabelForBrokerID:(NSString *)brokerID;
+ (NSString *)systemLabelForBrokerID:(NSString *)brokerID;
+ (NSString *)overrideLabelForBrokerID:(NSString *)brokerID;
+ (void)noteHitForBrokerID:(NSString *)brokerID forced:(BOOL)forced;
+ (NSUInteger)hitCountForBrokerID:(NSString *)brokerID;
+ (NSUInteger)forcedHitCountForBrokerID:(NSString *)brokerID;
+ (NSDictionary *)snapshotDictionary;
+ (void)resetAllBrokerOverrides;
@end

NS_ASSUME_NONNULL_END
