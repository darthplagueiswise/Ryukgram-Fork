#import "SCIAdaptiveGlass.h"
#import "../../Utils.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

BOOL SCIIsIOS26OrNewer(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

UIVisualEffect *SCIRealLiquidGlassEffect(BOOL clearStyle, BOOL interactive, UIColor *tintColor) {
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:(clearStyle ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular)];
        effect.interactive = interactive;
        effect.tintColor = tintColor;
        return effect;
    }
    return nil;
}

static NSInteger const kSCIRealGlassBackgroundTag = 0x51C126;

static UIColor *SCIGlassBorderColor(void);
static UIColor *SCIGlassReadableFillColor(void);

UIColor *SCIGlassBaseSurfaceColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.02 alpha:1.0]
            : [UIColor colorWithWhite:0.97 alpha:1.0];
    }];
}

UIColor *SCIGlassBackdropColor(void) {
    return SCIGlassBaseSurfaceColor();
}

void SCIApplyOfficialContainerGlassToViewController(UIViewController *vc) {
    if (!vc || !SCIIsIOS26OrNewer()) return;
    // UIKit 26 owns the container glass/background behavior when this selector exists.
    // Use objc_msgSend so the tweak keeps running on iOS 16.3+.
    NSInteger glassStyle = 1; // UIContainerBackgroundStyleGlass in the iOS 26 SDK.
    SEL preferred = NSSelectorFromString(@"setPreferredContainerBackgroundStyle:");
    SEL direct = NSSelectorFromString(@"setContainerBackgroundStyle:");
    if ([vc respondsToSelector:preferred]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(vc, preferred, glassStyle);
    } else if ([vc respondsToSelector:direct]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(vc, direct, glassStyle);
    }
}

static BOOL SCIViewShouldReceiveGlassBackground(UIView *view) {
    if (!view || view.tag == kSCIRealGlassBackgroundTag) return NO;
    NSString *className = NSStringFromClass(view.class) ?: @"";
    if ([className containsString:@"UIVisualEffectContent"]) return NO;
    if (![view isKindOfClass:UIVisualEffectView.class] && [view.superview isKindOfClass:UIVisualEffectView.class]) return NO;
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIStackView.class]) return NO;
    if ([view isKindOfClass:UITableView.class] || [view isKindOfClass:UICollectionView.class] || [view isKindOfClass:UIScrollView.class]) return NO;
    if ([view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class] || [view isKindOfClass:UITableViewHeaderFooterView.class]) return NO;
    if ([view isKindOfClass:UISegmentedControl.class] || [view isKindOfClass:UIButton.class]) return YES;
    return NO;
}

static UIVisualEffectView *SCIEnsureRealGlassBackground(UIView *view, CGFloat radius, BOOL interactive, BOOL clearStyle, UIColor *tintColor) {
    if (!view || !SCIIsIOS26OrNewer()) return nil;
    UIVisualEffect *effect = SCIRealLiquidGlassEffect(clearStyle, interactive, tintColor);
    if (!effect) return nil;

    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *effectView = (UIVisualEffectView *)view;
        effectView.effect = effect;
        effectView.backgroundColor = UIColor.clearColor;
        effectView.contentView.backgroundColor = UIColor.clearColor;
        effectView.layer.cornerRadius = radius;
        if ([effectView.layer respondsToSelector:@selector(setCornerCurve:)]) effectView.layer.cornerCurve = kCACornerCurveContinuous;
        effectView.layer.masksToBounds = YES;
        effectView.clipsToBounds = YES;
        return effectView;
    }

    UIVisualEffectView *glass = (UIVisualEffectView *)[view viewWithTag:kSCIRealGlassBackgroundTag];
    if (![glass isKindOfClass:UIVisualEffectView.class]) {
        glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.tag = kSCIRealGlassBackgroundTag;
        glass.userInteractionEnabled = NO;
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        [view insertSubview:glass atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [glass.topAnchor constraintEqualToAnchor:view.topAnchor],
            [glass.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        ]];
    } else {
        glass.effect = effect;
    }

    glass.backgroundColor = UIColor.clearColor;
    glass.contentView.backgroundColor = UIColor.clearColor;
    glass.layer.cornerRadius = radius;
    if ([glass.layer respondsToSelector:@selector(setCornerCurve:)]) glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.masksToBounds = YES;
    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = radius;
    if ([view.layer respondsToSelector:@selector(setCornerCurve:)]) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    return glass;
}

