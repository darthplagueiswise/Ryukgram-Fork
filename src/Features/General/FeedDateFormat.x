// Date format hooks — replace IG's relative timestamps with a custom format.
// Supports absolute formats, relative threshold, and compact relative style.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "SCIDateFormatEntries.h"
#import "SCIDateFormatTemplate.h"
#import <substrate.h>

static NSString *const kDateFmtKey = @"feed_date_format";
static NSString *const kShowSecondsKey = @"feed_date_show_seconds";
static NSString *const kRelativeThresholdKey = @"feed_date_relative_days_threshold";
static NSString *const kCompactRelativeKey = @"feed_date_compact_relative";
static NSString *const kCombineKey = @"feed_date_combine_with_date";

static NSDictionary<NSString *, NSArray<NSString *> *> *sciDatePatternMap(void) {
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

static NSDateFormatter *sciFormatterForPattern(NSString *pattern) {
	if (!pattern.length) return nil;

	static NSMutableDictionary<NSString *, NSDateFormatter *> *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSMutableDictionary dictionary];
	});

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

// compactKey is a "%ld<unit>" template; oneKey/manyKey are "%ld <unit> ago" templates.
// Each language localizes singular/plural in its own translation of the two full keys.
static NSString *sciRelativeUnit(NSInteger value, NSString *compactKey, NSString *oneKey, NSString *manyKey, BOOL compact) {
	if (compact) return [NSString stringWithFormat:SCILocalized(compactKey), (long)value];
	return [NSString stringWithFormat:SCILocalized(value == 1 ? oneKey : manyKey), (long)value];
}

static NSString *sciRelativeText(NSDate *date, BOOL compact) {
	if (!date) return nil;

	NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:date];
	if (diff < 0) diff = 0;

	if (diff < 60.0) return compact ? SCILocalized(@"now") : SCILocalized(@"just now");

	NSInteger minutes = (NSInteger)(diff / 60.0);
	if (minutes < 60) return sciRelativeUnit(minutes, @"%ldm", @"%ld minute ago", @"%ld minutes ago", compact);

	NSInteger hours = (NSInteger)(diff / 3600.0);
	if (hours < 24) return sciRelativeUnit(hours, @"%ldh", @"%ld hour ago", @"%ld hours ago", compact);

	NSInteger days = (NSInteger)(diff / 86400.0);
	if (days < 7) return sciRelativeUnit(MAX(days, 1), @"%ldd", @"%ld day ago", @"%ld days ago", compact);

	NSInteger weeks = (NSInteger)(diff / 604800.0);
	return sciRelativeUnit(MAX(weeks, 1), @"%ldw", @"%ld week ago", @"%ld weeks ago", compact);
}

static NSString *sciRelativeFormat(NSDate *date) {
	if (!date) return nil;

	NSInteger thresholdDays = (NSInteger)[SCIUtils getDoublePref:kRelativeThresholdKey];
	if (thresholdDays <= 0) return nil;

	NSTimeInterval diff = [[NSDate date] timeIntervalSinceDate:date];
	if (diff < 0) diff = 0;

	NSTimeInterval maxAge = (NSTimeInterval)thresholdDays * 86400.0;
	if (diff >= maxAge) return nil;

	return sciRelativeText(date, [SCIUtils getBoolPref:kCompactRelativeKey]);
}

static NSString *sciAbsoluteFormat(NSDate *date) {
	if (!date) return nil;

	NSString *fmt = [SCIUtils getStringPref:kDateFmtKey];
	if (!fmt.length || [fmt isEqualToString:@"default"]) return nil;

	NSString *pattern = nil;
	if ([fmt hasPrefix:@"custom:"]) {
		pattern = SCIDateFormatPatternFromTemplate(SCIDateFormatCustomTemplateForKey(fmt));
	} else {
		NSArray *patterns = sciDatePatternMap()[fmt];
		if (!patterns.count) return nil;
		pattern = patterns[[SCIUtils getBoolPref:kShowSecondsKey] ? 1 : 0];
	}
	if (!pattern.length) return nil;

	NSDateFormatter *df = sciFormatterForPattern(pattern);
	if (!df) return nil;

	@synchronized(df) {
		return [df stringFromDate:date];
	}
}

static NSString *sciFormatDate(NSDate *date) {
	NSString *relative = sciRelativeFormat(date);
	if (relative.length) return relative;

	NSString *absolute = sciAbsoluteFormat(date);
	if (!absolute.length) return absolute;

	NSString *mode = [SCIUtils getStringPref:kCombineKey];
	if (![mode isEqualToString:@"absolute_first"] && ![mode isEqualToString:@"relative_first"]) return absolute;

	NSString *rel = sciRelativeText(date, YES);
	if (!rel.length) return absolute;

	if ([mode isEqualToString:@"relative_first"]) return [NSString stringWithFormat:@"%@ – %@", rel, absolute];
	return [NSString stringWithFormat:@"%@ (%@)", absolute, rel];
}

#define SCI_HOOK0(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd); \
	}

#define SCI_HOOK1(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1); \
	}

#define SCI_HOOK2(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2); \
	}

#define SCI_HOOK3(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2, a3); \
	}

#define SCI_HOOK4(NAME, SEL_, LABEL, PREF) \
	static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger, NSInteger); \
	static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3, NSInteger a4) { \
		if ([SCIUtils getBoolPref:@PREF]) { \
			NSString *r = sciFormatDate(self); \
			if (r.length) return r; \
		} \
		return orig_##NAME(self, _cmd, a1, a2, a3, a4); \
	}

#define SCI_EMIT_HOOK(NAME, SEL_, LABEL, ARITY, PREF) SCI_HOOK##ARITY(NAME, SEL_, LABEL, PREF)
SCI_DATE_FORMAT_ENTRIES(SCI_EMIT_HOOK)

#define SCI_INSTALL_HOOK(NAME, SEL_, LABEL, ARITY, PREF) do { \
	SEL s = sel_registerName(SEL_); \
	if ([[NSDate class] instancesRespondToSelector:s]) { \
		MSHookMessageEx([NSDate class], s, (IMP)hook_##NAME, (IMP *)&orig_##NAME); \
	} \
} while (0);

// Active-thread inbox rows ship an empty timestampText (IG shows presence in the
// preview slot), so fill it from the message date to keep the format consistent.
static NSDictionary *sciInboxTSAttrs = nil; // cached style for empty rows

%hook IGDirectInboxThreadCellViewModel

- (NSAttributedString *)timestampText {
	NSAttributedString *orig = %orig;
	if (![SCIUtils getBoolPref:@"date_fmt_dms"]) return orig;

	if (orig.length > 0) {
		sciInboxTSAttrs = [orig attributesAtIndex:0 effectiveRange:NULL];
		return orig;
	}

	NSDate *date = nil;
	@try { date = [(id)self valueForKey:@"mostRecentMessageActivityDate"]; } @catch (__unused NSException *e) {}
	if (![date isKindOfClass:[NSDate class]]) return orig;

	NSString *formatted = sciFormatDate(date);
	if (!formatted.length) return orig;

	NSDictionary *attrs = sciInboxTSAttrs ?: @{ NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
	                                            NSFontAttributeName: [UIFont systemFontOfSize:13.0] };
	return [[NSAttributedString alloc] initWithString:[@"· " stringByAppendingString:formatted] attributes:attrs];
}

%end

%ctor {
	SCI_DATE_FORMAT_ENTRIES(SCI_INSTALL_HOOK)
}