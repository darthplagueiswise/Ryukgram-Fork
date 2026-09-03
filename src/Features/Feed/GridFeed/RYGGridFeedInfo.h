#import <UIKit/UIKit.h>

extern NSString *const kRYGGridInfoUsername;
extern NSString *const kRYGGridInfoLikes;
extern NSString *const kRYGGridInfoComments;
extern NSString *const kRYGGridInfoViews;
extern NSString *const kRYGGridInfoShares;
extern NSString *const kRYGGridInfoFollowing;
extern NSString *const kRYGGridInfoDate;

typedef NS_ENUM(NSInteger, RYGGridTogglePlacement) {
	RYGGridTogglePlacementHeartLongPress = 0,
	RYGGridTogglePlacementButton,
	RYGGridTogglePlacementOff,
};

typedef NS_ENUM(NSInteger, RYGGridDateFormat) {
	RYGGridDateFormatRelative = 0,
	RYGGridDateFormatDate,
	RYGGridDateFormatDateTime,
	RYGGridDateFormatTime,
};

// Posted on the main thread with userInfo `posts`, `replacing` and `next`.
extern NSString *const RYGGridFeedResponseNote;
// Last feed page the interceptor delivered (captured even before the grid installs).
#ifdef __cplusplus
extern "C" {
#endif
extern NSArray * _Nullable RYGLatestFeedPosts(void);
extern NSString * _Nullable RYGLatestFeedNextMaxID(void);
extern BOOL RYGLatestFeedReplacing(void);
#ifdef __cplusplus
}
#endif

// Posted on the main thread when the live grid/native-feed toggle flips.
extern NSString *const RYGGridFeedVisibilityDidChange;

// Config store for the grid tile info chips and behavior toggles, all pref-backed.
@interface RYGGridFeedInfo : NSObject

// Master gate, read once at launch: hooks only install when this is on.
+ (BOOL)active;
+ (void)setActive:(BOOL)active;

// Live state while the master gate is on. Off hands the feed back to IG, network and all.
+ (BOOL)visible;
+ (void)setVisible:(BOOL)visible;
+ (void)toggleVisible;

+ (RYGGridTogglePlacement)togglePlacement;
+ (void)setTogglePlacement:(RYGGridTogglePlacement)placement;
+ (NSString *)nameForTogglePlacement:(RYGGridTogglePlacement)placement;

+ (BOOL)hideStories;

+ (NSArray<NSString *> *)allElementIDs;
+ (NSArray<NSString *> *)orderedElementIDs;
+ (NSArray<NSString *> *)orderedEnabledElementIDs;
+ (BOOL)isElementEnabled:(NSString *)elementID;
+ (void)setElement:(NSString *)elementID enabled:(BOOL)enabled;
+ (void)setOrder:(NSArray<NSString *> *)order;

+ (NSString *)titleForElement:(NSString *)elementID;
+ (NSString *)symbolForElement:(NSString *)elementID;
+ (NSString *)rowIconForElement:(NSString *)elementID;
// IG glyph name for the on-card chip (resolved via RYGIcon, SF fallback in symbolForElement).
+ (nullable NSString *)cardIconForElement:(NSString *)elementID;
// IG's own asset, falling back to the SF symbol.
+ (nullable UIImage *)iconNamed:(nullable NSString *)igName symbol:(nullable NSString *)sfName pointSize:(CGFloat)pt;
+ (nullable UIImage *)iconForElement:(NSString *)elementID pointSize:(CGFloat)pt;

+ (BOOL)showAvatar;
+ (BOOL)showTypeBadge;
+ (BOOL)shortenedNumbers;
+ (NSInteger)columns;
+ (RYGGridDateFormat)dateFormat;
+ (void)setDateFormat:(RYGGridDateFormat)fmt;
+ (NSString *)nameForDateFormat:(RYGGridDateFormat)fmt;
// Longest rendering first, relative time last; callers walk it until one fits their width.
+ (nullable NSArray<NSString *> *)dateStringsForTimestamp:(NSTimeInterval)takenAt;

+ (void)resetToDefaults;

@end
