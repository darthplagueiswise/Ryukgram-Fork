#import "SCINotificationPillView.h"
#import <math.h>

static CGFloat const kPillCorner          = 30.0;
static CGFloat const kPillHeight          = 56.0;
static CGFloat const kToastTallHeight     = 72.0;
static CGFloat const kPillWidth           = 296.0;
static CGFloat const kDynamicPillHeight   = 52.0;
static CGFloat const kDynamicTallHeight   = 64.0;
static CGFloat const kDynamicMinWidth     = 200.0;
static CGFloat const kDynamicMaxWidth     = 320.0;
static CGFloat const kHorizontalPad       = 16.0;
static CGFloat const kIconBadgeSize       = 28.0;
static CGFloat const kRingLineWidth       = 2.5;

static UIImage *SCINotifIcon(NSString *name, CGFloat size, UIFontWeight weight) {
    if (!name.length) return nil;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

static NSString *SCINotifFallbackIconForTone(SCINotificationTone tone) {
    switch (tone) {
        case SCINotificationToneSuccess:  return @"checkmark.circle.fill";
        case SCINotificationToneError:    return @"exclamationmark.triangle.fill";
        case SCINotificationToneWarning:  return @"exclamationmark.circle.fill";
        case SCINotificationToneInfo:
        default:                          return @"info.circle.fill";
    }
}

static BOOL SCINotifStyleIsIsland(SCINotificationStyle s) {
    return s == SCINotificationStyleIsland;
}

#pragma mark - SCIPillSpinnerView

@implementation SCIPillSpinnerView {
    CAGradientLayer *_gradient;
    CAShapeLayer    *_ringMask;
    BOOL             _animating;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
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

    _color = [UIColor whiteColor];
    [self sciApplyColors];
    return self;
}

- (BOOL)isAnimating { return _animating; }

- (void)setColor:(UIColor *)color {
    _color = color ?: [UIColor whiteColor];
    [self sciApplyColors];
}

- (void)sciApplyColors {
    UIColor *c = _color;
    _gradient.colors = @[
        (id)[c colorWithAlphaComponent:0.0].CGColor,
        (id)[c colorWithAlphaComponent:0.10].CGColor,
        (id)[c colorWithAlphaComponent:0.55].CGColor,
        (id)c.CGColor,
    ];
    _gradient.locations = @[@0.0, @0.35, @0.75, @1.0];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    if (b.size.width < 1.0 || b.size.height < 1.0) return;

    CGFloat dim = MIN(b.size.width, b.size.height);
    CGFloat lw = MAX(2.5, dim * 0.18);

    _gradient.frame = b;
    _ringMask.frame = b;

    CGFloat inset = lw / 2.0 + 0.5;
    CGRect r = CGRectInset(b, inset, inset);
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:r];

    _ringMask.lineWidth = lw;
    _ringMask.path = path.CGPath;

    if (_animating) [self sciInstallRotation];
}

- (void)startAnimating {
    self.hidden = NO;
    if (_animating) return;
    _animating = YES;
    [self sciInstallRotation];
}

- (void)stopAnimating {
    _animating = NO;
    [_gradient removeAnimationForKey:@"sciSpinRotate"];
    self.hidden = YES;
}

- (void)sciInstallRotation {
    [_gradient removeAnimationForKey:@"sciSpinRotate"];
    CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rot.fromValue = @0.0;
    rot.toValue = @(2.0 * M_PI);
    rot.duration = 0.85;
    rot.repeatCount = HUGE_VALF;
    rot.removedOnCompletion = NO;
    [_gradient addAnimation:rot forKey:@"sciSpinRotate"];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && _animating) [self sciInstallRotation];
}

@end

#pragma mark - SCINotificationPillView

@interface SCINotificationPillView () <UIGestureRecognizerDelegate> {
    SCINotificationStyle    _style;
    SCINotificationPosition _position;
    SCINotificationTone     _tone;
    float                   _progress;
    CGPoint                 _panOriginCenter;
}
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView             *chromeOverlayView;
@property (nonatomic, strong) CAGradientLayer    *chromeGradientLayer;
@property (nonatomic, strong) UILabel            *titleLabel;
@property (nonatomic, strong) UILabel            *subtitleLabel;
@property (nonatomic, strong) UIStackView        *textStack;
@property (nonatomic, strong) UIProgressView     *progressView;
@property (nonatomic, strong) UIView             *progressRowContainer;
@property (nonatomic, strong) UIImageView        *iconView;
@property (nonatomic, strong) SCIPillSpinnerView *spinnerView;
@property (nonatomic, strong) UIView             *iconBadgeView;
@property (nonatomic, strong) CAGradientLayer    *iconBadgeGradientLayer;
@property (nonatomic, strong) UIButton           *closeButton;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *progressHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *progressRowHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *textTrailingWithButtonConstraint;
@property (nonatomic, strong) NSLayoutConstraint *textTrailingWithoutButtonConstraint;
@property (nonatomic, strong) CAShapeLayer       *progressRingTrackLayer;
@property (nonatomic, strong) CAShapeLayer       *progressRingLayer;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@end

