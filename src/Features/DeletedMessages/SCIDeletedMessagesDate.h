// Single source of truth for "when was this deleted" formatting. Reads
// `dm_log_date_format` pref (relative / absolute) on every call so the user
// can flip the setting and see the effect immediately, no relaunch.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIDeletedMessagesDate : NSObject

// Compact label used in cells / row metadata. Honors the pref.
+ (NSString *)stringForDate:(nullable NSDate *)date;

// Verbose label for tooltips / detail VCs. Always full date+time, never
// relative — used where space isn't an issue.
+ (NSString *)verboseStringForDate:(nullable NSDate *)date;

@end

NS_ASSUME_NONNULL_END
