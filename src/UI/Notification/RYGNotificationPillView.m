#import "RYGNotificationPillView.h"
#import "../RYGLiquidGlass.h"
#import <math.h>

static CGFloat const kPillHeight = 56.0;
static CGFloat const kToastTallHeight = 72.0;
static CGFloat const kDynamicPillHeight = 52.0;
static CGFloat const kDynamicTallHeight = 64.0;
static CGFloat const kDynamicMinWidth = 168.0;
static CGFloat const kDynamicMaxWidth = 320.0;
static CGFloat const kPillMaxWidth = 320.0;
static CGFloat const kHorizontalPad = 14.0;
static CGFloat const kIconBadgeSize = 28.0;
static CGFloat const kRingLineWidth = 2.5;

static UIImage *RYGNotifIcon(NSString *name, CGFloat size, UIFontWeight weight) {
    if (!name.length) return nil;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

static NSString *RYGNotifFallbackIconForTone(RYGNotificationTone tone) {
    switch (tone) {
        case RYGNotificationToneSuccess: return @"checkmark.circle.fill";
        case RYGNotificationToneError: return @"exclamationmark.triangle.fill";
        case RYGNotificationToneWarning: return @"exclamationmark.circle.fill";
        case RYGNotificationToneInfo:
        default: return @"info.circle.fill";
    }
}

static BOOL RYGNotifStyleIsIsland(RYGNotificationStyle style) {
    return style == RYGNotificationStyleIsland;
}

static CGFloat RYGClamp(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    return MIN(maxValue, MAX(minValue, value));
}

static CGFloat RYGTextWidth(NSString *text, UIFont *font) {
    if (!text.length || !font) return 0.0;
    CGRect r = [text boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, font.lineHeight)
                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                               attributes:@{NSFontAttributeName: font}
                                  context:nil];
    return ceil(CGRectGetWidth(r));
}

static CGFloat RYGTextHeight(NSString *text, UIFont *font, CGFloat width, NSInteger maxLines) {
    if (!text.length || !font || width < 1.0) return 0.0;
    CGRect r = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                               attributes:@{NSFontAttributeName: font}
                                  context:nil];
    return MIN(ceil(CGRectGetHeight(r)), ceil(font.lineHeight) * maxLines);
}

static UIColor *RYGNotifToneColor(RYGNotificationTone tone) {
    switch (tone) {
        case RYGNotificationToneSuccess: return UIColor.systemGreenColor;
        case RYGNotificationToneError: return UIColor.systemRedColor;
        case RYGNotificationToneWarning: return UIColor.systemOrangeColor;
        case RYGNotificationToneInfo:
        default: return UIColor.systemBlueColor;
    }
}

#pragma mark - Spinner

@implementation RYGPillSpinnerView {
    CAGradientLayer *_gradient;
    CAShapeLayer *_ringMask;
    BOOL _animating;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;

    _gradient = [CAGradientLayer layer];
    _gradient.type = kCAGradientLayerConic;
    _gradient.startPoint = CGPointMake(0.5, 0.5);
    _gradient.endPoint = CGPointMake(0.5, 0.0);
    [self.layer addSublayer:_gradient];

    _ringMask = [CAShapeLayer layer];
    _ringMask.fillColor = UIColor.clearColor.CGColor;
    _ringMask.strokeColor = UIColor.blackColor.CGColor;
    _ringMask.lineCap = kCALineCapRound;
    _gradient.mask = _ringMask;

    _color = UIColor.labelColor;
    [self rygApplyColors];
    return self;
}

- (BOOL)isAnimating { return _animating; }

- (void)setColor:(UIColor *)color {
    _color = color ?: UIColor.labelColor;
    [self rygApplyColors];
}

