#import "SCISettingsViewController.h"
#import "../UI/SCIPopupChrome.h"
#import "SCISearchBarStyler.h"
#import "../Features/General/SCICacheManager.h"
#import "../SCIImageCache.h"
#import "../Tweak.h"
#import "../UI/SCIColorPicker.h"

static char kSCIRowKey;

@interface SCISettingsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic, copy) NSArray<NSDictionary *> *searchIndex;
@property (nonatomic, copy) NSArray<NSDictionary *> *searchResults;

@property (nonatomic, assign) BOOL reduceMargin;
@property (nonatomic, assign) BOOL isRoot;

@end

@implementation SCISettingsViewController

- (instancetype)init {
	return [self initWithTitle:[SCITweakSettings title] sections:[SCITweakSettings sections] reduceMargin:YES];
}

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections reduceMargin:(BOOL)reduceMargin {
	self = [super init];
	if (!self) return nil;

	self.title = title;
	self.reduceMargin = reduceMargin;
	self.isRoot = reduceMargin;
	self.sections = [self filteredSections:sections];
	self.searchResults = @[];

	if (self.isRoot) self.searchIndex = [self buildSearchIndexFromSections:self.sections breadcrumb:@""];

	return self;
}

- (NSArray *)filteredSections:(NSArray *)sections {
	NSMutableArray *out = [NSMutableArray array];

	for (NSDictionary *section in sections) {
		if (![section isKindOfClass:NSDictionary.class]) continue;

		NSString *header = section[@"header"] ?: @"";
		NSString *footer = section[@"footer"] ?: @"";
		BOOL isDevOnly = [header hasPrefix:@"_"] && [footer hasPrefix:@"_"];
		BOOL isExperimental = [header isEqualToString:@"Experimental"];

		if (isDevOnly && ![[SCIUtils IGVersionString] isEqualToString:@"0.0.0"]) continue;
		if (isExperimental && ![[SCIUtils IGVersionString] hasSuffix:@"-dev"]) continue;

		[out addObject:section];
	}

	return out.copy;
}

- (NSArray<NSDictionary *> *)buildSearchIndexFromSections:(NSArray *)sections breadcrumb:(NSString *)breadcrumb {
	NSMutableArray *out = [NSMutableArray array];

	for (NSDictionary *section in sections) {
		if (![section isKindOfClass:NSDictionary.class]) continue;

		NSString *header = section[@"header"] ?: @"";
		NSArray *rows = section[@"rows"];
		NSString *sectionCrumb = breadcrumb.length && header.length ? [NSString stringWithFormat:@"%@ › %@", breadcrumb, header] : (header ?: breadcrumb);

		for (SCISetting *row in rows) {
			if (![row isKindOfClass:SCISetting.class]) continue;

			[out addObject:@{
				@"setting": row,
				@"breadcrumb": sectionCrumb ?: @"",
				@"haystack": [NSString stringWithFormat:@"%@ %@ %@", row.title ?: @"", row.subtitle ?: @"", sectionCrumb ?: @""]
			}];

			if (row.navSections.count) {
				NSString *childCrumb = sectionCrumb.length ? [NSString stringWithFormat:@"%@ › %@", sectionCrumb, row.title ?: @""] : (row.title ?: @"");
				[out addObjectsFromArray:[self buildSearchIndexFromSections:row.navSections breadcrumb:childCrumb]];
			}
		}
	}

	return out.copy;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];

	[self setupTableView];
	if (self.isRoot) [self setupRootNavigation];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sciCacheSizeDidUpdate) name:SCICacheSizeDidUpdateNotification object:nil];
}

- (void)setupTableView {
	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.backgroundColor = self.view.backgroundColor;
	self.tableView.contentInset = UIEdgeInsetsMake(self.reduceMargin ? -30.0 : -10.0, 0.0, 0.0, 0.0);
	self.tableView.dataSource = self;
	self.tableView.delegate = self;

	[self.view addSubview:self.tableView];
}

