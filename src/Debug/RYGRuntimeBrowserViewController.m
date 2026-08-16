#import "RYGRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

typedef NS_ENUM(NSInteger, RYGRuntimeBrowserMode) {
	RYGRuntimeBrowserModeBoolMethods = 0,
	RYGRuntimeBrowserModeMachOSymbols,
};

static NSString *const kRYGRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";
static NSString *const kRYGRuntimeModeKey = @"ryg_runtime_browser_mode";
static NSString *const kRYGRuntimeScopeKey = @"ryg_runtime_browser_scope";

static NSString *RYGRuntimeImagePersistenceID(NSString *path) {
	NSString *standard = path.stringByStandardizingPath;
	NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
	NSString *prefix = [root stringByAppendingString:@"/"];
	if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
	return standard.lastPathComponent ?: @"";
}

@interface RYGRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *boolRows;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *symbolRows;
@property (nonatomic, copy) NSArray *visibleRows;
@property (nonatomic, assign) RYGRuntimeBrowserScope scope;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, assign, getter=isScanning) BOOL scanning;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation RYGRuntimeBrowserViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Runtime browser");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.boolRows = @[];
	self.symbolRows = @[];
	self.visibleRows = @[];

	NSInteger storedMode = [NSUserDefaults.standardUserDefaults integerForKey:kRYGRuntimeModeKey];
	self.scope = (RYGRuntimeBrowserScope)[NSUserDefaults.standardUserDefaults integerForKey:kRYGRuntimeScopeKey];
	if (self.scope < RYGRuntimeBrowserScopeRelevant || self.scope > RYGRuntimeBrowserScopeAll) self.scope = RYGRuntimeBrowserScopeRelevant;

	UIView *controlBar = [UIView new];
	controlBar.translatesAutoresizingMaskIntoConstraints = NO;
	controlBar.backgroundColor = UIColor.clearColor;
	[self.view addSubview:controlBar];

	self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
	// Stable binary marker used by CI after RYG class-name obfuscation.
	self.imageButton.accessibilityIdentifier = @"RYGRuntimeBrowserLiveScan";
	self.imageButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.imageButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	self.imageButton.showsMenuAsPrimaryAction = YES;
	[self.imageButton setTitle:RYGLocalized(@"Image") forState:UIControlStateNormal];
	RYGLiquidGlassConfigureButton(self.imageButton, NO);
	[controlBar addSubview:self.imageButton];

	self.modeControl = [[UISegmentedControl alloc] initWithItems:@[RYGLocalized(@"BOOL gates"), RYGLocalized(@"Mach-O symbols")]];
	self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
	self.modeControl.selectedSegmentIndex = storedMode == RYGRuntimeBrowserModeMachOSymbols
		? RYGRuntimeBrowserModeMachOSymbols : RYGRuntimeBrowserModeBoolMethods;
	[self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
	[controlBar addSubview:self.modeControl];

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	[self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"runtime"];
	[self.view addSubview:self.tableView];

	UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[controlBar.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8.0],
		[controlBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
		[controlBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
		[self.imageButton.topAnchor constraintEqualToAnchor:controlBar.topAnchor],
		[self.imageButton.leadingAnchor constraintEqualToAnchor:controlBar.leadingAnchor],
		[self.imageButton.trailingAnchor constraintEqualToAnchor:controlBar.trailingAnchor],
		[self.imageButton.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
		[self.modeControl.topAnchor constraintEqualToAnchor:self.imageButton.bottomAnchor constant:8.0],
		[self.modeControl.leadingAnchor constraintEqualToAnchor:controlBar.leadingAnchor],
		[self.modeControl.trailingAnchor constraintEqualToAnchor:controlBar.trailingAnchor],
		[self.modeControl.bottomAnchor constraintEqualToAnchor:controlBar.bottomAnchor],
		[self.tableView.topAnchor constraintEqualToAnchor:controlBar.bottomAnchor constant:4.0],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController.searchResultsUpdater = self;
	self.searchController.obscuresBackgroundDuringPresentation = NO;
	self.searchController.searchBar.placeholder = RYGLocalized(@"Filter this live scan");
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = YES;

	UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
		style:UIBarButtonItemStylePlain target:self action:@selector(scanSelectedImage)];
	UIBarButtonItem *scope = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self scopeMenu]];
	self.navigationItem.rightBarButtonItems = @[refresh, scope];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.emptyLabel = [UILabel new];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

	[self refreshRuntimeImages];
	[self scanSelectedImage];
	RYGLiquidGlassApplyToViewController(self);
}

