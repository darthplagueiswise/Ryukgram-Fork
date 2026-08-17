#import "../Settings/RYGSettingsViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGDeveloperGateSurface) {
    RYGDeveloperGateSurfaceWordMark = 0,
    RYGDeveloperGateSurfaceInternal,
    RYGDeveloperGateSurfacePrism,
    RYGDeveloperGateSurfaceLiquidGlass,
};

@interface RYGDeveloperGateViewController : RYGSettingsViewController
- (instancetype)initWithSurface:(RYGDeveloperGateSurface)surface;
@end

NS_ASSUME_NONNULL_END