- (void)setupRootNavigation {
	UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
	sc.searchResultsUpdater = self;
	sc.delegate = self;
	sc.obscuresBackgroundDuringPresentation = NO;
	sc.searchBar.placeholder = SCILocalized(@"settings.search.placeholder");

	self.searchController = sc;
	self.navigationItem.searchController = sc;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = ![SCIUtils getBoolPref:@"liquid_glass_buttons"];

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(sciDismissSettings)];

	UIBarButtonItem *langItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"] style:UIBarButtonItemStylePlain target:nil action:nil];
	langItem.menu = [self sciBuildLanguageMenu];
	self.navigationItem.rightBarButtonItem = langItem;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
	[self sciStyleSearchBar];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self sciStyleSearchBar];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];

	if (![SCIUtils getBoolPref:@"liquid_glass_buttons"] && self.searchController.isActive) {
		self.searchController.active = NO;
	}

	if (self.isRoot) [self sciShowFirstRunAlertIfNeeded];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Language

- (UIMenu *)sciBuildLanguageMenu {
	NSString *current = [[NSUserDefaults standardUserDefaults] stringForKey:SCILanguagePrefKey] ?: @"system";
	NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];

	for (NSDictionary<NSString *, NSString *> *lang in SCIAvailableLanguages()) {
		NSString *code = lang[@"code"] ?: @"system";
		NSString *title = [code isEqualToString:@"system"] ? SCILocalized(@"settings.language.system") : (lang[@"native"] ?: code);

		UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *a) {
			NSString *prev = [[NSUserDefaults standardUserDefaults] stringForKey:SCILanguagePrefKey] ?: @"system";
			if ([prev isEqualToString:code]) return;

			[[NSUserDefaults standardUserDefaults] setObject:code forKey:SCILanguagePrefKey];
			SCILocalizationReset();
			[self sciApplyLanguageChange];
			[SCIUtils showRestartConfirmation];
		}];

		action.state = [code isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
		[items addObject:action];
	}

	UIAction *help = [UIAction actionWithTitle:[NSString stringWithFormat:@"❤️ %@", SCILocalized(@"settings.language.help_translate")] image:nil identifier:nil handler:^(__unused UIAction *a) {
		NSURL *url = [NSURL URLWithString:SCIRepoTranslateURL];
		if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	}];

	[items addObject:help];

	return [UIMenu menuWithTitle:SCILocalized(@"settings.language.title") children:items];
}

- (void)sciApplyLanguageChange {
	self.title = SCILocalized(@"settings.title");
	self.searchController.searchBar.placeholder = SCILocalized(@"settings.search.placeholder");

	if (self.navigationItem.rightBarButtonItem.menu) {
		self.navigationItem.rightBarButtonItem.menu = [self sciBuildLanguageMenu];
	}

	self.sections = [self filteredSections:[SCITweakSettings sections]];
	self.searchIndex = [self buildSearchIndexFromSections:self.sections breadcrumb:@""];
	[self.tableView reloadData];

	[[NSNotificationCenter defaultCenter] postNotificationName:@"SCILanguageDidChange" object:nil];
}

#pragma mark - Events

- (void)sciDismissSettings {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sciCacheSizeDidUpdate {
	[self.tableView reloadData];
}

- (void)sciStyleSearchBar {
	if (self.searchController.searchBar) [SCISearchBarStyler styleSearchBar:self.searchController.searchBar];
}

- (void)willPresentSearchController:(UISearchController *)searchController {
	[self sciStyleSearchBar];
}

- (void)didPresentSearchController:(UISearchController *)searchController {
	[self sciStyleSearchBar];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self sciStyleSearchBar];
	});
}

