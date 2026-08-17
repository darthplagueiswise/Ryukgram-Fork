#import "RYGLiquidGlass.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

static const void *kRYGGlassButtonConfiguredKey = &kRYGGlassButtonConfiguredKey;

@interface RYGGlassNavigationTitleView : UIView
@property (nonatomic, strong) UIVisualEffectView *rygGlassView;
@property (nonatomic, strong) UILabel *rygLabel;
- (instancetype)initWithTitle:(NSString *)title;
- (void)updateTitle:(NSString *)title;
@end

@implementation RYGGlassNavigationTitleView

- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;

        UIVisualEffectView *glass = RYGLiquidGlassView(NO, NO, nil);
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        glass.userInteractionEnabled = NO;
        glass.clipsToBounds = YES;
        [self addSubview:glass];

        UILabel *label = [UILabel new];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = title;
        label.textColor = UIColor.labelColor;
        label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontForContentSizeCategory = YES;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.72;
        label.numberOfLines = 1;
        [glass.contentView addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [glass.topAnchor constraintEqualToAnchor:self.topAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [label.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:12.0],
            [label.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-12.0],
            [label.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:5.0],
            [label.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-5.0],
        ]];

        self.rygGlassView = glass;
        self.rygLabel = label;
        self.accessibilityIdentifier = @"RYGGlassNavigationTitle";
    }
    return self;
}

- (void)updateTitle:(NSString *)title {
    NSString *next = title ?: @"";
    if (![self.rygLabel.text isEqualToString:next]) {
        self.rygLabel.text = next;
        [self invalidateIntrinsicContentSize];
    }
}

- (CGSize)intrinsicContentSize {
    CGSize labelSize = [self.rygLabel intrinsicContentSize];
    CGFloat width = MIN(220.0, MAX(58.0, ceil(labelSize.width) + 24.0));
    CGFloat height = MAX(34.0, ceil(labelSize.height) + 10.0);
    return CGSizeMake(width, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = CGRectGetHeight(self.bounds) * 0.5;
    self.rygGlassView.layer.cornerCurve = kCACornerCurveContinuous;
    self.rygGlassView.layer.cornerRadius = radius;
}

@end

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
    if (old) glass.cornerStyle = old.cornerStyle;

    // Menu-source controls should let UIKit own the capsule geometry. Copying
    // fixed contentInsets from a closed control is what made expanded morphs
    // look cramped and asymmetrical.
    BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
    if (old && !menuSource) glass.contentInsets = old.contentInsets;
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
        if ([ancestor isKindOfClass:UITableViewCell.class] || [ancestor isKindOfClass:UICollectionViewCell.class]) return YES;
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

        if ([view isKindOfClass:UIButton.class] && !RYGViewContainsGlass(view, 0)) {
            UIButton *button = (UIButton *)view;
            BOOL menuSource = button.showsMenuAsPrimaryAction || button.menu != nil;
            if (!RYGViewLivesInsideContentCell(button) || menuSource) {
                RYGLiquidGlassConfigureButton(button, NO);
            }
        }
        for (UIView *subview in view.subviews) [pending addObject:subview];
    }
}

static void RYGInstallGlassNavigationTitle(UIViewController *content) {
    if (!content || !content.navigationController || !content.title.length) return;

    UIView *existing = content.navigationItem.titleView;
    if (existing && ![existing isKindOfClass:RYGGlassNavigationTitleView.class]) {
        // Respect bespoke title views owned by another RyukGram screen.
        return;
    }

    RYGGlassNavigationTitleView *titleView = (RYGGlassNavigationTitleView *)existing;
    if (!titleView) {
        titleView = [[RYGGlassNavigationTitleView alloc] initWithTitle:content.title];
        content.navigationItem.titleView = titleView;
    } else {
        [titleView updateTitle:content.title];
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
