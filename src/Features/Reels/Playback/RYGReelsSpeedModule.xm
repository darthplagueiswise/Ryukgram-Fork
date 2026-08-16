// Reels playback speed. Hooks install only when enabled at launch (restart to enable).

#import "RYGReelsPlaybackMenu.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static inline BOOL rygSpeedEnabled(void) {
	return [RYGUtils getBoolPref:@"reels_playback_speed"];
}

static float rygSpeedRate(void) {
	double v = [RYGUtils getDoublePref:@"reels_playback_speed_rate"];
	if (v < 0.5 || v > 2.0) v = 1.0;
	return (float)v;
}

static void rygStoreSpeedRate(float rate) {
	if (rate < 0.5f) rate = 0.5f;
	if (rate > 2.0f) rate = 2.0f;
	[[NSUserDefaults standardUserDefaults] setDouble:rate forKey:@"reels_playback_speed_rate"];
}

static id rygPlayerOf(id view) {
	if (![view respondsToSelector:@selector(videoPlayer)]) return nil;
	@try { return ((id(*)(id, SEL))objc_msgSend)(view, @selector(videoPlayer)); }
	@catch (__unused id e) { return nil; }
}

static void rygApplyRateToPlayer(id player, float rate) {
	if (!player || ![player respondsToSelector:@selector(setPlaybackSpeed:)]) return;
	@try { ((void(*)(id, SEL, float))objc_msgSend)(player, @selector(setPlaybackSpeed:), rate); }
	@catch (__unused id e) {}
}

static BOOL rygViewIsInReels(UIView *view) {
	for (UIView *v = view; v; v = v.superview)
		if ([NSStringFromClass([v class]) containsString:@"Sundial"]) return YES;
	for (UIResponder *r = view; r; r = r.nextResponder)
		if ([NSStringFromClass([r class]) containsString:@"Sundial"]) return YES;
	return NO;
}

static NSHashTable *sReelsPlayers;
static BOOL rygIsReelsPlayer(id player) {
	return player && sReelsPlayers && [sReelsPlayers containsObject:player];
}
static void rygRegisterReelsPlayer(id player) {
	if (!player) return;
	if (!sReelsPlayers) sReelsPlayers = [NSHashTable weakObjectsHashTable];
	[sReelsPlayers addObject:player];
}
static void rygApplyRateToReelsPlayers(float rate) {
	for (id p in sReelsPlayers.allObjects) rygApplyRateToPlayer(p, rate);
}

static void rygApplyRateEverywhere(float rate) {
	rygApplyRateToReelsPlayers(rate);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{ rygApplyRateToReelsPlayers(rate); });
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{ rygApplyRateToReelsPlayers(rate); });
}

#pragma mark - Speed section view

@interface RYGReelsSpeedView : UIView <UIScrollViewDelegate>
@end

@implementation RYGReelsSpeedView {
	UIView *_container;
	UIScrollView *_scroll;
	UIStackView *_row;
	NSArray<UIButton *> *_pills;
	UIButton *_customPill;
	CAGradientLayer *_leftFade;
	CAGradientLayer *_rightFade;
	UIImageView *_leftArrow;
	UIImageView *_rightArrow;
	float _current;
}

