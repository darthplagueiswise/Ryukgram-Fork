#import "RYGDonatePrompt.h"
#import "../Tweak.h"
#import "../Localization/RYGLocalization.h"
#import "../UI/RYGLiquidGlass.h"

// Bump to re-arm the prompt for everyone, including people who silenced it.
static const NSInteger kCampaign = 1;

static const NSInteger kMinLaunches = 10;
static const NSInteger kSnoozeLaunches = 100;

static NSString *const kLaunchCountKey = @"ryg_donate_launch_count";
static NSString *const kSnoozeUntilKey = @"ryg_donate_snooze_until_launch";
static NSString *const kSilencedKey = @"ryg_donate_prompt_silenced";
static NSString *const kCampaignKey = @"ryg_donate_campaign";

static BOOL sShownThisSession;

@interface RYGDonatePrompt ()
+ (void)silence;
+ (void)snooze;
@end

#pragma mark - Gradient badge

@interface _RYGGradientCircle : UIView
@end

@implementation _RYGGradientCircle

+ (Class)layerClass { return CAGradientLayer.class; }

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	CAGradientLayer *g = (CAGradientLayer *)self.layer;
	g.colors = @[(id)[UIColor colorWithRed:1.00 green:0.35 blue:0.50 alpha:1.0].CGColor,
	             (id)[UIColor colorWithRed:1.00 green:0.60 blue:0.24 alpha:1.0].CGColor];
	g.startPoint = CGPointMake(0.0, 0.0);
	g.endPoint = CGPointMake(1.0, 1.0);
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	self.layer.cornerRadius = CGRectGetWidth(self.bounds) / 2.0;
	self.layer.cornerCurve = kCACornerCurveContinuous;
}

@end

#pragma mark - Card

@interface _RYGDonateCardVC : UIViewController
@property (nonatomic, strong) UIView *dim;
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIStackView *content;
@property (nonatomic, strong) _RYGGradientCircle *badge;
@property (nonatomic, assign) BOOL didAnimateIn;
@end

@implementation _RYGDonateCardVC

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.clearColor;

	self.blur = [[UIVisualEffectView alloc] initWithEffect:nil];
	self.blur.frame = self.view.bounds;
	self.blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.blur];

	self.dim = [[UIView alloc] initWithFrame:self.view.bounds];
	self.dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.42];
	self.dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.dim.alpha = 0.0;
	[self.view addSubview:self.dim];

	[self buildCard];

	self.card.alpha = 0.0;
	self.card.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 14), 0.88, 0.88);
}

- (void)buildCard {
	self.card = [UIView new];
	self.card.backgroundColor = UIColor.clearColor;
	self.card.layer.cornerRadius = 30.0;
	self.card.layer.cornerCurve = kCACornerCurveContinuous;
	self.card.layer.shadowColor = UIColor.blackColor.CGColor;
	self.card.layer.shadowOpacity = 0.28;
	self.card.layer.shadowRadius = 30.0;
	self.card.layer.shadowOffset = CGSizeMake(0, 14);
	self.card.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.card];

	UIVisualEffectView *glass = RYGLiquidGlassView(NO, NO, UIColor.secondarySystemBackgroundColor);
	glass.frame = self.card.bounds;
	glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	glass.layer.cornerRadius = 30.0;
	glass.layer.cornerCurve = kCACornerCurveContinuous;
	glass.clipsToBounds = YES;
	[self.card addSubview:glass];

	self.badge = [[_RYGGradientCircle alloc] initWithFrame:CGRectZero];
	self.badge.translatesAutoresizingMaskIntoConstraints = NO;

	UIImageView *heart = [[UIImageView alloc] initWithImage:
		[UIImage systemImageNamed:@"heart.fill"
				withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:36 weight:UIImageSymbolWeightBold]]];
	heart.tintColor = UIColor.whiteColor;
	heart.translatesAutoresizingMaskIntoConstraints = NO;
	[self.badge addSubview:heart];

	UILabel *title = [UILabel new];
	title.text = RYGLocalized(@"Enjoying RyukGram?");
	title.font = [UIFont systemFontOfSize:23 weight:UIFontWeightBold];
	title.textAlignment = NSTextAlignmentCenter;
	title.numberOfLines = 0;

	UILabel *body = [UILabel new];
	body.text = RYGLocalized(@"It's free, and nothing leaves your device. If you enjoy using it, a coffee keeps it going.");
	body.font = [UIFont systemFontOfSize:15];
	body.textColor = UIColor.secondaryLabelColor;
	body.textAlignment = NSTextAlignmentCenter;
	body.numberOfLines = 0;

	UIButton *donate = [self primaryButton];
	UIButton *already = [self textButtonWithTitle:RYGLocalized(@"I already did") font:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] color:UIColor.secondaryLabelColor];
	[already addTarget:self action:@selector(tapAlready) forControlEvents:UIControlEventTouchUpInside];
	UIButton *later = [self textButtonWithTitle:RYGLocalized(@"Maybe later") font:[UIFont systemFontOfSize:15] color:UIColor.tertiaryLabelColor];
	[later addTarget:self action:@selector(tapLater) forControlEvents:UIControlEventTouchUpInside];

	UIStackView *minor = [[UIStackView alloc] initWithArrangedSubviews:@[already, later]];
	minor.axis = UILayoutConstraintAxisHorizontal;
	minor.distribution = UIStackViewDistributionFillEqually;
	minor.spacing = 8;

	self.content = [[UIStackView alloc] initWithArrangedSubviews:@[self.badge, title, body, donate, minor]];
	self.content.axis = UILayoutConstraintAxisVertical;
	self.content.alignment = UIStackViewAlignmentCenter;
	self.content.spacing = 12;
	[self.content setCustomSpacing:18 afterView:self.badge];
	[self.content setCustomSpacing:8 afterView:title];
	[self.content setCustomSpacing:22 afterView:body];
	[self.content setCustomSpacing:6 afterView:donate];
	self.content.translatesAutoresizingMaskIntoConstraints = NO;
	[self.card addSubview:self.content];

	CGFloat width = MIN(340.0, UIScreen.mainScreen.bounds.size.width - 56.0);

	[NSLayoutConstraint activateConstraints:@[
		[self.card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.card.widthAnchor constraintEqualToConstant:width],

		[self.content.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:26],
		[self.content.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-16],
		[self.content.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:22],
		[self.content.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-22],

		[self.badge.widthAnchor constraintEqualToConstant:84],
		[self.badge.heightAnchor constraintEqualToConstant:84],
		[heart.centerXAnchor constraintEqualToAnchor:self.badge.centerXAnchor],
		[heart.centerYAnchor constraintEqualToAnchor:self.badge.centerYAnchor],

		[donate.widthAnchor constraintEqualToAnchor:self.content.widthAnchor],
		[donate.heightAnchor constraintEqualToConstant:52],
		[minor.widthAnchor constraintEqualToAnchor:self.content.widthAnchor],
		[minor.heightAnchor constraintEqualToConstant:44],
	]];
}

