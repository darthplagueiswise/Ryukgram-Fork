#import <Foundation/Foundation.h>
#import "SCIMobileConfigBrokerDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void SCIMCBrokerBootstrap(void);
FOUNDATION_EXPORT BOOL SCIMCBrokerInstall(SCIMobileConfigBrokerDescriptor *broker, NSError **error);
FOUNDATION_EXPORT BOOL SCIMCBrokerIsInstalled(NSString *brokerID);
FOUNDATION_EXPORT NSUInteger SCIMCBrokerInstalledCount(void);
FOUNDATION_EXPORT NSString *SCIMCBrokerRuntimeSummary(void);

NS_ASSUME_NONNULL_END
