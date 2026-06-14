#import "SCILockPasscodeView.h"
#import "../SCILockManager.h"
#import "../../Utils.h"

@interface SCILockPasscodeView ()

@property (nonatomic, strong) UIStackView *rootStack;
@property (nonatomic, strong) UIStackView *headerStack;
@property (nonatomic, strong) UIStackView *dotsStack;
@property (nonatomic, strong) UIStackView *numpadStack;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@property (nonatomic, strong) NSMutableArray<UIView *> *dotViews;
@property (nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *buttonSizeConstraints;

@property (nonatomic, strong) NSMutableString *currentCode;

@property (nonatomic, strong) UIButton *biometricButton;
@property (nonatomic, strong) UIButton *backspaceButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIView *bottomLeftHolder;

@property (nonatomic, strong) NSLayoutConstraint *rootLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *rootTrailingConstraint;

@property (nonatomic) BOOL acceptingInput;
@property (nonatomic) CGFloat currentButtonSize;
@property (nonatomic) CGFloat lastLayoutWidth;

@end

static const CGFloat kSCIMinButtonSize = 60.0;
static const CGFloat kSCIMaxButtonSize = 74.0;

static const CGFloat kSCIDotSize = 13.0;
static const CGFloat kSCIDotGap = 18.0;

@implementation SCILockPasscodeView

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		_codeLength = 4;
		_acceptingInput = YES;
		_currentCode = NSMutableString.new;
		_dotViews = NSMutableArray.new;
		_buttons = NSMutableArray.new;
		_buttonSizeConstraints = NSMutableArray.new;

		[self buildView];
	}
	return self;
}

#pragma mark - Build

