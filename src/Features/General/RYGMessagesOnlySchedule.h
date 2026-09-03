#import <Foundation/Foundation.h>

// Rebuilds the tab bar for the current messages_only prefs. NO when no live
// tab bar exists, or when the hooks were not installed this launch.
BOOL RYGMessagesOnlyApplyLive(void);

BOOL RYGMessagesOnlyHooksActive(void);

// Flips the messages_only master pref on/off across a daily time window.
// Runtime crossings apply live when possible, else prompt for a restart.
@interface RYGMessagesOnlySchedule : NSObject

+ (instancetype)shared;

- (void)start;
- (void)refreshFromPrefs;
- (BOOL)isWithinWindowNow;

@end