@implementation SCINotificationPillView

- (instancetype)initWithStyle:(SCINotificationStyle)style position:(SCINotificationPosition)position {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _style = style;
    _position = position;
    _tone = SCINotificationToneInfo;
    _progress = 0.0f;
    [self sciBuild];
    [self sciApplyVisualStyleAnimated:NO];
    return self;
}

- (SCINotificationStyle)style { return _style; }
- (SCINotificationPosition)position { return _position; }
- (SCINotificationTone)tone { return _tone; }
- (float)progress { return _progress; }

#pragma mark - Build

- (void)sciBuild {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.layer.cornerRadius = kPillCorner;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 0.65;
    self.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
    self.clipsToBounds = YES;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.translatesAutoresizingMaskIntoConstraints = NO;
    self.blurView.layer.cornerRadius = kPillCorner;
    self.blurView.layer.cornerCurve = kCACornerCurveContinuous;
    self.blurView.clipsToBounds = YES;
    [self addSubview:self.blurView];
    [NSLayoutConstraint activateConstraints:@[
        [self.blurView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.blurView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.blurView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    self.chromeOverlayView = [UIView new];
    self.chromeOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chromeOverlayView.userInteractionEnabled = NO;
    // Dark base for HDR-content visibility. Tone gradient stacks on top.
    self.chromeOverlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.22];
    self.chromeOverlayView.layer.cornerRadius = kPillCorner;
    self.chromeOverlayView.layer.cornerCurve = kCACornerCurveContinuous;
    self.chromeOverlayView.clipsToBounds = YES;
    [self addSubview:self.chromeOverlayView];
    [NSLayoutConstraint activateConstraints:@[
        [self.chromeOverlayView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.chromeOverlayView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.chromeOverlayView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.chromeOverlayView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];

    self.chromeGradientLayer = [CAGradientLayer layer];
    self.chromeGradientLayer.startPoint = CGPointMake(0.0, 0.0);
    self.chromeGradientLayer.endPoint = CGPointMake(1.0, 1.0);
    self.chromeGradientLayer.opacity = 0.9;
    [self.chromeOverlayView.layer addSublayer:self.chromeGradientLayer];

    self.iconBadgeView = [UIView new];
    self.iconBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconBadgeView.layer.cornerCurve = kCACornerCurveContinuous;
    self.iconBadgeView.layer.cornerRadius = kIconBadgeSize / 2.0;
    self.iconBadgeView.layer.borderWidth = 0.5;
    self.iconBadgeView.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.24] CGColor];
    self.iconBadgeView.clipsToBounds = YES;
    [self addSubview:self.iconBadgeView];

    self.iconBadgeGradientLayer = [CAGradientLayer layer];
    self.iconBadgeGradientLayer.startPoint = CGPointMake(0.0, 0.2);
    self.iconBadgeGradientLayer.endPoint = CGPointMake(1.0, 1.0);
    [self.iconBadgeView.layer insertSublayer:self.iconBadgeGradientLayer atIndex:0];

    self.iconView = [UIImageView new];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.tintColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    self.iconView.image = SCINotifIcon(@"arrow.down.to.line", 16.0, UIFontWeightSemibold);
    [self.iconBadgeView addSubview:self.iconView];

    self.spinnerView = [[SCIPillSpinnerView alloc] initWithFrame:CGRectZero];
    self.spinnerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinnerView.hidden = YES;
    self.spinnerView.color = [UIColor colorWithWhite:1.0 alpha:0.96];
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

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setImage:SCINotifIcon(@"xmark", 12.0, UIFontWeightBold) forState:UIControlStateNormal];
    self.closeButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.83];
    self.closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    self.closeButton.layer.cornerRadius = 12.0;
    self.closeButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.closeButton.layer.borderWidth = 0.5;
    self.closeButton.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.22] CGColor];
    self.closeButton.hidden = YES;
    [self.closeButton addTarget:self action:@selector(sciCloseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-13.0],
        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:24.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:24.0],
    ]];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = @"";
    self.titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.98];
    self.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    self.subtitleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    self.subtitleLabel.numberOfLines = 1;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.subtitleLabel.hidden = YES;

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.hidden = YES;
    self.progressView.progress = 0.0f;
    self.progressView.clipsToBounds = YES;
    self.progressView.layer.cornerCurve = kCACornerCurveContinuous;
    self.progressView.layer.cornerRadius = 0.0;

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
    self.textStack.alignment = UIStackViewAlignmentFill;
    self.textStack.distribution = UIStackViewDistributionFill;
    self.textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.textStack];

    self.textTrailingWithButtonConstraint = [self.textStack.trailingAnchor constraintEqualToAnchor:self.closeButton.leadingAnchor constant:-10.0];
    self.textTrailingWithoutButtonConstraint = [self.textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-kHorizontalPad];

    [NSLayoutConstraint activateConstraints:@[
        [self.textStack.leadingAnchor constraintEqualToAnchor:self.iconBadgeView.trailingAnchor constant:10.0],
        [self.textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        self.textTrailingWithoutButtonConstraint,
    ]];

    [self.progressView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self.progressView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    BOOL island = SCINotifStyleIsIsland(_style);
    self.widthConstraint = [self.widthAnchor constraintEqualToConstant:island ? kDynamicMinWidth : kPillWidth];
    self.heightConstraint = [self.heightAnchor constraintEqualToConstant:island ? kDynamicPillHeight : kPillHeight];
    self.widthConstraint.active = YES;
    self.heightConstraint.active = YES;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sciTapped)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];

    // Ring progress (Island only).
    self.progressRingTrackLayer = [CAShapeLayer layer];
    self.progressRingTrackLayer.fillColor = UIColor.clearColor.CGColor;
    self.progressRingTrackLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    self.progressRingTrackLayer.lineWidth = kRingLineWidth;
    self.progressRingTrackLayer.hidden = YES;
    [self.iconBadgeView.layer addSublayer:self.progressRingTrackLayer];

    self.progressRingLayer = [CAShapeLayer layer];
    self.progressRingLayer.fillColor = UIColor.clearColor.CGColor;
    self.progressRingLayer.strokeColor = UIColor.whiteColor.CGColor;
    self.progressRingLayer.lineWidth = kRingLineWidth;
    self.progressRingLayer.lineCap = kCALineCapRound;
    self.progressRingLayer.strokeEnd = 0.0;
    self.progressRingLayer.hidden = YES;
    [self.iconBadgeView.layer addSublayer:self.progressRingLayer];

    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sciPan:)];
    self.panGesture.delegate = self;
    [self addGestureRecognizer:self.panGesture];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    self.chromeGradientLayer.frame = self.chromeOverlayView.bounds;
    self.iconBadgeGradientLayer.frame = self.iconBadgeView.bounds;
    if (!self.progressView.hidden) {
        CGFloat h = CGRectGetHeight(self.progressView.bounds);
        if (h > 0.5) self.progressView.layer.cornerRadius = h * 0.5;
    }
    [self sciUpdateRingPath];

    // Island uses a true capsule (height/2); others use kPillCorner.
    CGFloat radius = SCINotifStyleIsIsland(_style)
        ? (CGRectGetHeight(self.bounds) / 2.0)
        : kPillCorner;
    self.layer.cornerRadius = radius;
    self.blurView.layer.cornerRadius = radius;
    self.chromeOverlayView.layer.cornerRadius = radius;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;
}

