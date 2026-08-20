#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGDeveloperRuntimeSurface) {
    RYGDeveloperRuntimeSurfacePrism = 0,
    RYGDeveloperRuntimeSurfaceLiquidGlass,
    RYGDeveloperRuntimeSurfaceStories,
    RYGDeveloperRuntimeSurfaceConsumerSubs,
    RYGDeveloperRuntimeSurfaceInternalOnly,
    RYGDeveloperRuntimeSurfaceDirectDogfood,
    // Source-compatibility aliases retained for callers from older dogfood builds.
    RYGDeveloperRuntimeSurfaceBugReport,
    RYGDeveloperRuntimeSurfaceSettingsRows,
};

NS_ASSUME_NONNULL_END
