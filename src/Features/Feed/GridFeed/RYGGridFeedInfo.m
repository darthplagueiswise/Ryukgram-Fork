#import "RYGGridFeedInfo.h"
#import "../../../UI/RYGIcon.h"
#import "../../../Utils.h"

NSString *const kRYGGridInfoUsername = @"username";
NSString *const kRYGGridInfoLikes    = @"likes";
NSString *const kRYGGridInfoComments = @"comments";
NSString *const kRYGGridInfoViews    = @"views";
NSString *const kRYGGridInfoShares   = @"shares";
NSString *const kRYGGridInfoFollowing = @"following";
NSString *const kRYGGridInfoDate     = @"date";

NSString *const RYGGridFeedVisibilityDidChange = @"RYGGridFeedVisibilityDidChange";

static NSString *const kOrderKey = @"grid_feed_info_order";
static NSString *const kDefaultOrder = @"username,following,likes,comments,views,shares,date";

@implementation RYGGridFeedInfo

+ (BOOL)active { return [RYGUtils getBoolPref:@"grid_feed_enabled"]; }

+ (void)setActive:(BOOL)active {
	[RYGUtils setPref:@(active) forKey:@"grid_feed_enabled"];
	// Enabling has to clear a left-over live-toggle off, or the grid stays hidden after restart.
	if (active) [self setVisible:YES];
}


+ (BOOL)visible { return [RYGUtils getBoolPref:@"grid_feed_visible"]; }

+ (void)setVisible:(BOOL)visible {
	if (visible == [self visible]) return;
	[RYGUtils setPref:@(visible) forKey:@"grid_feed_visible"];
	[[NSNotificationCenter defaultCenter] postNotificationName:RYGGridFeedVisibilityDidChange object:nil];
}

+ (void)toggleVisible { [self setVisible:![self visible]]; }

+ (RYGGridTogglePlacement)togglePlacement {
	NSInteger raw = (NSInteger)[RYGUtils getDoublePref:@"grid_feed_toggle_placement"];
	if (raw < 0 || raw > RYGGridTogglePlacementOff) return RYGGridTogglePlacementHeartLongPress;
	return (RYGGridTogglePlacement)raw;
}

+ (void)setTogglePlacement:(RYGGridTogglePlacement)placement {
	[RYGUtils setPref:@(placement) forKey:@"grid_feed_toggle_placement"];
	[[NSNotificationCenter defaultCenter] postNotificationName:RYGGridFeedVisibilityDidChange object:nil];
}

+ (NSString *)nameForTogglePlacement:(RYGGridTogglePlacement)placement {
	switch (placement) {
		case RYGGridTogglePlacementButton: return RYGLocalized(@"Floating button");
		case RYGGridTogglePlacementOff: return RYGLocalized(@"Off");
		default: return RYGLocalized(@"Hold the heart button");
	}
}

+ (BOOL)hideStories { return [RYGUtils getBoolPref:@"grid_feed_hide_stories"]; }

+ (NSArray<NSString *> *)allElementIDs {
	return @[kRYGGridInfoUsername, kRYGGridInfoFollowing, kRYGGridInfoLikes, kRYGGridInfoComments, kRYGGridInfoViews, kRYGGridInfoShares, kRYGGridInfoDate];
}

+ (RYGGridDateFormat)dateFormat {
	return (RYGGridDateFormat)(NSInteger)[RYGUtils getDoublePref:@"grid_feed_date_format"];
}

+ (void)setDateFormat:(RYGGridDateFormat)fmt {
	[RYGUtils setPref:@(fmt) forKey:@"grid_feed_date_format"];
}

+ (NSString *)nameForDateFormat:(RYGGridDateFormat)fmt {
	switch (fmt) {
		case RYGGridDateFormatDate: return RYGLocalized(@"Date");
		case RYGGridDateFormatDateTime: return RYGLocalized(@"Date and time");
		case RYGGridDateFormatTime: return RYGLocalized(@"Time");
		default: return RYGLocalized(@"Relative");
	}
}

static NSString *rygRelativeTime(NSTimeInterval takenAt) {
	NSTimeInterval s = [[NSDate date] timeIntervalSince1970] - takenAt;
	if (s < 0) s = 0;
	if (s < 60) return RYGLocalized(@"now");
	if (s < 3600) return [NSString stringWithFormat:@"%dm", (int)(s / 60)];
	if (s < 86400) return [NSString stringWithFormat:@"%dh", (int)(s / 3600)];
	if (s < 604800) return [NSString stringWithFormat:@"%dd", (int)(s / 86400)];
	return [NSString stringWithFormat:@"%dw", (int)(s / 604800)];
}