- (void)sciShowFirstRunAlertIfNeeded {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([[d objectForKey:@"SCInstaFirstRun"] isEqualToString:SCIVersionString]) return;

	[d setObject:SCIVersionString forKey:@"SCInstaFirstRun"];

	UIViewController *presenter = self.presentingViewController;
	if (!presenter) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"settings.firstrun.title") message:SCILocalized(@"settings.firstrun.message") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"settings.firstrun.ok") style:UIAlertActionStyleDefault handler:nil]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (BOOL)isSearching {
	return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	NSString *q = searchController.searchBar.text ?: @"";

	if (!q.length) {
		self.searchResults = @[];
		[self.tableView reloadData];
		return;
	}

	NSMutableArray *out = [NSMutableArray array];

	for (NSDictionary *entry in self.searchIndex) {
		NSString *haystack = entry[@"haystack"] ?: @"";
		if ([haystack rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
			[out addObject:entry];
		}
	}

	self.searchResults = out.copy;
	[self.tableView reloadData];
}

- (SCISetting *)settingForIndexPath:(NSIndexPath *)indexPath breadcrumbOut:(NSString **)outCrumb {
	if ([self isSearching]) {
		if (indexPath.row >= (NSInteger)self.searchResults.count) return nil;

		NSDictionary *entry = self.searchResults[indexPath.row];
		if (outCrumb) *outCrumb = entry[@"breadcrumb"];
		return entry[@"setting"];
	}

	if (indexPath.section >= (NSInteger)self.sections.count) return nil;

	NSArray *rows = self.sections[indexPath.section][@"rows"];
	if (indexPath.row >= (NSInteger)rows.count) return nil;

	return rows[indexPath.row];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [self isSearching] ? 1 : self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if ([self isSearching]) return self.searchResults.count;
	return [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ([self isSearching]) {
		NSUInteger count = self.searchResults.count;
		if (!count) return SCILocalized(@"No results");

		NSString *fmt = count == 1 ? SCILocalized(@"settings.results.one") : SCILocalized(@"settings.results.many");
		return [NSString stringWithFormat:fmt, (unsigned long)count];
	}

	return self.sections[section][@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return [self isSearching] ? nil : self.sections[section][@"footer"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *breadcrumb = nil;
	SCISetting *row = [self settingForIndexPath:indexPath breadcrumbOut:&breadcrumb];

	if (!row) {
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	UIListContentConfiguration *config = cell.defaultContentConfiguration;

	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.contentView.alpha = row.disabled ? 0.4 : 1.0;

	config.text = row.dynamicTitle ? row.dynamicTitle() : row.title;
	config.textProperties.color = row.titleColor ?: UIColor.labelColor;

	NSString *subtitle = ([self isSearching] && breadcrumb.length) ? breadcrumb : row.subtitle;
	if (subtitle.length) {
		config.secondaryText = subtitle;
		config.textToSecondaryTextVerticalPadding = 4.5;
	}

	[self configureIconForRow:row config:config indexPath:indexPath tableView:tableView];
	config = [self configuredContent:config forCell:cell row:row indexPath:indexPath];

	cell.contentConfiguration = config;
	return cell;
}

- (void)configureIconForRow:(SCISetting *)row config:(UIListContentConfiguration *)config indexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView {
	if (row.icon) {
		config.image = [row.icon image];
		config.imageProperties.tintColor = row.icon.color;
	}

	if (row.imageUrl) {
		config.imageToTextPadding = 14.0;
		[self loadImageFromURL:row.imageUrl atIndexPath:indexPath forTableView:tableView];
	}

	if (row.bundleImageName.length) {
		UIImage *img = [UIImage imageNamed:row.bundleImageName inBundle:SCILocalizationBundle() compatibleWithTraitCollection:nil];
		if (!img) return;

		config.image = img;
		config.imageProperties.maximumSize = CGSizeMake(45.0, 45.0);
		config.imageProperties.cornerRadius = 10.0;
		config.imageToTextPadding = 14.0;
	}
}

- (UIListContentConfiguration *)configuredContent:(UIListContentConfiguration *)config forCell:(UITableViewCell *)cell row:(SCISetting *)row indexPath:(NSIndexPath *)indexPath {
	switch (row.type) {
		case SCITableCellStatic: {
			cell.selectionStyle = UITableViewCellSelectionStyleNone;

			if (row.valueText.length && ![self isSearching]) {
				UILabel *value = UILabel.new;
				value.text = row.valueText;
				value.font = [UIFont systemFontOfSize:16.0];
				value.textColor = UIColor.secondaryLabelColor;
				[value sizeToFit];
				cell.accessoryView = value;
			}
			break;
		}

		case SCITableCellLink: {
			config.textProperties.color = UIColor.systemBlueColor;
			config.textProperties.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightMedium];

			UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"safari"]];
			icon.tintColor = UIColor.systemGray3Color;
			cell.accessoryView = icon;
			break;
		}

		case SCITableCellSwitch: {
			UISwitch *toggle = UISwitch.new;
			toggle.on = row.disabled ? NO : [[NSUserDefaults standardUserDefaults] boolForKey:row.defaultsKey];
			toggle.onTintColor = [SCIUtils SCIColor_Primary];
			toggle.enabled = !row.disabled;

			objc_setAssociatedObject(toggle, &kSCIRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];

			cell.accessoryView = toggle;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;
		}

		case SCITableCellStepper: {
			UIStepper *stepper = UIStepper.new;
			stepper.minimumValue = row.min;
			stepper.maximumValue = row.max;
			stepper.stepValue = row.step;
			stepper.value = [[NSUserDefaults standardUserDefaults] doubleForKey:row.defaultsKey];

			objc_setAssociatedObject(stepper, &kSCIRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[stepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];

			if (row.subtitle.length) {
				config.secondaryText = [self formatString:row.subtitle withValue:stepper.value label:row.label singularLabel:row.singularLabel];
			}

			cell.accessoryView = stepper;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;
		}

		case SCITableCellButton:
		case SCITableCellNavigation: {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;
		}

		case SCITableCellMenu: {
			UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
			[button setTitle:@"•••" forState:UIControlStateNormal];
			button.menu = [row menuForButton:button];
			button.showsMenuAsPrimaryAction = YES;
			button.enabled = !row.disabled;
			button.titleLabel.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightMedium];

			UIButtonConfiguration *buttonConfig = button.configuration ?: UIButtonConfiguration.plainButtonConfiguration;
			buttonConfig.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 8.0, 8.0, 8.0);
			button.configuration = buttonConfig;

			[button sizeToFit];

			cell.accessoryView = button;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;
		}

		case SCITableCellColor: {
			cell.accessoryView = [SCIColorPicker swatchViewForKey:row.defaultsKey defaultColor:row.defaultColor];
			break;
		}
	}

	return config;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	SCISetting *row = [self settingForIndexPath:indexPath breadcrumbOut:NULL];
	if (!row || row.disabled) {
		[tableView deselectRowAtIndexPath:indexPath animated:YES];
		return;
	}

	switch (row.type) {
		case SCITableCellLink:
			if (row.url) [[UIApplication sharedApplication] openURL:row.url options:@{} completionHandler:nil];
			break;

		case SCITableCellButton:
			if (row.action) row.action();
			break;

		case SCITableCellColor:
			[self presentColorPickerForRow:row indexPath:indexPath];
			break;

		case SCITableCellNavigation:
			[self pushNavigationForRow:row];
			break;

		default:
			break;
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)presentColorPickerForRow:(SCISetting *)row indexPath:(NSIndexPath *)indexPath {
	__weak typeof(self) weakSelf = self;

	[SCIColorPicker presentFrom:self title:row.title defaultsKey:row.defaultsKey defaultColor:row.defaultColor onChange:^(__unused UIColor *color) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
		cell.accessoryView = [SCIColorPicker swatchViewForKey:row.defaultsKey defaultColor:row.defaultColor];
	}];
}

- (void)pushNavigationForRow:(SCISetting *)row {
	if (row.navSections.count) {
		UIViewController *vc = [[SCISettingsViewController alloc] initWithTitle:row.title sections:row.navSections reduceMargin:NO];
		[self.navigationController pushViewController:vc animated:YES];
		return;
	}

	if (row.navViewController) {
		[self.navigationController pushViewController:row.navViewController animated:YES];
	}
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch *)sender {
	SCISetting *row = objc_getAssociatedObject(sender, &kSCIRowKey);
	if (!row.defaultsKey.length) return;

	[[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:row.defaultsKey];

	if (row.requiresRestart) [SCIUtils showRestartConfirmation];

	if ([row.defaultsKey isEqualToString:@"hide_suggested_stories"]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"SCISuggestedStoriesReload" object:nil];
	}

	if ([row.defaultsKey isEqualToString:@"show_fake_location_map_button"]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"SCIFakeLocationMapBtnPrefChanged" object:nil];
	}
}

