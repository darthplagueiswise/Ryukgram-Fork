#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Analyzer lists. First 8 are toggleable checks; visited profiles is tracked
// separately and isn't part of the catalog.
typedef NS_ENUM(NSInteger, SCIPACategory) {
	SCIPACategoryMutual,
	SCIPACategoryNotFollowingBack,
	SCIPACategoryDontFollowBack,
	SCIPACategoryNewFollowers,
	SCIPACategoryLostFollowers,
	SCIPACategoryYouStartedFollowing,
	SCIPACategoryYouUnfollowed,
	SCIPACategoryProfileUpdates,
	SCIPACategoryVisitedProfiles,
};

// One toggleable check. Titles/subtitles are English source — wrapped in
// SCILocalized() at display time.
@interface SCIPACheckDescriptor : NSObject
@property (nonatomic, assign) SCIPACategory category;
@property (nonatomic, copy)   NSString *prefKey;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *subtitle;
@property (nonatomic, copy)   NSString *symbol;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) BOOL requiresPrevious;
@end

@interface SCIProfileAnalyzerChecks : NSObject

// The 8 toggleable checks, in display order.
+ (NSArray<SCIPACheckDescriptor *> *)allChecks;

// Catalog entry for a category, or nil for non-checks (e.g. visited profiles).
+ (nullable SCIPACheckDescriptor *)descriptorForCategory:(SCIPACategory)category;

// Per-check pref (defaults YES).
+ (BOOL)isCheckEnabledForKey:(NSString *)prefKey;

// Whether a category is computed/shown; non-catalog categories (visited profiles) always are.
+ (BOOL)isCategoryEnabled:(SCIPACategory)category;

@end

NS_ASSUME_NONNULL_END
