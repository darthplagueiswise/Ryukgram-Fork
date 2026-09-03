#import "RYGAppIconPickerViewController.h"
#import "../Utils.h"
#import "../UI/RYGPopupChrome.h"

static NSString *const RYGSelectedAppIconNameKey = @"RYGSelectedAppIconName";
static NSString *const RYGPrimaryAppIconKey = @"__primary__";

@interface RYGAppIconPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *icons;
@property (nonatomic, copy) NSString *selectedIconKey;
@end

@implementation RYGAppIconPickerViewController

+ (void)presentIconPicker {
	UIViewController *top = topMostController();
	if (!top) return;

	RYGAppIconPickerViewController *vc = [RYGAppIconPickerViewController new];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;

	if (@available(iOS 15.0, *)) {
		nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
		nav.sheetPresentationController.prefersGrabberVisible = YES;
	}

	[top presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = RYGLocalized(@"App Icon");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];

	NSString *saved = [RYGUtils getStringPref:RYGSelectedAppIconNameKey];
	NSString *current = UIApplication.sharedApplication.alternateIconName;
	self.selectedIconKey = saved.length ? saved : (current.length ? current : RYGPrimaryAppIconKey);

	[self loadIconsFromInfoPlist];
	[self setupNavigation];
	[self setupTableView];
}

- (void)setupNavigation {
	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];
}

- (void)setupTableView {
	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = 76.0;
	self.tableView.contentInset = UIEdgeInsetsMake(-10.0, 0.0, 0.0, 0.0);

	[self.view addSubview:self.tableView];
}

- (void)loadIconsFromInfoPlist {
	NSMutableArray *items = [NSMutableArray array];
	NSDictionary *bundleIcons = NSBundle.mainBundle.infoDictionary[@"CFBundleIcons"];
	NSDictionary *primary = bundleIcons[@"CFBundlePrimaryIcon"];

	[items addObject:@{
		@"key": RYGPrimaryAppIconKey,
		@"title": RYGLocalized(@"Default"),
		@"files": primary[@"CFBundleIconFiles"] ?: @[]
	}];

	NSDictionary *alternates = bundleIcons[@"CFBundleAlternateIcons"];
	NSArray *keys = [alternates.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

	for (NSString *key in keys) {
		NSDictionary *info = alternates[key];
		if (!key.length || ![info isKindOfClass:NSDictionary.class]) continue;

		[items addObject:@{
			@"key": key,
			@"title": key,
			@"files": info[@"CFBundleIconFiles"] ?: @[]
		}];
	}

	self.icons = items.copy;
}

- (UIImage *)imageFromIconFiles:(NSArray *)files {
	if (![files isKindOfClass:NSArray.class]) return [self fallbackIconImage];

	for (NSString *file in files.reverseObjectEnumerator) {
		if (![file isKindOfClass:NSString.class] || !file.length) continue;

		for (NSString *scale in @[@"@3x", @"@2x", @""]) {
			NSString *name = [file stringByAppendingString:scale];

			for (NSString *ext in @[@"png", @"jpg", @"jpeg"]) {
				NSString *path = [NSBundle.mainBundle pathForResource:name ofType:ext];
				if (!path.length) continue;

				UIImage *image = [UIImage imageWithContentsOfFile:path];
				if (image && image.CGImage) return image;
			}
		}
	}

	return [self fallbackIconImage];
}

- (UIImage *)fallbackIconImage {
	CGSize size = CGSizeMake(48.0, 48.0);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);

	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, size} cornerRadius:11.0];
	[[RYGUtils RYGColor_Primary] setFill];
	[path fill];

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return image;
}

- (UIImage *)imageForIcon:(NSDictionary *)icon {
	return [self imageFromIconFiles:icon[@"files"]];
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveSelectedKey:(NSString *)key {
	[RYGUtils setPref:key forKey:RYGSelectedAppIconNameKey];
}

- (void)selectIconAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)self.icons.count) return;

	NSString *key = self.icons[indexPath.row][@"key"] ?: @"";
	if (!key.length) return;

	if (![UIApplication.sharedApplication supportsAlternateIcons]) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Alternate icons are not supported")];
		return;
	}

	BOOL primary = [key isEqualToString:RYGPrimaryAppIconKey];
	NSString *iconName = primary ? nil : key;
	NSString *previousKey = self.selectedIconKey;

	self.selectedIconKey = key;
	[self saveSelectedKey:key];
	[self.tableView reloadData];

	__weak typeof(self) weakSelf = self;

	[UIApplication.sharedApplication setAlternateIconName:iconName completionHandler:^(NSError *error) {
		if (!error) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;

			self.selectedIconKey = previousKey;
			[self saveSelectedKey:previousKey];
			[self.tableView reloadData];
			[RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: RYGLocalized(@"Failed to change icon")];
		});
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.icons.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return RYGLocalized(@"Choose Icon");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return RYGLocalized(@"The selected icon will be saved and shown here the next time you open this page.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"RYGAppIconPickerCell";

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];

	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	}

	NSDictionary *icon = self.icons[indexPath.row];
	NSString *key = icon[@"key"] ?: @"";
	BOOL selected = [key isEqualToString:self.selectedIconKey];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = icon[@"title"] ?: key;
	config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
	config.secondaryText = selected ? RYGLocalized(@"Selected") : RYGLocalized(@"Tap to apply");
	config.secondaryTextProperties.color = selected ? [RYGUtils RYGColor_Primary] : UIColor.secondaryLabelColor;
	config.image = [self imageForIcon:icon];
	config.imageProperties.maximumSize = CGSizeMake(48.0, 48.0);
	config.imageProperties.cornerRadius = 11.0;
	config.imageToTextPadding = 14.0;

	cell.contentConfiguration = config;
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.tintColor = [RYGUtils RYGColor_Primary];

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[self selectIconAtIndexPath:indexPath];
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end