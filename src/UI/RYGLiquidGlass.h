#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Liquid Glass is a presentation concern of RyukGram's own UI. Instagram's
/// experimental Lucent flags are intentionally kept separate.
FOUNDATION_EXPORT BOOL RYGLiquidGlassIsAvailable(void);

/// Creates a native interactive UIGlassEffect view on iOS 26+, with a material
/// fallback on older systems and an opaque accessibility fallback when Reduce
/// Transparency is enabled.
FOUNDATION_EXPORT UIVisualEffectView *RYGLiquidGlassView(BOOL interactive,
                                                        BOOL clearStyle,
                                                        UIColor * _Nullable tintColor);

/// Updates the tint of a view returned by RYGLiquidGlassView.
FOUNDATION_EXPORT void RYGLiquidGlassSetTint(UIVisualEffectView *view,
                                             UIColor * _Nullable tintColor);

/// Uses the SDK 26 glass button configurations while preserving the button's
/// visible title, image, insets and menu behavior. Older systems keep their
/// existing configuration.
FOUNDATION_EXPORT void RYGLiquidGlassConfigureButton(UIButton *button,
                                                     BOOL prominent);

/// Applies RyukGram's native navigation/control-layer styling. Content remains
/// on system backgrounds so glass is never stacked behind every table cell.
FOUNDATION_EXPORT void RYGLiquidGlassApplyToViewController(UIViewController *controller);

/// True for RyukGram-owned controllers (including navigation containers whose
/// visible/root controller is RyukGram-owned).
FOUNDATION_EXPORT BOOL RYGIsOwnedViewController(UIViewController *controller);

NS_ASSUME_NONNULL_END
