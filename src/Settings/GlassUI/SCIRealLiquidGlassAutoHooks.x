// SCIRealLiquidGlassAutoHooks.x
//
// Disabled intentionally.
// A global %hook UIView on didMoveToWindow/layoutSubviews is unsafe inside Instagram:
// it runs for every app view and can recursively trigger layout while applying glass.
// Real LiquidGlass must be applied directly by RyukGram settings/menu view controllers,
// cells, search bars, buttons and toolbars, not by a global UIView hook.

#import <UIKit/UIKit.h>
#import "SCIAdaptiveGlass.h"
