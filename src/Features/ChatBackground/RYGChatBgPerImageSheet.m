#import "RYGChatBgPerImageSheet.h"
#import "RYGChatBackgroundManager.h"
#import "RYGChatBgVideoView.h"
#import "RYGChatBgEditor.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../UI/RYGColorPickerSheet.h"
#import "../../Utils.h"

typedef NS_ENUM(NSInteger, RYGRow) {
	RYGRowOpacity,
	RYGRowBlur,
	RYGRowDim,
	RYGRowAutoBubble,
	RYGRowBubbleSides,
	RYGRowGradient,
	RYGRowGradientDir,
	RYGRowBubbleColor,
	RYGRowTextColor,
	RYGRowReset,
};

static NSString *const kCell = @"cell";

@interface RYGChatBgPerImageSheet () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *asset;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) RYGChatBgVideoView *videoPreview;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSNumber *> *rows;
@end

@implementation RYGChatBgPerImageSheet

- (instancetype)initWithAsset:(NSString *)asset {
	if ((self = [super init])) {
		_asset = [asset copy];
		self.title = RYGLocalized(@"Image Settings");
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:RYGLocalized(@"Done") style:UIBarButtonItemStyleDone target:self action:@selector(done)];

	_preview = [UIImageView new];
	_preview.contentMode = UIViewContentModeScaleAspectFill;
	_preview.clipsToBounds = YES;
	_preview.layer.cornerRadius = 16;
	_preview.layer.cornerCurve = kCACornerCurveContinuous;
	_preview.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_preview];

	if ([RYGChatBackgroundManager isVideoAsset:self.asset]) {
		_videoPreview = [[RYGChatBgVideoView alloc] initWithFrame:CGRectZero];
		_videoPreview.layer.cornerRadius = 16;
		_videoPreview.layer.cornerCurve = kCACornerCurveContinuous;
		_videoPreview.clipsToBounds = YES;
		_videoPreview.translatesAutoresizingMaskIntoConstraints = NO;
		[_preview addSubview:_videoPreview];
	}

	_dimView = [UIView new];
	_dimView.backgroundColor = UIColor.blackColor;
	_dimView.userInteractionEnabled = NO;
	_dimView.translatesAutoresizingMaskIntoConstraints = NO;
	[_preview addSubview:_dimView];

	_tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_tableView.dataSource = self;
	_tableView.delegate = self;
	_tableView.backgroundColor = self.view.backgroundColor;
	_tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
	_tableView.translatesAutoresizingMaskIntoConstraints = NO;
	[_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kCell];
	[self.view addSubview:_tableView];

	[NSLayoutConstraint activateConstraints:@[
		[_preview.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
		[_preview.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_preview.widthAnchor constraintEqualToConstant:210],
		[_preview.heightAnchor constraintEqualToConstant:294],

		[_dimView.topAnchor constraintEqualToAnchor:_preview.topAnchor],
		[_dimView.leadingAnchor constraintEqualToAnchor:_preview.leadingAnchor],
		[_dimView.trailingAnchor constraintEqualToAnchor:_preview.trailingAnchor],
		[_dimView.bottomAnchor constraintEqualToAnchor:_preview.bottomAnchor],

		[_tableView.topAnchor constraintEqualToAnchor:_preview.bottomAnchor constant:12],
		[_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	if (_videoPreview) [NSLayoutConstraint activateConstraints:@[
		[_videoPreview.topAnchor constraintEqualToAnchor:_preview.topAnchor],
		[_videoPreview.leadingAnchor constraintEqualToAnchor:_preview.leadingAnchor],
		[_videoPreview.trailingAnchor constraintEqualToAnchor:_preview.trailingAnchor],
		[_videoPreview.bottomAnchor constraintEqualToAnchor:_preview.bottomAnchor],
	]];

	_preview.userInteractionEnabled = YES;
	[_preview addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(editMedia)]];
	[self installEditBadge];

	[self rebuildRows];
	[self renderPreview];
}

- (void)installEditBadge {
	UIImageView *badge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"crop.rotate"]];
	badge.tintColor = UIColor.whiteColor;
	badge.contentMode = UIViewContentModeScaleAspectFit;
	badge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
	badge.layer.cornerRadius = 14;
	badge.clipsToBounds = YES;
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:badge];
	[NSLayoutConstraint activateConstraints:@[
		[badge.trailingAnchor constraintEqualToAnchor:_preview.trailingAnchor constant:-8],
		[badge.bottomAnchor constraintEqualToAnchor:_preview.bottomAnchor constant:-8],
		[badge.widthAnchor constraintEqualToConstant:28],
		[badge.heightAnchor constraintEqualToConstant:28],
	]];
}

