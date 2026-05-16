#import "SCIGallerySheetViewController.h"

static CGFloat const kSheetCardCornerRadius = 22.0;
static CGFloat const kSheetGrabberTop = 8.0;
static CGFloat const kSheetGrabberWidth = 36.0;
static CGFloat const kSheetGrabberHeight = 5.0;
static CGFloat const kSheetTitleTop = 18.0;
static CGFloat const kSheetTitleHeight = 28.0;
static CGFloat const kSheetHorizontalInset = 16.0;
static CGFloat const kSheetBottomContentInset = 24.0;
static CGFloat const kSheetDismissVelocity = 900.0;
static CGFloat const kSheetDismissProgress = 0.28;
static CGFloat const kSheetPanHeaderHeight = 62.0;

@interface SCIGallerySheetViewController () <UIGestureRecognizerDelegate, UIScrollViewDelegate>
@property (nonatomic, strong, readwrite) UIView *card;
@property (nonatomic, strong, readwrite) UIScrollView *scrollView;
@property (nonatomic, strong, readwrite) UIStackView *contentStack;
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UIView *grabber;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property (nonatomic, strong) NSLayoutConstraint *cardBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardHeightConstraint;
@property (nonatomic, assign) CGFloat compactHeight;
@property (nonatomic, assign) CGFloat maxHeight;
@property (nonatomic, assign) CGFloat panStartHeight;
@property (nonatomic, assign) CGFloat panStartBottomOffset;
@property (nonatomic, assign) BOOL didAnimateIn;
@property (nonatomic, assign) BOOL isDismissingSheet;
@end

@implementation SCIGallerySheetViewController

- (instancetype)init {
	self = [super init];
	if (!self) return nil;

	self.modalPresentationStyle = UIModalPresentationOverFullScreen;
	self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

	return self;
}

- (CGFloat)preferredCardHeight {
	CGFloat h = self.view.bounds.size.height ?: UIScreen.mainScreen.bounds.size.height;
	return MAX(330.0, MIN(430.0, h * 0.60));
}

- (CGFloat)maxCardHeight {
	CGFloat h = self.view.bounds.size.height ?: UIScreen.mainScreen.bounds.size.height;
	return MAX([self preferredCardHeight], h - self.view.safeAreaInsets.top - 12.0);
}

- (BOOL)scrollIsAtTop {
	return self.scrollView.contentOffset.y <= -self.scrollView.adjustedContentInset.top + 1.0;
}

- (CGFloat)clampedHeight:(CGFloat)height {
	return MIN(MAX(height, self.compactHeight), self.maxHeight);
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.clearColor;

	[self setupBackdrop];
	[self setupCard];
	[self setupGrabber];
	[self setupTitleLabel];
	[self setupContent];
	[self setupGestures];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGFloat oldCompact = self.compactHeight;
	self.compactHeight = [self preferredCardHeight];
	self.maxHeight = [self maxCardHeight];

	if (!self.didAnimateIn) {
		self.cardHeightConstraint.constant = self.compactHeight;
		self.cardBottomConstraint.constant = self.compactHeight;
		return;
	}

	if (fabs(oldCompact - self.compactHeight) > 1.0) {
		self.cardHeightConstraint.constant = [self clampedHeight:self.cardHeightConstraint.constant];
		self.cardBottomConstraint.constant = MIN(self.cardBottomConstraint.constant, self.cardHeightConstraint.constant);
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	if (self.didAnimateIn) return;

	self.didAnimateIn = YES;
	self.compactHeight = [self preferredCardHeight];
	self.maxHeight = [self maxCardHeight];
	self.cardHeightConstraint.constant = self.compactHeight;
	self.cardBottomConstraint.constant = self.compactHeight;

	[self.view layoutIfNeeded];

	self.cardBottomConstraint.constant = 0.0;

	[UIView animateWithDuration:0.28
						  delay:0.0
		 usingSpringWithDamping:0.92
		  initialSpringVelocity:0.45
						options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
					 animations:^{
		self.backdrop.alpha = 1.0;
		[self.view layoutIfNeeded];
	} completion:nil];
}

#pragma mark - Setup

- (void)setupBackdrop {
	self.backdrop = [UIView new];
	self.backdrop.translatesAutoresizingMaskIntoConstraints = NO;
	self.backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
	self.backdrop.alpha = 0.0;

	[self.view addSubview:self.backdrop];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backdropTapped)];
	[self.backdrop addGestureRecognizer:tap];

	[NSLayoutConstraint activateConstraints:@[
		[self.backdrop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.backdrop.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.backdrop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.backdrop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
	]];
}