static void SCIConfigureScrollViewForGlass(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *tableView = (UITableView *)view;
        tableView.backgroundColor = UIColor.clearColor;
        tableView.backgroundView = nil;
        if (@available(iOS 26.0, *)) {
            UIVisualEffect *effect = SCIRealLiquidGlassEffect(YES, NO, nil);
            SEL setBackgroundEffect = NSSelectorFromString(@"setBackgroundEffect:");
            if ([tableView respondsToSelector:setBackgroundEffect]) {
                ((void (*)(id, SEL, id))objc_msgSend)(tableView, setBackgroundEffect, effect);
            }
        }
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        tableView.separatorColor = UIColor.clearColor;
        if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 0.0;
    } else if ([view isKindOfClass:UICollectionView.class] || [view isKindOfClass:UIScrollView.class]) {
        view.backgroundColor = UIColor.clearColor;
    }
}

static BOOL SCIViewIsInsideAdaptiveGlass(UIView *view) {
    UIView *cur = view.superview;
    while (cur) {
        if ([cur isKindOfClass:SCIAdaptiveGlassPanelView.class]) return YES;
        cur = cur.superview;
    }
    return NO;
}

void SCIApplyLiquidGlassToViewTree(UIView *root) {
    if (!root || !SCIIsIOS26OrNewer()) return;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:root.subviews];
    while (stack.count) {
        UIView *view = stack.lastObject;
        [stack removeLastObject];
        if (view.tag == kSCIRealGlassBackgroundTag) continue;

        BOOL isScrollView = [view isKindOfClass:UITableView.class] ||
            [view isKindOfClass:UICollectionView.class] ||
            [view isKindOfClass:UIScrollView.class];
        SCIConfigureScrollViewForGlass(view);
        if ([view isKindOfClass:UISearchBar.class]) {
            SCIApplyGlassToSearchBar((UISearchBar *)view);
        } else if ([view isKindOfClass:UISegmentedControl.class]) {
            SCIApplyGlassToSegmentedControl((UISegmentedControl *)view);
        } else if ([view isKindOfClass:UITabBar.class]) {
            SCIApplyGlassToTabBar((UITabBar *)view);
        } else if ([view isKindOfClass:UIButton.class]) {
            SCIApplyGlassToButton((UIButton *)view);
        } else if (!isScrollView && SCIViewShouldReceiveGlassBackground(view)) {
            CGFloat radius = view.layer.cornerRadius > 0.0 ? view.layer.cornerRadius : 16.0;
            SCIApplyGlassToView(view, radius, [view isKindOfClass:UIControl.class]);
        }

        for (UIView *subview in view.subviews) [stack addObject:subview];
    }
}

void SCIStyleSearchBarForGlass(UISearchBar *searchBar) {
    if (!searchBar) return;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.backgroundImage = UIImage.new;
    searchBar.barTintColor = UIColor.clearColor;
    searchBar.backgroundColor = UIColor.clearColor;
    searchBar.translucent = YES;

    UITextField *field = searchBar.searchTextField;
    if (!field) return;

    field.textColor = UIColor.labelColor;
    field.tintColor = UIColor.systemBlueColor;
    field.borderStyle = UITextBorderStyleNone;
    field.background = nil;
    field.disabledBackground = nil;
    field.backgroundColor = UIColor.clearColor;
    field.layer.backgroundColor = UIColor.clearColor.CGColor;
    field.layer.cornerRadius = 0.0;
    field.layer.borderWidth = 0.0;
    field.layer.masksToBounds = NO;
    field.clipsToBounds = NO;
    field.leftView.tintColor = UIColor.secondaryLabelColor;
    field.rightView.tintColor = UIColor.secondaryLabelColor;

    NSString *placeholder = field.attributedPlaceholder.string ?: field.placeholder ?: @"";
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{
        NSForegroundColorAttributeName: UIColor.secondaryLabelColor
    }];
}

