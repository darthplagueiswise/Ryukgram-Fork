#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Fired on any real presence flip for a known pk (userInfo: @"pk", @"active").
FOUNDATION_EXPORT NSNotificationName const RYGActivityPresenceDidChangeNotification;

// Central gate + dedup + notify/log for live presence and typing signals.
@interface RYGActivityEngine : NSObject

// snapshot = IG's initial already-online baseline; recorded, never announced.
+ (void)handlePresenceActive:(BOOL)active forPK:(nullable NSString *)pk lastActivityAtMs:(double)ms snapshot:(BOOL)snapshot;
+ (void)handleTypingActive:(BOOL)active forPK:(nullable NSString *)pk threadId:(nullable NSString *)threadId;

// 1 = active, 0 = offline, -1 = unknown (never seen).
+ (int)presenceForPK:(nullable NSString *)pk;

// Match a header's lastActiveTime (ms) to a tracked pk when we lack its pk.
+ (int)presenceForLastActiveMs:(double)ms;

@end

NS_ASSUME_NONNULL_END
