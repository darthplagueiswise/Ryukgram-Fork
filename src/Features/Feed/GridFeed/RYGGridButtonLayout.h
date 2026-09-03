// Placement store for the grid/feed switch button.

#import "../../../UI/DragLayout/RYGOverlayButtonLayout.h"

extern NSString *const RYGGridBtnToggle;

@interface RYGGridButtonLayout : RYGOverlayButtonLayout
// IG's chrome, normalized against the safe area and measured live by the feed.
+ (CGRect)headerRectNormalized;
+ (CGRect)tabBarRectNormalized;
+ (BOOL)hasBottomBar;
+ (void)recordHeaderRect:(CGRect)header tabBarRect:(CGRect)tabBar;
@end