- (void)rygApplyColors {
    UIColor *c = _color ?: UIColor.labelColor;
    _gradient.colors = @[
        (id)[c colorWithAlphaComponent:0.0].CGColor,
        (id)[c colorWithAlphaComponent:0.12].CGColor,
        (id)[c colorWithAlphaComponent:0.58].CGColor,
        (id)c.CGColor,
    ];
    _gradient.locations = @[@0.0, @0.35, @0.75, @1.0];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (CGRectIsEmpty(b)) return;
    CGFloat dim = MIN(CGRectGetWidth(b), CGRectGetHeight(b));
    CGFloat lw = MAX(2.5, dim * 0.18);
    CGRect r = CGRectInset(b, lw / 2.0 + 0.5, lw / 2.0 + 0.5);
    _gradient.frame = b;
    _ringMask.frame = b;
    _ringMask.lineWidth = lw;
    _ringMask.path = [UIBezierPath bezierPathWithOvalInRect:r].CGPath;
    if (_animating) [self rygInstallRotation];
}

- (void)startAnimating {
    self.hidden = NO;
    if (_animating) return;
    _animating = YES;
    [self rygInstallRotation];
}

- (void)stopAnimating {
    _animating = NO;
    [_gradient removeAnimationForKey:@"rygSpinRotate"];
    self.hidden = YES;
}

- (void)rygInstallRotation {
    [_gradient removeAnimationForKey:@"rygSpinRotate"];
    CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rot.fromValue = @0.0;
    rot.toValue = @(2.0 * M_PI);
    rot.duration = 0.85;
    rot.repeatCount = HUGE_VALF;
    rot.removedOnCompletion = NO;
    [_gradient addAnimation:rot forKey:@"rygSpinRotate"];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && _animating) [self rygInstallRotation];
}

@end

#pragma mark - Notification pill

@interface RYGNotificationPillView () <UIGestureRecognizerDelegate> {
    RYGNotificationStyle _style;
    RYGNotificationPosition _position;
    RYGNotificationTone _tone;
    float _progress;
    CGPoint _panOriginCenter;
}
@property(nonatomic,strong) UIVisualEffectView *glassView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIStackView *textStack;
@property(nonatomic,strong) UIProgressView *progressView;
@property(nonatomic,strong) UIView *progressRowContainer;
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) RYGPillSpinnerView *spinnerView;
@property(nonatomic,strong) UIView *iconBadgeView;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) NSLayoutConstraint *widthConstraint;
@property(nonatomic,strong) NSLayoutConstraint *heightConstraint;
@property(nonatomic,strong) NSLayoutConstraint *progressHeightConstraint;
@property(nonatomic,strong) NSLayoutConstraint *progressRowHeightConstraint;
@property(nonatomic,strong) NSLayoutConstraint *textTrailingWithButtonConstraint;
@property(nonatomic,strong) NSLayoutConstraint *textTrailingWithoutButtonConstraint;
@property(nonatomic,strong) CAShapeLayer *progressRingTrackLayer;
@property(nonatomic,strong) CAShapeLayer *progressRingLayer;
@property(nonatomic,strong) UIPanGestureRecognizer *panGesture;
@end

@implementation RYGNotificationPillView

- (instancetype)initWithStyle:(RYGNotificationStyle)style position:(RYGNotificationPosition)position {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _style = style;
    _position = position;
    _tone = RYGNotificationToneInfo;
    _progress = 0.0f;
    [self rygBuild];
    [self rygApplyVisualStyleAnimated:NO];
    return self;
}

- (RYGNotificationStyle)style { return _style; }
- (RYGNotificationPosition)position { return _position; }
- (RYGNotificationTone)tone { return _tone; }
- (float)progress { return _progress; }

- (void)rygBuild {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipsToBounds = NO;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    [self rygBuildGlassBackground];
    [self rygBuildIcon];
    [self rygBuildCloseButton];
    [self rygBuildTextAndProgress];
    [self rygBuildSizeConstraints];
    [self rygBuildProgressRing];
    [self rygBuildGestures];
}

- (void)rygPinView:(UIView *)view toView:(UIView *)target {
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:target.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:target.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:target.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],
    ]];
}

- (void)rygBuildGlassBackground {
    BOOL clear = _style == RYGNotificationStyleMinimal || _style == RYGNotificationStyleIsland;
    self.glassView = RYGLiquidGlassView(YES, clear, nil);
    self.glassView.translatesAutoresizingMaskIntoConstraints = NO;
    self.glassView.userInteractionEnabled = NO;
    self.glassView.clipsToBounds = YES;
    self.glassView.layer.cornerCurve = kCACornerCurveContinuous;
    [self insertSubview:self.glassView atIndex:0];
    [self rygPinView:self.glassView toView:self];
}

