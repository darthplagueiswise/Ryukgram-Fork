#import <Foundation/Foundation.h>

// KVO on a single NSUserDefaults key. Handler runs on main queue.
// App-lifetime observer — no teardown.
//
// Usage:
//   [RYGPrefObserver observeKey:@"my_pref_key" handler:^{
//       // main queue — do the reflect work here
//   }];
@interface RYGPrefObserver : NSObject

+ (void)observeKey:(NSString *)key handler:(void (^)(void))handler;

@end
