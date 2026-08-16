#import "RYGLiquidGlass.h"

// Keep the design pass tied to RyukGram-owned controller trees. viewWillAppear
// configures navigation-layer glass; viewDidLayoutSubviews catches menu source
// buttons/cells created by a later table reload without touching Instagram UI.
%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (RYGIsOwnedViewController(self)) RYGLiquidGlassApplyToViewController(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (RYGIsOwnedViewController(self)) RYGLiquidGlassApplyToViewController(self);
}

%end
