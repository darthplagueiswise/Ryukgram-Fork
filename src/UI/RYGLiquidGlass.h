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

/// Explicit ownership is the source of truth for controls inserted by RyukGram
/// into Instagram-owned view-controller trees. Ownership is exact to the marked
/// view/class: it never propagates through an Instagram parent, sibling or child.
FOUNDATION_EXPORT void RYGMarkOwnedView(UIView *view);
FOUNDATION_EXPORT BOOL RYGIsOwnedView(UIView *view);
FOUNDATION_EXPORT BOOL RYGIsOwnedTargetAction(id _Nullable target, SEL _Nullable action);
FOUNDATION_EXPORT BOOL RYGIsOwnedCodeAddress(const void * _Nullable address);

FOUNDATION_EXPORT void RYGLiquidGlassConfigureButton(UIButton *button,
                                                     BOOL prominent);
FOUNDATION_EXPORT UIView *RYGLiquidGlassNavigationTitleView(NSString *title);
FOUNDATION_EXPORT void RYGLiquidGlassConfigureNavigationController(UINavigationController *navigationController);
FOUNDATION_EXPORT void RYGLiquidGlassApplyToViewController(UIViewController *controller);
FOUNDATION_EXPORT BOOL RYGIsOwnedViewController(UIViewController *controller);

NS_ASSUME_NONNULL_END