- (void)sciUpdateRingPath {
    CGRect b = self.iconBadgeView.bounds;
    if (CGRectIsEmpty(b)) return;
    CGFloat inset = kRingLineWidth / 2.0 + 0.5;
    CGRect r = CGRectInset(b, inset, inset);
    CGPoint center = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    CGFloat radius = MIN(CGRectGetWidth(r), CGRectGetHeight(r)) / 2.0;
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                        radius:radius
                                                    startAngle:-M_PI_2
                                                      endAngle:(-M_PI_2 + 2.0 * M_PI)
                                                     clockwise:YES];
    self.progressRingTrackLayer.path = path.CGPath;
    self.progressRingLayer.path = path.CGPath;
    self.progressRingTrackLayer.frame = b;
    self.progressRingLayer.frame = b;
}

#pragma mark - Color tables

- (NSArray *)sciChromeColorsForTone:(SCINotificationTone)tone {
    if (_style == SCINotificationStyleIsland) {
        return @[(id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
                 (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor];
    }
    if (_style == SCINotificationStyleMinimal) {
        return @[(id)[UIColor colorWithWhite:1.0 alpha:0.20].CGColor,
                 (id)[UIColor colorWithWhite:0.85 alpha:0.14].CGColor];
    }
    switch (tone) {
        case SCINotificationToneSuccess:
            return @[(id)[UIColor colorWithRed:0.12 green:0.35 blue:0.29 alpha:0.46].CGColor,
                     (id)[UIColor colorWithRed:0.11 green:0.29 blue:0.24 alpha:0.38].CGColor];
        case SCINotificationToneError:
            return @[(id)[UIColor colorWithRed:0.42 green:0.14 blue:0.20 alpha:0.45].CGColor,
                     (id)[UIColor colorWithRed:0.32 green:0.10 blue:0.13 alpha:0.38].CGColor];
        case SCINotificationToneWarning:
            return @[(id)[UIColor colorWithRed:0.45 green:0.32 blue:0.10 alpha:0.46].CGColor,
                     (id)[UIColor colorWithRed:0.34 green:0.23 blue:0.07 alpha:0.38].CGColor];
        case SCINotificationToneInfo:
        default:
            return @[(id)[UIColor colorWithRed:0.06 green:0.35 blue:0.75 alpha:0.42].CGColor,
                     (id)[UIColor colorWithRed:0.04 green:0.25 blue:0.55 alpha:0.35].CGColor];
    }
}

- (NSArray *)sciBadgeColorsForTone:(SCINotificationTone)tone {
    if (_style == SCINotificationStyleIsland) {
        switch (tone) {
            case SCINotificationToneSuccess:
                return @[(id)[UIColor colorWithRed:0.22 green:0.80 blue:0.55 alpha:0.30].CGColor,
                         (id)[UIColor colorWithRed:0.16 green:0.60 blue:0.42 alpha:0.25].CGColor];
            case SCINotificationToneError:
                return @[(id)[UIColor colorWithRed:0.90 green:0.30 blue:0.38 alpha:0.30].CGColor,
                         (id)[UIColor colorWithRed:0.70 green:0.18 blue:0.25 alpha:0.25].CGColor];
            case SCINotificationToneWarning:
                return @[(id)[UIColor colorWithRed:0.95 green:0.65 blue:0.20 alpha:0.30].CGColor,
                         (id)[UIColor colorWithRed:0.78 green:0.50 blue:0.10 alpha:0.25].CGColor];
            case SCINotificationToneInfo:
            default:
                return @[(id)[UIColor colorWithRed:0.30 green:0.65 blue:0.95 alpha:0.28].CGColor,
                         (id)[UIColor colorWithRed:0.20 green:0.50 blue:0.80 alpha:0.22].CGColor];
        }
    }

    if (_style == SCINotificationStyleMinimal) {
        switch (tone) {
            case SCINotificationToneError:
                return @[(id)[UIColor colorWithRed:1.00 green:0.83 blue:0.86 alpha:0.96].CGColor,
                         (id)[UIColor colorWithRed:0.87 green:0.53 blue:0.59 alpha:0.94].CGColor];
            case SCINotificationToneInfo:
                return @[(id)[UIColor colorWithRed:0.80 green:0.92 blue:0.99 alpha:0.96].CGColor,
                         (id)[UIColor colorWithRed:0.50 green:0.78 blue:0.96 alpha:0.94].CGColor];
            case SCINotificationToneWarning:
                return @[(id)[UIColor colorWithRed:1.00 green:0.92 blue:0.78 alpha:0.96].CGColor,
                         (id)[UIColor colorWithRed:0.95 green:0.75 blue:0.40 alpha:0.94].CGColor];
            case SCINotificationToneSuccess:
            default:
                return @[(id)[UIColor colorWithRed:0.96 green:0.98 blue:0.97 alpha:0.95].CGColor,
                         (id)[UIColor colorWithRed:0.75 green:0.87 blue:0.81 alpha:0.92].CGColor];
        }
    }

    switch (tone) {
        case SCINotificationToneSuccess:
            return @[(id)[UIColor colorWithRed:0.35 green:0.96 blue:0.70 alpha:0.95].CGColor,
                     (id)[UIColor colorWithRed:0.20 green:0.63 blue:0.46 alpha:0.95].CGColor];
        case SCINotificationToneError:
            return @[(id)[UIColor colorWithRed:1.00 green:0.53 blue:0.58 alpha:0.94].CGColor,
                     (id)[UIColor colorWithRed:0.83 green:0.26 blue:0.36 alpha:0.94].CGColor];
        case SCINotificationToneWarning:
            return @[(id)[UIColor colorWithRed:1.00 green:0.84 blue:0.40 alpha:0.95].CGColor,
                     (id)[UIColor colorWithRed:0.95 green:0.65 blue:0.18 alpha:0.95].CGColor];
        case SCINotificationToneInfo:
        default:
            return @[(id)[UIColor colorWithRed:0.50 green:0.85 blue:1.00 alpha:0.95].CGColor,
                     (id)[UIColor colorWithRed:0.25 green:0.65 blue:0.90 alpha:0.95].CGColor];
    }
}

- (NSArray *)sciProgressColorsForTone:(SCINotificationTone)tone {
    if (_style == SCINotificationStyleMinimal) {
        switch (tone) {
            case SCINotificationToneError:
                return @[(id)[UIColor colorWithRed:1.00 green:0.80 blue:0.82 alpha:1.0].CGColor,
                         (id)[UIColor colorWithRed:0.90 green:0.40 blue:0.47 alpha:1.0].CGColor];
            case SCINotificationToneInfo:
                return @[(id)[UIColor colorWithRed:0.60 green:0.88 blue:0.98 alpha:1.0].CGColor,
                         (id)[UIColor colorWithRed:0.20 green:0.68 blue:0.90 alpha:1.0].CGColor];
            case SCINotificationToneSuccess:
            default:
                return @[(id)[UIColor colorWithRed:0.75 green:0.97 blue:0.88 alpha:1.0].CGColor,
                         (id)[UIColor colorWithRed:0.38 green:0.78 blue:0.60 alpha:1.0].CGColor];
        }
    }
    switch (tone) {
        case SCINotificationToneSuccess:
            return @[(id)[UIColor colorWithRed:0.66 green:1.00 blue:0.84 alpha:1.0].CGColor,
                     (id)[UIColor colorWithRed:0.29 green:0.83 blue:0.55 alpha:1.0].CGColor];
        case SCINotificationToneError:
            return @[(id)[UIColor colorWithRed:1.00 green:0.67 blue:0.71 alpha:1.0].CGColor,
                     (id)[UIColor colorWithRed:0.95 green:0.34 blue:0.44 alpha:1.0].CGColor];
        case SCINotificationToneWarning:
            return @[(id)[UIColor colorWithRed:1.00 green:0.86 blue:0.50 alpha:1.0].CGColor,
                     (id)[UIColor colorWithRed:0.95 green:0.65 blue:0.18 alpha:1.0].CGColor];
        case SCINotificationToneInfo:
        default:
            return @[(id)[UIColor colorWithRed:0.50 green:0.90 blue:1.00 alpha:1.0].CGColor,
                     (id)[UIColor colorWithRed:0.15 green:0.70 blue:0.95 alpha:1.0].CGColor];
    }
}

- (UIColor *)sciIconTintForTone:(SCINotificationTone)tone {
    if (_style == SCINotificationStyleIsland) return [UIColor colorWithWhite:1.0 alpha:0.95];

    if (_style == SCINotificationStyleMinimal) {
        switch (tone) {
            case SCINotificationToneSuccess:  return [UIColor colorWithRed:0.18 green:0.43 blue:0.34 alpha:1.0];
            case SCINotificationToneError:    return [UIColor colorWithRed:0.52 green:0.14 blue:0.21 alpha:1.0];
            case SCINotificationToneWarning:  return [UIColor colorWithRed:0.50 green:0.32 blue:0.05 alpha:1.0];
            case SCINotificationToneInfo:
            default:                          return [UIColor colorWithRed:0.08 green:0.35 blue:0.60 alpha:1.0];
        }
    }
    switch (tone) {
        case SCINotificationToneSuccess:  return [UIColor colorWithRed:0.12 green:0.29 blue:0.22 alpha:1.0];
        case SCINotificationToneError:    return [UIColor colorWithRed:0.40 green:0.08 blue:0.15 alpha:1.0];
        case SCINotificationToneWarning:  return [UIColor colorWithRed:0.40 green:0.26 blue:0.04 alpha:1.0];
        case SCINotificationToneInfo:
        default:                          return [UIColor colorWithRed:0.05 green:0.30 blue:0.60 alpha:1.0];
    }
}

- (UIColor *)sciGlowColorForTone:(SCINotificationTone)tone {
    switch (tone) {
        case SCINotificationToneSuccess:  return [UIColor colorWithRed:0.20 green:0.85 blue:0.55 alpha:1.0];
        case SCINotificationToneError:    return [UIColor colorWithRed:0.95 green:0.30 blue:0.40 alpha:1.0];
        case SCINotificationToneWarning:  return [UIColor colorWithRed:0.95 green:0.70 blue:0.18 alpha:1.0];
        case SCINotificationToneInfo:
        default:                          return [UIColor colorWithRed:0.30 green:0.65 blue:0.98 alpha:1.0];
    }
}

#pragma mark - Apply visuals

- (void)sciApplyVisualStyleAnimated:(BOOL)animated {
    BOOL island = SCINotifStyleIsIsland(_style);
    BOOL glow = (_style == SCINotificationStyleGlow);

    void (^apply)(void) = ^{
        self.chromeGradientLayer.colors = [self sciChromeColorsForTone:self->_tone];
        self.iconBadgeGradientLayer.colors = [self sciBadgeColorsForTone:self->_tone];
        NSArray *progColors = [self sciProgressColorsForTone:self->_tone];
        if (progColors.count > 0) {
            self.progressView.progressTintColor = [UIColor colorWithCGColor:(__bridge CGColorRef)progColors[1]];
            self.progressRingLayer.strokeColor = (__bridge CGColorRef)progColors[1];
        }
        self.progressView.trackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];

        // Self stays unclipped so shadow renders; blur + chrome self-clip via cornerRadius.
        self.clipsToBounds = NO;

        CGFloat radius;
        if (island) {
            radius = CGRectGetHeight(self.bounds) / 2.0;
            if (radius < 1.0) radius = kPillCorner;
        } else {
            radius = kPillCorner;
        }
        self.layer.cornerRadius = radius;
        self.blurView.layer.cornerRadius = radius;
        self.chromeOverlayView.layer.cornerRadius = radius;

        if (island) {
            self.chromeGradientLayer.opacity = 0.0;
            self.layer.shadowColor = UIColor.blackColor.CGColor;
            self.layer.shadowOpacity = 0.28;
            self.layer.shadowRadius = 14.0;
            self.layer.shadowOffset = CGSizeMake(0, 4);
            self.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.10] CGColor];
            self.iconBadgeView.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.12] CGColor];
        } else if (glow) {
            self.chromeGradientLayer.opacity = 0.9;
            UIColor *gc = [self sciGlowColorForTone:self->_tone];
            self.layer.shadowColor = gc.CGColor;
            self.layer.shadowOpacity = 0.55;
            self.layer.shadowRadius = 22.0;
            self.layer.shadowOffset = CGSizeMake(0, 5);
            self.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
            self.iconBadgeView.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.24] CGColor];
        } else if (self->_style == SCINotificationStyleColorful) {
            self.chromeGradientLayer.opacity = 0.9;
            self.layer.shadowColor = UIColor.blackColor.CGColor;
            self.layer.shadowOpacity = 0.22;
            self.layer.shadowRadius = 12.0;
            self.layer.shadowOffset = CGSizeMake(0, 4);
            self.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
            self.iconBadgeView.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.24] CGColor];
        } else {
            self.chromeGradientLayer.opacity = 0.0;
            self.layer.shadowColor = UIColor.clearColor.CGColor;
            self.layer.shadowOpacity = 0.0;
            self.layer.shadowRadius = 0.0;
            self.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.10] CGColor];
            self.iconBadgeView.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
        }
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:radius].CGPath;

        self.titleLabel.textColor = (self->_style == SCINotificationStyleMinimal)
            ? [UIColor colorWithWhite:1.0 alpha:0.95]
            : [UIColor colorWithWhite:1.0 alpha:0.98];
        self.subtitleLabel.textColor = (self->_style == SCINotificationStyleMinimal)
            ? [UIColor colorWithWhite:1.0 alpha:0.76]
            : [UIColor colorWithWhite:1.0 alpha:0.82];
    };

    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:apply completion:nil];
    } else {
        apply();
    }
}