- (UIButton *)primaryButton {
	UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
	cfg.attributedTitle = [[NSAttributedString alloc] initWithString:RYGLocalized(@"Donate") attributes:@{
		NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold],
		NSForegroundColorAttributeName: UIColor.whiteColor,
	}];
	cfg.image = [UIImage systemImageNamed:@"cup.and.saucer.fill"
						withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold]];
	cfg.imagePadding = 9;
	cfg.imagePlacement = NSDirectionalRectEdgeLeading;
	cfg.baseForegroundColor = UIColor.whiteColor;
	cfg.baseBackgroundColor = [UIColor colorWithRed:1.00 green:0.42 blue:0.42 alpha:1.0];
	cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;

	UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
	b.translatesAutoresizingMaskIntoConstraints = NO;
	[b addTarget:self action:@selector(tapDonate) forControlEvents:UIControlEventTouchUpInside];
	return b;
}

- (UIButton *)textButtonWithTitle:(NSString *)title font:(UIFont *)font color:(UIColor *)color {
	UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
	cfg.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
		NSFontAttributeName: font,
		NSForegroundColorAttributeName: color,
	}];
	UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
	b.translatesAutoresizingMaskIntoConstraints = NO;
	return b;
}

#pragma mark - Animation

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];

	if (self.didAnimateIn) return;
	self.didAnimateIn = YES;

	// A layout pass landing mid-spring resets the card frame and jumps the transform.
	self.card.transform = CGAffineTransformIdentity;
	[self.view layoutIfNeeded];
	self.card.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 14), 0.88, 0.88);

	[UIView animateWithDuration:0.32 animations:^{
		self.blur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
		self.dim.alpha = 1.0;
	}];

	[UIView animateWithDuration:0.46 delay:0.04 usingSpringWithDamping:0.72 initialSpringVelocity:0.6 options:0 animations:^{
		self.card.alpha = 1.0;
		self.card.transform = CGAffineTransformIdentity;
	} completion:^(__unused BOOL done) { [self startPulse]; }];

	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft] impactOccurred];
}

- (void)startPulse {
	CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
	a.fromValue = @1.0;
	a.toValue = @1.06;
	a.duration = 1.1;
	a.autoreverses = YES;
	a.repeatCount = HUGE_VALF;
	a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	[self.badge.layer addAnimation:a forKey:@"pulse"];
}

- (void)burstHearts {
	CGPoint origin = [self.card convertPoint:self.badge.center toView:self.view];

	for (NSInteger i = 0; i < 9; i++) {
		UILabel *h = [UILabel new];
		h.text = @"❤️";
		h.font = [UIFont systemFontOfSize:14 + arc4random_uniform(12)];
		[h sizeToFit];
		h.center = origin;
		h.alpha = 0.0;
		[self.view addSubview:h];

		CGFloat dx = (CGFloat)arc4random_uniform(220) - 110.0;
		CGFloat dy = -(CGFloat)(120 + arc4random_uniform(160));
		NSTimeInterval delay = (double)arc4random_uniform(180) / 1000.0;

		[UIView animateWithDuration:0.16 delay:delay options:0 animations:^{ h.alpha = 1.0; } completion:nil];
		[UIView animateWithDuration:1.0 delay:delay options:UIViewAnimationOptionCurveEaseOut animations:^{
			h.transform = CGAffineTransformRotate(CGAffineTransformMakeTranslation(dx, dy), (CGFloat)(arc4random_uniform(80) / 100.0) - 0.4);
			h.alpha = 0.0;
		} completion:^(__unused BOOL done) { [h removeFromSuperview]; }];
	}
}