- (void)stepperChanged:(UIStepper *)sender {
	SCISetting *row = objc_getAssociatedObject(sender, &kSCIRowKey);
	if (!row.defaultsKey.length) return;

	[[NSUserDefaults standardUserDefaults] setDouble:sender.value forKey:row.defaultsKey];
	[self reloadCellForView:sender animated:NO];
}

- (void)menuChanged:(UICommand *)command {
	NSDictionary *props = [command.propertyList isKindOfClass:NSDictionary.class] ? command.propertyList : nil;
	NSString *key = props[@"defaultsKey"];
	id value = props[@"value"];

	if (key.length && value) [[NSUserDefaults standardUserDefaults] setValue:value forKey:key];

	CGPoint offset = self.tableView.contentOffset;
	[self.tableView reloadData];
	self.tableView.contentOffset = offset;

	NSString *pickerKey = props[@"presentColorPickerForKey"];
	if (pickerKey.length) {
		__weak typeof(self) weakSelf = self;

		[SCIColorPicker presentFrom:self title:command.title defaultsKey:pickerKey defaultColor:UIColor.blackColor onChange:^(__unused UIColor *color) {
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;

			CGPoint offset = self.tableView.contentOffset;
			[self.tableView reloadData];
			self.tableView.contentOffset = offset;
		}];
	}

	if ([props[@"requiresRestart"] boolValue]) {
		[SCIUtils showRestartConfirmation];
	}
}