- (void)refreshRuntimeImages {
	self.images = [RYGRuntimeBrowserEngine runtimeImagePaths];
	NSString *storedIdentity = [NSUserDefaults.standardUserDefaults stringForKey:kRYGRuntimeSelectedImageKey];
	if (!self.selectedImagePath.length || ![self.images containsObject:self.selectedImagePath]) {
		self.selectedImagePath = nil;
		for (NSString *path in self.images) {
			BOOL exactIdentity = storedIdentity.length
				&& [RYGRuntimeImagePersistenceID(path) isEqualToString:storedIdentity];
			// One-time compatibility with the former basename-only preference.
			BOOL legacyName = storedIdentity.length && ![storedIdentity containsString:@"/"]
				&& [[RYGRuntimeBrowserEngine shortNameForImagePath:path] isEqualToString:storedIdentity];
			if (exactIdentity || legacyName) {
				self.selectedImagePath = path;
				[NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImagePersistenceID(path)
					forKey:kRYGRuntimeSelectedImageKey];
				break;
			}
		}
		if (!self.selectedImagePath) self.selectedImagePath = self.images.firstObject;
	}
	[self rebuildImageMenu];
}

- (void)rebuildImageMenu {
	NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
	__weak __typeof__(self) weakSelf = self;
	for (NSString *path in self.images) {
		NSString *name = [RYGRuntimeBrowserEngine shortNameForImagePath:path];
		UIAction *action = [UIAction actionWithTitle:name image:[UIImage systemImageNamed:[path isEqualToString:NSBundle.mainBundle.executablePath.stringByStandardizingPath] ? @"app" : @"shippingbox"] identifier:nil handler:^(__kindof UIAction *item) {
			__strong __typeof__(weakSelf) self = weakSelf;
			self.selectedImagePath = path;
			[NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImagePersistenceID(path)
				forKey:kRYGRuntimeSelectedImageKey];
			[self rebuildImageMenu];
			[self scanSelectedImage];
		}];
		action.state = [path isEqualToString:self.selectedImagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:action];
	}
	NSString *name = self.selectedImagePath.length ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath] : RYGLocalized(@"No loaded image");
	NSString *title = [NSString stringWithFormat:RYGLocalized(@"Image: %@"), name];
	[self.imageButton setTitle:title forState:UIControlStateNormal];
	if (self.imageButton.configuration) {
		UIButtonConfiguration *configuration = self.imageButton.configuration;
		configuration.title = title;
		self.imageButton.configuration = configuration;
	}
	self.imageButton.menu = [UIMenu menuWithTitle:RYGLocalized(@"Loaded executable and frameworks") children:actions];
}

- (UIMenu *)scopeMenu {
	__weak __typeof__(self) weakSelf = self;
	NSMutableArray *actions = [NSMutableArray array];
	NSArray *items = @[
		@[@(RYGRuntimeBrowserScopeRelevant), RYGLocalized(@"Relevant gates"), @"sparkles"],
		@[@(RYGRuntimeBrowserScopeEmployee), RYGLocalized(@"Employee / Dogfood"), @"person.badge.key"],
		@[@(RYGRuntimeBrowserScopeAll), RYGLocalized(@"All safe BOOL methods"), @"list.bullet"],
	];
	for (NSArray *item in items) {
		RYGRuntimeBrowserScope value = [item[0] integerValue];
		UIAction *action = [UIAction actionWithTitle:item[1] image:[UIImage systemImageNamed:item[2]] identifier:nil handler:^(__kindof UIAction *sender) {
			__strong __typeof__(weakSelf) self = weakSelf;
			self.scope = value;
			[NSUserDefaults.standardUserDefaults setInteger:value forKey:kRYGRuntimeScopeKey];
			self.navigationItem.rightBarButtonItems.lastObject.menu = [self scopeMenu];
			if (self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeBoolMethods) [self scanSelectedImage];
		}];
		action.state = self.scope == value ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:action];
	}
	return [UIMenu menuWithTitle:RYGLocalized(@"BOOL scope") children:actions];
}