- (CGFloat)sciSubtitleRowHeight {
    UIFont *f = self.subtitleLabel.font ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    return ceil(f.lineHeight);
}

- (CGFloat)sciProgressBarHeight {
    return MAX(2.0, ceil([self sciSubtitleRowHeight] / 3.0));
}

#pragma mark - Public setters

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    self.titleLabel.text = titleText ?: @"";
}

- (void)setSubtitleText:(NSString *)subtitleText {
    _subtitleText = [subtitleText copy];
    self.subtitleLabel.text = subtitleText ?: @"";
    self.subtitleLabel.hidden = (subtitleText.length == 0);
}

- (void)setIconSymbolName:(NSString *)iconSymbolName {
    _iconSymbolName = [iconSymbolName copy];
    NSString *name = iconSymbolName ?: SCINotifFallbackIconForTone(_tone);
    self.iconView.image = SCINotifIcon(name, 16.0, UIFontWeightSemibold);
}

- (void)setShowsProgress:(BOOL)showsProgress {
    _showsProgress = showsProgress;
    [self sciApplyProgressVisibility];
}

- (void)setIndeterminate:(BOOL)indeterminate {
    if (_indeterminate == indeterminate) return;
    _indeterminate = indeterminate;
    [self sciApplyProgressVisibility];
}

