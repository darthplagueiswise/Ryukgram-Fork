#import "SCIColorPickerSheet.h"
#import "../Localization/SCILocalization.h"
#import "SCISheetDetent.h"
#import <objc/runtime.h>

// Solid mode presents UIColorPickerViewController directly — embedding it
// breaks the eyedropper dismiss path under IGNavigationController. Gradient
// mode keeps the Start/End swatches with an embedded picker.

static char kSCIPickerSelfRetainKey;
static UISheetPresentationControllerDetentIdentifier const kSCIPickerFitDetentID = @"sci_color_picker_fit";

@interface SCIColorPickerSheet () <UIColorPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, assign) SCIColorPickerSheetMode mode;
@property (nonatomic, strong) UIColor *startColor;
@property (nonatomic, strong, nullable) UIColor *endColor;
@property (nonatomic, copy) SCIColorPickerSheetApplyHandler applyHandler;
@property (nonatomic, assign) BOOL editingEndSlot;
@property (nonatomic, strong) UIColorPickerViewController *embeddedPicker;
@property (nonatomic, weak) UIColorPickerViewController *standalonePicker;
@property (nonatomic, strong) UIStackView *swatchRow;
@property (nonatomic, strong) UIButton *startSwatch;
@property (nonatomic, strong) UIButton *endSwatch;
@property (nonatomic, assign) CFTimeInterval lastApply;
@end

@implementation SCIColorPickerSheet

+ (instancetype)sheetWithMode:(SCIColorPickerSheetMode)mode
				   startColor:(UIColor *)start
					 endColor:(UIColor *)end
				 applyHandler:(SCIColorPickerSheetApplyHandler)handler {
	SCIColorPickerSheet *vc = [SCIColorPickerSheet new];
	vc.mode = mode;
	vc.startColor = start ?: UIColor.systemPinkColor;
	vc.endColor = end ?: UIColor.systemPurpleColor;
	vc.applyHandler = handler;
	return vc;
}

#pragma mark - Sheet

- (void)configureSheetForViewController:(UIViewController *)vc {
	vc.modalPresentationStyle = UIModalPresentationPageSheet;
	vc.presentationController.delegate = self;

	UISheetPresentationController *sheet = vc.sheetPresentationController;
	if (!sheet) return;

	BOOL solid = (vc != self);

	// Tuned custom detent on iOS 16+; medium/large fallback keeps it compiling
	// and working on the iOS 15 SDK (SCICustomSheetDetent returns nil there).
	UISheetPresentationControllerDetent *fit =
		SCICustomSheetDetent(kSCIPickerFitDetentID, ^CGFloat(CGFloat max) {
			CGFloat wanted = max * (solid ? 0.65 : 0.67) + 5.0;
			CGFloat minimum = MIN(solid ? 570.0 : 600.0, max * (solid ? 0.79 : 0.82));
			CGFloat maximum = max * (solid ? 0.79 : 0.82);
			return MIN(MAX(wanted, minimum), maximum);
		});

	if (fit) {
		sheet.detents = solid ? @[ fit, UISheetPresentationControllerDetent.largeDetent ] : @[ fit ];
		sheet.selectedDetentIdentifier = kSCIPickerFitDetentID;
	} else {
		sheet.detents = @[
			UISheetPresentationControllerDetent.mediumDetent,
			UISheetPresentationControllerDetent.largeDetent
		];
		sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
	}

	sheet.largestUndimmedDetentIdentifier = nil;
	sheet.prefersGrabberVisible = YES;
	sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;

	if ([sheet respondsToSelector:@selector(setPreferredCornerRadius:)]) {
		sheet.preferredCornerRadius = 42.0;
	}
}
#pragma mark - Picker

- (UIColorPickerViewController *)makePickerSeededWith:(UIColor *)seed {
	UIColorPickerViewController *picker = [UIColorPickerViewController new];
	picker.delegate = self;
	picker.supportsAlpha = NO;
	picker.title = SCILocalized(@"Colors");
	picker.selectedColor = seed ?: UIColor.systemPinkColor;
	picker.view.backgroundColor = UIColor.clearColor;
	return picker;
}

- (UIColorPickerViewController *)makeStandalonePickerSeededWith:(UIColor *)seed {
	UIColorPickerViewController *picker = [self makePickerSeededWith:seed];
	objc_setAssociatedObject(picker, &kSCIPickerSelfRetainKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	self.standalonePicker = picker;
	[self configureSheetForViewController:picker];
	return picker;
}

- (void)tearDownStandalonePicker:(UIColorPickerViewController *)picker {
	if (!picker) return;
	picker.delegate = nil;
	objc_setAssociatedObject(picker, &kSCIPickerSelfRetainKey, nil, OBJC_ASSOCIATION_ASSIGN);
	if (self.standalonePicker == picker) self.standalonePicker = nil;
}

#pragma mark - Present

- (void)presentFromViewController:(UIViewController *)presenter {
	if (!presenter) return;

	if (_mode == SCIColorPickerSheetModeSolid) {
		UIColorPickerViewController *picker = [self makeStandalonePickerSeededWith:_startColor];
		[self fireApplyForced:YES];
		[presenter presentViewController:picker animated:YES completion:nil];
		return;
	}

	[self configureSheetForViewController:self];
	[presenter presentViewController:self animated:YES completion:nil];
}

#pragma mark - Gradient host

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.clearColor;
	if (_mode != SCIColorPickerSheetModeGradient) return;

	[self buildSwatchRow];
	[self buildEmbeddedPicker];
	[self layoutGradient];
	[self refreshSwatches];
	[self fireApplyForced:YES];
}

