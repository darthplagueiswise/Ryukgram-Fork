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
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.backgroundColor = self.effect ? UIColor.clearColor : UIColor.secondarySystemBackgroundColor;

        UILabel *label = [UILabel new];
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
    if (!content || !content.title.length || !content.navigationController) return;

    UIView *existing = content.navigationItem.titleView;
    if (existing && ![existing isKindOfClass:RYGGlassNavigationTitleCapsule.class]) {
        // Respect intentionally custom title views owned by a specialized page.
        return;
    }

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

// The old implementation tried to fix individual screens after the fact. Keep
// the policy at the RyukGram controller boundary instead: only controller trees
// owned by the tweak receive this pass, while Instagram's own hierarchy remains
// untouched.
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