- (void)reactWithFace:(NSString *)face caption:(NSString *)caption {
	self.view.userInteractionEnabled = NO;
	[self.badge.layer removeAnimationForKey:@"pulse"];

	UILabel *emoji = [UILabel new];
	emoji.text = face;
	emoji.font = [UIFont systemFontOfSize:62];
	emoji.textAlignment = NSTextAlignmentCenter;

	UILabel *cap = [UILabel new];
	cap.text = caption;
	cap.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	cap.textColor = UIColor.secondaryLabelColor;
	cap.textAlignment = NSTextAlignmentCenter;
	cap.numberOfLines = 0;

	UIStackView *reaction = [[UIStackView alloc] initWithArrangedSubviews:@[emoji, cap]];
	reaction.axis = UILayoutConstraintAxisVertical;
	reaction.alignment = UIStackViewAlignmentCenter;
	reaction.spacing = 8;
	reaction.alpha = 0.0;
	reaction.transform = CGAffineTransformMakeScale(0.5, 0.5);
	reaction.translatesAutoresizingMaskIntoConstraints = NO;
	[self.card addSubview:reaction];

	[NSLayoutConstraint activateConstraints:@[
		[reaction.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
		[reaction.centerYAnchor constraintEqualToAnchor:self.card.centerYAnchor],
		[reaction.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.card.leadingAnchor constant:22],
	]];

	[UIView animateWithDuration:0.18 animations:^{ self.content.alpha = 0.0; }];
	[UIView animateWithDuration:0.52 delay:0.12 usingSpringWithDamping:0.58 initialSpringVelocity:0.9 options:0 animations:^{
		reaction.alpha = 1.0;
		reaction.transform = CGAffineTransformIdentity;
	} completion:nil];
}

- (void)dismissAfter:(NSTimeInterval)delay then:(void (^)(void))then {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[UIView animateWithDuration:0.24 animations:^{
			self.card.alpha = 0.0;
			self.card.transform = CGAffineTransformMakeScale(0.9, 0.9);
			self.dim.alpha = 0.0;
			self.blur.effect = nil;
		} completion:^(__unused BOOL done) {
			[self dismissViewControllerAnimated:NO completion:then];
		}];
	});
}

#pragma mark - Actions

- (void)tapDonate {
	[RYGDonatePrompt silence];
	[[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
	[self burstHearts];
	[self reactWithFace:@"🥰" caption:RYGLocalized(@"This means a lot")];
	[self dismissAfter:1.15 then:^{
		NSURL *url = [NSURL URLWithString:RYGDonateURL];
		if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
	}];
}

- (void)tapAlready {
	[RYGDonatePrompt silence];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	[self burstHearts];
	[self reactWithFace:@"🫶" caption:RYGLocalized(@"Appreciate the support")];
	[self dismissAfter:1.25 then:nil];
}

- (void)tapLater {
	[RYGDonatePrompt snooze];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid] impactOccurred];
	[self reactWithFace:@"🥲" caption:RYGLocalized(@"No worries, enjoy the tweak")];
	[self dismissAfter:1.15 then:nil];
}

@end

#pragma mark - Public API

@implementation RYGDonatePrompt

// Launch count survives, so anyone already past the gate is asked again on next open.
+ (void)applyCampaign {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if ([ud integerForKey:kCampaignKey] == kCampaign) return;

	[ud setInteger:kCampaign forKey:kCampaignKey];
	[ud setBool:NO forKey:kSilencedKey];
	[ud setInteger:0 forKey:kSnoozeUntilKey];
}

+ (void)noteAppLaunch {
	[self applyCampaign];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	[ud setInteger:[ud integerForKey:kLaunchCountKey] + 1 forKey:kLaunchCountKey];
}

+ (void)silence {
	[NSUserDefaults.standardUserDefaults setBool:YES forKey:kSilencedKey];
}

+ (void)snooze {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	[ud setInteger:[ud integerForKey:kLaunchCountKey] + kSnoozeLaunches forKey:kSnoozeUntilKey];
}

+ (BOOL)isDue {
	[self applyCampaign];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if ([ud boolForKey:kSilencedKey]) return NO;

	NSInteger launches = [ud integerForKey:kLaunchCountKey];
	return launches >= kMinLaunches && launches >= [ud integerForKey:kSnoozeUntilKey];
}

+ (void)presentIfDueFrom:(UIViewController *)host {
	if (sShownThisSession || !host.view.window || host.presentedViewController) return;
	if (![self isDue]) return;

	sShownThisSession = YES;

	_RYGDonateCardVC *vc = [_RYGDonateCardVC new];
	vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
	[host presentViewController:vc animated:NO completion:nil];
}

@end
