#import "RYGLiquidGlass.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <dlfcn.h>

static const void *kRYGGlassButtonConfiguredKey = &kRYGGlassButtonConfiguredKey;

static NSString *RYGDefiningImagePath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info = {0};
        if (dladdr((const void *)&RYGIsOwnedViewController, &info) && info.dli_fname) {
            path = [[[NSString alloc] initWithUTF8String:info.dli_fname]
                stringByResolvingSymlinksInPath].stringByStandardizingPath;
        }
    });
    return path;
}

static BOOL RYGClassNameIsOwned(Class cls) {
    NSString *name = cls ? NSStringFromClass(cls) : @"";
    if ([name hasPrefix:@"RYG"] || [name hasPrefix:@"_RYG"]) return YES;
    const char *rawImage = cls ? class_getImageName(cls) : NULL;
    if (!rawImage) return NO;
    NSString *classImage = [[[[NSString alloc] initWithUTF8String:rawImage]
        stringByResolvingSymlinksInPath] stringByStandardizingPath];
    return classImage.length && [classImage isEqualToString:RYGDefiningImagePath()];
}

static BOOL RYGControllerTreeIsOwned(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 8) return NO;
    if (RYGClassNameIsOwned(controller.class)) return YES;
    if ([controller isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigationController = (UINavigationController *)controller;
        UIViewController *candidate = navigationController.visibleViewController ?: navigationController.viewControllers.firstObject;
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

UIVisualEffectView *RYGLiquidGlassView(BOOL interactive,
                                       BOOL clearStyle,
                                       UIColor *tintColor) {
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            UIGlassEffect *glass = [UIGlassEffect effectWithStyle:
                clearStyle ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
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

static UIButtonConfiguration *RYGGlassConfigurationForButton(UIButton *button,
                                                              BOOL prominent) API_AVAILABLE(ios(26.0)) {
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
    if (old) glass.cornerStyle = old.cornerStyle;

    BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
    glass.baseForegroundColor = old.baseForegroundColor ?: (menuSource ? UIColor.labelColor : button.tintColor);
    if (menuSource) {
        [glass setDefaultContentInsets];
        glass.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    } else if (old) {
        glass.contentInsets = old.contentInsets;
    }
    return glass;
}

void RYGLiquidGlassConfigureButton(UIButton *button, BOOL prominent) {
    if (!button) return;
    if (@available(iOS 26.0, *)) {
        if (!RYGLiquidGlassIsAvailable()) {
            [button sizeToFit];
            return;
        }

        BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
        NSString *stateKey = [NSString stringWithFormat:@"%d:%d", prominent, menuSource];
        NSString *configured = objc_getAssociatedObject(button, kRYGGlassButtonConfiguredKey);
        if (![configured isEqualToString:stateKey]) {
            button.backgroundColor = UIColor.clearColor;
            if (menuSource) button.tintColor = UIColor.labelColor;
            button.configuration = RYGGlassConfigurationForButton(button, prominent);
            objc_setAssociatedObject(button,
                                     kRYGGlassButtonConfiguredKey,
                                     stateKey,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    }

    // UITableViewCell.accessoryView reads the view's current bounds. Several
    // Developer selectors were returned with CGRectZero after assigning a
    // UIButtonConfiguration; UIKit then positioned the visible Glass content
    // over the cell's leading labels. Resolve the intrinsic size before the
    // button becomes an accessory. This does not control the expanded menu;
    // UIMenu/UIButton still own that geometry and morph transition.
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button invalidateIntrinsicContentSize];
    [button sizeToFit];
}

UIView *RYGLiquidGlassNavigationTitleView(NSString *title) {
    if (!title.length) return [UIView new];

    UIButton *pill = [UIButton buttonWithType:UIButtonTypeSystem];
    pill.userInteractionEnabled = NO;
    pill.accessibilityLabel = title;

    UIFont *font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    NSAttributedString *attributed = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: UIColor.labelColor,
            }];

    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.attributedTitle = attributed;
        configuration.baseForegroundColor = UIColor.labelColor;
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(5.0, 12.0, 5.0, 12.0);
        pill.configuration = configuration;
    } else {
        [pill setAttributedTitle:attributed forState:UIControlStateNormal];
        pill.contentEdgeInsets = UIEdgeInsetsMake(5.0, 12.0, 5.0, 12.0);
    }

    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            RYGLiquidGlassConfigureButton(pill, NO);
            UIButtonConfiguration *configuration = pill.configuration;
            configuration.baseForegroundColor = UIColor.labelColor;
            configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
            pill.configuration = configuration;
        }
    }

    [pill sizeToFit];
    return pill;
}

static BOOL RYGViewLivesInsideContentCell(UIView *view) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:UITableViewCell.class] ||
            [ancestor isKindOfClass:UICollectionViewCell.class]) return YES;
    }
    return NO;
}

static void RYGStyleOwnedControls(UIView *root) {
    if (!root) return;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];

        if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            // Cell accessories are configured explicitly when they are created.
            // Reconfiguring them later during a recursive view walk changes the
            // intrinsic size after UITableView has already laid out its content.
            if (!RYGViewLivesInsideContentCell(button)) {
                RYGLiquidGlassConfigureButton(button, NO);
            }
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

    if (content.navigationItem.titleView == nil && content.title.length) {
        content.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(content.title);
    }

    if (content.isViewLoaded) {
        if ([content isKindOfClass:UITableViewController.class]) {
            UITableView *table = ((UITableViewController *)content).tableView;
            table.backgroundColor = UIColor.systemGroupedBackgroundColor;
            content.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
        }
        RYGStyleOwnedControls(content.view);
    }
}