- (void)rygBuildIcon {
    self.iconBadgeView = [UIView new];
    self.iconBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconBadgeView.layer.cornerCurve = kCACornerCurveContinuous;
    self.iconBadgeView.clipsToBounds = YES;
    [self addSubview:self.iconBadgeView];

    self.iconView = [UIImageView new];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.image = RYGNotifIcon(RYGNotifFallbackIconForTone(_tone), 16.0, UIFontWeightSemibold);
    [self.iconBadgeView addSubview:self.iconView];

    self.spinnerView = [[RYGPillSpinnerView alloc] initWithFrame:CGRectZero];
    self.spinnerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinnerView.hidden = YES;
    [self.iconBadgeView addSubview:self.spinnerView];

    [NSLayoutConstraint activateConstraints:@[
        [self.iconBadgeView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kHorizontalPad],
        [self.iconBadgeView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.iconBadgeView.widthAnchor constraintEqualToConstant:kIconBadgeSize],
        [self.iconBadgeView.heightAnchor constraintEqualToConstant:kIconBadgeSize],
        [self.iconView.centerXAnchor constraintEqualToAnchor:self.iconBadgeView.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.iconBadgeView.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:16.0],
        [self.iconView.heightAnchor constraintEqualToConstant:16.0],
        [self.spinnerView.centerXAnchor constraintEqualToAnchor:self.iconBadgeView.centerXAnchor],
        [self.spinnerView.centerYAnchor constraintEqualToAnchor:self.iconBadgeView.centerYAnchor],
        [self.spinnerView.widthAnchor constraintEqualToConstant:20.0],
        [self.spinnerView.heightAnchor constraintEqualToConstant:20.0],
    ]];
}

- (void)rygBuildCloseButton {
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setImage:RYGNotifIcon(@"xmark", 12.0, UIFontWeightBold) forState:UIControlStateNormal];
    self.closeButton.hidden = YES;
    [self.closeButton addTarget:self action:@selector(rygCloseTapped) forControlEvents:UIControlEventTouchUpInside];
    RYGLiquidGlassConfigureButton(self.closeButton, NO);
    [self addSubview:self.closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:30.0],
        [self.closeButton.heightAnchor constraintGreaterThanOrEqualToConstant:30.0],
    ]];
}

- (void)rygBuildTextAndProgress {
    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = UIColor.labelColor;
    self.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.subtitleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    self.subtitleLabel.numberOfLines = 1;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.subtitleLabel.hidden = YES;

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.hidden = YES;
    self.progressView.progress = 0.0f;
    self.progressView.clipsToBounds = YES;

    self.progressRowContainer = [UIView new];
    self.progressRowContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressRowContainer.backgroundColor = UIColor.clearColor;
    self.progressRowContainer.hidden = YES;
    [self.progressRowContainer addSubview:self.progressView];

    self.progressHeightConstraint = [self.progressView.heightAnchor constraintEqualToConstant:0.0];
    self.progressRowHeightConstraint = [self.progressRowContainer.heightAnchor constraintEqualToConstant:0.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.progressRowContainer.leadingAnchor],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.progressRowContainer.trailingAnchor],
        [self.progressView.centerYAnchor constraintEqualToAnchor:self.progressRowContainer.centerYAnchor],
        self.progressHeightConstraint,
        self.progressRowHeightConstraint,
    ]];

    self.textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel, self.progressRowContainer]];
    self.textStack.axis = UILayoutConstraintAxisVertical;
    self.textStack.spacing = 2.0;
    self.textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.textStack];

    self.textTrailingWithButtonConstraint = [self.textStack.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-8.0];
    self.textTrailingWithoutButtonConstraint = [self.textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-kHorizontalPad];
    [NSLayoutConstraint activateConstraints:@[
        [self.textStack.leadingAnchor constraintEqualToAnchor:self.iconBadgeView.trailingAnchor constant:10.0],
        [self.textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        self.textTrailingWithoutButtonConstraint,
    ]];
}

