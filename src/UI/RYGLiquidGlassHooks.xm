#import "RYGLiquidGlass.h"

static UIVisualEffect *RYGNavigationTitleEffect(void) {
    if (@available(iOS 26.0, *)) {
        if (!UIAccessibilityIsReduceTransparencyEnabled()) {
            UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
            glass.interactive = NO;
            return glass;
        }
    }
    if (!UIAccessibilityIsReduceTransparencyEnabled()) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    }
    return nil;
}

@interface RYGGlassNavigationTitleCapsule : UIVisualEffectView
@property(nonatomic, strong) UILabel *rygTitleLabel;
- (instancetype)initWithTitle:(NSString *)title;
- (void)rygSetTitle:(NSString *)title;
@end

@implementation RYGGlassNavigationTitleCapsule

- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithEffect:RYGNavigationTitleEffect()])) {
        RYGMarkOwnedView(self);
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.backgroundColor = self.effect ? UIColor.clearColor : UIColor.secondarySystemBackgroundColor;

        UILabel *label = [UILabel new];
        RYGMarkOwnedView(label);
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textColor = UIColor.labelColor;
        label.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontForContentSizeCategory = YES;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.78;
        label.numberOfLines = 1;
        [self.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [label.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],
            [label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [label.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
        ]];
        self.rygTitleLabel = label;
        [self rygSetTitle:title];
    }
    return self;
}

- (void)rygSetTitle:(NSString *)title {
    self.rygTitleLabel.text = title ?: @"";
    self.accessibilityLabel = title;
    [self invalidateIntrinsicContentSize];
}

- (CGSize)intrinsicContentSize {
    CGSize labelSize = self.rygTitleLabel.intrinsicContentSize;
    return CGSizeMake(MAX(76.0, labelSize.width + 28.0), MAX(36.0, labelSize.height + 12.0));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) * 0.5;
}

@end

static UIViewController *RYGGlassContentController(UIViewController *controller) {
    if ([controller isKindOfClass:UINavigationController.class]) {
        return ((UINavigationController *)controller).visibleViewController ?: controller;
    }
    return controller;
}

static void RYGEnsureGlassNavigationTitle(UIViewController *controller) {
    UIViewController *content = RYGGlassContentController(controller);
    if (!content || !RYGIsOwnedViewController(content) || !content.title.length || !content.navigationController) return;

    UIView *existing = content.navigationItem.titleView;
    if (existing && ![existing isKindOfClass:RYGGlassNavigationTitleCapsule.class]) return;

    RYGGlassNavigationTitleCapsule *titleView =
        [existing isKindOfClass:RYGGlassNavigationTitleCapsule.class]
            ? (RYGGlassNavigationTitleCapsule *)existing
            : [[RYGGlassNavigationTitleCapsule alloc] initWithTitle:content.title];
    [titleView rygSetTitle:content.title];
    content.navigationItem.titleView = titleView;
}

static void RYGApplyOwnedControllerChrome(UIViewController *controller) {
    if (!RYGIsOwnedViewController(controller)) return;
    RYGLiquidGlassApplyToViewController(controller);
    RYGEnsureGlassNavigationTitle(controller);
}

static BOOL RYGCallerBelongsToTweak(void) {
    return RYGIsOwnedCodeAddress(__builtin_return_address(0));
}

// Controller chrome is still observed at the UIKit boundary, but ownership is
// strict: only a RyukGram concrete controller (or a generic UIKit container
// actively presenting one) can pass RYGIsOwnedViewController(). Instagram
// parents no longer become owned merely because they contain a RyukGram child.
%hook UIViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    RYGApplyOwnedControllerChrome(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    RYGApplyOwnedControllerChrome(self);
}

%end

// A RyukGram button can live directly inside an Instagram controller. Control
// ownership therefore follows the creator/target/action, not the controller.
// These hooks never glass an arbitrary UIButton: they only mark controls whose
// creation/configuration call site is in RyukGram or whose target/action IMP is
// implemented by the RyukGram dylib.
%hook UIButton

+ (instancetype)buttonWithType:(UIButtonType)buttonType {
    BOOL ownedCallSite = RYGCallerBelongsToTweak();
    UIButton *button = %orig;
    if (ownedCallSite && button) {
        RYGMarkOwnedView(button);
        RYGLiquidGlassConfigureButton(button, NO);
    }
    return button;
}

+ (instancetype)buttonWithConfiguration:(UIButtonConfiguration *)configuration
                           primaryAction:(UIAction *)primaryAction {
    BOOL ownedCallSite = RYGCallerBelongsToTweak();
    UIButton *button = %orig;
    if (ownedCallSite && button) {
        RYGMarkOwnedView(button);
        RYGLiquidGlassConfigureButton(button, NO);
    }
    return button;
}

- (void)setMenu:(UIMenu *)menu {
    BOOL ownedCallSite = RYGCallerBelongsToTweak();
    %orig;
    if (ownedCallSite) RYGMarkOwnedView(self);
    if (RYGIsOwnedView(self)) RYGLiquidGlassConfigureButton(self, NO);
}

- (void)setShowsMenuAsPrimaryAction:(BOOL)showsMenuAsPrimaryAction {
    BOOL ownedCallSite = RYGCallerBelongsToTweak();
    %orig;
    if (ownedCallSite) RYGMarkOwnedView(self);
    if (RYGIsOwnedView(self)) RYGLiquidGlassConfigureButton(self, NO);
}

- (void)didMoveToWindow {
    %orig;
    if (RYGIsOwnedView(self)) RYGLiquidGlassConfigureButton(self, NO);
}

%end

%hook UIControl

- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents {
    BOOL owned = [self isKindOfClass:UIButton.class] && RYGIsOwnedTargetAction(target, action);
    %orig;
    if (owned) {
        UIButton *button = (UIButton *)self;
        RYGMarkOwnedView(button);
        RYGLiquidGlassConfigureButton(button, NO);
    }
}

- (void)addAction:(UIAction *)action forControlEvents:(UIControlEvents)controlEvents {
    BOOL ownedCallSite = [self isKindOfClass:UIButton.class] && RYGCallerBelongsToTweak();
    %orig;
    if (ownedCallSite) {
        UIButton *button = (UIButton *)self;
        RYGMarkOwnedView(button);
        RYGLiquidGlassConfigureButton(button, NO);
    }
}

%end