void SCIApplyGlassBackdropToViewController(UIViewController *vc) {
    if (!vc) return;
    if (!vc.isViewLoaded) [vc loadViewIfNeeded];

    SCIApplyOfficialContainerGlassToViewController(vc);

    UIView *root = vc.view;
    root.backgroundColor = SCIGlassBaseSurfaceColor();
    root.opaque = YES;
    root.layer.backgroundColor = [SCIGlassBaseSurfaceColor() resolvedColorWithTraitCollection:root.traitCollection].CGColor;
    SCIConfigureScrollViewForGlass(root);
    SCIApplyLiquidGlassToViewTree(root);

    UINavigationBar *bar = vc.navigationController.navigationBar;
    if (bar) {
        bar.translucent = YES;
        bar.backgroundColor = UIColor.clearColor;
        bar.prefersLargeTitles = NO;
        if (@available(iOS 13.0, *)) {
            UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
            [appearance configureWithTransparentBackground];
            appearance.backgroundColor = UIColor.clearColor;
            appearance.shadowColor = UIColor.clearColor;
            bar.standardAppearance = appearance;
            bar.scrollEdgeAppearance = appearance;
            bar.compactAppearance = appearance;
        }
    }

    UIToolbar *toolbar = vc.navigationController.toolbar;
    if (toolbar && @available(iOS 13.0, *)) {
        UIToolbarAppearance *appearance = [UIToolbarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.shadowColor = UIColor.clearColor;
        toolbar.standardAppearance = appearance;
        if (@available(iOS 15.0, *)) toolbar.scrollEdgeAppearance = appearance;
        toolbar.translucent = YES;
        toolbar.backgroundColor = UIColor.clearColor;
    }

    if (vc.tabBarController.tabBar) SCIApplyGlassToTabBar(vc.tabBarController.tabBar);
}

static UIButtonConfiguration *SCIRealGlassButtonConfiguration(BOOL prominent) {
    if (@available(iOS 26.0, *)) {
        return prominent ? [UIButtonConfiguration prominentGlassButtonConfiguration] : [UIButtonConfiguration clearGlassButtonConfiguration];
    }
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.background.backgroundColor = UIColor.clearColor;
        cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
        return cfg;
    }
    return nil;
}

void SCIApplyGlassToView(UIView *view, CGFloat radius, BOOL interactive) {
    if (!view) return;
    view.backgroundColor = UIColor.clearColor;
    view.layer.cornerRadius = radius;
    if ([view.layer respondsToSelector:@selector(setCornerCurve:)]) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    SCIEnsureRealGlassBackground(view, radius, interactive, NO, nil);
}

void SCIApplyGlassToButton(UIButton *button) {
    if (!button) return;
    button.backgroundColor = UIColor.clearColor;
    if (@available(iOS 15.0, *)) {
        NSString *title = [button titleForState:UIControlStateNormal];
        UIImage *image = [button imageForState:UIControlStateNormal];
        UIButtonConfiguration *cfg = button.configuration ?: SCIRealGlassButtonConfiguration(NO);
        if (title.length) cfg.title = title;
        if (image) cfg.image = image;
        cfg.background.backgroundColor = UIColor.clearColor;
        cfg.baseForegroundColor = button.tintColor ?: UIColor.labelColor;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 12.0, 8.0, 12.0);
        button.configuration = cfg;
    }
}