- (void)rygBuildSizeConstraints {
    BOOL island = RYGNotifStyleIsIsland(_style);
    self.widthConstraint = [self.widthAnchor constraintEqualToConstant:island ? kDynamicMinWidth : 220.0];
    self.heightConstraint = [self.heightAnchor constraintEqualToConstant:island ? kDynamicPillHeight : kPillHeight];
    self.widthConstraint.active = YES;
    self.heightConstraint.active = YES;
}

- (void)rygBuildProgressRing {
    self.progressRingTrackLayer = [CAShapeLayer layer];
    self.progressRingTrackLayer.fillColor = UIColor.clearColor.CGColor;
    self.progressRingTrackLayer.strokeColor = [UIColor.secondaryLabelColor colorWithAlphaComponent:0.25].CGColor;
    self.progressRingTrackLayer.lineWidth = kRingLineWidth;
    self.progressRingTrackLayer.hidden = YES;
    [self.iconBadgeView.layer addSublayer:self.progressRingTrackLayer];

    self.progressRingLayer = [CAShapeLayer layer];
    self.progressRingLayer.fillColor = UIColor.clearColor.CGColor;
    self.progressRingLayer.lineWidth = kRingLineWidth;
    self.progressRingLayer.lineCap = kCALineCapRound;
    self.progressRingLayer.strokeEnd = 0.0;
    self.progressRingLayer.hidden = YES;
    [self.iconBadgeView.layer addSublayer:self.progressRingLayer];
}

- (void)rygBuildGestures {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rygTapped)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];

    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(rygPan:)];
    self.panGesture.delegate = self;
    [self addGestureRecognizer:self.panGesture];
}

- (CGFloat)rygCurrentCornerRadius {
    return MAX(CGRectGetHeight(self.bounds) * 0.5, 18.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = [self rygCurrentCornerRadius];
    self.layer.cornerRadius = radius;
    self.glassView.layer.cornerRadius = radius;
    self.iconBadgeView.layer.cornerRadius = kIconBadgeSize * 0.5;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;

    if (!self.progressView.hidden) {
        CGFloat h = CGRectGetHeight(self.progressView.bounds);
        if (h > 0.5) self.progressView.layer.cornerRadius = h * 0.5;
    }
    [self rygUpdateRingPath];
}

- (void)rygUpdateRingPath {
    CGRect b = self.iconBadgeView.bounds;
    if (CGRectIsEmpty(b)) return;
    CGFloat inset = kRingLineWidth / 2.0 + 0.5;
    CGRect r = CGRectInset(b, inset, inset);
    CGPoint center = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    CGFloat radius = MIN(CGRectGetWidth(r), CGRectGetHeight(r)) / 2.0;
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:-M_PI_2 endAngle:(-M_PI_2 + 2.0 * M_PI) clockwise:YES];
    self.progressRingTrackLayer.frame = b;
    self.progressRingLayer.frame = b;
    self.progressRingTrackLayer.path = path.CGPath;
    self.progressRingLayer.path = path.CGPath;
}

- (UIColor *)rygGlassTintForTone:(RYGNotificationTone)tone {
    if (_style == RYGNotificationStyleMinimal) return nil;
    UIColor *toneColor = RYGNotifToneColor(tone);
    CGFloat alpha = _style == RYGNotificationStyleIsland ? 0.11 : (_style == RYGNotificationStyleGlow ? 0.20 : 0.16);
    return [toneColor colorWithAlphaComponent:alpha];
}

