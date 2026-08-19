#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGDeveloperExactSurface) {
    RYGDeveloperExactSurfaceStories = 0,
    RYGDeveloperExactSurfaceBugReport,
    RYGDeveloperExactSurfaceSettingsVisibility,
    RYGDeveloperExactSurfaceDirectDogfood,
};

@interface RYGDeveloperExactSurfaceViewController : UITableViewController
- (instancetype)initWithSurface:(RYGDeveloperExactSurface)surface;
@end

NS_ASSUME_NONNULL_END