void SCIApplyGlassToSearchBar(UISearchBar *searchBar) {
    SCIStyleSearchBarForGlass(searchBar);
}

void SCIApplyGlassToSegmentedControl(UISegmentedControl *control) {
    SCIStyleSegmentedControlForGlass(control);
}

void SCIApplyGlassToTabBar(UITabBar *tabBar) {
    if (!tabBar) return;
    tabBar.translucent = YES;
    tabBar.backgroundColor = UIColor.clearColor;
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.shadowColor = UIColor.clearColor;
        tabBar.standardAppearance = appearance;
        if (@available(iOS 15.0, *)) tabBar.scrollEdgeAppearance = appearance;
    }
}

void SCIStyleTableViewForGlass(UITableView *tableView) {
    if (!tableView) return;
    SCIConfigureScrollViewForGlass(tableView);
}

void SCIStyleCollectionViewForGlass(UICollectionView *collectionView) {
    if (!collectionView) return;
    collectionView.backgroundColor = UIColor.clearColor;
}

void SCIStyleCellForGlass(UITableViewCell *cell) {
    if (!cell) return;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    UIView *selected = [UIView new];
    selected.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.08];
    cell.selectedBackgroundView = selected;
    if (SCIIsIOS26OrNewer() && @available(iOS 14.0, *)) {
        UIBackgroundConfiguration *bg = [UIBackgroundConfiguration clearConfiguration];
        bg.backgroundColor = SCIGlassReadableFillColor();
        bg.visualEffect = SCIRealLiquidGlassEffect(NO, YES, nil);
        bg.cornerRadius = 18.0;
        bg.strokeColor = UIColor.clearColor;
        bg.strokeWidth = 0.0;
        cell.backgroundConfiguration = bg;
        cell.backgroundView = nil;
    } else {
        SCIEnsureRealGlassBackground(cell.contentView, 14.0, YES, NO, nil);
    }
}

void SCIStyleSegmentedControlForGlass(UISegmentedControl *control) {
    if (!control) return;
    control.backgroundColor = UIColor.clearColor;
    control.selectedSegmentTintColor = SCIIsIOS26OrNewer() ? nil : [UIColor.labelColor colorWithAlphaComponent:0.12];
    NSDictionary *normal = @{ NSForegroundColorAttributeName: UIColor.secondaryLabelColor };
    NSDictionary *selected = @{ NSForegroundColorAttributeName: UIColor.labelColor, NSFontAttributeName: [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold] };
    [control setTitleTextAttributes:normal forState:UIControlStateNormal];
    [control setTitleTextAttributes:selected forState:UIControlStateSelected];
}

static UIColor *SCIGlassBorderColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.08]
            : [UIColor colorWithWhite:0.0 alpha:0.08];
    }];
}

static UIColor *SCIGlassReadableFillColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.08 alpha:0.84]
            : [UIColor colorWithWhite:1.0 alpha:0.88];
    }];
}

@implementation SCIAdaptiveGlassPanelView

- (instancetype)initWithRadius:(CGFloat)radius {
    self = [super initWithEffect:SCIRealLiquidGlassEffect(NO, NO, nil)];
    if (self) {
        _sciCornerRadius = radius;
        [self applyReadableGlassStyle];
    }
    return self;
}

- (instancetype)initWithEffect:(UIVisualEffect *)effect {
    self = [super initWithEffect:effect ?: SCIRealLiquidGlassEffect(NO, NO, nil)];
    if (self) {
        _sciCornerRadius = 22.0;
        [self applyReadableGlassStyle];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self applyReadableGlassStyle];
}

- (void)setSciGlassInteractive:(BOOL)sciGlassInteractive {
    _sciGlassInteractive = sciGlassInteractive;
    [self applyReadableGlassStyle];
}

- (void)setSciGlassClearStyle:(BOOL)sciGlassClearStyle {
    _sciGlassClearStyle = sciGlassClearStyle;
    [self applyReadableGlassStyle];
}