- (void)setupCard {
	self.compactHeight = [self preferredCardHeight];
	self.maxHeight = [self maxCardHeight];

	self.card = [UIView new];
	self.card.translatesAutoresizingMaskIntoConstraints = NO;
	self.card.backgroundColor = UIColor.secondarySystemBackgroundColor;
	self.card.opaque = YES;
	self.card.clipsToBounds = YES;
	self.card.layer.cornerRadius = kSheetCardCornerRadius;
	self.card.layer.cornerCurve = kCACornerCurveContinuous;
	self.card.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;

	[self.view addSubview:self.card];

	self.cardBottomConstraint = [self.card.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:self.compactHeight];
	self.cardHeightConstraint = [self.card.heightAnchor constraintEqualToConstant:self.compactHeight];

	[NSLayoutConstraint activateConstraints:@[
		[self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		self.cardBottomConstraint,
		self.cardHeightConstraint,
	]];
}

- (void)setupGrabber {
	self.grabber = [UIView new];
	self.grabber.translatesAutoresizingMaskIntoConstraints = NO;
	self.grabber.backgroundColor = UIColor.systemFillColor;
	self.grabber.layer.cornerRadius = kSheetGrabberHeight / 2.0;

	[self.card addSubview:self.grabber];

	[NSLayoutConstraint activateConstraints:@[
		[self.grabber.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:kSheetGrabberTop],
		[self.grabber.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
		[self.grabber.widthAnchor constraintEqualToConstant:kSheetGrabberWidth],
		[self.grabber.heightAnchor constraintEqualToConstant:kSheetGrabberHeight],
	]];
}

- (void)setupTitleLabel {
	self.titleLabel = [UILabel new];
	self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
	self.titleLabel.textColor = UIColor.labelColor;
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.text = self.sheetTitle ?: @"";

	[self.card addSubview:self.titleLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.titleLabel.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:kSheetTitleTop],
		[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:kSheetHorizontalInset],
		[self.titleLabel.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-kSheetHorizontalInset],
		[self.titleLabel.heightAnchor constraintEqualToConstant:kSheetTitleHeight],
	]];
}