#pragma mark - Helpers

- (NSString *)formatString:(NSString *)template withValue:(double)value label:(NSString *)label singularLabel:(NSString *)singularLabel {
	if (fabs(value) < 0.00001) value = 0.0;

	NSString *unit = fabs(value - 1.0) < 0.00001 ? singularLabel : label;

	static NSNumberFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = NSNumberFormatter.new;
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
		formatter.minimumFractionDigits = 0;
	});

	formatter.maximumFractionDigits = [SCIUtils decimalPlacesInDouble:value];

	NSString *number = [formatter stringFromNumber:@(value)] ?: @"0";
	return [NSString stringWithFormat:template, number, unit ?: @""];
}

- (void)reloadCellForView:(UIView *)view animated:(BOOL)animated {
	UITableViewCell *cell = nil;
	UIView *cur = view;

	while (cur) {
		if ([cur isKindOfClass:UITableViewCell.class]) {
			cell = (UITableViewCell *)cur;
			break;
		}
		cur = cur.superview;
	}

	if (!cell) return;

	NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
	if (!indexPath) return;

	[self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:animated ? UITableViewRowAnimationAutomatic : UITableViewRowAnimationNone];
}

- (void)reloadCellForView:(UIView *)view {
	[self reloadCellForView:view animated:NO];
}

- (void)loadImageFromURL:(NSURL *)url atIndexPath:(NSIndexPath *)indexPath forTableView:(UITableView *)tableView {
	if (!url) return;

	[SCIImageCache loadImageFromURL:url completion:^(UIImage *image) {
		if (!image) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
			if (!cell) return;

			UIListContentConfiguration *config = (UIListContentConfiguration *)cell.contentConfiguration;
			config.image = image;
			config.imageProperties.maximumSize = CGSizeMake(45.0, 45.0);
			config.imageProperties.cornerRadius = 22.5;
			config.imageToTextPadding = 14.0;
			cell.contentConfiguration = config;
		});
	}];
}

@end