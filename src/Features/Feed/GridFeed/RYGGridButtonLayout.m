#import "RYGGridButtonLayout.h"
#import "../../../Utils.h"

NSString *const RYGGridBtnToggle = @"toggle";

static NSString *const kChromePref = @"grid_feed_chrome";

// Measured on IG 438, replaced the first time the feed lays out.
static const CGRect kFallbackHeader = {{0.0, 0.0}, {1.0, 0.0611}};
static const CGRect kFallbackTabBar = {{0.0531, 0.9413}, {0.8937, 0.0733}};
static const CGFloat kChromeMargin = 0.0073;
static const CGFloat kSideMarginN = 0.012;

static CGRect gHeader, gTabBar;
static BOOL gChromeLoaded = NO;
// NO on iPad, where the tab bar is a side rail — the button then reaches the bottom edge.
static BOOL gHasBottomBar = YES;

static CGRect rygRectFromPref(NSString *key, CGRect fallback) {
	NSDictionary *d = [RYGUtils getDictPref:kChromePref][key];
	if (![d isKindOfClass:NSDictionary.class] || ![d[@"h"] doubleValue]) return fallback;
	return CGRectMake([d[@"x"] doubleValue], [d[@"y"] doubleValue], [d[@"w"] doubleValue], [d[@"h"] doubleValue]);
}

// Reject chrome that isn't a wide top/bottom band (iPad's side-rail tab bar) — it would
// collapse the placeable area.
static BOOL rygHeaderSane(CGRect h) {
	return CGRectGetMinY(h) < 0.2 && h.size.width > 0.4 && h.size.height > 0.0 && h.size.height < 0.3;
}
static BOOL rygTabBarSane(CGRect t) {
	return CGRectGetMinY(t) > 0.5 && t.size.width > 0.4 && t.size.height > 0.0 && t.size.height < 0.3;
}

// Read once: the feed asks on every layout pass.
static void rygLoadChrome(void) {
	if (gChromeLoaded) return;
	gHeader = rygRectFromPref(@"header", kFallbackHeader);
	gTabBar = rygRectFromPref(@"tabBar", kFallbackTabBar);
	if (!rygHeaderSane(gHeader)) gHeader = kFallbackHeader;
	if (!rygTabBarSane(gTabBar)) gTabBar = kFallbackTabBar;
	gChromeLoaded = YES;
}

@implementation RYGGridButtonLayout

+ (NSString *)prefKey { return @"grid_feed_button_layout"; }
+ (NSArray<NSString *> *)allIDs { return @[RYGGridBtnToggle]; }
+ (CGFloat)diameterForID:(NSString *)buttonID { return 42.0; }
+ (NSString *)iconForID:(NSString *)buttonID { return @"ig_icon_photo_grid_filled_24"; }
+ (CGPoint)defaultPositionForID:(NSString *)buttonID { return CGPointMake(0.92, 0.90); }

+ (CGRect)headerRectNormalized { rygLoadChrome(); return gHeader; }
+ (CGRect)tabBarRectNormalized { rygLoadChrome(); return gTabBar; }
+ (BOOL)hasBottomBar { rygLoadChrome(); return gHasBottomBar; }

+ (void)recordHeaderRect:(CGRect)header tabBarRect:(CGRect)tabBar {
	CGRect newHeader = rygHeaderSane(header) ? header : [self headerRectNormalized];
	BOOL bottomBar = rygTabBarSane(tabBar);
	CGRect newTabBar = bottomBar ? tabBar : [self tabBarRectNormalized];
	if (bottomBar == gHasBottomBar && CGRectEqualToRect(newHeader, gHeader) && CGRectEqualToRect(newTabBar, gTabBar)) return;
	gHasBottomBar = bottomBar;
	gHeader = newHeader;
	gTabBar = newTabBar;
	gChromeLoaded = YES;
	[RYGUtils setPref:@{
		@"header": @{ @"x": @(newHeader.origin.x), @"y": @(newHeader.origin.y), @"w": @(newHeader.size.width), @"h": @(newHeader.size.height) },
		@"tabBar": @{ @"x": @(newTabBar.origin.x), @"y": @(newTabBar.origin.y), @"w": @(newTabBar.size.width), @"h": @(newTabBar.size.height) },
	} forKey:kChromePref];
}

+ (UIEdgeInsets)placeableInsetsNormalized {
	CGFloat top = CGRectGetMaxY([self headerRectNormalized]) + kChromeMargin;
	CGFloat bottom = gHasBottomBar ? 1.0 - CGRectGetMinY([self tabBarRectNormalized]) + kChromeMargin : kChromeMargin;
	top = MAX(0.0, MIN(top, 0.45));
	bottom = MAX(0.0, MIN(bottom, 0.45));
	return UIEdgeInsetsMake(top, kSideMarginN, bottom, kSideMarginN);
}

@end