- (void)setSciGlassTintColor:(UIColor *)sciGlassTintColor {
    _sciGlassTintColor = sciGlassTintColor;
    [self applyReadableGlassStyle];
}

- (void)applyReadableGlassStyle {
    self.effect = SCIRealLiquidGlassEffect(self.sciGlassClearStyle, self.sciGlassInteractive, self.sciGlassTintColor);
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = SCIGlassReadableFillColor();
    self.layer.cornerRadius = self.sciCornerRadius;
    if ([self.layer respondsToSelector:@selector(setCornerCurve:)]) self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = SCIIsIOS26OrNewer();
    self.clipsToBounds = SCIIsIOS26OrNewer();
    self.layer.borderWidth = SCIIsIOS26OrNewer() ? 0.0 : 0.7;
    self.layer.borderColor = SCIIsIOS26OrNewer() ? UIColor.clearColor.CGColor : SCIGlassBorderColor().CGColor;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = SCIIsIOS26OrNewer() ? 0.0 : 0.10;
    self.layer.shadowRadius = SCIIsIOS26OrNewer() ? 0.0 : 14.0;
    self.layer.shadowOffset = SCIIsIOS26OrNewer() ? CGSizeZero : CGSizeMake(0, 6);
}

@end

@interface SCIGlassSectionHeaderView ()
@property (nonatomic, strong) SCIAdaptiveGlassPanelView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation SCIGlassSectionHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (self) {
        self.contentView.backgroundColor = UIColor.clearColor;
        _panel = [[SCIAdaptiveGlassPanelView alloc] initWithRadius:16.0];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_panel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 2.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_panel.contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
            [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [stack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:10.0],
            [stack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14.0],
            [stack.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-14.0],
            [stack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-10.0],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.subtitleLabel.hidden = subtitle.length == 0;
}

@end

@interface SCIGlassParamCell ()
@property (nonatomic, strong) SCIAdaptiveGlassPanelView *panel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *badgeLabel;
@end

@implementation SCIGlassParamCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectedBackgroundView = [UIView new];
        self.selectedBackgroundView.backgroundColor = UIColor.clearColor;

        _panel = [[SCIAdaptiveGlassPanelView alloc] initWithRadius:18.0];
        _panel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_panel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _titleLabel.textColor = UIColor.labelColor;
        _titleLabel.numberOfLines = 2;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _subtitleLabel = [UILabel new];
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 4;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _badgeLabel = [UILabel new];
        _badgeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        _badgeLabel.textColor = UIColor.labelColor;
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badgeLabel.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.08];
        _badgeLabel.layer.cornerRadius = 10.0;
        _badgeLabel.layer.cornerCurve = kCACornerCurveContinuous;
        _badgeLabel.clipsToBounds = YES;
        _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 4.0;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;

        [_panel.contentView addSubview:textStack];
        [_panel.contentView addSubview:_badgeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5.0],
            [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14.0],
            [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],
            [_panel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5.0],
            [textStack.topAnchor constraintEqualToAnchor:_panel.contentView.topAnchor constant:12.0],
            [textStack.leadingAnchor constraintEqualToAnchor:_panel.contentView.leadingAnchor constant:14.0],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_badgeLabel.leadingAnchor constant:-10.0],
            [textStack.bottomAnchor constraintEqualToAnchor:_panel.contentView.bottomAnchor constant:-12.0],
            [_badgeLabel.trailingAnchor constraintEqualToAnchor:_panel.contentView.trailingAnchor constant:-12.0],
            [_badgeLabel.centerYAnchor constraintEqualToAnchor:_panel.contentView.centerYAnchor],
            [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:48.0],
            [_badgeLabel.heightAnchor constraintEqualToConstant:22.0],
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self configureWithTitle:@"" subtitle:@"" badge:nil emphasized:NO];
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle badge:(NSString *)badge emphasized:(BOOL)emphasized {
    self.titleLabel.text = title ?: @"";
    self.subtitleLabel.text = subtitle ?: @"";
    self.badgeLabel.text = badge ?: @"";
    self.badgeLabel.hidden = badge.length == 0;
    self.titleLabel.font = emphasized ? [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] : [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.panel.sciGlassTintColor = nil;
    self.panel.contentView.backgroundColor = emphasized ? [[SCIUtils SCIColor_Primary] colorWithAlphaComponent:0.18] : SCIGlassReadableFillColor();
    if (SCIIsIOS26OrNewer()) {
        self.badgeLabel.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:emphasized ? 0.12 : 0.08];
    }
}

