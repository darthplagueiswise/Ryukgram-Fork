#import "SCIAppIconPickerViewController.h"
#import "../Utils.h"
#import "../UI/SCIPopupChrome.h"

static NSString *const SCISelectedAppIconNameKey = @"SCISelectedAppIconName";
static NSString *const SCIPrimaryAppIconKey = @"__primary__";
static NSString *const SCIPrimaryAppIconTitle = @"Default";

@interface SCIAppIconPickerViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *icons;
@property (nonatomic, copy) NSString *selectedIconKey;

@end

@implementation SCIAppIconPickerViewController

+ (void)presentIconPicker {
	UIViewController *top = topMostController();
	if (!top) return;

	SCIAppIconPickerViewController *vc = [[SCIAppIconPickerViewController alloc] init];
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

	self.title = SCILocalized(@"App Icon");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];

	[self loadSelectedIconKey];
	[self loadIconsFromInfoPlist];
	[self setupNavigation];
	[self setupTableView];
}

- (void)loadSelectedIconKey {
	NSString *savedIcon = [NSUserDefaults.standardUserDefaults stringForKey:SCISelectedAppIconNameKey];
	NSString *currentIcon = UIApplication.sharedApplication.alternateIconName;

	self.selectedIconKey = savedIcon.length ? savedIcon : (currentIcon.length ? currentIcon : SCIPrimaryAppIconKey);
}

- (void)saveSelectedIconKey:(NSString *)key {
	if (!key.length) return;

	self.selectedIconKey = key;
	[NSUserDefaults.standardUserDefaults setObject:key forKey:SCISelectedAppIconNameKey];
	[NSUserDefaults.standardUserDefaults synchronize];
}

- (void)setupNavigation {
	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
																						  target:self
																						  action:@selector(closeTapped)];
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
	NSMutableArray<NSDictionary *> *items = [NSMutableArray array];

	NSDictionary *bundleIcons = NSBundle.mainBundle.infoDictionary[@"CFBundleIcons"];
	NSDictionary *primaryIcon = bundleIcons[@"CFBundlePrimaryIcon"];
	NSArray *primaryFiles = primaryIcon[@"CFBundleIconFiles"];
	NSString *primaryIconName = primaryIcon[@"CFBundleIconName"];

	[items addObject:@{
		@"key": SCIPrimaryAppIconKey,
		@"title": SCILocalized(SCIPrimaryAppIconTitle),
		@"alternateName": @"",
		@"iconName": primaryIconName ?: @"",
		@"files": primaryFiles ?: @[]
	}];

	NSDictionary *alternateIcons = bundleIcons[@"CFBundleAlternateIcons"];
	NSArray *sortedKeys = [alternateIcons.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

	for (NSString *key in sortedKeys) {
		if (![key isKindOfClass:NSString.class] || !key.length) continue;

		NSDictionary *iconInfo = alternateIcons[key];
		NSArray *files = iconInfo[@"CFBundleIconFiles"];

		[items addObject:@{
			@"key": key,
			@"title": key,
			@"alternateName": key,
			@"iconName": key,
			@"files": files ?: @[]
		}];
	}

	self.icons = items.copy;
}

#pragma mark - Actions

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)selectIconAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= (NSInteger)self.icons.count) return;

	NSDictionary *icon = self.icons[indexPath.row];
	NSString *key = icon[@"key"] ?: @"";
	NSString *alternateName = [key isEqualToString:SCIPrimaryAppIconKey] ? nil : key;

	if (!key.length) return;

	if (![UIApplication.sharedApplication supportsAlternateIcons]) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Alternate icons are not supported")];
		return;
	}

	NSString *currentAlternateName = UIApplication.sharedApplication.alternateIconName;

	if ((!currentAlternateName && !alternateName) || [currentAlternateName isEqualToString:alternateName]) {
		[self saveSelectedIconKey:key];
		[self.tableView reloadData];
		return;
	}

	__weak typeof(self) weakSelf = self;

	[UIApplication.sharedApplication setAlternateIconName:alternateName completionHandler:^(NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;

			if (error) {
				[SCIUtils showErrorHUDWithDescription:error.localizedDescription ?: SCILocalized(@"Failed to change icon")];
				return;
			}

			[self saveSelectedIconKey:key];
			[self.tableView reloadData];
		});
	}];
}

#pragma mark - Icon loading

- (UIImage *)imageNamedFromBundle:(NSString *)name {
	if (!name.length) return nil;

	UIImage *image = [UIImage imageNamed:name];
	if (image) return image;

	for (NSString *ext in @[@"png", @"jpg", @"jpeg"]) {
		NSString *path = [NSBundle.mainBundle pathForResource:name ofType:ext];
		if (path.length) {
			image = [UIImage imageWithContentsOfFile:path];
			if (image) return image;
		}
	}

	return nil;
}

- (UIImage *)imageForIcon:(NSDictionary *)icon {
	NSArray *files = icon[@"files"];
	NSString *key = icon[@"key"];
	NSString *iconName = icon[@"iconName"];

	NSMutableArray<NSString *> *names = [NSMutableArray array];

	if (iconName.length) {
		[names addObject:iconName];
		[names addObject:[NSString stringWithFormat:@"%@@3x", iconName]];
		[names addObject:[NSString stringWithFormat:@"%@@2x", iconName]];
	}

	if (key.length && ![key isEqualToString:SCIPrimaryAppIconKey]) {
		[names addObject:key];
		[names addObject:[NSString stringWithFormat:@"%@@3x", key]];
		[names addObject:[NSString stringWithFormat:@"%@@2x", key]];
	}

	for (NSString *file in files) {
		if (![file isKindOfClass:NSString.class] || !file.length) continue;
		[names addObject:file];
	}

	for (NSString *name in names) {
		UIImage *image = [self imageNamedFromBundle:name];
		if (image) return image;
	}

	return [UIImage imageNamed:@"AppIcon"];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.icons.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return SCILocalized(@"Choose Icon");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return SCILocalized(@"The selected icon will be saved and shown here the next time you open this page.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"SCIAppIconPickerCell";

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	}

	if (indexPath.row >= (NSInteger)self.icons.count) return cell;

	NSDictionary *icon = self.icons[indexPath.row];
	NSString *key = icon[@"key"] ?: @"";
	NSString *title = icon[@"title"] ?: key;
	BOOL selected = [key isEqualToString:self.selectedIconKey];

	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	config.text = title;
	config.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
	config.textProperties.color = UIColor.labelColor;

	config.secondaryText = selected ? SCILocalized(@"Selected") : SCILocalized(@"Tap to apply");
	config.secondaryTextProperties.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
	config.secondaryTextProperties.color = selected ? [SCIUtils SCIColor_Primary] : UIColor.secondaryLabelColor;
	config.textToSecondaryTextVerticalPadding = 4.0;
	config.imageToTextPadding = 14.0;

	UIImage *preview = [self imageForIcon:icon];
	config.image = preview;
	config.imageProperties.maximumSize = CGSizeMake(48.0, 48.0);
	config.imageProperties.cornerRadius = 11.0;

	cell.contentConfiguration = config;
	cell.accessoryView = nil;
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.tintColor = [SCIUtils SCIColor_Primary];

	return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 76.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[self selectIconAtIndexPath:indexPath];
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end