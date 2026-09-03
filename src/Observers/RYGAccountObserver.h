// Global active-account observer. Fires whenever the signed-in IG account
// changes (quick-switch, login, logout). One shared instance, many subscribers.
// Detection polls currentUserPK at coarse triggers (foreground, tab-bar appear).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RYGActiveAccountDidChangeNotification;
extern NSString *const RYGAccountObserverPreviousPKKey;   // NSString, or NSNull if none
extern NSString *const RYGAccountObserverCurrentPKKey;    // NSString, or NSNull if none

typedef void (^RYGAccountChangeHandler)(NSString *_Nullable previousPK, NSString *_Nullable currentPK);

@interface RYGAccountObserver : NSObject

+ (instancetype)shared;

// nil before any account resolves. Thread-safe.
@property (atomic, copy, readonly, nullable) NSString *currentPK;

// Idempotent; installs the triggers.
- (void)start;

// Force a check now — call after a code path that itself causes a switch.
- (void)refreshNow;

// Handler fires on the main thread; returns a token for -removeChangeHandler:.
- (id)addChangeHandler:(RYGAccountChangeHandler)handler;
- (void)removeChangeHandler:(nullable id)token;

@end

NS_ASSUME_NONNULL_END