- (UIButton *)makeSwatch {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.layer.cornerRadius = 20.0;
	button.layer.masksToBounds = YES;
	button.layer.borderColor = UIColor.separatorColor.CGColor;
	button.layer.borderWidth = 2.0;

	[NSLayoutConstraint activateConstraints:@[
		[button.widthAnchor constraintEqualToConstant:40.0],
		[button.heightAnchor constraintEqualToConstant:40.0]
	]];

	return button;
}

- (UILabel *)makeLabel:(NSString *)title {
	UILabel *label = [UILabel new];
	label.text = title;
	label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
	label.textColor = UIColor.secondaryLabelColor;
	return label;
}

- (UIStackView *)makeSwatchColumnWithTitle:(NSString *)title swatch:(UIButton *)swatch {
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
		[self makeLabel:title],
		swatch
	]];

	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 6.0;
	return stack;
}

- (void)buildSwatchRow {
	_startSwatch = [self makeSwatch];
	_endSwatch = [self makeSwatch];

	[_startSwatch addTarget:self action:@selector(selectStartSlot) forControlEvents:UIControlEventTouchUpInside];
	[_endSwatch addTarget:self action:@selector(selectEndSlot) forControlEvents:UIControlEventTouchUpInside];

	_swatchRow = [[UIStackView alloc] initWithArrangedSubviews:@[
		[self makeSwatchColumnWithTitle:SCILocalized(@"Start") swatch:_startSwatch],
		[self makeSwatchColumnWithTitle:SCILocalized(@"End") swatch:_endSwatch]
	]];

	_swatchRow.axis = UILayoutConstraintAxisHorizontal;
	_swatchRow.alignment = UIStackViewAlignmentCenter;
	_swatchRow.spacing = 36.0;
	_swatchRow.translatesAutoresizingMaskIntoConstraints = NO;
}

- (void)buildEmbeddedPicker {
	_embeddedPicker = [self makePickerSeededWith:_startColor];

	[self addChildViewController:_embeddedPicker];
	_embeddedPicker.view.translatesAutoresizingMaskIntoConstraints = NO;
	_embeddedPicker.view.backgroundColor = UIColor.clearColor;
}

- (void)layoutGradient {
	[self.view addSubview:_swatchRow];
	[self.view addSubview:_embeddedPicker.view];
	[_embeddedPicker didMoveToParentViewController:self];

	UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

	[NSLayoutConstraint activateConstraints:@[
		[_swatchRow.topAnchor constraintEqualToAnchor:guide.topAnchor constant:14.0],
		[_swatchRow.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],

		[_embeddedPicker.view.topAnchor constraintEqualToAnchor:_swatchRow.bottomAnchor constant:10.0],
		[_embeddedPicker.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_embeddedPicker.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_embeddedPicker.view.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
	]];
}

- (void)refreshSwatches {
	BOOL end = self.editingEndSlot;

	self.startSwatch.backgroundColor = self.startColor;
	self.endSwatch.backgroundColor = self.endColor;

	self.startSwatch.layer.borderColor = (end ? UIColor.separatorColor : UIColor.labelColor).CGColor;
	self.endSwatch.layer.borderColor = (end ? UIColor.labelColor : UIColor.separatorColor).CGColor;

	self.startSwatch.layer.borderWidth = end ? 2.0 : 3.0;
	self.endSwatch.layer.borderWidth = end ? 3.0 : 2.0;
}

- (void)selectStartSlot {
	_editingEndSlot = NO;
	_embeddedPicker.selectedColor = _startColor;
	[self refreshSwatches];
}

- (void)selectEndSlot {
	_editingEndSlot = YES;
	_embeddedPicker.selectedColor = _endColor;
	[self refreshSwatches];
}

#pragma mark - Picker delegate

- (void)applyPickedColor:(UIColor *)color throttle:(BOOL)throttle {
	if (![color isKindOfClass:UIColor.class]) return;

	UIColor *opaque = [color colorWithAlphaComponent:1.0];

	if (_mode == SCIColorPickerSheetModeGradient) {
		if (_editingEndSlot) _endColor = opaque;
		else _startColor = opaque;
		[self refreshSwatches];
	} else {
		_startColor = opaque;
	}

	[self fireApplyForced:!throttle];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
				   didSelectColor:(UIColor *)color
					 continuously:(BOOL)continuously {
	[self applyPickedColor:color throttle:continuously];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
	[self applyPickedColor:viewController.selectedColor throttle:NO];

	if (viewController == self.standalonePicker) {
		[self tearDownStandalonePicker:viewController];
	}
}

#pragma mark - Presentation delegate

- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
	return YES;
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
	UIViewController *presented = presentationController.presentedViewController;

	if (presented == self.standalonePicker) {
		[self tearDownStandalonePicker:(UIColorPickerViewController *)presented];
		return;
	}

	if (presented == self) {
		[self fireApplyForced:YES];
	}
}

#pragma mark - Apply

- (void)fireApplyForced:(BOOL)forced {
	CFTimeInterval now = CACurrentMediaTime();

	if (!forced && now - _lastApply < 0.05) return;

	_lastApply = now;

	if (_applyHandler) {
		_applyHandler(_mode, _startColor, (_mode == SCIColorPickerSheetModeGradient) ? _endColor : nil);
	}
}

#pragma mark - Cleanup

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];

	if (_mode == SCIColorPickerSheetModeGradient && self.isBeingDismissed) {
		[self fireApplyForced:YES];
	}
}

- (void)dealloc {
	_embeddedPicker.delegate = nil;
	[self tearDownStandalonePicker:_standalonePicker];
}

@end