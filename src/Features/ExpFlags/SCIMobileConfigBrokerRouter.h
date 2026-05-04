#import <Foundation/Foundation.h>
#import "SCIMobileConfigBrokerDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIMobileConfigBrokerRouter : NSObject
+ (void)bootstrap;
+ (BOOL)installBroker:(SCIMobileConfigBrokerDescriptor *)descriptor error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)isInstalled:(NSString *)brokerID;
+ (NSUInteger)installedCount;
+ (NSDictionary<NSString *, NSString *> *)installErrors;
+ (void)installEnabledBrokers;
+ (void)retryPendingBrokersForImageBasename:(NSString *)basename;
@end

NS_ASSUME_NONNULL_END