// Templates, not literal patterns: the locale decides day/month order and 12h vs 24h.
static NSDateFormatter *rygFormatterForTemplate(NSString *template) {
	static NSMutableDictionary<NSString *, NSDateFormatter *> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
	@synchronized (cache) {
		NSDateFormatter *f = cache[template];
		if (!f) {
			f = [NSDateFormatter new];
			f.locale = [NSLocale currentLocale];
			f.dateFormat = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:f.locale];
			cache[template] = f;
		}
		return f;
	}
}

+ (NSArray<NSString *> *)dateStringsForTimestamp:(NSTimeInterval)takenAt {
	if (takenAt <= 0) return nil;
	NSDate *date = [NSDate dateWithTimeIntervalSince1970:takenAt];
	NSString *relative = rygRelativeTime(takenAt);
	RYGGridDateFormat fmt = [self dateFormat];
	if (fmt == RYGGridDateFormatRelative) return @[relative];

	NSCalendar *cal = [NSCalendar currentCalendar];
	BOOL thisYear = [cal component:NSCalendarUnitYear fromDate:date] == [cal component:NSCalendarUnitYear fromDate:[NSDate date]];
	NSString *day = [rygFormatterForTemplate(@"dMMM") stringFromDate:date];
	NSString *dayYear = [rygFormatterForTemplate(@"dMMMyy") stringFromDate:date];
	NSString *dated = thisYear ? day : dayYear;
	NSString *time = [rygFormatterForTemplate(@"jmm") stringFromDate:date];

	NSMutableArray<NSString *> *out = [NSMutableArray array];
	if (fmt == RYGGridDateFormatDateTime) {
		[out addObject:[NSString stringWithFormat:@"%@ %@", dated, time]];
		if (!thisYear) [out addObject:[NSString stringWithFormat:@"%@ %@", day, time]];
	}
	if (fmt == RYGGridDateFormatTime && thisYear) [out addObject:time];
	[out addObject:dated];
	if (!thisYear) [out addObject:day];
	[out addObject:relative];
	return out;
}

+ (NSString *)prefKeyForElement:(NSString *)elementID {
	return [@"grid_feed_el_" stringByAppendingString:elementID];
}

+ (BOOL)showAvatar { return [RYGUtils getBoolPref:@"grid_feed_show_avatar"]; }
+ (BOOL)showTypeBadge { return [RYGUtils getBoolPref:@"grid_feed_show_type_badge"]; }
+ (BOOL)shortenedNumbers { return [RYGUtils getBoolPref:@"grid_feed_shortened_numbers"]; }

+ (NSInteger)columns {
	NSInteger c = (NSInteger)[RYGUtils getDoublePref:@"grid_feed_columns"];
	return MAX(2, MIN(6, c ?: 3));
}

+ (NSArray<NSString *> *)orderedElementIDs {
	NSString *csv = [RYGUtils getStringPref:kOrderKey];
	if (!csv.length) csv = kDefaultOrder;
	NSMutableArray *out = [NSMutableArray array];
	NSArray *all = [self allElementIDs];
	for (NSString *raw in [csv componentsSeparatedByString:@","]) {
		NSString *id_ = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([all containsObject:id_] && ![out containsObject:id_]) [out addObject:id_];
	}
	for (NSString *id_ in all) if (![out containsObject:id_]) [out addObject:id_];
	return out;
}

+ (NSArray<NSString *> *)orderedEnabledElementIDs {
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *id_ in [self orderedElementIDs]) if ([self isElementEnabled:id_]) [out addObject:id_];
	return out;
}

+ (BOOL)isElementEnabled:(NSString *)elementID {
	return [RYGUtils getBoolPref:[self prefKeyForElement:elementID]];
}

+ (void)setElement:(NSString *)elementID enabled:(BOOL)enabled {
	[RYGUtils setPref:@(enabled) forKey:[self prefKeyForElement:elementID]];
}

+ (void)setOrder:(NSArray<NSString *> *)order {
	[RYGUtils setPref:[order componentsJoinedByString:@","] forKey:kOrderKey];
}

