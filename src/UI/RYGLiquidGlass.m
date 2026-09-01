#import "RYGLiquidGlass.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <math.h>

static const void *kRYGGlassButtonConfiguredKey = &kRYGGlassButtonConfiguredKey;
static const void *kRYGGlassButtonDeferredFitKey = &kRYGGlassButtonDeferredFitKey;

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
        // UIGlassEffect owns its accessibility adaptations. iOS makes the
        // material frostier for Reduce Transparency, raises contrast when
        // requested, and reduces its motion automatically. Replacing it with
        // a plain view here removed the closed-menu/title material precisely
        // for users who need the stronger legibility treatment.
        return ![RYGUtils getBoolPref:@"liquid_glass_force_off"];
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

static void RYGPrepareAdaptiveMenu(UIMenu *menu) {
    if (!menu) return;

    // UIMenu's default large layout is deliberately a full-width action list.
    // That looks wasteful for the tweak's one/two-item selectors. Automatic is
    // the public UIKit policy that lets the presentation choose the compact
    // layout appropriate to the actual children instead of us baking a width.
    if (@available(iOS 16.0, *)) {
        menu.preferredElementSize = UIMenuElementSizeAutomatic;
    }

    // Apply the same policy to nested selection groups (for example Output ->
    // Native/On/Off) so opening a submenu cannot re-introduce a fixed large
    // surface after the root menu was made adaptive.
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) {
            RYGPrepareAdaptiveMenu((UIMenu *)element);
        }
    }
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
        // UIKit owns the closed -> expanded Liquid Glass menu morph. Keep its
        // default source metrics; never carry a hand-authored inset into the
        // expanded menu geometry.
        [glass setDefaultContentInsets];
    } else if (old) {
        // Preserve author-owned metrics only for ordinary action buttons.
        // Menu source controls always use UIKit's intrinsic Glass geometry.
        glass.contentInsets = old.contentInsets;
    }
    return glass;
}

static void RYGFitFrameManagedMenuButton(UIButton *button) {
    if (!button) return;
    [button invalidateIntrinsicContentSize];
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    // UITableViewCell.accessoryView is frame-managed, while stack/constraint
    // based controls are not. Only own the former's frame. Re-measuring here
    // after the final configuration/title fixes the clipped pills in late
    // table reloads without fighting Auto Layout elsewhere in the tweak.
    if (!button.translatesAutoresizingMaskIntoConstraints) return;
    [button sizeToFit];
    CGSize intrinsic = button.intrinsicContentSize;
    CGRect frame = button.frame;
    if (intrinsic.width > 0.0 && isfinite(intrinsic.width)) frame.size.width = ceil(intrinsic.width);
    if (intrinsic.height > 0.0 && isfinite(intrinsic.height)) frame.size.height = ceil(intrinsic.height);
    button.frame = frame;
}

static void RYGSynchronizeGlassButton(UIButton *button, BOOL prominent) {
    if (!button) return;
    if (@available(iOS 26.0, *)) {
        if (!RYGLiquidGlassIsAvailable()) return;

        BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
        if (menuSource && button.menu) RYGPrepareAdaptiveMenu(button.menu);

        NSString *title = button.configuration.title ?: [button titleForState:UIControlStateNormal] ?: @"";
        NSString *stateKey = [NSString stringWithFormat:@"%d:%d:%@", prominent, menuSource, title];
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

        if (menuSource) RYGFitFrameManagedMenuButton(button);
    }
}

void RYGLiquidGlassConfigureButton(UIButton *button, BOOL prominent) {
    if (!button) return;
    RYGSynchronizeGlassButton(button, prominent);

    if (@available(iOS 26.0, *)) {
        if (!RYGLiquidGlassIsAvailable()) return;
        BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
        if (!menuSource || !button.translatesAutoresizingMaskIntoConstraints) return;

        // A number of menu builders intentionally call the common styler and
        // then mutate UIButtonConfiguration.title. The old implementation
        // measured the accessory before that mutation, leaving the cell with a
        // stale narrow frame. A single end-of-runloop reconciliation observes
        // the caller's final title/menu and fixes every such source globally.
        if (![objc_getAssociatedObject(button, kRYGGlassButtonDeferredFitKey) boolValue]) {
            objc_setAssociatedObject(button,
                                     kRYGGlassButtonDeferredFitKey,
                                     @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak UIButton *weakButton = button;
            dispatch_async(dispatch_get_main_queue(), ^{
                UIButton *strongButton = weakButton;
                if (!strongButton) return;
                objc_setAssociatedObject(strongButton,
                                         kRYGGlassButtonDeferredFitKey,
                                         nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                RYGSynchronizeGlassButton(strongButton, prominent);
            });
        }
    }
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
        // The navigation title is itself a standard Glass control. Let UIKit
        // choose its intrinsic capsule metrics so Dynamic Type and iOS 26's
        // navigation transitions do not inherit fixed tweak-side margins.
        [configuration setDefaultContentInsets];
        pill.configuration = configuration;
    } else {
        [pill setAttributedTitle:attributed forState:UIControlStateNormal];
        pill.contentEdgeInsets = UIEdgeInsetsZero;
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
            BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
            if (menuSource || !RYGViewLivesInsideContentCell(button)) {
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