- (instancetype)init {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		_current = rygSpeedRate();

		_container = [UIView new];
		_container.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_container];

		_scroll = [UIScrollView new];
		_scroll.translatesAutoresizingMaskIntoConstraints = NO;
		_scroll.showsHorizontalScrollIndicator = NO;
		_scroll.contentInset = UIEdgeInsetsMake(0, 14, 0, 14);
		_scroll.delegate = self;
		[_container addSubview:_scroll];

		_row = [UIStackView new];
		_row.translatesAutoresizingMaskIntoConstraints = NO;
		_row.axis = UILayoutConstraintAxisHorizontal;
		_row.spacing = 6;
		_row.alignment = UIStackViewAlignmentCenter;
		[_scroll addSubview:_row];

		NSArray<NSNumber *> *rates = @[ @0.5f, @0.75f, @1.0f, @1.25f, @1.5f, @2.0f ];
		NSMutableArray<UIButton *> *pills = [NSMutableArray array];
		for (NSNumber *r in rates) {
			UIButton *pill = [self _pillWithRate:r.floatValue];
			[_row addArrangedSubview:pill];
			[pills addObject:pill];
		}
		_pills = pills;

		_customPill = [UIButton buttonWithType:UIButtonTypeCustom];
		_customPill.translatesAutoresizingMaskIntoConstraints = NO;
		[_customPill setTitle:RYGLocalized(@"Custom") forState:UIControlStateNormal];
		_customPill.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
		_customPill.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
		_customPill.layer.cornerRadius = 16;
		_customPill.layer.cornerCurve = kCACornerCurveContinuous;
		_customPill.layer.borderWidth = 1;
		_customPill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
		[_customPill setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[_customPill addTarget:self action:@selector(_onCustomTap) forControlEvents:UIControlEventTouchUpInside];
		[_customPill.heightAnchor constraintEqualToConstant:32].active = YES;
		[_row addArrangedSubview:_customPill];

		[self _refreshPills];

		_leftFade = [CAGradientLayer layer];
		_leftFade.colors = @[ (id)[UIColor colorWithWhite:0.08 alpha:1.0].CGColor,
							  (id)[UIColor colorWithWhite:0.08 alpha:0.0].CGColor ];
		_leftFade.startPoint = CGPointMake(0, 0.5);
		_leftFade.endPoint = CGPointMake(1, 0.5);
		_leftFade.opacity = 0;
		[_container.layer addSublayer:_leftFade];

		_rightFade = [CAGradientLayer layer];
		_rightFade.colors = @[ (id)[UIColor colorWithWhite:0.08 alpha:0.0].CGColor,
							   (id)[UIColor colorWithWhite:0.08 alpha:1.0].CGColor ];
		_rightFade.startPoint = CGPointMake(0, 0.5);
		_rightFade.endPoint = CGPointMake(1, 0.5);
		_rightFade.opacity = 1;
		[_container.layer addSublayer:_rightFade];

		UIImageSymbolConfiguration *arrCfg = [UIImageSymbolConfiguration
			configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
		_leftArrow = [[UIImageView alloc] initWithImage:
			[UIImage systemImageNamed:@"chevron.left" withConfiguration:arrCfg]];
		_leftArrow.translatesAutoresizingMaskIntoConstraints = NO;
		_leftArrow.tintColor = [UIColor colorWithWhite:1 alpha:0.8];
		_leftArrow.alpha = 0;
		_leftArrow.contentMode = UIViewContentModeCenter;
		[_container addSubview:_leftArrow];

		_rightArrow = [[UIImageView alloc] initWithImage:
			[UIImage systemImageNamed:@"chevron.right" withConfiguration:arrCfg]];
		_rightArrow.translatesAutoresizingMaskIntoConstraints = NO;
		_rightArrow.tintColor = [UIColor colorWithWhite:1 alpha:0.8];
		_rightArrow.alpha = 1;
		_rightArrow.contentMode = UIViewContentModeCenter;
		[_container addSubview:_rightArrow];

		[NSLayoutConstraint activateConstraints:@[
			[_container.topAnchor constraintEqualToAnchor:self.topAnchor],
			[_container.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[_container.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[_container.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[_container.heightAnchor constraintEqualToConstant:40],

			[_scroll.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor],
			[_scroll.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor],
			[_scroll.topAnchor constraintEqualToAnchor:_container.topAnchor],
			[_scroll.bottomAnchor constraintEqualToAnchor:_container.bottomAnchor],

			[_row.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
			[_row.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
			[_row.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
			[_row.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
			[_row.heightAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.heightAnchor],

			[_leftArrow.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:4],
			[_leftArrow.centerYAnchor constraintEqualToAnchor:_scroll.centerYAnchor],
			[_leftArrow.widthAnchor constraintEqualToConstant:18],
			[_leftArrow.heightAnchor constraintEqualToConstant:32],

			[_rightArrow.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-4],
			[_rightArrow.centerYAnchor constraintEqualToAnchor:_scroll.centerYAnchor],
			[_rightArrow.widthAnchor constraintEqualToConstant:18],
			[_rightArrow.heightAnchor constraintEqualToConstant:32],
		]];
	}
	return self;
}

- (UIButton *)_pillWithRate:(float)v {
	UIButton *p = [UIButton buttonWithType:UIButtonTypeCustom];
	p.translatesAutoresizingMaskIntoConstraints = NO;
	NSString *t = (v == (int)v) ? [NSString stringWithFormat:@"%d×", (int)v]
								: [NSString stringWithFormat:@"%g×", v];
	[p setTitle:t forState:UIControlStateNormal];
	p.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	p.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
	p.layer.cornerRadius = 16;
	p.layer.cornerCurve = kCACornerCurveContinuous;
	p.tag = (NSInteger)(v * 100);
	[p addTarget:self action:@selector(_onPillTap:) forControlEvents:UIControlEventTouchUpInside];
	[p.heightAnchor constraintEqualToConstant:32].active = YES;
	return p;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat fadeW = 22;
	CGRect b = _container.bounds;
	_leftFade.frame = CGRectMake(0, 0, fadeW, b.size.height);
	_rightFade.frame = CGRectMake(b.size.width - fadeW, 0, fadeW, b.size.height);
	[self _updateFades];
}

- (void)_updateFades {
	CGFloat ox = _scroll.contentOffset.x + _scroll.contentInset.left;
	CGFloat maxX = _scroll.contentSize.width + _scroll.contentInset.left
				 + _scroll.contentInset.right - _scroll.bounds.size.width;
	BOOL canLeft = ox > 4;
	BOOL canRight = ox < (maxX - 4);
	_leftFade.opacity = canLeft ? 1.0 : 0.0;
	_rightFade.opacity = canRight ? 1.0 : 0.0;
	[UIView animateWithDuration:0.18 animations:^{
		_leftArrow.alpha = canLeft ? 1.0 : 0.0;
		_rightArrow.alpha = canRight ? 1.0 : 0.0;
	}];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self _updateFades]; }

- (void)_refreshPills {
	BOOL anyPreset = NO;
	for (UIButton *p in _pills) {
		float v = (float)p.tag / 100.0f;
		BOOL sel = fabsf(v - _current) < 0.01f;
		if (sel) anyPreset = YES;
		p.backgroundColor = sel ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.10];
		[p setTitleColor:sel ? [UIColor blackColor] : [UIColor whiteColor] forState:UIControlStateNormal];
	}
	BOOL customSel = !anyPreset;
	_customPill.backgroundColor = customSel ? [UIColor whiteColor] : [UIColor clearColor];
	_customPill.layer.borderColor = customSel ? [UIColor whiteColor].CGColor
											  : [UIColor colorWithWhite:1 alpha:0.30].CGColor;
	[_customPill setTitleColor:customSel ? [UIColor blackColor] : [UIColor whiteColor] forState:UIControlStateNormal];
	if (customSel) {
		[_customPill setTitle:[NSString stringWithFormat:@"%g×", _current] forState:UIControlStateNormal];
	} else {
		[_customPill setTitle:RYGLocalized(@"Custom") forState:UIControlStateNormal];
	}
}

- (void)_apply:(float)v {
	_current = v;
	rygStoreSpeedRate(v);
	rygApplyRateEverywhere(v);
	[self _refreshPills];
	UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[h impactOccurred];
}

- (void)_onPillTap:(UIButton *)sender {
	[self _apply:(float)sender.tag / 100.0f];
}

- (void)_onCustomTap {
	UIViewController *presenter = nil;
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if (![s isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)s).windows) {
			if (w.isKeyWindow) { presenter = w.rootViewController; break; }
		}
		if (presenter) break;
	}
	while (presenter.presentedViewController) presenter = presenter.presentedViewController;
	if (!presenter) return;

	UIAlertController *ac = [UIAlertController
		alertControllerWithTitle:RYGLocalized(@"Custom speed")
						 message:RYGLocalized(@"Enter a value between 0.5 and 2.0")
				  preferredStyle:UIAlertControllerStyleAlert];
	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.keyboardType = UIKeyboardTypeDecimalPad;
		tf.placeholder = RYGLocalized(@"e.g. 1.75");
		tf.text = [NSString stringWithFormat:@"%.2f", _current];
		tf.clearButtonMode = UITextFieldViewModeAlways;
	}];
	__weak RYGReelsSpeedView *ws = self;
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Apply")
										   style:UIAlertActionStyleDefault
										 handler:^(UIAlertAction *a) {
		float v = ac.textFields.firstObject.text.floatValue;
		if (v < 0.5f) v = 0.5f;
		if (v > 2.0f) v = 2.0f;
		[ws _apply:v];
	}]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[presenter presentViewController:ac animated:YES completion:nil];
}