// While indeterminate, swap the tone-tinted badge for a neutral translucent
// disc so the spinner reads cleanly against any tone.
- (void)sciApplyProgressVisibility {
    BOOL island = SCINotifStyleIsIsland(_style);
    BOOL spinning = (_showsProgress && _indeterminate);
    BOOL determinate = (_showsProgress && !_indeterminate);

    self.iconView.hidden = spinning;
    self.iconBadgeGradientLayer.hidden = spinning;
    self.iconBadgeView.backgroundColor = spinning
        ? [UIColor colorWithWhite:1.0 alpha:0.10]
        : UIColor.clearColor;
    if (spinning) {
        self.iconBadgeView.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.18] CGColor];
        self.spinnerView.color = [UIColor whiteColor];
        [self.spinnerView startAnimating];
    } else {
        [self.spinnerView stopAnimating];
    }

    if (island) {
        self.progressRowContainer.hidden = YES;
        self.progressView.hidden = YES;
        self.progressRowHeightConstraint.constant = 0.0;
        self.progressHeightConstraint.constant = 0.0;
        self.progressRingTrackLayer.hidden = !determinate;
        self.progressRingLayer.hidden = !determinate;
        if (!determinate) self.progressRingLayer.strokeEnd = 0.0;
    } else {
        self.progressRingTrackLayer.hidden = YES;
        self.progressRingLayer.hidden = YES;
        self.progressRowContainer.hidden = !determinate;
        if (determinate) {
            self.progressRowHeightConstraint.constant = [self sciSubtitleRowHeight];
            self.progressHeightConstraint.constant = [self sciProgressBarHeight];
            self.progressView.hidden = NO;
        } else {
            self.progressRowHeightConstraint.constant = 0.0;
            self.progressHeightConstraint.constant = 0.0;
            self.progressView.hidden = YES;
            self.progressView.layer.cornerRadius = 0.0;
        }
    }
}