- (void)buildView {
	self.backgroundColor = UIColor.clearColor;

	self.rootStack = UIStackView.new;
	self.rootStack.translatesAutoresizingMaskIntoConstraints = NO;
	self.rootStack.axis = UILayoutConstraintAxisVertical;
	self.rootStack.alignment = UIStackViewAlignmentCenter;
	self.rootStack.spacing = 0.0;

	[self addSubview:self.rootStack];

	self.headerStack = UIStackView.new;
	self.headerStack.axis = UILayoutConstraintAxisVertical;
	self.headerStack.alignment = UIStackViewAlignmentCenter;
	self.headerStack.spacing = 8.0;

	self.titleLabel = UILabel.new;
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.numberOfLines = 0;
	self.titleLabel.textColor = UIColor.labelColor;
	self.titleLabel.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
	self.titleLabel.adjustsFontForContentSizeCategory = YES;

	self.subtitleLabel = UILabel.new;
	self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
	self.subtitleLabel.numberOfLines = 0;
	self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
	self.subtitleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
	self.subtitleLabel.adjustsFontForContentSizeCategory = YES;

	[self.headerStack addArrangedSubview:self.titleLabel];
	[self.headerStack addArrangedSubview:self.subtitleLabel];

	self.dotsStack = UIStackView.new;
	self.dotsStack.axis = UILayoutConstraintAxisHorizontal;
	self.dotsStack.alignment = UIStackViewAlignmentCenter;
	self.dotsStack.spacing = kSCIDotGap;

	self.numpadStack = [self buildNumpadStack];

	self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.cancelButton.hidden = YES;
	self.cancelButton.tintColor = UIColor.secondaryLabelColor;
	self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
	self.cancelButton.contentEdgeInsets = UIEdgeInsetsMake(10.0, 18.0, 10.0, 18.0);
	[self.cancelButton addTarget:self action:@selector(tapCancel) forControlEvents:UIControlEventTouchUpInside];

	UIView *topSpacer = UIView.new;
	UIView *middleSpacer = UIView.new;
	UIView *bottomSpacer = UIView.new;

	[topSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
	[middleSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
	[bottomSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];

	[self.rootStack addArrangedSubview:topSpacer];
	[self.rootStack addArrangedSubview:self.headerStack];
	[self.rootStack addArrangedSubview:middleSpacer];
	[self.rootStack addArrangedSubview:self.dotsStack];
	[self.rootStack setCustomSpacing:34.0 afterView:self.dotsStack];
	[self.rootStack addArrangedSubview:self.numpadStack];
	[self.rootStack setCustomSpacing:12.0 afterView:self.numpadStack];
	[self.rootStack addArrangedSubview:self.cancelButton];
	[self.rootStack addArrangedSubview:bottomSpacer];

	self.rootLeadingConstraint = [self.rootStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24.0];
	self.rootTrailingConstraint = [self.rootStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24.0];

	[NSLayoutConstraint activateConstraints:@[
		self.rootLeadingConstraint,
		self.rootTrailingConstraint,
		[self.rootStack.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor],
		[self.rootStack.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor],

		[self.headerStack.widthAnchor constraintLessThanOrEqualToAnchor:self.rootStack.widthAnchor],
		[self.titleLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.rootStack.widthAnchor],
		[self.subtitleLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.rootStack.widthAnchor constant:-12.0],

		[topSpacer.heightAnchor constraintGreaterThanOrEqualToConstant:8.0],
		[middleSpacer.heightAnchor constraintGreaterThanOrEqualToConstant:24.0],
		[bottomSpacer.heightAnchor constraintGreaterThanOrEqualToConstant:8.0],
		[topSpacer.heightAnchor constraintEqualToAnchor:bottomSpacer.heightAnchor],
	]];

	[self rebuildDots];
	[self updateResponsiveMetrics];
}

- (UIStackView *)buildNumpadStack {
	UIStackView *stack = UIStackView.new;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 14.0;

	NSArray<NSArray<NSNumber *> *> *rows = @[
		@[@1, @2, @3],
		@[@4, @5, @6],
		@[@7, @8, @9]
	];

	for (NSArray<NSNumber *> *digits in rows) {
		UIStackView *row = [self numpadRow];

		for (NSNumber *digit in digits) {
			[row addArrangedSubview:[self digitButton:digit.integerValue]];
		}

		[stack addArrangedSubview:row];
	}

	UIStackView *bottomRow = [self numpadRow];

	self.bottomLeftHolder = [self emptyButtonSlot];

	self.biometricButton = [self iconButtonWithSystemName:nil action:@selector(tapBiometric)];
	self.biometricButton.hidden = YES;

	[self.bottomLeftHolder addSubview:self.biometricButton];

	[NSLayoutConstraint activateConstraints:@[
		[self.biometricButton.centerXAnchor constraintEqualToAnchor:self.bottomLeftHolder.centerXAnchor],
		[self.biometricButton.centerYAnchor constraintEqualToAnchor:self.bottomLeftHolder.centerYAnchor],
	]];

	[bottomRow addArrangedSubview:self.bottomLeftHolder];
	[bottomRow addArrangedSubview:[self digitButton:0]];

	self.backspaceButton = [self iconButtonWithSystemName:@"delete.left" action:@selector(tapBackspace)];
	[bottomRow addArrangedSubview:self.backspaceButton];

	[stack addArrangedSubview:bottomRow];

	return stack;
}

- (UIStackView *)numpadRow {
	UIStackView *row = UIStackView.new;
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 22.0;
	return row;
}

#pragma mark - Responsive Layout

- (void)layoutSubviews {
	[super layoutSubviews];
	[self updateResponsiveMetrics];
}

- (void)updateResponsiveMetrics {
	CGFloat width = self.bounds.size.width;
	if (width <= 0.0 || fabs(width - self.lastLayoutWidth) < 0.5) return;

	self.lastLayoutWidth = width;

	BOOL compact = width < 360.0;
	CGFloat sideInset = compact ? 18.0 : 24.0;
	CGFloat minGap = compact ? 14.0 : 18.0;
	CGFloat maxGap = width >= 390.0 ? 24.0 : 21.0;
	CGFloat available = MAX(width - (sideInset * 2.0), 240.0);

	CGFloat buttonSize = floor(MIN(kSCIMaxButtonSize, MAX(kSCIMinButtonSize, (available - (minGap * 2.0)) / 3.0)));
	CGFloat gap = floor(MIN(maxGap, MAX(minGap, (available - (buttonSize * 3.0)) / 2.0)));
	CGFloat rowGap = compact ? 10.0 : 14.0;

	self.currentButtonSize = buttonSize;
	self.rootLeadingConstraint.constant = sideInset;
	self.rootTrailingConstraint.constant = -sideInset;
	self.numpadStack.spacing = rowGap;

	for (UIStackView *row in self.numpadStack.arrangedSubviews) {
		if ([row isKindOfClass:UIStackView.class]) {
			row.spacing = gap;
		}
	}

	for (NSLayoutConstraint *constraint in self.buttonSizeConstraints) {
		constraint.constant = buttonSize;
	}

	for (UIButton *button in self.buttons) {
		button.layer.cornerRadius = button.tag >= 1000 ? buttonSize / 2.0 : 0.0;
	}

	self.titleLabel.font = [UIFont systemFontOfSize:compact ? 25.0 : 28.0 weight:UIFontWeightBold];
	self.subtitleLabel.font = [UIFont systemFontOfSize:compact ? 14.0 : 15.0 weight:UIFontWeightRegular];

	UIImageSymbolConfiguration *backspaceConfig = [UIImageSymbolConfiguration configurationWithPointSize:compact ? 21.0 : 23.0 weight:UIImageSymbolWeightRegular];
	[self.backspaceButton setImage:[UIImage systemImageNamed:@"delete.left" withConfiguration:backspaceConfig] forState:UIControlStateNormal];

	if (self.biometricButtonVisible) {
		[self refreshBiometricImage];
	}
}

#pragma mark - Buttons

- (UIButton *)digitButton:(NSInteger)digit {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];

	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tag = digit + 1000;
	button.backgroundColor = UIColor.secondarySystemFillColor;
	button.clipsToBounds = YES;
	button.layer.cornerCurve = kCACornerCurveContinuous;

	button.titleLabel.font = [UIFont systemFontOfSize:31.0 weight:UIFontWeightRegular];
	button.titleLabel.adjustsFontForContentSizeCategory = YES;

	[button setTitle:[NSString stringWithFormat:@"%ld", (long)digit] forState:UIControlStateNormal];
	[button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];

	[button addTarget:self action:@selector(tapDigit:) forControlEvents:UIControlEventTouchUpInside];
	[button addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
	[button addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

	[self addSizeConstraintsForView:button];
	[self.buttons addObject:button];

	return button;
}

- (UIButton *)iconButtonWithSystemName:(NSString *)systemName action:(SEL)action {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];

	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = UIColor.labelColor;
	button.backgroundColor = UIColor.clearColor;

	if (systemName.length) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:23.0 weight:UIImageSymbolWeightRegular];
		[button setImage:[UIImage systemImageNamed:systemName withConfiguration:config] forState:UIControlStateNormal];
	}

	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[button addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
	[button addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

	[self addSizeConstraintsForView:button];
	[self.buttons addObject:button];

	return button;
}

- (UIView *)emptyButtonSlot {
	UIView *view = UIView.new;
	view.translatesAutoresizingMaskIntoConstraints = NO;
	[self addSizeConstraintsForView:view];
	return view;
}

- (void)addSizeConstraintsForView:(UIView *)view {
	NSLayoutConstraint *width = [view.widthAnchor constraintEqualToConstant:70.0];
	NSLayoutConstraint *height = [view.heightAnchor constraintEqualToConstant:70.0];

	[NSLayoutConstraint activateConstraints:@[width, height]];

	[self.buttonSizeConstraints addObject:width];
	[self.buttonSizeConstraints addObject:height];
}

- (void)buttonDown:(UIButton *)button {
	[UIView animateWithDuration:0.06 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
		button.transform = CGAffineTransformMakeScale(0.94, 0.94);

		if (button.tag >= 1000) {
			button.backgroundColor = UIColor.tertiarySystemFillColor;
		}
	} completion:nil];
}

- (void)buttonUp:(UIButton *)button {
	[UIView animateWithDuration:0.12 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
		button.transform = CGAffineTransformIdentity;

		if (button.tag >= 1000) {
			button.backgroundColor = UIColor.secondarySystemFillColor;
		}
	} completion:nil];
}