- (void)editMedia {
	[RYGChatBgEditor reEditAsset:self.asset from:self completion:^(NSString *newRel) {
		if (!newRel) return;
		[[RYGChatBackgroundManager shared] replaceAsset:self.asset withAsset:newRel];
		self.asset = newRel;
		[self rebuildRows];
		[self.tableView reloadData];
		[self renderPreview];
	}];
}

- (void)rebuildRows {
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	NSMutableArray *rows = [@[@(RYGRowOpacity), @(RYGRowBlur), @(RYGRowDim), @(RYGRowAutoBubble)] mutableCopy];
	if ([m autoBubbleEnabledForAsset:self.asset]) {
		[rows addObjectsFromArray:@[@(RYGRowBubbleSides), @(RYGRowGradient)]];
		if ([m bubbleGradientForAsset:self.asset]) [rows addObject:@(RYGRowGradientDir)];
		[rows addObjectsFromArray:@[@(RYGRowBubbleColor), @(RYGRowTextColor)]];
	}
	[rows addObject:@(RYGRowReset)];
	self.rows = rows;
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renderPreview) object:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)prev {
	[super traitCollectionDidChange:prev];
	if (prev.userInterfaceStyle != self.traitCollection.userInterfaceStyle) [self renderPreview];
}

- (BOOL)isDark {
	return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

- (void)done {
	[self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)renderPreview {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renderPreview) object:nil];

	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	self.preview.alpha = [m effectiveOpacityForAsset:self.asset];
	self.preview.backgroundColor = self.isDark ? UIColor.blackColor : UIColor.whiteColor;

	if (self.videoPreview) {
		self.preview.image = [m imageForAsset:self.asset];
		self.dimView.alpha = 0;
		self.videoPreview.videoURL = [m urlForRelativeAsset:self.asset];
		[self.videoPreview setBlurRadius:(CGFloat)[m effectiveBlurForAsset:self.asset]
									  dim:(self.isDark ? (CGFloat)[m effectiveDimForAsset:self.asset] : 0.0)];
		[self.videoPreview play];
		return;
	}

	self.preview.image = [m processedImageForAsset:self.asset darkAppearance:self.isDark];
	self.dimView.alpha = self.isDark ? [m effectiveDimForAsset:self.asset] : 0;
}

- (void)quickPreview {
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	self.preview.alpha = [m effectiveOpacityForAsset:self.asset];
	self.dimView.alpha = self.isDark ? [m effectiveDimForAsset:self.asset] : 0;
}

