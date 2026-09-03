#import "RYGPlaybackControls.h"
#import "../../Utils.h"

@implementation RYGPlaybackPills

+ (UIButton *)pillWithTitle:(NSString *)title target:(id)target action:(SEL)action {
	UIButton *p = [UIButton buttonWithType:UIButtonTypeCustom];
	p.translatesAutoresizingMaskIntoConstraints = NO;
	[p setTitle:title forState:UIControlStateNormal];
	p.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	p.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
	p.layer.cornerRadius = 16;
	p.layer.cornerCurve = kCACornerCurveContinuous;
	p.layer.borderWidth = 1;
	[p addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	[p.heightAnchor constraintEqualToConstant:32].active = YES;
	return p;
}

+ (UIButton *)actionPillWithSymbol:(NSString *)symbol target:(id)target action:(SEL)action {
	UIButton *p = [UIButton buttonWithType:UIButtonTypeCustom];
	p.translatesAutoresizingMaskIntoConstraints = NO;
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
		configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
	[p setImage:[[UIImage systemImageNamed:symbol withConfiguration:cfg]
		imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
	p.tintColor = [UIColor whiteColor];
	p.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	[p setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	p.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
	p.layer.cornerRadius = 18;
	p.layer.cornerCurve = kCACornerCurveContinuous;
	p.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
	[p addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	[p.heightAnchor constraintEqualToConstant:40].active = YES;
	return p;
}

+ (void)stylePill:(UIButton *)pill selected:(BOOL)selected {
	pill.backgroundColor = selected ? [UIColor whiteColor] : [UIColor clearColor];
	pill.layer.borderColor = (selected ? [UIColor clearColor]
		: [UIColor colorWithWhite:1 alpha:0.30]).CGColor;
	[pill setTitleColor:selected ? [UIColor blackColor] : [UIColor whiteColor]
			   forState:UIControlStateNormal];
}

+ (void)promptNumberWithTitle:(NSString *)title
                      message:(NSString *)message
                        value:(double)value
                          min:(double)min
                          max:(double)max
                        apply:(void (^)(double))apply {
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

	UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
																message:message
														 preferredStyle:UIAlertControllerStyleAlert];
	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.keyboardType = UIKeyboardTypeDecimalPad;
		tf.text = [NSString stringWithFormat:@"%g", value];
		tf.clearButtonMode = UITextFieldViewModeAlways;
	}];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Apply")
										   style:UIAlertActionStyleDefault
										 handler:^(UIAlertAction *a) {
		double v = ac.textFields.firstObject.text.doubleValue;
		if (v < min) v = min;
		if (v > max) v = max;
		if (apply) apply(v);
	}]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
										   style:UIAlertActionStyleCancel handler:nil]];
	[presenter presentViewController:ac animated:YES completion:nil];
}

@end

#pragma mark - Speed

@interface RYGPlaybackSpeedView () <UIScrollViewDelegate>
@end

@implementation RYGPlaybackSpeedView {
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
	void (^_onChange)(float);
}

