#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presentation policy for RyukGram-owned UI. Instagram's own Prism/Lucent
/// experiments remain separate from this layer.
FOUNDATION_EXPORT BOOL RYGLiquidGlassIsAvailable(void);
FOUNDATION_EXPORT UIVisualEffectView *RYGLiquidGlassView(BOOL interactive,
                                                        BOOL clearStyle,
                                                        UIColor * _Nullable tintColor);
FOUNDATION_EXPORT void RYGLiquidGlassSetTint(UIVisualEffectView *view,
                                             UIColor * _Nullable tintColor);
FOUNDATION_EXPORT void RYGLiquidGlassConfigureButton(UIButton *button,
                                                     BOOL prominent);
FOUNDATION_EXPORT UIView *RYGLiquidGlassNavigationTitleView(NSString *title);
FOUNDATION_EXPORT void RYGLiquidGlassConfigureNavigationController(UINavigationController *navigationController);
FOUNDATION_EXPORT void RYGLiquidGlassApplyToViewController(UIViewController *controller);
FOUNDATION_EXPORT BOOL RYGIsOwnedViewController(UIViewController *controller);

NS_ASSUME_NONNULL_END
