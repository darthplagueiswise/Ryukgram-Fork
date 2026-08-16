#import "RYGLiquidGlass.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

static const void *kRYGGlassButtonConfiguredKey = &kRYGGlassButtonConfiguredKey;

static NSString *RYGDefiningImagePath(void) {
	static NSString *path;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Dl_info info = {0};
		if (dladdr((const void *)&RYGIsOwnedViewController, &info) && info.dli_fname) {
			path = [[[NSString alloc] initWithUTF8String:info.dli_fname] stringByStandardizingPath];
		}
	});
	return path;
}

static BOOL RYGClassNameIsOwned(Class cls) {
	NSString *name = cls ? NSStringFromClass(cls) : @"";
	if ([name hasPrefix:@"RYG"] || [name hasPrefix:@"_RYG"]) return YES;
	const char *rawImage = cls ? class_getImageName(cls) : NULL;
	if (!rawImage) return NO;
	NSString *classImage = [[[NSString alloc] initWithUTF8String:rawImage] stringByStandardizingPath];
	return classImage.length && [classImage isEqualToString:RYGDefiningImagePath()];
}

static BOOL RYGControllerTreeIsOwned(UIViewController *controller, NSUInteger depth) {
	if (!controller || depth > 8) return NO;
	if (RYGClassNameIsOwned(controller.class)) return YES;
	if ([controller isKindOfClass:UINavigationController.class]) {
		UINavigationController *nav = (UINavigationController *)controller;
		UIViewController *candidate = nav.visibleViewController ?: nav.viewControllers.firstObject;
		return candidate != controller && RYGControllerTreeIsOwned(candidate, depth + 1);
	}
	if ([controller isKindOfClass:UITabBarController.class]) {
		UIViewController *candidate = ((UITabBarController *)controller).selectedViewController;
		return candidate != controller && RYGControllerTreeIsOwned(candidate, depth + 1);
	}
	for (UIViewController *child in controller.childViewControllers) {
		if (child != controller && RYGControllerTreeIsOwned(child, depth + 1)) return YES;
	}
	return NO;
}

BOOL RYGIsOwnedViewController(UIViewController *controller) {
	return RYGControllerTreeIsOwned(controller, 0);
}

BOOL RYGLiquidGlassIsAvailable(void) {
	if (@available(iOS 26.0, *)) {
		return !UIAccessibilityIsReduceTransparencyEnabled()
			&& ![RYGUtils getBoolPref:@"liquid_glass_force_off"];
	}
	return NO;
}

UIVisualEffectView *RYGLiquidGlassView(BOOL interactive, BOOL clearStyle, UIColor *tintColor) {
	UIVisualEffect *effect = nil;
	if (@available(iOS 26.0, *)) {
		if (RYGLiquidGlassIsAvailable()) {
			UIGlassEffectStyle style = clearStyle ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular;
			UIGlassEffect *glass = [UIGlassEffect effectWithStyle:style];
			glass.interactive = interactive;
			glass.tintColor = tintColor;
			effect = glass;
		}
	}
	if (!effect && !UIAccessibilityIsReduceTransparencyEnabled()) {
		effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
	}

	UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
	view.userInteractionEnabled = NO;
	if (!effect) view.backgroundColor = tintColor ?: UIColor.secondarySystemBackgroundColor;
	return view;
}

void RYGLiquidGlassSetTint(UIVisualEffectView *view, UIColor *tintColor) {
	if (!view) return;
	if (@available(iOS 26.0, *)) {
		if ([view.effect isKindOfClass:UIGlassEffect.class]) {
			((UIGlassEffect *)view.effect).tintColor = tintColor;
			view.backgroundColor = UIColor.clearColor;
			return;
		}
	}
	view.backgroundColor = tintColor ?: UIColor.clearColor;
}