- (void)rygApplyVisualStyleAnimated:(BOOL)animated {
    void (^apply)(void) = ^{
        UIColor *toneColor = RYGNotifToneColor(self->_tone);
        RYGLiquidGlassSetTint(self.glassView, [self rygGlassTintForTone:self->_tone]);

        self.titleLabel.textColor = UIColor.labelColor;
        self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
        self.iconView.tintColor = toneColor;
        self.spinnerView.color = toneColor;
        self.iconBadgeView.backgroundColor = [toneColor colorWithAlphaComponent:0.12];
        self.progressView.progressTintColor = toneColor;
        self.progressView.trackTintColor = [UIColor.secondaryLabelColor colorWithAlphaComponent:0.22];
        self.progressRingLayer.strokeColor = toneColor.CGColor;

        BOOL glow = self->_style == RYGNotificationStyleGlow;
        self.layer.borderWidth = 0.0;
        self.layer.shadowColor = (glow ? toneColor : UIColor.blackColor).CGColor;
        self.layer.shadowOpacity = glow ? 0.28 : 0.12;
        self.layer.shadowRadius = glow ? 18.0 : 10.0;
        self.layer.shadowOffset = CGSizeMake(0, 5);

        RYGLiquidGlassConfigureButton(self.closeButton, NO);
    };

    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:apply completion:nil];
    } else {
        apply();
    }
}

- (CGFloat)rygSubtitleRowHeight {
    return ceil((self.subtitleLabel.font ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium]).lineHeight);
}

- (CGFloat)rygProgressBarHeight {
    return MAX(2.0, ceil([self rygSubtitleRowHeight] / 3.0));
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    self.titleLabel.text = titleText ?: @"";
}

- (void)setSubtitleText:(NSString *)subtitleText {
    _subtitleText = [subtitleText copy];
    self.subtitleLabel.text = subtitleText ?: @"";
    self.subtitleLabel.hidden = subtitleText.length == 0;
}

- (void)setIconSymbolName:(NSString *)iconSymbolName {
    _iconSymbolName = [iconSymbolName copy];
    self.iconView.image = RYGNotifIcon(iconSymbolName.length ? iconSymbolName : RYGNotifFallbackIconForTone(_tone), 16.0, UIFontWeightSemibold);
}

- (void)setShowsProgress:(BOOL)showsProgress {
    if (_showsProgress == showsProgress) return;
    _showsProgress = showsProgress;
    [self rygApplyProgressVisibility];
}

- (void)setIndeterminate:(BOOL)indeterminate {
    if (_indeterminate == indeterminate) return;
    _indeterminate = indeterminate;
    [self rygApplyProgressVisibility];
}

- (void)rygApplyProgressVisibility {
    BOOL island = RYGNotifStyleIsIsland(_style);
    BOOL spinning = _showsProgress && _indeterminate;
    BOOL determinate = _showsProgress && !_indeterminate;

    self.iconView.hidden = spinning;
    self.iconBadgeView.backgroundColor = [RYGNotifToneColor(_tone) colorWithAlphaComponent:spinning ? 0.08 : 0.12];
    if (spinning) [self.spinnerView startAnimating];
    else [self.spinnerView stopAnimating];

    self.progressRingTrackLayer.hidden = !island || !determinate;
    self.progressRingLayer.hidden = !island || !determinate;
    if (!determinate) self.progressRingLayer.strokeEnd = 0.0;

    if (island) {
        self.progressRowContainer.hidden = YES;
        self.progressView.hidden = YES;
        self.progressRowHeightConstraint.constant = 0.0;
        self.progressHeightConstraint.constant = 0.0;
    } else {
        self.progressRowContainer.hidden = !determinate;
        self.progressView.hidden = !determinate;
        self.progressRowHeightConstraint.constant = determinate ? [self rygSubtitleRowHeight] : 0.0;
        self.progressHeightConstraint.constant = determinate ? [self rygProgressBarHeight] : 0.0;
    }
}

- (void)setShowsCancelButton:(BOOL)showsCancelButton {
    if (_showsCancelButton == showsCancelButton) return;
    _showsCancelButton = showsCancelButton;
    self.closeButton.hidden = !showsCancelButton;
    self.textTrailingWithButtonConstraint.active = showsCancelButton;
    self.textTrailingWithoutButtonConstraint.active = !showsCancelButton;
    [self refreshSizeAnimated:YES];
}

- (void)applyTone:(RYGNotificationTone)tone animated:(BOOL)animated {
    _tone = tone;
    if (!self.iconSymbolName.length) {
        self.iconView.image = RYGNotifIcon(RYGNotifFallbackIconForTone(tone), 16.0, UIFontWeightSemibold);
    }
    [self rygApplyVisualStyleAnimated:animated];
    [self rygApplyProgressVisibility];
}

