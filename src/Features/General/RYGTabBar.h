// Single owner of tab bar order and visibility. Everything that touches the tab
// bar goes through here so no two call sites can disagree.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const RYGTabKeyFeed;
extern NSString *const RYGTabKeyReels;
extern NSString *const RYGTabKeyMessages;
extern NSString *const RYGTabKeyExplore;
extern NSString *const RYGTabKeyProfile;
extern NSString *const RYGTabKeyCreate;

@interface RYGTabBar : NSObject

+ (NSArray<NSString *> *)catalogTabKeys;
+ (NSString *)hidePrefForTabKey:(NSString *)tabKey;
+ (NSString *)tabKeyForLaunchTabValue:(NSString *)value;

+ (BOOL)messagesOnlyActive;
+ (BOOL)isTabKeyVisible:(NSString *)tabKey;
+ (NSArray<NSString *> *)orderedTabKeys;

+ (NSString *)tabKeyForSurface:(id)surface;
+ (BOOL)isSurfaceVisible:(id)surface;

+ (NSArray *)orderedSurfaces:(NSArray *)surfaces;
+ (NSArray *)visibleSurfaces:(NSArray *)surfaces;
+ (id)coerceToVisibleSurface:(id)surface inController:(id)ctrl;

+ (UIViewController *)liveController;
+ (void)applyOrderToController:(id)ctrl;
+ (NSArray<UIView *> *)orderedVisibleButtonsForController:(id)ctrl;

@end