- (void)modeChanged:(UISegmentedControl *)sender {
	[NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegmentIndex forKey:kRYGRuntimeModeKey];
	[self scanSelectedImage];
}

- (void)setScanning:(BOOL)scanning {
	_scanning = scanning;
	if (scanning) {
		[self.spinner startAnimating];
		self.tableView.backgroundView = self.spinner;
	} else {
		[self.spinner stopAnimating];
		self.tableView.backgroundView = self.visibleRows.count ? nil : self.emptyLabel;
	}
}

- (void)scanSelectedImage {
	[self refreshRuntimeImages];
	NSString *path = self.selectedImagePath.copy;
	if (!path.length) {
		self.boolRows = @[];
		self.symbolRows = @[];
		[self applySearchFilter];
		return;
	}
	RYGRuntimeBrowserMode mode = (RYGRuntimeBrowserMode)self.modeControl.selectedSegmentIndex;
	RYGRuntimeBrowserScope scope = self.scope;
	NSUInteger generation = ++self.scanGeneration;
	self.scanning = YES;
	self.navigationItem.rightBarButtonItems.firstObject.enabled = NO;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray *rows;
		if (mode == RYGRuntimeBrowserModeBoolMethods) {
			rows = [RYGRuntimeBrowserEngine boolMethodsForImagePath:path scope:scope];
		} else {
			rows = [RYGRuntimeBrowserEngine machOSymbolsForImagePath:path];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self.scanGeneration) return;
			if (mode == RYGRuntimeBrowserModeBoolMethods) self.boolRows = rows;
			else self.symbolRows = rows;
			self.scanning = NO;
			self.navigationItem.rightBarButtonItems.firstObject.enabled = YES;
			[self applySearchFilter];
		});
	});
}

- (void)applySearchFilter {
	NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
	BOOL boolMode = self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeBoolMethods;
	NSArray *source;
	if (boolMode) source = self.boolRows;
	else source = self.symbolRows;
	if (!query.length) {
		self.visibleRows = source;
	} else if (boolMode) {
		self.visibleRows = [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeBoolMethod *row, NSDictionary *bindings) {
			return [row.className.lowercaseString containsString:query] || [row.selectorName.lowercaseString containsString:query];
		}]];
	} else {
		self.visibleRows = [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMachOSymbol *row, NSDictionary *bindings) {
			return [row.name.lowercaseString containsString:query] || [row.kind.lowercaseString containsString:query];
		}]];
	}
	self.emptyLabel.text = boolMode
		? RYGLocalized(@"No safe BOOL gate matched this real-time scan. Structural methods such as isEqual: and respondsToSelector: are always excluded.")
		: RYGLocalized(@"No Mach-O symbol matched this loaded image.");
	self.tableView.backgroundView = self.visibleRows.count || self.isScanning ? (self.isScanning ? self.spinner : nil) : self.emptyLabel;
	[self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	[self applySearchFilter];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.visibleRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"runtime"];
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.numberOfLines = 2;
	if (self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeBoolMethods) {
		RYGRuntimeBoolMethod *row = self.visibleRows[indexPath.row];
		cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", row.classMethod ? @"+" : @"-", row.selectorName];
		NSNumber *live = row.liveValue;
		NSNumber *forced = row.overrideValue;
		NSString *argument = row.argumentKind == RYGRuntimeArgumentNone ? @"no args" : (row.argumentKind == RYGRuntimeArgumentObject ? @"object arg" : @"integer arg");
		NSString *state = forced ? [NSString stringWithFormat:@"forced %@", forced.boolValue ? @"true" : @"false"]
			: (live ? [NSString stringWithFormat:@"live %@", live.boolValue ? @"true" : @"false"] : @"live value not observed");
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", row.className, argument, state];
		if (forced) {
			cell.imageView.image = [UIImage systemImageNamed:forced.boolValue ? @"checkmark.circle.fill" : @"xmark.circle.fill"];
			cell.imageView.tintColor = forced.boolValue ? UIColor.systemGreenColor : UIColor.systemRedColor;
		} else {
			cell.imageView.image = [UIImage systemImageNamed:@"function"];
			cell.imageView.tintColor = UIColor.secondaryLabelColor;
		}
	} else {
		RYGMachOSymbol *row = self.visibleRows[indexPath.row];
		cell.textLabel.text = row.name;
		NSString *address = row.address ? [NSString stringWithFormat:@"0x%llx", row.address] : @"unresolved";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", row.kind, row.external ? @"external" : @"local", address];
		cell.imageView.image = [UIImage systemImageNamed:[row.kind isEqualToString:@"Function"] ? @"function" : @"memorychip"];
		cell.imageView.tintColor = UIColor.secondaryLabelColor;
	}
	return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	NSString *image = self.selectedImagePath.length ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath] : @"—";
	return [NSString stringWithFormat:RYGLocalized(@"%lu live row(s) from %@. Rows and addresses are never persisted; pull a new scan with the refresh button."), (unsigned long)self.visibleRows.count, image];
}