- (void)setShowsCancelButton:(BOOL)showsCancelButton {
    _showsCancelButton = showsCancelButton;
    self.closeButton.hidden = !showsCancelButton;
    self.textTrailingWithButtonConstraint.active = showsCancelButton;
    self.textTrailingWithoutButtonConstraint.active = !showsCancelButton;
}

- (void)applyTone:(SCINotificationTone)tone animated:(BOOL)animated {
    _tone = tone;
    [self sciApplyVisualStyleAnimated:animated];
    if (!self.iconSymbolName.length) {
        self.iconView.image = SCINotifIcon(SCINotifFallbackIconForTone(tone), 16.0, UIFontWeightSemibold);
    }
    self.iconView.tintColor = [self sciIconTintForTone:tone];
}

- (void)setProgress:(float)progress animated:(BOOL)animated {
    _progress = MAX(0.0f, MIN(1.0f, progress));
    if (_indeterminate) {
        _indeterminate = NO;
        [self sciApplyProgressVisibility];
    }
    if (SCINotifStyleIsIsland(_style)) {
        [CATransaction begin];
        if (animated) {
            [CATransaction setAnimationDuration:0.3];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        } else {
            [CATransaction setDisableActions:YES];
        }
        self.progressRingLayer.strokeEnd = _progress;
        [CATransaction commit];
    } else {
        if (animated) {
            [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self.progressView.progress = self->_progress;
            } completion:nil];
        } else {
            self.progressView.progress = _progress;
        }
    }
}

