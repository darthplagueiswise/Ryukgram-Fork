#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGDeveloperRuntimeSurface) {
    RYGDeveloperRuntimeSurfacePrism = 0,
    RYGDeveloperRuntimeSurfaceLiquidGlass,
    RYGDeveloperRuntimeSurfaceStories,
    RYGDeveloperRuntimeSurfaceConsumerSubs,
    RYGDeveloperRuntimeSurfaceInternalOnly,
    RYGDeveloperRuntimeSurfaceDirectDogfood,
    RYGDeveloperRuntimeSurfaceBugReport,
    RYGDeveloperRuntimeSurfaceSettingsRows,
};

@interface RYGDeveloperTopicViewController : UITableViewController
- (instancetype)initWithSurface:(RYGDeveloperRuntimeSurface)surface;
+ (void)activatePersistedNativeFeatures;
@end

NS_ASSUME_NONNULL_END
