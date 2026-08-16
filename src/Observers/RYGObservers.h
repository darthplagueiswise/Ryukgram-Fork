// One roof for the tweak's app-wide observers (active account, prefs). Feature-
// local "…DidChangeNotification" store events stay in their own files.

#import <Foundation/Foundation.h>
#import "RYGAccountObserver.h"
#import "RYGPrefObserver.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGObservers : NSObject

// Active signed-in account (quick-switch / login / logout).
+ (RYGAccountObserver *)account;

// KVO on a single NSUserDefaults key; handler runs on the main queue.
+ (void)observePrefKey:(NSString *)key handler:(void (^)(void))handler;

@end

NS_ASSUME_NONNULL_END
