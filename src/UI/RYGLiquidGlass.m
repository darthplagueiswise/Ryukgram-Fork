#import "RYGLiquidGlass.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif

static const void *kRYGGlassButtonConfiguredKey = &kRYGGlassButtonConfiguredKey;
static const void *kRYGOwnedViewKey = &kRYGOwnedViewKey;

static NSString *RYGNormalizeImagePath(const char *rawPath) {
    if (!rawPath) return nil;
    NSString *path = [[NSString alloc] initWithUTF8String:rawPath];
    return [[path stringByResolvingSymlinksInPath] stringByStandardizingPath];
}

static NSString *RYGDefiningImagePath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info = {0};
        if (dladdr((const void *)&RYGIsOwnedViewController, &info) && info.dli_fname)
            path = RYGNormalizeImagePath(info.dli_fname);
    });
    return path;
}

static const void *RYGUnsignedCodePointer(const void *address) {
#if __has_feature(ptrauth_calls)
    return ptrauth_strip(address, ptrauth_key_function_pointer);
#else
    return address;
#endif
}

BOOL RYGIsOwnedCodeAddress(const void *address) {
    if (!address) return NO;
    Dl_info info = {0};
    if (!dladdr(RYGUnsignedCodePointer(address), &info) || !info.dli_fname) return NO;
    NSString *image = RYGNormalizeImagePath(info.dli_fname);
    NSString *owner = RYGDefiningImagePath();
    return image.length && owner.length && [image isEqualToString:owner];
}

static BOOL RYGClassNameIsOwned(Class cls) {
    NSString *name = cls ? NSStringFromClass(cls) : @"";
    if ([name hasPrefix:@"RYG"] || [name hasPrefix:@"_RYG"]) return YES;
    const char *rawImage = cls ? class_getImageName(cls) : NULL;
    if (!rawImage) return NO;
    NSString *classImage = RYGNormalizeImagePath(rawImage);
    NSString *owner = RYGDefiningImagePath();
    return classImage.length && owner.length && [classImage isEqualToString:owner];
}

void RYGMarkOwnedView(UIView *view) {
    if (view) objc_setAssociatedObject(view, kRYGOwnedViewKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

BOOL RYGIsOwnedView(UIView *view) {
    if (!view) return NO;
    if ([objc_getAssociatedObject(view, kRYGOwnedViewKey) boolValue]) return YES;
    return RYGClassNameIsOwned(view.class);
}

BOOL RYGIsOwnedTargetAction(id target, SEL action) {
    if (!target || !action) return NO;
    Class cls = object_isClass(target) ? (Class)target : object_getClass(target);
    return cls && RYGClassNameIsOwned(cls);
}

static BOOL RYGControllerDirectlyOwned(UIViewController *controller) {
    return controller && RYGClassNameIsOwned(controller.class);
}

static UIViewController *RYGOwnedContainerContent(UIViewController *controller, NSUInteger depth) {
    if (!controller || depth > 6) return nil;
    if (RYGControllerDirectlyOwned(controller)) return controller;
    if ([controller isKindOfClass:UINavigationController.class]) {
        UIViewController *candidate = ((UINavigationController *)controller).visibleViewController ?: ((UINavigationController *)controller).topViewController;
        return candidate && candidate != controller ? RYGOwnedContainerContent(candidate, depth + 1) : nil;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        UIViewController *candidate = ((UITabBarController *)controller).selectedViewController;
        return candidate && candidate != controller ? RYGOwnedContainerContent(candidate, depth + 1) : nil;
    }
    return nil;
}

BOOL RYGIsOwnedViewController(UIViewController *controller) { return RYGOwnedContainerContent(controller, 0) != nil; }

BOOL RYGLiquidGlassIsAvailable(void) {
    if (@available(iOS 26.0, *)) return !UIAccessibilityIsReduceTransparencyEnabled();
    return NO;
}

UIVisualEffectView *RYGLiquidGlassView(BOOL interactive, BOOL clearStyle, UIColor *tintColor) {
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            UIGlassEffect *glass = [UIGlassEffect effectWithStyle:clearStyle ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
            glass.interactive = interactive;
            glass.tintColor = tintColor;
            effect = glass;
        }
    }
    if (!effect && !UIAccessibilityIsReduceTransparencyEnabled())
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
    RYGMarkOwnedView(view);
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
    for (UIMenuElement *element in menu.children)
        if ([element isKindOfClass:UIMenu.class]) RYGPrepareAdaptiveMenu((UIMenu *)element);
}

static UIButtonConfiguration *RYGGlassConfigurationForButton(UIButton *button, BOOL prominent) API_AVAILABLE(ios(26.0)) {
    UIButtonConfiguration *old = button.configuration;
    UIButtonConfiguration *glass = prominent ? [UIButtonConfiguration prominentClearGlassButtonConfiguration]
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
    if (menuSource) [glass setDefaultContentInsets];
    else if (old) glass.contentInsets = old.contentInsets;
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
                objc_setAssociatedObject(button, kRYGGlassButtonConfiguredKey, stateKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
            }
        }
    }
    [button invalidateIntrinsicContentSize];
}

