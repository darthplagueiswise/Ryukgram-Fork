#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Tracks follow requests you send and receive, detecting each outcome by a
// throttled background poll. Capture is driven by hooks.
@interface RYGFollowRequestTracker : NSObject

+ (instancetype)shared;

// Re-read prefs and re-arm the background timer.
- (void)refreshFromPrefs;

// Hook entry points.
- (void)captureFollowForUser:(id)igUser;        // you tapped Follow
- (void)captureCancelForUser:(id)igUser;        // you tapped Unfollow / Requested
- (void)captureIgnoreIncomingPK:(NSString *)pk; // you deleted an incoming request

// Record a re-follow made via our own API (confirms it became pending first).
- (void)recordManualFollowForPK:(NSString *)pk
                       username:(nullable NSString *)username
                       fullName:(nullable NSString *)fullName
                         picURL:(nullable NSString *)picURL
                          picID:(nullable NSString *)picID;

// Poll now, bypassing the throttle (pull-to-refresh).
- (void)checkNowWithCompletion:(nullable void (^)(void))completion;

// force=NO respects the throttle (foreground / list open); YES is manual.
// completion receives how many requests flipped state.
- (void)checkNowForced:(BOOL)force completion:(nullable void (^)(NSInteger changed))completion;

@property (nonatomic, readonly) BOOL isChecking;

@end

NS_ASSUME_NONNULL_END
