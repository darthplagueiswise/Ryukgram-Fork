// Shared chrome for full-screen popups (Settings, Gallery, Deleted messages,
// Profile Analyzer, Storage). Backdrop colour, full-screen modal wrap, and
// an auto-injected (X) close button.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIPopupChrome : NSObject

/// Backdrop colour for a popup VC's view + table view background.
+ (UIColor *)backgroundColor;

/// Apply the backdrop colour to a VC and any nested scroll views.
+ (void)applyBackdropTo:(UIViewController *)vc;

/// Wrap `content` in a navigation controller, force full-screen presentation,
/// and add an (X) close button if no leading nav item was set.
+ (UINavigationController *)wrap:(UIViewController *)content;

/// Wrap + present. Falls back to the top-most controller when `presenter` is nil.
+ (void)presentVC:(UIViewController *)content
             from:(nullable UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