#pragma mark - Dots

- (void)rebuildDots {
	for (UIView *dot in self.dotViews) {
		[dot removeFromSuperview];
	}

	[self.dotViews removeAllObjects];

	for (NSInteger i = 0; i < self.codeLength; i++) {
		UIView *dot = UIView.new;
		dot.translatesAutoresizingMaskIntoConstraints = NO;
		dot.backgroundColor = UIColor.clearColor;
		dot.layer.cornerRadius = kSCIDotSize / 2.0;
		dot.layer.cornerCurve = kCACornerCurveContinuous;
		dot.layer.borderWidth = 1.5;
		dot.layer.borderColor = UIColor.tertiaryLabelColor.CGColor;

		[NSLayoutConstraint activateConstraints:@[
			[dot.widthAnchor constraintEqualToConstant:kSCIDotSize],
			[dot.heightAnchor constraintEqualToConstant:kSCIDotSize],
		]];

		[self.dotsStack addArrangedSubview:dot];
		[self.dotViews addObject:dot];
	}

	[self refreshDotsAnimated:NO];
}

- (void)refreshDotsAnimated:(BOOL)animated {
	UIColor *filledColor = [SCIUtils SCIColor_Primary] ?: UIColor.labelColor;

	for (NSInteger i = 0; i < self.dotViews.count; i++) {
		UIView *dot = self.dotViews[i];
		BOOL filled = i < (NSInteger)self.currentCode.length;

		void (^updates)(void) = ^{
			dot.backgroundColor = filled ? filledColor : UIColor.clearColor;
			dot.layer.borderColor = (filled ? filledColor : UIColor.tertiaryLabelColor).CGColor;
			dot.transform = filled && animated ? CGAffineTransformMakeScale(1.12, 1.12) : CGAffineTransformIdentity;
		};

		if (!animated) {
			updates();
			continue;
		}

		[UIView animateWithDuration:0.14
							  delay:0.0
							options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
						 animations:updates
						 completion:^(__unused BOOL finished) {
			if (!filled) return;

			[UIView animateWithDuration:0.10
								  delay:0.0
								options:UIViewAnimationOptionAllowUserInteraction
							 animations:^{
				dot.transform = CGAffineTransformIdentity;
			} completion:nil];
		}];
	}
}