@end

#pragma mark - Module registration + speed hook

static void rygApplyRateToSelf(id view, id playerArg) {
	if (!rygSpeedEnabled()) return;
	id player = playerArg ?: rygPlayerOf(view);
	if (!player) return;
	if (![view isKindOfClass:[UIView class]] || !rygViewIsInReels((UIView *)view)) return;
	rygRegisterReelsPlayer(player);
	float rate = rygSpeedRate();
	if (fabsf(rate - 1.0f) < 0.001f) return;
	rygApplyRateToPlayer(player, rate);
}

%group RYGSpeedGroup

%hook IGStatefulVideoPlayer

- (void)setPlaybackSpeed:(float)speed {
	if (rygSpeedEnabled() && rygIsReelsPlayer(self)) {
		float ours = rygSpeedRate();
		if (ours > 0 && fabsf(ours - 1.0f) > 0.001f) {
			%orig(ours);
			return;
		}
	}
	%orig(speed);
}

%end

%hook _TtC11IGVideoView11IGVideoView

- (void)videoPlayerDidInitialPlay:(id)player { %orig; rygApplyRateToSelf(self, player); }
- (void)videoPlayerDidReadyToDisplay:(id)player { %orig; rygApplyRateToSelf(self, player); }
- (void)videoPlayerDidFinishPrepare:(id)player { %orig; rygApplyRateToSelf(self, player); }
- (void)videoPlayerDidUnpause:(id)player { %orig; rygApplyRateToSelf(self, player); }

%end

%end

%ctor {
	[RYGReelsPlaybackMenu registerModuleWithID:@"speed"
		isOn:^BOOL { return rygSpeedEnabled(); }
		buildSection:^UIView *{
			return [[RYGReelsPlaybackSection alloc] initWithTitle:RYGLocalized(@"Speed")
														 content:[RYGReelsSpeedView new]];
		}];
	if (rygSpeedEnabled()) %init(RYGSpeedGroup);
}