- (void)renderPreviewSoon {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renderPreview) object:nil];
	[self performSelector:@selector(renderPreview) withObject:nil afterDelay:0.08];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return self.rows.count;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return RYGLocalized(@"Reset sets opacity to 1.0, blur to 0, dim to 0.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCell forIndexPath:ip];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.imageView.image = nil;

	NSInteger tag = self.rows[ip.row].integerValue;
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];

	if (tag == RYGRowReset) {
		cell.textLabel.text = RYGLocalized(@"Reset");
		cell.textLabel.textColor = UIColor.systemRedColor;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		return cell;
	}

	if (tag == RYGRowAutoBubble) {
		cell.textLabel.text = RYGLocalized(@"Auto bubble color");
		cell.textLabel.textColor = UIColor.labelColor;

		UISwitch *sw = [UISwitch new];
		sw.on = [m autoBubbleEnabledForAsset:self.asset];
		sw.onTintColor = [RYGUtils RYGColor_Primary];
		[sw addTarget:self action:@selector(autoBubbleToggled:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		return cell;
	}

	if (tag == RYGRowBubbleSides) {
		cell.textLabel.text = RYGLocalized(@"Apply to");

		UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[
			RYGLocalized(@"Other"), RYGLocalized(@"Me"), RYGLocalized(@"Both")
		]];
		seg.selectedSegmentIndex = [m bubbleSidesForAsset:self.asset];
		seg.selectedSegmentTintColor = [RYGUtils RYGColor_Primary];
		[seg addTarget:self action:@selector(sidesChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = seg;
		cell.textLabel.textColor = UIColor.labelColor;
		return cell;
	}

	if (tag == RYGRowGradient) {
		cell.textLabel.text = RYGLocalized(@"Gradient");
		cell.textLabel.textColor = UIColor.labelColor;

		UISwitch *sw = [UISwitch new];
		sw.on = [m bubbleGradientForAsset:self.asset];
		sw.onTintColor = [RYGUtils RYGColor_Primary];
		[sw addTarget:self action:@selector(gradientToggled:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = sw;
		return cell;
	}

	if (tag == RYGRowGradientDir) {
		cell.textLabel.text = RYGLocalized(@"Direction");

		UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[
			RYGLocalized(@"Vertical"), RYGLocalized(@"Horizontal"), RYGLocalized(@"Diagonal")
		]];
		seg.selectedSegmentIndex = [m bubbleGradientDirectionForAsset:self.asset];
		seg.selectedSegmentTintColor = [RYGUtils RYGColor_Primary];
		[seg addTarget:self action:@selector(gradientDirChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = seg;
		cell.textLabel.textColor = UIColor.labelColor;
		return cell;
	}

	if (tag == RYGRowBubbleColor) {
		cell.textLabel.text = RYGLocalized(@"Bubble color");
		cell.textLabel.textColor = UIColor.labelColor;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		NSArray<UIColor *> *colors = [m bubbleColorsForAsset:self.asset];
		if (colors.count) {
			cell.imageView.image = [self swatchForColors:colors];
			cell.imageView.layer.cornerRadius = 5;
			cell.imageView.clipsToBounds = YES;
		}
		return cell;
	}

	if (tag == RYGRowTextColor) {
		cell.textLabel.text = RYGLocalized(@"Text color");
		cell.textLabel.textColor = UIColor.labelColor;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		UIColor *textColor = [m autoBubbleTextColorForAsset:self.asset];
		if (textColor) {
			cell.imageView.image = [self swatchForColors:@[textColor]];
			cell.imageView.layer.cornerRadius = 5;
			cell.imageView.clipsToBounds = YES;
		}
		return cell;
	}

	UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 170, 31)];
	slider.tintColor = [RYGUtils RYGColor_Primary];
	slider.tag = tag;
	[slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
	[slider addTarget:self action:@selector(sliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

	if (tag == RYGRowOpacity) {
		cell.textLabel.text = RYGLocalized(@"Opacity");
		slider.minimumValue = 0.1;
		slider.maximumValue = 1.0;
		slider.value = [m effectiveOpacityForAsset:self.asset];
	} else if (tag == RYGRowBlur) {
		cell.textLabel.text = RYGLocalized(@"Blur");
		slider.minimumValue = 0;
		slider.maximumValue = 30;
		slider.value = [m effectiveBlurForAsset:self.asset];
	} else {
		cell.textLabel.text = RYGLocalized(@"Dim in dark mode");
		slider.minimumValue = 0;
		slider.maximumValue = 0.85;
		slider.value = [m effectiveDimForAsset:self.asset];
	}

	cell.textLabel.textColor = UIColor.labelColor;
	cell.accessoryView = slider;
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	NSInteger tag = self.rows[ip.row].integerValue;

	if (tag == RYGRowReset) {
		[[RYGChatBackgroundManager shared] resetSettingsForAsset:self.asset];
		[self rebuildRows];
		[self renderPreview];
		[self.tableView reloadData];
	} else if (tag == RYGRowBubbleColor) {
		[self editBubbleColor];
	} else if (tag == RYGRowTextColor) {
		[self editTextColor];
	}
}

#pragma mark - Slider

- (void)sliderChanged:(UISlider *)s {
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];

	if (s.tag == RYGRowOpacity) {
		[m setOpacity:s.value forAsset:self.asset];
		[self quickPreview];
	} else if (s.tag == RYGRowBlur) {
		[m setBlur:s.value forAsset:self.asset];
		[self renderPreviewSoon];
	} else {
		[m setDim:s.value forAsset:self.asset];
		[self quickPreview];
	}
}

- (void)sliderDone:(UISlider *)s {
	if (s.tag == RYGRowBlur) [self renderPreview];
}

- (void)autoBubbleToggled:(UISwitch *)sw {
	[[RYGChatBackgroundManager shared] setAutoBubble:sw.on forAsset:self.asset];
	[self rebuildRows];
	[self.tableView reloadData];
}

- (void)sidesChanged:(UISegmentedControl *)seg {
	[[RYGChatBackgroundManager shared] setBubbleSides:(RYGBubbleSides)seg.selectedSegmentIndex forAsset:self.asset];
}

- (void)gradientToggled:(UISwitch *)sw {
	[[RYGChatBackgroundManager shared] setBubbleGradient:sw.on forAsset:self.asset];
	[self rebuildRows];
	[self.tableView reloadData];
}

- (void)gradientDirChanged:(UISegmentedControl *)seg {
	[[RYGChatBackgroundManager shared] setBubbleGradientDirection:(RYGBubbleGradientDirection)seg.selectedSegmentIndex forAsset:self.asset];
}

- (void)editBubbleColor {
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	NSString *capturedAsset = self.asset;
	NSArray<UIColor *> *colors = [m bubbleColorsForAsset:capturedAsset];
	BOOL gradient = [m bubbleGradientForAsset:capturedAsset];

	RYGColorPickerSheet *picker = [RYGColorPickerSheet sheetWithMode:gradient ? RYGColorPickerSheetModeGradient : RYGColorPickerSheetModeSolid
														 startColor:colors.firstObject ?: UIColor.systemBlueColor
														   endColor:gradient ? (colors.count > 1 ? colors.lastObject : nil) : nil
													   applyHandler:^(RYGColorPickerSheetMode mode, UIColor *primary, UIColor *secondary) {
		NSArray<UIColor *> *picked = (mode == RYGColorPickerSheetModeGradient && secondary) ? @[primary, secondary] : @[primary];
		[m setBubbleColorOverride:picked forAsset:capturedAsset];
		[self.tableView reloadData];
	}];
	[picker presentFromViewController:self];
}

- (void)editTextColor {
	RYGChatBackgroundManager *m = [RYGChatBackgroundManager shared];
	NSString *capturedAsset = self.asset;

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Text color") message:nil preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Automatic (contrast)") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[m setBubbleTextColorOverride:nil forAsset:capturedAsset];
		[self.tableView reloadData];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Choose color…") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		UIColor *start = [m bubbleTextColorOverrideForAsset:capturedAsset] ?: [m autoBubbleTextColorForAsset:capturedAsset] ?: UIColor.whiteColor;
		RYGColorPickerSheet *picker = [RYGColorPickerSheet sheetWithMode:RYGColorPickerSheetModeSolid
															 startColor:start
															   endColor:nil
														   applyHandler:^(__unused RYGColorPickerSheetMode mode, UIColor *primary, __unused UIColor *secondary) {
			[m setBubbleTextColorOverride:primary forAsset:capturedAsset];
			[self.tableView reloadData];
		}];
		[picker presentFromViewController:self];
	}]];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	UITableViewCell *cell = nil;
	NSInteger idx = [self.rows indexOfObject:@(RYGRowTextColor)];
	if (idx != NSNotFound) cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0]];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;

	[self presentViewController:sheet animated:YES completion:nil];
}

- (UIImage *)swatchForColors:(NSArray<UIColor *> *)colors {
	CGSize size = CGSizeMake(26, 26);
	UIGraphicsImageRendererFormat *fmt = UIGraphicsImageRendererFormat.preferredFormat;
	fmt.opaque = NO;
	return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:5];
		[path addClip];
		if (colors.count >= 2) {
			CGFloat locs[2] = {0, 1};
			NSArray *cgs = @[(id)[colors[0] CGColor], (id)[colors[1] CGColor]];
			CGGradientRef grad = CGGradientCreateWithColors(CGColorSpaceCreateDeviceRGB(), (__bridge CFArrayRef)cgs, locs);
			CGContextDrawLinearGradient(ctx.CGContext, grad, CGPointMake(0, 0), CGPointMake(0, size.height), 0);
			CGGradientRelease(grad);
		} else {
			[colors.firstObject ?: UIColor.clearColor setFill];
			[path fill];
		}
	}];
}

@end