- (instancetype)initWithRate:(float)rate onChange:(void (^)(float))onChange {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		_current = rate;
		_onChange = [onChange copy];

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

		NSMutableArray<UIButton *> *pills = [NSMutableArray array];
		for (NSNumber *r in @[ @0.5f, @0.75f, @1.0f, @1.25f, @1.5f, @2.0f ]) {
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
		self->_leftArrow.alpha = canLeft ? 1.0 : 0.0;
		self->_rightArrow.alpha = canRight ? 1.0 : 0.0;
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
	[_customPill setTitleColor:customSel ? [UIColor blackColor] : [UIColor whiteColor]
					  forState:UIControlStateNormal];
	[_customPill setTitle:customSel ? [NSString stringWithFormat:@"%g×", _current]
									: RYGLocalized(@"Custom")
				 forState:UIControlStateNormal];
}

- (void)_apply:(float)v {
	_current = v;
	if (_onChange) _onChange(v);
	[self _refreshPills];
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (void)_onPillTap:(UIButton *)sender {
	[self _apply:(float)sender.tag / 100.0f];
}

- (void)_onCustomTap {
	__weak RYGPlaybackSpeedView *ws = self;
	[RYGPlaybackPills promptNumberWithTitle:RYGLocalized(@"Custom speed")
									message:RYGLocalized(@"Enter a value between 0.5 and 2.0")
									  value:_current
										min:0.5
										max:2.0
									  apply:^(double v) { [ws _apply:(float)v]; }];
}

@end

#pragma mark - Seek + transport

@implementation RYGPlaybackSeekView {
	NSArray<NSNumber *> *_presets;
	NSMutableArray<UIButton *> *_presetPills;
	UIButton *_customPill;
	UIButton *_backBtn;
	UIButton *_fwdBtn;
	UIButton *_pauseBtn;
	double _step;
	void (^_stepDidChange)(double);
	void (^_onSeek)(double);
	void (^_pauseToggle)(void);
	BOOL (^_isPlaying)(void);
}

- (instancetype)initWithStep:(double)step
               stepDidChange:(void (^)(double))stepDidChange
                      onSeek:(void (^)(double))onSeek
                 pauseToggle:(void (^)(void))pauseToggle
                   isPlaying:(BOOL (^)(void))isPlaying {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		_presets = @[ @1, @5, @10, @15, @30 ];
		_step = step;
		_stepDidChange = [stepDidChange copy];
		_onSeek = [onSeek copy];
		_pauseToggle = [pauseToggle copy];
		_isPlaying = [isPlaying copy];

		UIStackView *col = [UIStackView new];
		col.translatesAutoresizingMaskIntoConstraints = NO;
		col.axis = UILayoutConstraintAxisVertical;
		col.spacing = 10;
		col.alignment = UIStackViewAlignmentFill;
		[self addSubview:col];

		if (_onSeek) {
			UIScrollView *scroll = [UIScrollView new];
			scroll.translatesAutoresizingMaskIntoConstraints = NO;
			scroll.showsHorizontalScrollIndicator = NO;
			scroll.contentInset = UIEdgeInsetsMake(0, 18, 0, 18);

			UIStackView *pillRow = [UIStackView new];
			pillRow.translatesAutoresizingMaskIntoConstraints = NO;
			pillRow.axis = UILayoutConstraintAxisHorizontal;
			pillRow.spacing = 6;
			pillRow.alignment = UIStackViewAlignmentCenter;
			[scroll addSubview:pillRow];

			_presetPills = [NSMutableArray array];
			for (NSNumber *n in _presets) {
				UIButton *p = [RYGPlaybackPills pillWithTitle:[NSString stringWithFormat:@"%gs", n.doubleValue]
													   target:self action:@selector(_onPresetTap:)];
				p.tag = (NSInteger)(n.doubleValue * 10);
				[pillRow addArrangedSubview:p];
				[_presetPills addObject:p];
			}
			_customPill = [RYGPlaybackPills pillWithTitle:RYGLocalized(@"Custom")
												   target:self action:@selector(_onCustomTap)];
			[pillRow addArrangedSubview:_customPill];

			[col addArrangedSubview:scroll];
			[NSLayoutConstraint activateConstraints:@[
				[scroll.heightAnchor constraintEqualToConstant:32],
				[pillRow.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
				[pillRow.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
				[pillRow.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
				[pillRow.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
				[pillRow.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
			]];
		}

		UIStackView *actionRow = [UIStackView new];
		actionRow.translatesAutoresizingMaskIntoConstraints = NO;
		actionRow.axis = UILayoutConstraintAxisHorizontal;
		actionRow.spacing = 10;
		actionRow.distribution = UIStackViewDistributionFillEqually;

		if (_onSeek) {
			_backBtn = [RYGPlaybackPills actionPillWithSymbol:@"gobackward" target:self action:@selector(_onBack)];
			[actionRow addArrangedSubview:_backBtn];
		}
		if (_pauseToggle) {
			_pauseBtn = [RYGPlaybackPills actionPillWithSymbol:@"pause.fill" target:self action:@selector(_onPause)];
			[actionRow addArrangedSubview:_pauseBtn];
		}
		if (_onSeek) {
			_fwdBtn = [RYGPlaybackPills actionPillWithSymbol:@"goforward" target:self action:@selector(_onForward)];
			[actionRow addArrangedSubview:_fwdBtn];
		}
		[col addArrangedSubview:actionRow];

		[NSLayoutConstraint activateConstraints:@[
			[col.topAnchor constraintEqualToAnchor:self.topAnchor],
			[col.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[col.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[col.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

			[actionRow.leadingAnchor constraintEqualToAnchor:col.leadingAnchor constant:18],
			[actionRow.trailingAnchor constraintEqualToAnchor:col.trailingAnchor constant:-18],
		]];

		[self _refresh];
	}
	return self;
}

- (void)_refresh {
	if (_onSeek) {
		BOOL isPreset = NO;
		for (NSUInteger i = 0; i < _presets.count; i++) {
			BOOL sel = (_presets[i].doubleValue == _step);
			if (sel) isPreset = YES;
			[RYGPlaybackPills stylePill:_presetPills[i] selected:sel];
		}
		[RYGPlaybackPills stylePill:_customPill selected:!isPreset];
		[_customPill setTitle:isPreset ? RYGLocalized(@"Custom")
									   : [NSString stringWithFormat:@"%gs", _step]
					 forState:UIControlStateNormal];

		NSString *label = [NSString stringWithFormat:@"  %gs", _step];
		[_backBtn setTitle:label forState:UIControlStateNormal];
		[_fwdBtn setTitle:label forState:UIControlStateNormal];
	}
	[self _refreshPauseIcon];
}

- (void)_refreshPauseIcon {
	if (!_pauseBtn) return;
	BOOL playing = _isPlaying ? _isPlaying() : YES;
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
		configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
	UIImage *img = [UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill"
						   withConfiguration:cfg];
	[_pauseBtn setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
			   forState:UIControlStateNormal];
}

- (void)_onPresetTap:(UIButton *)sender {
	_step = (double)sender.tag / 10.0;
	if (_stepDidChange) _stepDidChange(_step);
	[self _refresh];
	[[UISelectionFeedbackGenerator new] selectionChanged];
}

- (void)_onCustomTap {
	__weak RYGPlaybackSeekView *ws = self;
	[RYGPlaybackPills promptNumberWithTitle:RYGLocalized(@"Custom seek step")
									message:RYGLocalized(@"Enter the number of seconds to skip")
									  value:_step
										min:1.0
										max:600.0
									  apply:^(double v) {
		RYGPlaybackSeekView *s = ws;
		if (!s) return;
		s->_step = v;
		if (s->_stepDidChange) s->_stepDidChange(v);
		[s _refresh];
	}];
}

- (void)_onBack { if (_onSeek) _onSeek(-_step); }
- (void)_onForward { if (_onSeek) _onSeek(_step); }

- (void)_onPause {
	if (_pauseToggle) _pauseToggle();
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	__weak RYGPlaybackSeekView *ws = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{ [ws _refreshPauseIcon]; });
}

@end