// Width fits text + paddings (+ cancel button if shown), clamped per style.
// Height bumps to "tall" when subtitle or progress is on.
- (void)refreshSizeAnimated:(BOOL)animated {
    BOOL island = SCINotifStyleIsIsland(_style);
    BOOL hasSubtitle = (self.subtitleText.length > 0);
    BOOL hasProgress = (self.showsProgress && !self.indeterminate);
    BOOL hasButton = self.showsCancelButton;

    CGFloat targetH;
    if (island) {
        targetH = (hasSubtitle || hasProgress) ? kDynamicTallHeight : kDynamicPillHeight;
    } else {
        targetH = (hasSubtitle || hasProgress) ? kToastTallHeight : kPillHeight;
    }

    CGFloat targetW;
    UIFont *titleFont = self.titleLabel.font ?: [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    UIFont *subFont   = self.subtitleLabel.font ?: [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];

    CGFloat titleW = self.titleText.length
        ? ceil([self.titleText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, titleFont.lineHeight)
                                             options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                          attributes:@{NSFontAttributeName: titleFont}
                                             context:nil].size.width)
        : 0;
    CGFloat subW = self.subtitleText.length
        ? ceil([self.subtitleText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, subFont.lineHeight)
                                                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                             attributes:@{NSFontAttributeName: subFont}
                                                context:nil].size.width)
        : 0;
    CGFloat textW = MAX(titleW, subW);

    CGFloat fixedW = kHorizontalPad + kIconBadgeSize + 10.0 + kHorizontalPad;
    if (hasButton) fixedW += 24.0 + 13.0 + 10.0;
    CGFloat minW = island ? kDynamicMinWidth : 200.0;
    CGFloat maxW = island ? kDynamicMaxWidth : kPillWidth;
    targetW = MIN(maxW, MAX(minW, ceil(textW) + fixedW + 6.0));

    if (fabs(self.widthConstraint.constant - targetW) < 0.5 &&
        fabs(self.heightConstraint.constant - targetH) < 0.5) {
        return;
    }

    self.widthConstraint.constant = targetW;
    self.heightConstraint.constant = targetH;

    if (!animated || !self.superview) {
        [self.superview layoutIfNeeded];
        return;
    }

    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self.superview layoutIfNeeded];
    } completion:nil];
}

