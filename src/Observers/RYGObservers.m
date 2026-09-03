#import "RYGObservers.h"

@implementation RYGObservers

+ (RYGAccountObserver *)account { return [RYGAccountObserver shared]; }

+ (void)observePrefKey:(NSString *)key handler:(void (^)(void))handler {
    [RYGPrefObserver observeKey:key handler:handler];
}

@end