- (void)setProgress:(float)progress { [self setProgress:progress animated:NO]; }

- (void)setProgress:(float)progress animated:(BOOL)animated {
    _progress = fmaxf(0.0f, fminf(progress, 1.0f));
    if (animated) [self.progressView setProgress:_progress animated:YES];
    else self.progressView.progress = _progress;
    self.progressRingLayer.strokeEnd = _progress;
}

- (void)refreshSizeAnimated:(BOOL)animated {
    BOOL island = RYGNotifStyleIsIsland(_style);
    BOOL tall = self.subtitleText.length > 0 || (self.showsProgress && !self.indeterminate);
    BOOL hasButton = self.showsCancelButton;

    CGFloat targetH = island ? (tall ? kDynamicTallHeight : kDynamicPillHeight) : (tall ? kToastTallHeight : kPillHeight);
    CGFloat textW = MAX(RYGTextWidth(self.titleText, self.titleLabel.font), RYGTextWidth(self.subtitleText, self.subtitleLabel.font));
    CGFloat fixedW = kHorizontalPad + kIconBadgeSize + 10.0 + kHorizontalPad + (hasButton ? 42.0 : 0.0);
    CGFloat minW = island ? kDynamicMinWidth : 180.0;
    CGFloat maxW = island ? kDynamicMaxWidth : kPillMaxWidth;
    CGFloat targetW = RYGClamp(ceil(textW) + fixedW + 6.0, minW, maxW);

    CGFloat availTextW = MAX(targetW - fixedW - 6.0, 40.0);
    CGFloat titleH = RYGTextHeight(self.titleText, self.titleLabel.font, availTextW, 2);
    CGFloat oneLine = ceil(self.titleLabel.font.lineHeight);
    if (titleH > oneLine + 0.5) targetH += titleH - oneLine;

    self.widthConstraint.constant = targetW;
    self.heightConstraint.constant = targetH;
    if (!animated || !self.superview) {
        [self.superview layoutIfNeeded];
        return;
    }
    [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.45 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self.superview layoutIfNeeded];
    } completion:nil];
}

- (CGFloat)pillTargetHeight {
    return self.heightConstraint.constant > 1.0 ? self.heightConstraint.constant : self.bounds.size.height;
}

- (void)pulseIcon {
    [UIView animateKeyframesWithDuration:0.30 delay:0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.55 animations:^{ self.iconBadgeView.transform = CGAffineTransformMakeScale(1.10, 1.10); }];
        [UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.45 animations:^{ self.iconBadgeView.transform = CGAffineTransformIdentity; }];
    } completion:nil];
}

- (void)rygTapped { if (self.onTap) self.onTap(self); }
- (void)rygCloseTapped { if (self.onCancel) self.onCancel(self); }

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return touch.view ? ![touch.view isDescendantOfView:self.closeButton] : YES;
}

- (void)rygPan:(UIPanGestureRecognizer *)pan {
    BOOL bottom = _position == RYGNotificationPositionBottom;
    CGFloat sign = bottom ? 1.0 : -1.0;
    CGPoint translation = [pan translationInView:self.superview];
    CGFloat dismissTrans = translation.y * sign;
    CGFloat velocity = [pan velocityInView:self.superview].y;

    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            _panOriginCenter = self.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat delta = translation.y;
            if (dismissTrans < 0.0) delta *= 0.25;
            self.center = CGPointMake(_panOriginCenter.x, _panOriginCenter.y + delta);
            self.alpha = 1.0 - (RYGClamp(dismissTrans / 60.0, 0.0, 1.0) * 0.5);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            BOOL away = dismissTrans > 20.0 || velocity * sign > 300.0;
            if (away && self.onSwipeDismiss) {
                self.onSwipeDismiss(self);
                return;
            }
            [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.74 initialSpringVelocity:0.45 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.center = self->_panOriginCenter;
                self.alpha = 1.0;
            } completion:nil];
            break;
        }
        default: break;
    }
}

@end
