#import "RYGDateFormatRender.h"
#import "../../Utils.h"
#import "RYGDateFormatTemplate.h"

static NSString *const kDateFmtKey = @"feed_date_format";
static NSString *const kShowSecondsKey = @"feed_date_show_seconds";
static NSString *const kRelativeThresholdKey = @"feed_date_relative_days_threshold";
static NSString *const kCompactRelativeKey = @"feed_date_compact_relative";
static NSString *const kCombineKey = @"feed_date_combine_with_date";

static NSDictionary<NSString *, NSArray<NSString *> *> *rygDatePatternMap(void) {
	static NSDictionary *map = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			@"short": @[@"MMM d", @"MMM d"],
			@"medium": @[@"MMM d, yyyy", @"MMM d, yyyy"],
			@"full": @[@"MMM d, yyyy 'at' h:mm a", @"MMM d, yyyy 'at' h:mm:ss a"],
			@"time_12": @[@"MMM d 'at' h:mm a", @"MMM d 'at' h:mm:ss a"],
			@"time_24": @[@"MMM d 'at' HH:mm", @"MMM d 'at' HH:mm:ss"],
			@"dd_mmm": @[@"dd-MMM-yyyy 'at' h:mm a", @"dd-MMM-yyyy 'at' h:mm:ss a"],
			@"day_slash": @[@"dd/MM/yyyy h:mm a", @"dd/MM/yyyy h:mm:ss a"],
			@"day_slash_24": @[@"dd/MM/yyyy HH:mm", @"dd/MM/yyyy HH:mm:ss"],
			@"month_slash": @[@"MM/dd/yyyy h:mm a", @"MM/dd/yyyy h:mm:ss a"],
			@"euro": @[@"dd.MM.yyyy HH:mm", @"dd.MM.yyyy HH:mm:ss"],
			@"iso": @[@"yyyy-MM-dd", @"yyyy-MM-dd"],
			@"iso_time": @[@"yyyy-MM-dd HH:mm", @"yyyy-MM-dd HH:mm:ss"],
		};
	});
	return map;
}

static NSDateFormatter *rygFormatterForPattern(NSString *pattern) {
	if (!pattern.length) return nil;

	static NSMutableDictionary<NSString *, NSDateFormatter *> *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

	@synchronized(cache) {
		NSDateFormatter *df = cache[pattern];
		if (!df) {
			df = [NSDateFormatter new];
			df.locale = [NSLocale currentLocale];
			df.dateFormat = pattern;
			cache[pattern] = df;
		}
		return df;
	}
}

static NSString *rygRelativeUnit(NSInteger value, NSString *compactKey, NSString *oneKey, NSString *manyKey, BOOL compact) {
	if (compact) return [NSString stringWithFormat:RYGLocalized(compactKey), (long)value];
	return [NSString stringWithFormat:RYGLocalized(value == 1 ? oneKey : manyKey), (long)value];
}

static NSString *rygRelativeText(NSDate *date, BOOL compact) {
	if (!date) return nil;

	NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:date];
	if (diff < 0) diff = 0;

	if (diff < 60.0) return compact ? RYGLocalized(@"now") : RYGLocalized(@"just now");

	NSInteger minutes = (NSInteger)(diff / 60.0);
	if (minutes < 60) return rygRelativeUnit(minutes, @"%ldm", @"%ld minute ago", @"%ld minutes ago", compact);

	NSInteger hours = (NSInteger)(diff / 3600.0);
	if (hours < 24) return rygRelativeUnit(hours, @"%ldh", @"%ld hour ago", @"%ld hours ago", compact);

	NSInteger days = (NSInteger)(diff / 86400.0);
	if (days < 7) return rygRelativeUnit(MAX(days, 1), @"%ldd", @"%ld day ago", @"%ld days ago", compact);

	NSInteger weeks = (NSInteger)(diff / 604800.0);
	return rygRelativeUnit(MAX(weeks, 1), @"%ldw", @"%ld week ago", @"%ld weeks ago", compact);
}

static NSString *rygRelativeFormat(NSDate *date) {
	if (!date) return nil;

	NSInteger thresholdDays = (NSInteger)[RYGUtils getDoublePref:kRelativeThresholdKey];
	if (thresholdDays <= 0) return nil;

	NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:date];
	if (diff < 0) diff = 0;

	if (diff >= (NSTimeInterval)thresholdDays * 86400.0) return nil;

	return rygRelativeText(date, [RYGUtils getBoolPref:kCompactRelativeKey]);
}

NSString *RYGCompactRelativeDateString(NSDate *date) {
	return rygRelativeText(date, YES);
}

NSString *RYGDateStringForKey(NSDate *date, NSString *fmtKey, BOOL showSeconds) {
	if (!date || !fmtKey.length || [fmtKey isEqualToString:@"default"]) return nil;

	NSString *pattern = nil;
	if ([fmtKey hasPrefix:@"custom:"]) {
		pattern = RYGDateFormatPatternFromTemplate(RYGDateFormatCustomTemplateForKey(fmtKey));
	} else {
		NSArray *patterns = rygDatePatternMap()[fmtKey];
		if (!patterns.count) return nil;
		pattern = patterns[showSeconds ? 1 : 0];
	}
	if (!pattern.length) return nil;

	NSDateFormatter *df = rygFormatterForPattern(pattern);
	if (!df) return nil;

	@synchronized(df) {
		return [df stringFromDate:date];
	}
}

NSString *RYGGeneralDateString(NSDate *date) {
	NSString *relative = rygRelativeFormat(date);
	if (relative.length) return relative;

	NSString *absolute = RYGDateStringForKey(date, [RYGUtils getStringPref:kDateFmtKey], [RYGUtils getBoolPref:kShowSecondsKey]);
	if (!absolute.length) return absolute;

	NSString *mode = [RYGUtils getStringPref:kCombineKey];
	if (![mode isEqualToString:@"absolute_first"] && ![mode isEqualToString:@"relative_first"]) return absolute;

	NSString *rel = rygRelativeText(date, YES);
	if (!rel.length) return absolute;

	if ([mode isEqualToString:@"relative_first"]) return [NSString stringWithFormat:@"%@ – %@", rel, absolute];
	return [NSString stringWithFormat:@"%@ (%@)", absolute, rel];
}
