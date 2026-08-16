#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Analyzer lists. First 8 are toggleable checks; visited profiles is tracked
// separately and isn't part of the catalog.
typedef NS_ENUM(NSInteger, RYGPACategory) {
	RYGPACategoryMutual,
	RYGPACategoryNotFollowingBack,
	RYGPACategoryDontFollowBack,
	RYGPACategoryNewFollowers,
	RYGPACategoryLostFollowers,
	RYGPACategoryYouStartedFollowing,
	RYGPACategoryYouUnfollowed,
	RYGPACategoryProfileUpdates,
	RYGPACategoryVisitedProfiles,
};

// One toggleable check. Titles/subtitles are English source — wrapped in
// RYGLocalized() at display time.
@interface RYGPACheckDescriptor : NSObject
@property (nonatomic, assign) RYGPACategory category;
@property (nonatomic, copy)   NSString *prefKey;
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *subtitle;
@property (nonatomic, copy)   NSString *symbol;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) BOOL requiresPrevious;
@end

@interface RYGProfileAnalyzerChecks : NSObject

// The 8 toggleable checks, in display order.
+ (NSArray<RYGPACheckDescriptor *> *)allChecks;

// Catalog entry for a category, or nil for non-checks (e.g. visited profiles).
+ (nullable RYGPACheckDescriptor *)descriptorForCategory:(RYGPACategory)category;

// Per-check pref (defaults YES).
+ (BOOL)isCheckEnabledForKey:(NSString *)prefKey;

// Whether a category is computed/shown; non-catalog categories (visited profiles) always are.
+ (BOOL)isCategoryEnabled:(RYGPACategory)category;

@end

NS_ASSUME_NONNULL_END
