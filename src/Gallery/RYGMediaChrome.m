#import "RYGMediaChrome.h"
#import "RYGAssetUtils.h"
#import "../Utils.h"
#import "../UI/RYGLiquidGlass.h"

CGFloat const RYGMediaChromeTopBarContentHeight = 44.0;
CGFloat const RYGMediaChromeBottomBarHeight = 52.0;

static CGFloat const kRYGMediaChromeTopIconPointSize = 17.0;
static CGFloat const kRYGMediaChromeBottomIconPointSize = 17.0;
static CGFloat const kRYGMediaChromeFloatingCornerRadius = 26.0;
static CGFloat const kRYGMediaChromeHorizontalMargin = 16.0;
static CGFloat const kRYGMediaChromeBottomGap = 12.0;

UIBlurEffect *RYGMediaChromeBlurEffect(void) {
	if (@available(iOS 13.0, *)) {
		return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
	}
	return [UIBlurEffect effectWithStyle:UIBlurEffectStyleProminent];
}

void RYGApplyMediaChromeNavigationBar(UINavigationBar *bar) {
	if (!bar) return;
	if (@available(iOS 26.0, *)) {
		if (RYGLiquidGlassIsAvailable()) {
			// Leaving the bar's appearance native is what lets UIKit supply the
			// SDK 26 navigation glass and scroll-edge transitions.
			bar.translucent = YES;
			bar.barTintColor = nil;
			bar.tintColor = UIColor.labelColor;
			return;
		}
	}
	if (@available(iOS 13.0, *)) {
		UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
		[appearance configureWithTransparentBackground];
		appearance.backgroundEffect = RYGMediaChromeBlurEffect();
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

UILabel *RYGMediaChromeTitleLabel(NSString *text) {
	UILabel *label = [[UILabel alloc] init];
	label.text = text ?: @"";
	label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
	label.textColor = [UIColor labelColor];
	label.textAlignment = NSTextAlignmentCenter;
	[label sizeToFit];
	return label;
}

UIImage *RYGMediaChromeTopIcon(NSString *resourceName) {
	return [RYGAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
								   pointSize:kRYGMediaChromeTopIconPointSize];
}

UIImage *RYGMediaChromeBottomIcon(NSString *resourceName) {
	return [RYGAssetUtils instagramIconNamed:(resourceName.length > 0 ? resourceName : @"more")
								   pointSize:kRYGMediaChromeBottomIconPointSize];
}

UIBarButtonItem *RYGMediaChromeTopBarButtonItem(NSString *resourceName, id target, SEL action) {
	UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:RYGMediaChromeTopIcon(resourceName)
															  style:UIBarButtonItemStylePlain
															 target:target
															 action:action];
	item.tintColor = [UIColor labelColor];
	return item;
}

// Floating blurred capsule above the safe-area bottom inset.
UIView *RYGMediaChromeInstallBottomBar(UIView *hostView) {
	UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
	bar.translatesAutoresizingMaskIntoConstraints = NO;
	bar.clipsToBounds = NO;
	bar.layer.shadowColor = [UIColor blackColor].CGColor;
	bar.layer.shadowOpacity = 0.18;
	bar.layer.shadowRadius = 14.0;
	bar.layer.shadowOffset = CGSizeMake(0.0, 6.0);
	[hostView addSubview:bar];

	UIVisualEffectView *blur = RYGLiquidGlassView(YES, NO, nil);
	blur.translatesAutoresizingMaskIntoConstraints = NO;
	blur.userInteractionEnabled = YES;
	blur.clipsToBounds = YES;
	blur.layer.cornerRadius = kRYGMediaChromeFloatingCornerRadius;
	blur.layer.cornerCurve = kCACornerCurveContinuous;
	if (!RYGLiquidGlassIsAvailable()) {
		blur.layer.borderWidth = 0.5;
		blur.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
	}
	[bar addSubview:blur];

	// Subtle inner highlight along the top edge (one-pixel hairline).
	UIView *highlight = [[UIView alloc] init];
	highlight.translatesAutoresizingMaskIntoConstraints = NO;
	highlight.backgroundColor = RYGLiquidGlassIsAvailable()
		? UIColor.clearColor : [UIColor colorWithWhite:1.0 alpha:0.10];
	highlight.layer.cornerRadius = 0.5;
	[blur.contentView addSubview:highlight];

	[NSLayoutConstraint activateConstraints:@[
		[blur.topAnchor constraintEqualToAnchor:bar.topAnchor],
		[blur.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
		[blur.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
		[blur.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],

		[highlight.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor constant:1.0],
		[highlight.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor constant:18.0],
		[highlight.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor constant:-18.0],
		[highlight.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
	]];

	[NSLayoutConstraint activateConstraints:@[
		[bar.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor constant:kRYGMediaChromeHorizontalMargin],
		[bar.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor constant:-kRYGMediaChromeHorizontalMargin],
		[bar.bottomAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.bottomAnchor constant:-kRYGMediaChromeBottomGap],
		[bar.heightAnchor constraintEqualToConstant:RYGMediaChromeBottomBarHeight],
	]];

	return bar;
}

// Normalize each glyph's largest dimension to a common target so every bar icon shares one footprint.
static UIImage *RYGNormalizedBottomIcon(UIImage *image) {
	if (!image) return nil;

	static CGFloat const target = 21.0;
	static CGSize const box = (CGSize){26.0, 24.0};
	CGSize source = image.size;
	CGFloat maxDimension = MAX(source.width, source.height);
	if (maxDimension <= 0.0) return image;

	CGFloat scale = target / maxDimension;
	CGSize drawn = CGSizeMake(source.width * scale, source.height * scale);
	CGRect rect = CGRectMake((box.width - drawn.width) / 2.0, (box.height - drawn.height) / 2.0, drawn.width, drawn.height);

	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.opaque = NO;

	UIImage *out = [[[UIGraphicsImageRenderer alloc] initWithSize:box format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		(void)ctx;
		[image drawInRect:rect];
	}];

	return [out imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIButton *RYGMediaChromeBottomButton(NSString *resourceName, NSString *accessibilityLabel) {
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	btn.translatesAutoresizingMaskIntoConstraints = NO;
	[btn setImage:RYGNormalizedBottomIcon(RYGMediaChromeBottomIcon(resourceName)) forState:UIControlStateNormal];
	btn.tintColor = [UIColor labelColor];
	btn.accessibilityLabel = accessibilityLabel;
	btn.adjustsImageWhenHighlighted = NO;
	return btn;
}

UIStackView *RYGMediaChromeInstallBottomRow(UIView *bottomBar, NSArray<UIView *> *row) {
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:row];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.distribution = UIStackViewDistributionFillEqually;
	stack.alignment = UIStackViewAlignmentCenter;

	UIVisualEffectView *blur = (UIVisualEffectView *)bottomBar.subviews.firstObject;
	UIView *host = [blur isKindOfClass:UIVisualEffectView.class] ? blur.contentView : bottomBar;
	[host addSubview:stack];

	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:host.topAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:6.0],
		[stack.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-6.0],
	]];
	for (UIView *v in row) {
		[v.heightAnchor constraintEqualToConstant:RYGMediaChromeBottomBarHeight].active = YES;
	}

	return stack;
}