- (UIMenu *)menuForBoolMethod:(RYGRuntimeBoolMethod *)method refresh:(BOOL)refresh {
	__weak __typeof__(self) weakSelf = self;
	void (^setValue)(NSNumber *) = ^(NSNumber *value) {
		[RYGRuntimeBrowserEngine setOverride:value forMethod:method];
		if (refresh) [weakSelf applySearchFilter];
	};
	UIAction *forceTrue = [UIAction actionWithTitle:RYGLocalized(@"Force true") image:[UIImage systemImageNamed:@"checkmark.circle"] identifier:nil handler:^(__kindof UIAction *action) { setValue(@YES); }];
	UIAction *forceFalse = [UIAction actionWithTitle:RYGLocalized(@"Force false") image:[UIImage systemImageNamed:@"xmark.circle"] identifier:nil handler:^(__kindof UIAction *action) { setValue(@NO); }];
	UIAction *native = [UIAction actionWithTitle:RYGLocalized(@"Use native value") image:[UIImage systemImageNamed:@"arrow.uturn.backward.circle"] identifier:nil handler:^(__kindof UIAction *action) { setValue(nil); }];
	native.attributes = method.overrideValue ? 0 : UIMenuElementAttributesDisabled;
	UIAction *copy = [UIAction actionWithTitle:RYGLocalized(@"Copy method details") image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__kindof UIAction *action) {
		UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@", method.classMethod ? @"+" : @"-", method.className, method.selectorName, method.typeEncoding];
	}];
	return [UIMenu menuWithTitle:method.className children:@[forceTrue, forceFalse, native, copy]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
	if (self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeBoolMethods) {
		RYGRuntimeBoolMethod *method = self.visibleRows[indexPath.row];
		return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
			return [self menuForBoolMethod:method refresh:YES];
		}];
	}
	RYGMachOSymbol *symbol = self.visibleRows[indexPath.row];
	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
		UIAction *copyName = [UIAction actionWithTitle:RYGLocalized(@"Copy symbol") image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(__kindof UIAction *action) { UIPasteboard.generalPasteboard.string = symbol.name; }];
		UIAction *copyAddress = [UIAction actionWithTitle:RYGLocalized(@"Copy live address") image:[UIImage systemImageNamed:@"number"] identifier:nil handler:^(__kindof UIAction *action) { UIPasteboard.generalPasteboard.string = symbol.address ? [NSString stringWithFormat:@"0x%llx", symbol.address] : @"0x0"; }];
		return [UIMenu menuWithTitle:symbol.kind children:@[copyName, copyAddress]];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.modeControl.selectedSegmentIndex != RYGRuntimeBrowserModeBoolMethods) {
		RYGMachOSymbol *symbol = self.visibleRows[indexPath.row];
		UIPasteboard.generalPasteboard.string = symbol.name;
		[RYGUtils showToastForDuration:1.2 title:RYGLocalized(@"Copied") subtitle:symbol.name];
		return;
	}
	RYGRuntimeBoolMethod *method = self.visibleRows[indexPath.row];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:method.selectorName message:method.className preferredStyle:UIAlertControllerStyleActionSheet];
	__weak __typeof__(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Force true") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method]; [weakSelf applySearchFilter]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Force false") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method]; [weakSelf applySearchFilter]; }]];
	if (method.overrideValue) [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Use native value") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [RYGRuntimeBrowserEngine setOverride:nil forMethod:method]; [weakSelf applySearchFilter]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		sheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
		sheet.popoverPresentationController.sourceRect = [tableView cellForRowAtIndexPath:indexPath].bounds;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

@end