- (void)setupContent {
	self.scrollView = [UIScrollView new];
	self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.scrollView.backgroundColor = UIColor.clearColor;
	self.scrollView.showsVerticalScrollIndicator = NO;
	self.scrollView.alwaysBounceVertical = YES;
	self.scrollView.delaysContentTouches = NO;
	self.scrollView.delegate = self;
	self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

	[self.card addSubview:self.scrollView];

	self.contentStack = [UIStackView new];
	self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
	self.contentStack.axis = UILayoutConstraintAxisVertical;
	self.contentStack.spacing = 10.0;

	[self.scrollView addSubview:self.contentStack];

	[NSLayoutConstraint activateConstraints:@[
		[self.scrollView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
		[self.scrollView.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
		[self.scrollView.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
		[self.scrollView.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],

		[self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:8.0],
		[self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:kSheetHorizontalInset],
		[self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-kSheetHorizontalInset],
		[self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-kSheetBottomContentInset],
	]];
}

- (void)setupGestures {
	self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
	self.panGesture.delegate = self;
	self.panGesture.cancelsTouchesInView = NO;
	[self.card addGestureRecognizer:self.panGesture];
}

#pragma mark - Title sync

- (void)setSheetTitle:(NSString *)sheetTitle {
	_sheetTitle = [sheetTitle copy];
	self.titleLabel.text = sheetTitle ?: @"";
}

#pragma mark - Dismiss

- (void)backdropTapped {
	[self dismissAnimated];
}

- (void)dismissAnimated {
	if (self.isDismissingSheet) return;

	self.isDismissingSheet = YES;
	[self.view layoutIfNeeded];

	self.cardBottomConstraint.constant = MAX(self.cardHeightConstraint.constant, 1.0);

	[UIView animateWithDuration:0.22
						  delay:0.0
						options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
					 animations:^{
		self.backdrop.alpha = 0.0;
		[self.view layoutIfNeeded];
	} completion:^(BOOL finished) {
		(void)finished;
		[self dismissViewControllerAnimated:NO completion:nil];
	}];
}

#pragma mark - Pan

- (void)settleSheetToHeight:(CGFloat)height {
	self.cardBottomConstraint.constant = 0.0;
	self.cardHeightConstraint.constant = [self clampedHeight:height];

	[UIView animateWithDuration:0.24
						  delay:0.0
		 usingSpringWithDamping:0.90
		  initialSpringVelocity:0.25
						options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
					 animations:^{
		self.backdrop.alpha = 1.0;
		[self.view layoutIfNeeded];
	} completion:nil];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
	CGFloat dy = [pan translationInView:self.view].y;
	CGFloat velocity = [pan velocityInView:self.view].y;

	if (pan.state == UIGestureRecognizerStateBegan) {
		self.panStartHeight = self.cardHeightConstraint.constant;
		self.panStartBottomOffset = self.cardBottomConstraint.constant;
		return;
	}

	if (pan.state == UIGestureRecognizerStateChanged) {
		if (dy < 0.0) {
			self.cardBottomConstraint.constant = 0.0;
			self.cardHeightConstraint.constant = [self clampedHeight:self.panStartHeight - dy];
		} else {
			self.cardHeightConstraint.constant = self.panStartHeight;
			self.cardBottomConstraint.constant = MAX(0.0, self.panStartBottomOffset + dy);

			CGFloat progress = MIN(1.0, self.cardBottomConstraint.constant / MAX(self.panStartHeight, 1.0));
			self.backdrop.alpha = 1.0 - progress * 0.85;
		}

		[self.view layoutIfNeeded];
		return;
	}

	if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled) return;

	CGFloat offset = self.cardBottomConstraint.constant;
	BOOL dismiss = offset > self.panStartHeight * kSheetDismissProgress || velocity > kSheetDismissVelocity;

	if (dismiss) {
		[self dismissAnimated];
		return;
	}

	BOOL expand = velocity < -300.0 || self.cardHeightConstraint.constant > (self.compactHeight + self.maxHeight) * 0.5;
	[self settleSheetToHeight:(expand ? self.maxHeight : self.compactHeight)];
}

#pragma mark - Gestures

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
	if (gestureRecognizer != self.panGesture) return YES;

	UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
	CGPoint velocity = [pan velocityInView:self.card];
	if (fabs(velocity.x) > fabs(velocity.y)) return NO;

	CGPoint cardPoint = [pan locationInView:self.card];
	BOOL startedInHeader = cardPoint.y <= kSheetPanHeaderHeight;

	if (startedInHeader) return YES;

	if (velocity.y > 0.0 && [self scrollIsAtTop]) return YES;

	return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
	return NO;
}

#pragma mark - Content API

- (void)addSectionTitle:(NSString *)title {
	UILabel *label = [UILabel new];
	label.text = title.uppercaseString;
	label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
	label.textColor = UIColor.secondaryLabelColor;

	[self.contentStack addArrangedSubview:label];
	[self.contentStack setCustomSpacing:6.0 afterView:label];
}

- (void)addCardRow:(UIView *)row {
	if (!row) return;

	[self.contentStack addArrangedSubview:row];
	[self.contentStack setCustomSpacing:14.0 afterView:row];
}

- (void)addContentView:(UIView *)view {
	if (!view) return;

	[self.contentStack addArrangedSubview:view];
	[self.contentStack setCustomSpacing:14.0 afterView:view];
}

@end