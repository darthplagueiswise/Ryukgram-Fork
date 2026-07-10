#import "SCIProfileAnalyzerChecks.h"
#import "../../Utils.h"

@implementation SCIPACheckDescriptor @end

@implementation SCIProfileAnalyzerChecks

+ (NSArray<SCIPACheckDescriptor *> *)allChecks {
	static NSArray *checks;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SCIPACheckDescriptor *(^make)(SCIPACategory, NSString *, NSString *, NSString *, NSString *, UIColor *, BOOL) =
		^SCIPACheckDescriptor *(SCIPACategory c, NSString *key, NSString *t, NSString *s, NSString *sym, UIColor *col, BOOL reqPrev) {
			SCIPACheckDescriptor *d = [SCIPACheckDescriptor new];
			d.category = c; d.prefKey = key; d.title = t; d.subtitle = s; d.symbol = sym; d.color = col;
			d.requiresPrevious = reqPrev;
			return d;
		};
		checks = @[
			make(SCIPACategoryMutual, @"profile_analyzer_check_mutual",
				 @"Mutual followers", @"You both follow each other",
				 @"person.2.fill", [UIColor systemBlueColor], NO),
			make(SCIPACategoryNotFollowingBack, @"profile_analyzer_check_not_following_back",
				 @"Not following you back", @"You follow them, they don't follow back",
				 @"person.fill.xmark", [UIColor systemOrangeColor], NO),
			make(SCIPACategoryDontFollowBack, @"profile_analyzer_check_dont_follow_back",
				 @"You don't follow back", @"They follow you, you don't follow back",
				 @"person.fill.questionmark", [UIColor systemTealColor], NO),
			make(SCIPACategoryNewFollowers, @"profile_analyzer_check_new_followers",
				 @"New followers", @"Gained since last scan",
				 @"person.fill.badge.plus", [UIColor systemGreenColor], YES),
			make(SCIPACategoryLostFollowers, @"profile_analyzer_check_lost_followers",
				 @"Lost followers", @"Unfollowed you since last scan",
				 @"person.fill.badge.minus", [UIColor systemRedColor], YES),
			make(SCIPACategoryYouStartedFollowing, @"profile_analyzer_check_started_following",
				 @"You started following", @"Since last scan",
				 @"arrow.up.forward.circle.fill", [UIColor systemIndigoColor], YES),
			make(SCIPACategoryYouUnfollowed, @"profile_analyzer_check_unfollowed",
				 @"You unfollowed", @"Since last scan",
				 @"arrow.down.backward.circle.fill", [UIColor systemPurpleColor], YES),
			make(SCIPACategoryProfileUpdates, @"profile_analyzer_check_profile_updates",
				 @"Profile updates", @"Username, name or picture changes",
				 @"person.crop.circle.badge.exclamationmark", [UIColor systemPinkColor], YES),
		];
	});
	return checks;
}

+ (SCIPACheckDescriptor *)descriptorForCategory:(SCIPACategory)category {
	for (SCIPACheckDescriptor *c in [self allChecks])
		if (c.category == category) return c;
	return nil;
}

+ (BOOL)isCheckEnabledForKey:(NSString *)prefKey {
	return prefKey.length ? [SCIUtils getBoolPref:prefKey] : YES;
}

+ (BOOL)isCategoryEnabled:(SCIPACategory)category {
	SCIPACheckDescriptor *d = [self descriptorForCategory:category];
	return d ? [self isCheckEnabledForKey:d.prefKey] : YES;
}

@end