@end

@interface SCIGlassFloatingToolbar ()
@property (nonatomic, strong) UIButton *captureButton;
@end

@implementation SCIGlassFloatingToolbar

static UIButton *SCIToolbarButton(NSString *title, NSString *symbol, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg;
        if (@available(iOS 26.0, *)) cfg = [UIButtonConfiguration clearGlassButtonConfiguration];
        else cfg = [UIButtonConfiguration plainButtonConfiguration];
        cfg.title = title;
        cfg.image = [UIImage systemImageNamed:symbol];
        cfg.imagePadding = 5.0;
        cfg.buttonSize = UIButtonConfigurationSizeSmall;
        button.configuration = cfg;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
    }
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (instancetype)initWithTarget:(id)target refresh:(SEL)refresh clear:(SEL)clear export:(SEL)export toggleCapture:(SEL)toggleCapture {
    self = [super initWithRadius:24.0];
    if (self) {
        self.sciGlassClearStyle = NO;
        self.sciGlassInteractive = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        UIButton *refreshButton = SCIToolbarButton(@"Refresh", @"arrow.clockwise", target, refresh);
        UIButton *exportButton = SCIToolbarButton(@"Export", @"square.and.arrow.up", target, export);
        UIButton *clearButton = SCIToolbarButton(@"Clear", @"trash", target, clear);
        _captureButton = SCIToolbarButton(@"Capture", @"dot.radiowaves.left.and.right", target, toggleCapture);
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[refreshButton, exportButton, clearButton, _captureButton]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.distribution = UIStackViewDistributionEqualSpacing;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 4.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10.0],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0],
        ]];
    }
    return self;
}

- (void)setCaptureEnabled:(BOOL)enabled {
    NSString *title = enabled ? @"Capture ON" : @"Capture OFF";
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = self.captureButton.configuration ?: ({
            UIButtonConfiguration *fallback;
            if (@available(iOS 26.0, *)) fallback = [UIButtonConfiguration clearGlassButtonConfiguration];
            else fallback = [UIButtonConfiguration plainButtonConfiguration];
            fallback;
        });
        cfg.title = title;
        cfg.baseForegroundColor = enabled ? [SCIUtils SCIColor_Primary] : UIColor.secondaryLabelColor;
        self.captureButton.configuration = cfg;
    } else {
        [self.captureButton setTitle:title forState:UIControlStateNormal];
    }
}

@end

@interface SCIGlassSearchBar ()
@property (nonatomic, strong, readwrite) UISearchBar *searchBar;
@end

@implementation SCIGlassSearchBar

- (instancetype)initWithRadius:(CGFloat)radius {
    self = [super initWithRadius:radius];
    if (self) [self commonInit];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self commonInit];
    return self;
}

- (void)commonInit {
    self.sciCornerRadius = 22.0;
    self.sciGlassInteractive = YES;
    [self applyReadableGlassStyle];
    _searchBar = [UISearchBar new];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_searchBar];
    SCIStyleSearchBarForGlass(_searchBar);
    [NSLayoutConstraint activateConstraints:@[
        [_searchBar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2.0],
        [_searchBar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4.0],
        [_searchBar.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4.0],
        [_searchBar.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2.0],
    ]];
}

@end
