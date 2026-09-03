// Deleted-message date formatting. Re-reads dm_log_date_format per call so the
// setting applies without a relaunch.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGDeletedMessagesDate : NSObject

// Compact label for cells and row metadata.
+ (NSString *)stringForDate:(nullable NSDate *)date;

+ (NSString *)stringForDeletedAt:(nullable NSDate *)deletedAt sentAt:(nullable NSDate *)sentAt;

// Always full date and time, never relative.
+ (NSString *)verboseStringForDate:(nullable NSDate *)date;

@end

NS_ASSUME_NONNULL_END
