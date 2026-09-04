#import "RYGLiquidGlass.h"
#import <objc/runtime.h>
#import <dlfcn.h>

static const void *kRYGGlassButtonConfiguredKey = &kRYGGlassButtonConfiguredKey;
static const void *kRYGGeneratedTitleViewKey = &kRYGGeneratedTitleViewKey;

static NSString *RYGDefiningImagePath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info = {0};
        if (dladdr((const void *)&RYGIsOwnedViewController, &info) && info.dli_fname) {
            path = [[[[NSString alloc] initWithUTF8String:info.dli_fname]
                stringByResolvingSymlinksInPath] stringByStandardizingPath];
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

static BOOL RYGControllerDirectlyOwned(UIViewController *controller) {
    return controller && RYGClassNameIsOwned(controller.class);
}

static UIViewController *RYGOwnedContainerContent(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 6) return nil;

    // A controller is owned only when its concrete class belongs to RyukGram.
    // Never infer ownership from arbitrary childViewControllers: Instagram can
    // legitimately host a RyukGram child/overlay inside an otherwise native
    // controller. Treating that parent as owned caused the previous pass to
    // glass every UIButton in the Instagram screen.
    if (RYGControllerDirectlyOwned(controller)) return controller;

    // Generic UIKit presentation containers are allowed to forward ownership
    // only to the content they are actively presenting. This keeps a standard
    // UINavigationController wrapper around a RyukGram page working without
    // broadening ownership to Instagram's surrounding hierarchy.
    if ([controller isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)controller;
        UIViewController *candidate = nav.visibleViewController ?: nav.topViewController;
        if (candidate && candidate != controller) return RYGOwnedContainerContent(candidate, depth + 1);
        return nil;
    }

    if ([controller isKindOfClass:UITabBarController.class]) {
        UIViewController *candidate = ((UITabBarController *)controller).selectedViewController;
        if (candidate && candidate != controller) return RYGOwnedContainerContent(candidate, depth + 1);
        return nil;
    }

    return nil;
}

BOOL RYGIsOwnedViewController(UIViewController *controller) {
    return RYGOwnedContainerContent(controller, 0) != nil;
}

BOOL RYGLiquidGlassIsAvailable(void) {
    if (@available(iOS 26.0, *)) {
        // Liquid Glass is the visual baseline for RyukGram-owned UI on iOS 26.
        // Do not let a stale hidden preference silently turn the design off.
        return !UIAccessibilityIsReduceTransparencyEnabled();
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
    if (@available(iOS 17.0, *)) menu.preferredElementSize = UIMenuElementSizeAutomatic;
    for (UIMenuElement *element in menu.children) {
        if ([element isKindOfClass:UIMenu.class]) RYGPrepareAdaptiveMenu((UIMenu *)element);
    }
}

static UIButtonConfiguration *RYGGlassConfigurationForButton(UIButton *button,
                                                              BOOL prominent) API_AVAILABLE(ios(26.0)) {
    UIButtonConfiguration *old = button.configuration;
    UIButtonConfiguration *glass = prominent
        ? [UIButtonConfiguration prominentClearGlassButtonConfiguration]
        : [UIButtonConfiguration clearGlassButtonConfiguration];

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
    } else if (old) {
        glass.contentInsets = old.contentInsets;
    }
    return glass;
}

static void RYGSynchronizeGlassButton(UIButton *button, BOOL prominent) {
    if (!button) return;

    BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
    if (menuSource && button.menu) RYGPrepareAdaptiveMenu(button.menu);

    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            NSString *title = button.configuration.title ?: [button titleForState:UIControlStateNormal] ?: @"";
            NSString *stateKey = [NSString stringWithFormat:@"%d:%d:%@", prominent, menuSource, title];
            NSString *configured = objc_getAssociatedObject(button, kRYGGlassButtonConfiguredKey);
            if (![configured isEqualToString:stateKey]) {
                button.backgroundColor = UIColor.clearColor;
                button.configuration = RYGGlassConfigurationForButton(button, prominent);
                button.tintColor = UIColor.labelColor;
                objc_setAssociatedObject(button,
                                         kRYGGlassButtonConfiguredKey,
                                         stateKey,
                                         OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
        }
    }

    // SDK 26 glass/menu transitions depend on intrinsic geometry. Never rewrite
    // the control frame after applying the configuration.
    [button invalidateIntrinsicContentSize];
}

void RYGLiquidGlassConfigureButton(UIButton *button, BOOL prominent) {
    RYGSynchronizeGlassButton(button, prominent);
}

UIView *RYGLiquidGlassNavigationTitleView(NSString *title) {
    UILabel *label = [UILabel new];
    label.text = title ?: @"";
    label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.labelColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    label.accessibilityLabel = title;
    [label sizeToFit];
    objc_setAssociatedObject(label, kRYGGeneratedTitleViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return label;
}

void RYGLiquidGlassConfigureNavigationController(UINavigationController *navigationController) {
    if (!navigationController) return;
    navigationController.navigationBar.translucent = YES;
    navigationController.toolbar.translucent = YES;
    navigationController.navigationBar.prefersLargeTitles = NO;
    navigationController.navigationBar.tintColor = UIColor.labelColor;
}

static void RYGUseNativeNavigationTitle(UIViewController *controller) {
    if (!controller) return;
    controller.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UIView *titleView = controller.navigationItem.titleView;
    if (titleView && [objc_getAssociatedObject(titleView, kRYGGeneratedTitleViewKey) boolValue]) {
        controller.navigationItem.titleView = nil;
    }
}

static void RYGStyleOwnedControls(UIView *root) {
    if (!root) return;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];

        // The root passed here is now guaranteed to belong directly to a
        // RyukGram controller. We no longer traverse an Instagram parent just
        // because it happens to contain one RyukGram child controller.
        if ([view isKindOfClass:UIButton.class]) {
            RYGLiquidGlassConfigureButton((UIButton *)view, NO);
        }
        for (UIView *subview in view.subviews) [pending addObject:subview];
    }
}

void RYGLiquidGlassApplyToViewController(UIViewController *controller) {
    UIViewController *content = RYGOwnedContainerContent(controller, 0);
    if (!content || !RYGControllerDirectlyOwned(content)) return;

    UINavigationController *navigationController = content.navigationController;
    if ([controller isKindOfClass:UINavigationController.class]) {
        navigationController = (UINavigationController *)controller;
    }

    if (navigationController) RYGLiquidGlassConfigureNavigationController(navigationController);
    RYGUseNativeNavigationTitle(content);

    if (content.isViewLoaded) {
        if ([content isKindOfClass:UITableViewController.class]) {
            UITableView *table = ((UITableViewController *)content).tableView;
            table.backgroundColor = UIColor.systemGroupedBackgroundColor;
            content.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
        } else if (!content.view.backgroundColor) {
            content.view.backgroundColor = UIColor.systemBackgroundColor;
        }
        RYGStyleOwnedControls(content.view);
    }
}