#pragma mark - Setters

- (void)setCodeLength:(NSInteger)codeLength {
	NSInteger safeLength = codeLength == 6 ? 6 : 4;
	if (_codeLength == safeLength) return;

	_codeLength = safeLength;
	[self.currentCode setString:@""];
	self.acceptingInput = YES;
	[self rebuildDots];
}

- (void)setTitleText:(NSString *)titleText {
	_titleText = [titleText copy];
	self.titleLabel.text = titleText;
	self.titleLabel.hidden = !titleText.length;
}

- (void)setSubtitleText:(NSString *)subtitleText {
	_subtitleText = [subtitleText copy];
	self.subtitleLabel.text = subtitleText;
	self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
	self.subtitleLabel.hidden = !subtitleText.length;
}

- (void)setSubtitleText:(NSString *)text flash:(BOOL)flash {
	_subtitleText = [text copy];
	self.subtitleLabel.text = text;
	self.subtitleLabel.hidden = !text.length;

	[UIView transitionWithView:self.subtitleLabel
					  duration:0.14
					   options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
					animations:^{
		self.subtitleLabel.textColor = flash ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
	} completion:nil];
}

- (void)setBiometricButtonVisible:(BOOL)visible {
	_biometricButtonVisible = visible;

	if (visible) {
		[self refreshBiometricImage];
		self.biometricButton.hidden = NO;
	} else {
		self.biometricButton.hidden = YES;
	}
}

- (void)refreshBiometricImage {
	NSString *symbolName = [SCILockManager biometricSymbolName];

	if (!symbolName.length) {
		self.biometricButton.hidden = YES;
		return;
	}

	BOOL compact = self.bounds.size.width > 0.0 && self.bounds.size.width < 360.0;
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:compact ? 28.0 : 30.0 weight:UIImageSymbolWeightRegular];

	[self.biometricButton setImage:[UIImage systemImageNamed:symbolName withConfiguration:config] forState:UIControlStateNormal];
	self.biometricButton.tintColor = [SCIUtils SCIColor_Primary] ?: UIColor.labelColor;
}

- (void)setCancelTitle:(NSString *)cancelTitle {
	_cancelTitle = [cancelTitle copy];

	[self.cancelButton setTitle:cancelTitle forState:UIControlStateNormal];
	self.cancelButton.hidden = !cancelTitle.length;
}

#pragma mark - Actions

- (void)tapDigit:(UIButton *)sender {
	if (!self.acceptingInput || (NSInteger)self.currentCode.length >= self.codeLength) return;

	if (!self.currentCode.length && [self.delegate respondsToSelector:@selector(passcodeViewDidBeginInput:)]) {
		[self.delegate passcodeViewDidBeginInput:self];
	}

	NSInteger digit = sender.tag - 1000;
	[self.currentCode appendFormat:@"%ld", (long)digit];

	[self refreshDotsAnimated:YES];
	[self lightFeedback];

	if ((NSInteger)self.currentCode.length != self.codeLength) return;

	self.acceptingInput = NO;

	NSString *code = self.currentCode.copy;
	[self.delegate passcodeView:self didCompleteCode:code];
}

- (void)tapBackspace {
	if (!self.acceptingInput || !self.currentCode.length) return;

	[self.currentCode deleteCharactersInRange:NSMakeRange(self.currentCode.length - 1, 1)];
	[self refreshDotsAnimated:YES];
	[self lightFeedback];
}

- (void)tapBiometric {
	[self lightFeedback];

	if ([self.delegate respondsToSelector:@selector(passcodeViewDidTapBiometric:)]) {
		[self.delegate passcodeViewDidTapBiometric:self];
	}
}

- (void)tapCancel {
	[self lightFeedback];

	if ([self.delegate respondsToSelector:@selector(passcodeViewDidTapCancel:)]) {
		[self.delegate passcodeViewDidTapCancel:self];
	}
}

#pragma mark - Public

- (void)reset {
	[self.currentCode setString:@""];
	self.acceptingInput = YES;
	[self refreshDotsAnimated:NO];
}

- (void)flashError {
	CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
	shake.values = @[@(-13.0), @(13.0), @(-9.0), @(9.0), @(-4.0), @(4.0), @(0.0)];
	shake.duration = 0.34;
	shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];

	[self.dotsStack.layer addAnimation:shake forKey:@"sci.passcode.shake"];

	[self errorFeedback];

	__weak typeof(self) weakSelf = self;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.34 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf reset];
	});
}

#pragma mark - Feedback

- (void)lightFeedback {
	UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[feedback impactOccurred];
}

- (void)errorFeedback {
	UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
	[feedback impactOccurred];
}

@end
