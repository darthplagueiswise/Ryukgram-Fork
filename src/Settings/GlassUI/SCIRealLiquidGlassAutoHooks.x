// SCIRealLiquidGlassAutoHooks.x
// Applies real iOS 26 UIGlassEffect styling to RyukGram preference UI surfaces
// as they appear. Scope is intentionally limited to Ryuk/SCI responders so the
// Instagram app UI is not globally mutated.

#import "SCIAdaptiveGlass.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL SCIResponderChainIsRyuk(id view) {
    UIResponder *r = [view isKindOfClass:UIResponder.class] ? (UIResponder *)view : nil;
    for (NSUInteger i = 0; r && i < 24; i++, r = r.nextResponder) {
        NSString *cn = NSStringFromClass(object_getClass(r));
        if ([cn hasPrefix:@"SCI"] || [cn containsString:@"Ryuk"] || [cn containsString:@"TweakSettings"]) return YES;
    }
    return NO;
}

static void SCIApplyRealGlassIfNeeded(UIView *v) {
    if (!v || !SCIIsIOS26OrNewer()) return;
    if (!SCIResponderChainIsRyuk(v)) return;
    if ([v isKindOfClass:UILabel.class] || [v isKindOfClass:UIImageView.class] || [v isKindOfClass:UIStackView.class]) return;
    if ([v isKindOfClass:UIButton.class]) { SCIApplyGlassToButton((UIButton *)v); return; }
    if ([v isKindOfClass:UISearchBar.class]) { SCIApplyGlassToSearchBar((UISearchBar *)v); return; }
    if ([v isKindOfClass:UISegmentedControl.class]) { SCIApplyGlassToSegmentedControl((UISegmentedControl *)v); return; }
    if ([v isKindOfClass:UITabBar.class]) { SCIApplyGlassToTabBar((UITabBar *)v); return; }
    if ([v isKindOfClass:UITableView.class]) { SCIStyleTableViewForGlass((UITableView *)v); return; }
    if ([v isKindOfClass:UICollectionView.class]) { SCIStyleCollectionViewForGlass((UICollectionView *)v); return; }
    if ([v isKindOfClass:UITableViewCell.class]) { SCIStyleCellForGlass((UITableViewCell *)v); return; }
    if ([v isKindOfClass:UICollectionViewCell.class]) { SCIApplyGlassToView(v, 18.0, YES); return; }
    if (v.bounds.size.width >= 24.0 && v.bounds.size.height >= 24.0) SCIApplyGlassToView(v, 18.0, [v isKindOfClass:UIControl.class]);
}

%hook UIView
- (void)didMoveToWindow {
    %orig;
    SCIApplyRealGlassIfNeeded(self);
}
- (void)layoutSubviews {
    %orig;
    SCIApplyRealGlassIfNeeded(self);
}
%end
