#import <Foundation/Foundation.h>

// Flips the messages_only master pref on/off across a daily time window.
// Runtime crossings prompt a restart; launch crossings apply silently.
@interface SCIMessagesOnlySchedule : NSObject

+ (instancetype)shared;

- (void)start;            // launch: arm timer + apply silently
- (void)refreshFromPrefs; // toggle/time changed: re-apply + re-arm
- (BOOL)isWithinWindowNow;

@end