- (void)pulseIcon {
    [UIView animateKeyframesWithDuration:0.32 delay:0 options:UIViewKeyframeAnimationOptionCalculationModeCubic animations:^{
        [UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:0.55 animations:^{
            self.iconBadgeView.transform = CGAffineTransformMakeScale(1.10, 1.10);
        }];
        [UIView addKeyframeWithRelativeStartTime:0.55 relativeDuration:0.45 animations:^{
            self.iconBadgeView.transform = CGAffineTransformIdentity;
        }];
    } completion:nil];
}

#pragma mark - Gestures

- (void)sciTapped {
    if (self.onTap) self.onTap(self);
}

- (void)sciCloseTapped {
    if (self.onCancel) self.onCancel(self);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *touched = touch.view;
    if (touched && [touched isDescendantOfView:self.closeButton]) return NO;
    return YES;
}

// Direction follows the pill's edge: top → swipe up, bottom → swipe down.
- (void)sciPan:(UIPanGestureRecognizer *)pan {
    BOOL bottom = (_position == SCINotificationPositionBottom);
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
            if (dismissTrans < 0) delta *= 0.25;
            self.center = CGPointMake(_panOriginCenter.x, _panOriginCenter.y + delta);
            CGFloat fade = MIN(1.0, MAX(0.0, dismissTrans / 60.0));
            self.alpha = 1.0 - (fade * 0.5);
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            BOOL away = (dismissTrans > 20.0) || (velocity * sign > 300.0);
            if (away && self.onSwipeDismiss) {
                self.onSwipeDismiss(self);
            } else {
                [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                                    options:UIViewAnimationOptionCurveEaseOut animations:^{
                    self.center = self->_panOriginCenter;
                    self.alpha = 1.0;
                } completion:nil];
            }
            break;
        }
        default: break;
    }
}

@end
