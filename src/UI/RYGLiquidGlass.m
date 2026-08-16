#import "RYGLiquidGlass.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

static const void *kRYGGlassButtonConfiguredKey = &kRYGGlassButtonConfiguredKey;

@interface RYGGlassNavigationTitleView : UIVisualEffectView
@property (nonatomic, strong) UILabel *rygLabel;
@end

@implementation RYGGlassNavigationTitleView
- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithEffect:nil])) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        UILabel *label = [UILabel new];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = title;
        label.textColor = UIColor.labelColor;
        label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontForContentSizeCategory = YES;
        label.minimumScaleFactor = 0.78;
        label.adjustsFontSizeToFitWidth = YES;
        [self.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
            [label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
            [label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],
        ]];
        self.rygLabel = label;
    }
    return self;
}
- (CGSize)intrinsicContentSize {
    CGSize s = [self.rygLabel intrinsicContentSize];
    return CGSizeMake(s.width + 24.0, MAX(34.0, s.height + 10.0));
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) * 0.5;
}
@end

static NSString *RYGDefiningImagePath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info = {0};
        if (dladdr((const void *)&RYGIsOwnedViewController, &info) && info.dli_fname) path = [[[NSString alloc] initWithUTF8String:info.dli_fname] stringByStandardizingPath];
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
        UIViewController *candidate = ((UINavigationController *)controller).visibleViewController ?: ((UINavigationController *)controller).viewControllers.firstObject;
        return candidate != controller && RYGControllerTreeIsOwned(candidate, depth + 1);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        UIViewController *candidate = ((UITabBarController *)controller).selectedViewController;
        return candidate != controller && RYGControllerTreeIsOwned(candidate, depth + 1);
    }
    for (UIViewController *child in controller.childViewControllers) if (child != controller && RYGControllerTreeIsOwned(child, depth + 1)) return YES;
    return NO;
}

BOOL RYGIsOwnedViewController(UIViewController *controller) { return RYGControllerTreeIsOwned(controller, 0); }

BOOL RYGLiquidGlassIsAvailable(void) {
    if (@available(iOS 26.0, *)) return !UIAccessibilityIsReduceTransparencyEnabled() && ![RYGUtils getBoolPref:@"liquid_glass_force_off"];
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
    if (!effect && !UIAccessibilityIsReduceTransparencyEnabled()) effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
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
    UIButtonConfiguration *glass = prominent ? [UIButtonConfiguration prominentGlassButtonConfiguration] : [UIButtonConfiguration glassButtonConfiguration];
    glass.title = old.title ?: [button titleForState:UIControlStateNormal];
    glass.attributedTitle = old.attributedTitle;
    glass.subtitle = old.subtitle;
    glass.attributedSubtitle = old.attributedSubtitle;
    glass.image = old.image ?: [button imageForState:UIControlStateNormal];
    glass.imagePlacement = old ? old.imagePlacement : NSDirectionalRectEdgeLeading;
    if (old) {
        glass.imagePadding = old.imagePadding;
        glass.titlePadding = old.titlePadding;
        glass.cornerStyle = old.cornerStyle;
    }
    BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
    if (old && !menuSource) glass.contentInsets = old.contentInsets;
    glass.baseForegroundColor = old.baseForegroundColor ?: button.tintColor;
    return glass;
}

void RYGLiquidGlassConfigureButton(UIButton *button, BOOL prominent) {
    if (!button) return;
    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            button.backgroundColor = UIColor.clearColor;
            button.configuration = RYGGlassConfigurationPreservingButton(button, prominent);
            [button invalidateIntrinsicContentSize];
            objc_setAssociatedObject(button, kRYGGlassButtonConfiguredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static BOOL RYGViewLivesInsideContentCell(UIView *view) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:UITableViewCell.class] || [ancestor isKindOfClass:UICollectionViewCell.class]) return YES;
        if (@available(iOS 26.0, *)) if ([ancestor isKindOfClass:UIVisualEffectView.class] && [((UIVisualEffectView *)ancestor).effect isKindOfClass:UIGlassEffect.class]) return YES;
    }
    return NO;
}

static BOOL RYGViewContainsGlass(UIView *view, NSUInteger depth) {
    if (!view || depth > 4) return NO;
    for (UIView *subview in view.subviews) {
        if (@available(iOS 26.0, *)) if ([subview isKindOfClass:UIVisualEffectView.class] && [((UIVisualEffectView *)subview).effect isKindOfClass:UIGlassEffect.class]) return YES;
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
        if ([view isKindOfClass:UITableView.class]) {
            UITableView *table = (UITableView *)view;
            if (table.contentInset.top < 0.0) {
                UIEdgeInsets inset = table.contentInset; inset.top = 0.0; table.contentInset = inset;
                UIEdgeInsets indicators = table.scrollIndicatorInsets; if (indicators.top < 0.0) { indicators.top = 0.0; table.scrollIndicatorInsets = indicators; }
            }
        }
        if ([view isKindOfClass:UIButton.class] && !RYGViewContainsGlass(view, 0)) {
            UIButton *button = (UIButton *)view;
            BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
            if (!RYGViewLivesInsideContentCell(button) || menuSource) RYGLiquidGlassConfigureButton(button, NO);
        }
        for (UIView *subview in view.subviews) [pending addObject:subview];
    }
}

static void RYGInstallGlassNavigationTitle(UIViewController *content) {
    if (!content || !content.navigationController || !content.title.length) return;
    RYGGlassNavigationTitleView *titleView = [content.navigationItem.titleView isKindOfClass:RYGGlassNavigationTitleView.class] ? (RYGGlassNavigationTitleView *)content.navigationItem.titleView : nil;
    if (!titleView) {
        titleView = [[RYGGlassNavigationTitleView alloc] initWithTitle:content.title];
        titleView.accessibilityIdentifier = @"RYGGlassNavigationTitle";
        content.navigationItem.titleView = titleView;
    }
    titleView.rygLabel.text = content.title;
    [titleView invalidateIntrinsicContentSize];
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) {
        if (RYGLiquidGlassIsAvailable()) {
            UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
            glass.interactive = NO;
            effect = glass;
        }
    }
    if (!effect && !UIAccessibilityIsReduceTransparencyEnabled()) effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    titleView.effect = effect;
    titleView.backgroundColor = effect ? UIColor.clearColor : UIColor.secondarySystemBackgroundColor;
}

void RYGLiquidGlassApplyToViewController(UIViewController *controller) {
    if (!RYGIsOwnedViewController(controller)) return;
    UIViewController *content = controller;
    if ([controller isKindOfClass:UINavigationController.class]) content = ((UINavigationController *)controller).visibleViewController ?: controller;
    UINavigationBar *navigationBar = content.navigationController.navigationBar;
    if (navigationBar) {
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
    RYGInstallGlassNavigationTitle(content);
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