void RYGLiquidGlassConfigureButton(UIButton *button, BOOL prominent) {
    if (!button) return;
    // This function is the ownership boundary. Callers must invoke it only for a
    // concrete control created/taken over by RyukGram; ownership never propagates
    // from a parent controller/view into Instagram controls.
    RYGMarkOwnedView(button);
    RYGSynchronizeGlassButton(button, prominent);
}

@interface RYGGlassNavigationTitleView : UIView
@property (nonatomic, strong) UILabel *label;
@end

@implementation RYGGlassNavigationTitleView
- (CGSize)intrinsicContentSize {
    CGSize text = [self.label sizeThatFits:CGSizeMake(280.0, 44.0)];
    return CGSizeMake(ceil(text.width) + 22.0, ceil(text.height) + 8.0);
}
@end

UIView *RYGLiquidGlassNavigationTitleView(NSString *title) {
    RYGGlassNavigationTitleView *container = [RYGGlassNavigationTitleView new];
    RYGMarkOwnedView(container);
    container.clipsToBounds = YES;
    container.layer.cornerRadius = 16.0;

    UIVisualEffectView *glass = RYGLiquidGlassView(NO, YES, nil);
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:glass];

    UILabel *label = [UILabel new];
    RYGMarkOwnedView(label);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title ?: @"";
    label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.labelColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    label.accessibilityLabel = title;
    container.label = label;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [glass.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [glass.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [glass.topAnchor constraintEqualToAnchor:container.topAnchor],
        [glass.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:11.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-11.0],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:4.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4.0],
    ]];
    return container;
}

void RYGLiquidGlassConfigureNavigationController(UINavigationController *navigationController) {
    if (!navigationController) return;
    navigationController.navigationBar.translucent = YES;
    navigationController.toolbar.translucent = YES;
    navigationController.navigationBar.prefersLargeTitles = NO;
    navigationController.navigationBar.tintColor = UIColor.labelColor;
}

void RYGLiquidGlassApplyToViewController(UIViewController *controller) {
    UIViewController *content = RYGOwnedContainerContent(controller, 0);
    if (!content || !RYGControllerDirectlyOwned(content)) return;
    content.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    // Never mutate an Instagram-owned navigation controller merely because it
    // hosts a RyukGram page.
    UINavigationController *navigationController = nil;
    if ([controller isKindOfClass:UINavigationController.class] && RYGControllerDirectlyOwned(controller))
        navigationController = (UINavigationController *)controller;
    else if (content.navigationController && RYGControllerDirectlyOwned(content.navigationController))
        navigationController = content.navigationController;
    if (navigationController) RYGLiquidGlassConfigureNavigationController(navigationController);

    if (content.isViewLoaded) {
        if ([content isKindOfClass:UITableViewController.class]) {
            UITableView *table = ((UITableViewController *)content).tableView;
            table.backgroundColor = UIColor.systemGroupedBackgroundColor;
            content.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
        } else if (!content.view.backgroundColor) {
            content.view.backgroundColor = UIColor.systemBackgroundColor;
        }
    }

    // Deliberately no recursive UIButton traversal here. Buttons receive Glass
    // only at their RyukGram creation/takeover site via ConfigureButton().
}