static UIButtonConfiguration *RYGGlassConfigurationPreservingButton(UIButton *button, BOOL prominent) API_AVAILABLE(ios(26.0)) {
	UIButtonConfiguration *old = button.configuration;
	UIButtonConfiguration *glass = prominent
		? [UIButtonConfiguration prominentGlassButtonConfiguration]
		: [UIButtonConfiguration glassButtonConfiguration];

	glass.title = old.title ?: [button titleForState:UIControlStateNormal];
	glass.attributedTitle = old.attributedTitle;
	glass.subtitle = old.subtitle;
	glass.attributedSubtitle = old.attributedSubtitle;
	glass.image = old.image ?: [button imageForState:UIControlStateNormal];
	glass.imagePlacement = old ? old.imagePlacement : NSDirectionalRectEdgeLeading;
	glass.imagePadding = old ? old.imagePadding : 6.0;
	glass.titlePadding = old.titlePadding;
	glass.contentInsets = old ? old.contentInsets : NSDirectionalEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
	glass.cornerStyle = old ? old.cornerStyle : UIButtonConfigurationCornerStyleCapsule;
	glass.baseForegroundColor = old.baseForegroundColor ?: button.tintColor;
	return glass;
}

void RYGLiquidGlassConfigureButton(UIButton *button, BOOL prominent) {
	if (!button || objc_getAssociatedObject(button, kRYGGlassButtonConfiguredKey)) return;
	if (@available(iOS 26.0, *)) {
		if (RYGLiquidGlassIsAvailable()) {
			button.backgroundColor = UIColor.clearColor;
			button.configuration = RYGGlassConfigurationPreservingButton(button, prominent);
			objc_setAssociatedObject(button, kRYGGlassButtonConfiguredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	}
}

static BOOL RYGViewLivesInsideContentCell(UIView *view) {
	for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
		if ([ancestor isKindOfClass:UITableViewCell.class]
			|| [ancestor isKindOfClass:UICollectionViewCell.class]) return YES;
		if (@available(iOS 26.0, *)) {
			if ([ancestor isKindOfClass:UIVisualEffectView.class]
				&& [((UIVisualEffectView *)ancestor).effect isKindOfClass:UIGlassEffect.class]) return YES;
		}
	}
	return NO;
}

static BOOL RYGViewContainsGlass(UIView *view, NSUInteger depth) {
	if (!view || depth > 4) return NO;
	for (UIView *subview in view.subviews) {
		if (@available(iOS 26.0, *)) {
			if ([subview isKindOfClass:UIVisualEffectView.class]
				&& [((UIVisualEffectView *)subview).effect isKindOfClass:UIGlassEffect.class]) return YES;
		}
		if (RYGViewContainsGlass(subview, depth + 1)) return YES;
	}
	return NO;
}

static void RYGStyleOwnedViewTree(UIView *root) {
	if (!root) return;
	NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
	while (pending.count) {
		UIView *view = pending.lastObject;
		[pending removeLastObject];

		if ([view isKindOfClass:UIButton.class]
			&& !RYGViewLivesInsideContentCell(view)
			&& !RYGViewContainsGlass(view, 0)) {
			RYGLiquidGlassConfigureButton((UIButton *)view, NO);
		}
		for (UIView *subview in view.subviews) [pending addObject:subview];
	}
}

void RYGLiquidGlassApplyToViewController(UIViewController *controller) {
	if (!RYGIsOwnedViewController(controller)) return;
	UIViewController *content = controller;
	if ([controller isKindOfClass:UINavigationController.class]) {
		content = ((UINavigationController *)controller).visibleViewController ?: controller;
	}

	UINavigationBar *navigationBar = content.navigationController.navigationBar;
	if (navigationBar) {
		// SDK 26 supplies Liquid Glass automatically when bars are left native.
		navigationBar.translucent = YES;
		navigationBar.barTintColor = nil;
		navigationBar.backgroundColor = UIColor.clearColor;
	}
	UIToolbar *toolbar = content.navigationController.toolbar;
	if (toolbar) {
		toolbar.translucent = YES;
		toolbar.barTintColor = nil;
		toolbar.backgroundColor = UIColor.clearColor;
	}

	if (content.isViewLoaded) {
		UIView *view = content.view;
		if ([content isKindOfClass:UITableViewController.class]) {
			UITableView *table = ((UITableViewController *)content).tableView;
			table.backgroundColor = UIColor.systemGroupedBackgroundColor;
			view.backgroundColor = UIColor.systemGroupedBackgroundColor;
		}
		RYGStyleOwnedViewTree(view);
	}
}