+ (NSString *)titleForElement:(NSString *)elementID {
	if ([elementID isEqualToString:kRYGGridInfoUsername]) return RYGLocalized(@"Username");
	if ([elementID isEqualToString:kRYGGridInfoLikes]) return RYGLocalized(@"Likes");
	if ([elementID isEqualToString:kRYGGridInfoComments]) return RYGLocalized(@"Comments");
	if ([elementID isEqualToString:kRYGGridInfoViews]) return RYGLocalized(@"Views");
	if ([elementID isEqualToString:kRYGGridInfoShares]) return RYGLocalized(@"Shares");
	if ([elementID isEqualToString:kRYGGridInfoFollowing]) return RYGLocalized(@"Follow status");
	if ([elementID isEqualToString:kRYGGridInfoDate]) return RYGLocalized(@"Date");
	return elementID;
}

+ (NSString *)symbolForElement:(NSString *)elementID {
	if ([elementID isEqualToString:kRYGGridInfoUsername]) return @"person.circle.fill";
	if ([elementID isEqualToString:kRYGGridInfoLikes]) return @"heart.fill";
	if ([elementID isEqualToString:kRYGGridInfoComments]) return @"bubble.right.fill";
	if ([elementID isEqualToString:kRYGGridInfoViews]) return @"play.fill";
	if ([elementID isEqualToString:kRYGGridInfoShares]) return @"paperplane.fill";
	if ([elementID isEqualToString:kRYGGridInfoFollowing]) return @"checkmark.circle.fill";
	if ([elementID isEqualToString:kRYGGridInfoDate]) return @"clock.fill";
	return @"circle.fill";
}

+ (NSString *)cardIconForElement:(NSString *)elementID {
	if ([elementID isEqualToString:kRYGGridInfoLikes]) return @"ig_icon_heart_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoComments]) return @"ig_icon_comment_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoViews]) return @"ig_icon_eye_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoShares]) return @"ig_icon_direct_prism_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoFollowing]) return @"ig_icon_user_following_prism_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoDate]) return @"ig_icon_clock_dotted_pano_outline_24";
	return nil;
}

// RYGIcon takes one name; cards carry a raw catalog name plus a different SF fallback.
+ (UIImage *)iconNamed:(NSString *)igName symbol:(NSString *)sfName pointSize:(CGFloat)pt {
	UIImage *img = igName.length ? [RYGIcon imageNamed:igName pointSize:pt] : nil;
	if (!img && sfName.length) img = [RYGIcon sfImageNamed:sfName pointSize:pt weight:UIImageSymbolWeightBold];
	return img;
}

+ (UIImage *)iconForElement:(NSString *)elementID pointSize:(CGFloat)pt {
	return [self iconNamed:[self cardIconForElement:elementID] symbol:[self symbolForElement:elementID] pointSize:pt];
}

+ (NSString *)rowIconForElement:(NSString *)elementID {
	if ([elementID isEqualToString:kRYGGridInfoUsername]) return @"ig_icon_user_circle_pano_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoLikes]) return @"ig_icon_heart_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoComments]) return @"ig_icon_comment_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoViews]) return @"ig_icon_eye_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoShares]) return @"ig_icon_direct_prism_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoFollowing]) return @"ig_icon_user_following_prism_outline_24";
	if ([elementID isEqualToString:kRYGGridInfoDate]) return @"ig_icon_clock_dotted_pano_outline_24";
	return @"ig_icon_info_outline_24";
}

+ (void)resetToDefaults {
	[RYGUtils setPref:kDefaultOrder forKey:kOrderKey];
	[RYGUtils setPref:@(YES) forKey:[self prefKeyForElement:kRYGGridInfoUsername]];
	[RYGUtils setPref:@(NO) forKey:[self prefKeyForElement:kRYGGridInfoFollowing]];
	[RYGUtils setPref:@(YES) forKey:[self prefKeyForElement:kRYGGridInfoLikes]];
	[RYGUtils setPref:@(YES) forKey:[self prefKeyForElement:kRYGGridInfoComments]];
	[RYGUtils setPref:@(YES) forKey:[self prefKeyForElement:kRYGGridInfoViews]];
	[RYGUtils setPref:@(NO) forKey:[self prefKeyForElement:kRYGGridInfoShares]];
	[RYGUtils setPref:@(NO) forKey:[self prefKeyForElement:kRYGGridInfoDate]];
	[RYGUtils setPref:@(YES) forKey:@"grid_feed_show_avatar"];
	[RYGUtils setPref:@(YES) forKey:@"grid_feed_show_type_badge"];
	[RYGUtils setPref:@(YES) forKey:@"grid_feed_shortened_numbers"];
	[RYGUtils setPref:@(0) forKey:@"grid_feed_date_format"];
}

@end
