#import "RYGDeletedMessagesDate.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"

@implementation RYGDeletedMessagesDate

+ (NSDateFormatter *)shortFormatter {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.dateStyle = NSDateFormatterShortStyle;
        f.timeStyle = NSDateFormatterShortStyle;
    });
    return f;
}

+ (NSDateFormatter *)mediumFormatter {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.dateStyle = NSDateFormatterMediumStyle;
        f.timeStyle = NSDateFormatterShortStyle;
    });
    return f;
}

+ (NSDateFormatter *)dayMonthFormatter {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMd" options:0
                                                       locale:[NSLocale currentLocale]];
    });
    return f;
}

+ (NSDateFormatter *)timeOnlyFormatter {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.dateStyle = NSDateFormatterNoStyle;
        f.timeStyle = NSDateFormatterShortStyle;
    });
    return f;
}

// Tight relative-time formatter — "now", "Nm ago", "Nh ago", "Nd ago"
// (up to 6 days), otherwise falls back to abbreviated month-day. Today's
// times are shown as the time-only string so the user can tell which
// message is most recent at a glance.
+ (NSString *)relativeStringForDate:(NSDate *)d {
    if (!d) return @"";
    NSTimeInterval delta = -[d timeIntervalSinceNow];
    if (delta < 0) delta = 0;
    if (delta < 60)        return RYGLocalized(@"now");
    if (delta < 3600)      return [NSString stringWithFormat:RYGLocalized(@"%dm ago"), (int)(delta / 60)];
    if (delta < 86400) {
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDate *startOfToday = [cal startOfDayForDate:[NSDate date]];
        if ([d compare:startOfToday] != NSOrderedAscending) {
            return [[self timeOnlyFormatter] stringFromDate:d];
        }
        return [NSString stringWithFormat:RYGLocalized(@"%dh ago"), (int)(delta / 3600)];
    }
    if (delta < 86400 * 7) return [NSString stringWithFormat:RYGLocalized(@"%dd ago"), (int)(delta / 86400)];
    return [[self dayMonthFormatter] stringFromDate:d];
}

+ (NSString *)stringForDate:(NSDate *)d {
    if (!d) return @"";
    NSString *mode = [RYGUtils getStringPref:@"dm_log_date_format"];
    if (![mode isEqualToString:@"absolute"]) return [self relativeStringForDate:d];
    return [[self shortFormatter] stringFromDate:d];
}

+ (NSDateFormatter *)dayMonthYearFormatter {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [NSDateFormatter new];
        f.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMdyyyy" options:0
                                                       locale:[NSLocale currentLocale]];
    });
    return f;
}

+ (NSString *)stringForDeletedAt:(NSDate *)deletedAt sentAt:(NSDate *)sentAt {
    NSString *base = [self stringForDate:deletedAt];
    if (!sentAt) return base;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter;

    if ([cal isDateInToday:sentAt]) formatter = [self timeOnlyFormatter];
    else if ([cal component:NSCalendarUnitYear fromDate:sentAt] == [cal component:NSCalendarUnitYear fromDate:now]) formatter = [self dayMonthFormatter];
    else formatter = [self dayMonthYearFormatter];

    NSString *sent = [formatter stringFromDate:sentAt];
    if (!sent.length) return base;

    return base.length ? [NSString stringWithFormat:RYGLocalized(@"%@ · sent %@"), base, sent] : sent;
}

+ (NSString *)verboseStringForDate:(NSDate *)d {
    if (!d) return @"";
    return [[self mediumFormatter] stringFromDate:d];
}

@end
