#import "SCIMediaChrome.h"
#import "SCIAssetUtils.h"
#import "../Settings/GlassUI/SCIAdaptiveGlass.h"
#import "../Utils.h"

CGFloat const SCIMediaChromeTopBarContentHeight = 44.0;
CGFloat const SCIMediaChromeBottomBarHeight = 52.0;

static CGFloat const kSCIMediaChromeTopIconPointSize = 17.0;
static CGFloat const kSCIMediaChromeBottomIconPointSize = 17.0;
static CGFloat const kSCIMediaChromeFloatingCornerRadius = 26.0;
static CGFloat const kSCIMediaChromeHorizontalMargin = 16.0;
static CGFloat const kSCIMediaChromeBottomGap = 12.0;

UIVisualEffect *SCIMediaChromeGlassEffect(void) {
	return SCIRealLiquidGlassEffect(NO, YES, nil);
}

void SCIApplyMediaChromeNavigationBar(UINavigationBar *bar) {
	if (!bar) return;
	if (@available(iOS 13.0, *)) {
		UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
		[appearance configureWithTransparentBackground];
		appearance.backgroundEffect = SCIMediaChromeGlassEffect();
		appearance.shadowColor = [UIColor clearColor];
		appearance.shadowImage = [UIImage new];
		bar.standardAppearance = appearance;
		bar.scrollEdgeAppearance = appearance;
		bar.compactAppearance = appearance;
		if (@available(iOS 15.0, *)) {
			bar.compactScrollEdgeAppearance = appearance;
		}
	}
	bar.tintColor = [UIColor labelColor];
}

UILabel *SCIMediaChromeTitleLabel(NSString *text) {
	UILabel *label = [[UILabel alloc] init];
	label.text = text ?: @"";
	label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
	label.textColor = [UIColor labelColor];
	label.textAlignment = NSTextAlignmentCenter;
	[label sizeToFit];
	return label;
}

UIImage *SCIMediaChromeTopIcon(NSString *resourceName) {
	return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
								   pointSize:kSCIMediaChromeTopIconPointSize];
}

UIImage *SCIMediaChromeBottomIcon(NSString *resourceName) {
	return [SCIAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
								   pointSize:kSCIMediaChromeBottomIconPointSize];
}

UIBarButtonItem *SCIMediaChromeTopBarButtonItem(NSString *resourceName, id target, SEL action) {
	UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:SCIMediaChromeTopIcon(resourceName)
															  style:UIBarButtonItemStylePlain
															 target:target
															 action:action];
	item.tintColor = [UIColor labelColor];
	return item;
}

UIView *SCIMediaChromeInstallBottomBar(UIView *hostView) {
	UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
	bar.translatesAutoresizingMaskIntoConstraints = NO;
	bar.clipsToBounds = NO;
	bar.layer.shadowColor = [UIColor blackColor].CGColor;
	bar.layer.shadowOpacity = 0.0;
	bar.layer.shadowRadius = 0.0;
	bar.layer.shadowOffset = CGSizeZero;
	[hostView addSubview:bar];

	UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:SCIMediaChromeGlassEffect()];
	glass.translatesAutoresizingMaskIntoConstraints = NO;
	glass.clipsToBounds = YES;
	glass.layer.cornerRadius = kSCIMediaChromeFloatingCornerRadius;
	glass.layer.cornerCurve = kCACornerCurveContinuous;
	glass.layer.borderWidth = 0.0;
	glass.layer.borderColor = UIColor.clearColor.CGColor;
	[bar addSubview:glass];

	[NSLayoutConstraint activateConstraints:@[
		[glass.topAnchor constraintEqualToAnchor:bar.topAnchor],
		[glass.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
		[glass.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
		[glass.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
	]];

	[NSLayoutConstraint activateConstraints:@[
		[bar.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor constant:kSCIMediaChromeHorizontalMargin],
		[bar.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor constant:-kSCIMediaChromeHorizontalMargin],
		[bar.bottomAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.bottomAnchor constant:-kSCIMediaChromeBottomGap],
		[bar.heightAnchor constraintEqualToConstant:SCIMediaChromeBottomBarHeight],
	]];

	return bar;
}

UIButton *SCIMediaChromeBottomButton(NSString *resourceName, NSString *accessibilityLabel) {
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	btn.translatesAutoresizingMaskIntoConstraints = NO;
	[btn setImage:SCIMediaChromeBottomIcon(resourceName) forState:UIControlStateNormal];
	btn.tintColor = [UIColor labelColor];
	btn.accessibilityLabel = accessibilityLabel;
	btn.adjustsImageWhenHighlighted = NO;
	return btn;
}

UIStackView *SCIMediaChromeInstallBottomRow(UIView *bottomBar, NSArray<UIView *> *row) {
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:row];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.distribution = UIStackViewDistributionFillEqually;
	stack.alignment = UIStackViewAlignmentCenter;

	UIVisualEffectView *glass = (UIVisualEffectView *)bottomBar.subviews.firstObject;
	UIView *host = [glass isKindOfClass:UIVisualEffectView.class] ? glass.contentView : bottomBar;
	[host addSubview:stack];

	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:host.topAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:6.0],
		[stack.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-6.0],
	]];
	for (UIView *v in row) {
		[v.heightAnchor constraintEqualToConstant:SCIMediaChromeBottomBarHeight].active = YES;
	}

	return stack;
}
