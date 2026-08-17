#import "RYGLiquidGlass.h"

// Keep the presentation pass tied to RyukGram-owned controllers. Applying in
// viewWillAppear gives navigation chrome its glass before the transition; the
// second pass in viewDidAppear catches controls created by a late table reload
// without mutating UIKit while it is inside viewDidLayoutSubviews.
%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (RYGIsOwnedViewController(self)) RYGLiquidGlassApplyToViewController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (RYGIsOwnedViewController(self)) RYGLiquidGlassApplyToViewController(self);
}

%end
