#import "RYGLiquidGlass.h"

// Most tweak controllers already call super from viewWillAppear:. Keeping the
// hook at UIViewController avoids coupling the design system to dozens of
// individual screens while the ownership guard leaves Instagram untouched.
%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	if (RYGIsOwnedViewController(self)) {
		RYGLiquidGlassApplyToViewController(self);
	}
}

%end
