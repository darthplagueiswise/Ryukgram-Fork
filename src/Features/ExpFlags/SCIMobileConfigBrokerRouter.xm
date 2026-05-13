#import "SCIMobileConfigBrokerRouter.h"
#import "SCIMobileConfigBrokerStore.h"
#import <Foundation/Foundation.h>

static NSString *SCIMCBrokerNoopMessage(void) {
    return @"MC Broker runtime observer disabled for launch stability";
}

static NSError *SCIMCBrokerNoopError(void) {
    return [NSError errorWithDomain:@"SCIMobileConfigBrokerRouter"
                               code:410
                           userInfo:@{NSLocalizedDescriptionKey: SCIMCBrokerNoopMessage()}];
}

@implementation SCIMobileConfigBrokerRouter

+ (void)bootstrap {
    [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
    NSLog(@"[RyukGram][MCBR] %@", SCIMCBrokerNoopMessage());
}

+ (BOOL)installBroker:(SCIMobileConfigBrokerDescriptor *)descriptor error:(NSError * _Nullable * _Nullable)error {
    NSString *brokerID = descriptor.brokerID ?: @"unknown";
    [SCIMobileConfigBrokerStore setBrokerHookEnabled:NO brokerID:brokerID];
    [SCIMobileConfigBrokerStore noteLastError:SCIMCBrokerNoopMessage() brokerID:brokerID];
    if (error) *error = SCIMCBrokerNoopError();
    return NO;
}

+ (BOOL)isInstalled:(NSString *)brokerID {
    (void)brokerID;
    return NO;
}

+ (NSUInteger)installedCount {
    return 0;
}

+ (NSDictionary<NSString *,NSString *> *)installErrors {
    return @{@"disabled": SCIMCBrokerNoopMessage()};
}

+ (void)installEnabledBrokers {
}

+ (void)retryPendingBrokersForImageBasename:(NSString *)basename {
    (void)basename;
}

@end

%ctor {
    [SCIMobileConfigBrokerRouter bootstrap];
}
