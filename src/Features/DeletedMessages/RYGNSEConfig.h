#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Bridges main-app prefs into a JSON in the shared app-group container so the
// Notification Service Extension (a separate process) can gate itself.
@interface RYGNSEConfig : NSObject

// <group>/RyukGram absolute dir, shared by main app + appex. nil without an app group.
+ (nullable NSString *)sharedDir;

// Mirror the NSE-relevant prefs into <sharedDir>/nse_config.json.
+ (void)sync;

// Sync now and re-sync on pref changes. Idempotent.
+ (void)startObserving;

@end

NS_ASSUME_NONNULL_END
