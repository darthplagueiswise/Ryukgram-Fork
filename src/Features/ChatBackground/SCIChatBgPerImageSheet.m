#import "SCIChatBgPerImageSheet.h"
#import "SCIChatBackgroundManager.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../Utils.h"

typedef NS_ENUM(NSInteger, SCIRow) {
	SCIRowOpacity,
	SCIRowBlur,
	SCIRowDim,
	SCIRowReset,
	SCIRowCount
};

static NSString *const kCell = @"cell";

@interface SCIChatBgPerImageSheet () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *asset;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation SCIChatBgPerImageSheet

- (instancetype)initWithAsset:(NSString *)asset {
	if ((self = [super init])) {
		_asset = [asset copy];
		self.title = SCILocalized(@"Image Settings");
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Done") style:UIBarButtonItemStyleDone target:self action:@selector(done)];

	_preview = [UIImageView new];
	_preview.contentMode = UIViewContentModeScaleAspectFill;
	_preview.clipsToBounds = YES;
	_preview.layer.cornerRadius = 16;
	_preview.layer.cornerCurve = kCACornerCurveContinuous;
	_preview.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:_preview];

	_dimView = [UIView new];
	_dimView.backgroundColor = UIColor.blackColor;
	_dimView.userInteractionEnabled = NO;
	_dimView.translatesAutoresizingMaskIntoConstraints = NO;
	[_preview addSubview:_dimView];

	_tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	_tableView.dataSource = self;
	_tableView.delegate = self;
	_tableView.backgroundColor = self.view.backgroundColor;
	_tableView.contentInset = UIEdgeInsetsMake(-6, 0, 0, 0);
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

	[self renderPreview];
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

	SCIChatBackgroundManager *m = [SCIChatBackgroundManager shared];
	self.preview.image = [m processedImageForAsset:self.asset darkAppearance:self.isDark];
	self.preview.alpha = [m effectiveOpacityForAsset:self.asset];
	self.preview.backgroundColor = self.isDark ? UIColor.blackColor : UIColor.whiteColor;
	self.dimView.alpha = self.isDark ? [m effectiveDimForAsset:self.asset] : 0;
}

- (void)quickPreview {
	SCIChatBackgroundManager *m = [SCIChatBackgroundManager shared];
	self.preview.alpha = [m effectiveOpacityForAsset:self.asset];
	self.dimView.alpha = self.isDark ? [m effectiveDimForAsset:self.asset] : 0;
}

- (void)renderPreviewSoon {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(renderPreview) object:nil];
	[self performSelector:@selector(renderPreview) withObject:nil afterDelay:0.08];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
	return SCIRowCount;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
	return SCILocalized(@"Reset sets opacity to 1.0, blur to 0, dim to 0.");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCell forIndexPath:ip];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (ip.row == SCIRowReset) {
		cell.textLabel.text = SCILocalized(@"Reset");
		cell.textLabel.textColor = UIColor.systemRedColor;
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		return cell;
	}

	UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 170, 31)];
	slider.tintColor = [SCIUtils SCIColor_Primary];
	slider.tag = ip.row;
	[slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
	[slider addTarget:self action:@selector(sliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

	SCIChatBackgroundManager *m = [SCIChatBackgroundManager shared];

	if (ip.row == SCIRowOpacity) {
		cell.textLabel.text = SCILocalized(@"Opacity");
		slider.minimumValue = 0.1;
		slider.maximumValue = 1.0;
		slider.value = [m effectiveOpacityForAsset:self.asset];
	} else if (ip.row == SCIRowBlur) {
		cell.textLabel.text = SCILocalized(@"Blur");
		slider.minimumValue = 0;
		slider.maximumValue = 30;
		slider.value = [m effectiveBlurForAsset:self.asset];
	} else {
		cell.textLabel.text = SCILocalized(@"Dim in dark mode");
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
	if (ip.row != SCIRowReset) return;

	[[SCIChatBackgroundManager shared] resetSettingsForAsset:self.asset];
	[self renderPreview];
	[self.tableView reloadData];
}

#pragma mark - Slider

- (void)sliderChanged:(UISlider *)s {
	SCIChatBackgroundManager *m = [SCIChatBackgroundManager shared];

	if (s.tag == SCIRowOpacity) {
		[m setOpacity:s.value forAsset:self.asset];
		[self quickPreview];
	} else if (s.tag == SCIRowBlur) {
		[m setBlur:s.value forAsset:self.asset];
		[self renderPreviewSoon];
	} else {
		[m setDim:s.value forAsset:self.asset];
		[self quickPreview];
	}
}

- (void)sliderDone:(UISlider *)s {
	if (s.tag == SCIRowBlur) [self renderPreview];
}

@end