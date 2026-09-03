#import "RYGSettingsViewController.h"
#import "RYGWhatsNew.h"
#import "RYGDonatePrompt.h"
#import "../UI/RYGPopupChrome.h"
#import "RYGSearchBarStyler.h"
#import "../Features/General/RYGCacheManager.h"
#import "../RYGImageCache.h"
#import "../Tweak.h"
#import "../UI/RYGColorPicker.h"

static char kRYGRowKey;

#pragma mark - Language Picker

@interface RYGLanguagePickerViewController : UITableViewController
@property (nonatomic, copy) void (^onPick)(NSString *code);
@end

@interface RYGLanguagePickerViewController ()
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *languages;
@property (nonatomic, copy) NSString *currentCode;
@end

@implementation RYGLanguagePickerViewController

- (instancetype)init {
	if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
		_languages = RYGAvailableLanguages();
		_currentCode = [NSUserDefaults.standardUserDefaults stringForKey:RYGLanguagePrefKey] ?: @"system";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"settings.language.title");
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(rygClose)];
	UIColor *bg = [RYGPopupChrome backgroundColor];
	self.view.backgroundColor = bg;
	self.tableView.backgroundColor = bg;
	[self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"lang"];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	NSInteger idx = [self rygActiveIndex];
	if (idx != NSNotFound) [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
}

- (NSInteger)rygActiveIndex {
	for (NSUInteger i = 0; i < self.languages.count; i++)
		if ([(self.languages[i][@"code"] ?: @"system") isEqualToString:self.currentCode]) return (NSInteger)i;
	return NSNotFound;
}

- (void)rygClose { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? (NSInteger)self.languages.count : 1; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"lang" forIndexPath:ip];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.detailTextLabel.text = nil;
	cell.textLabel.textColor = UIColor.labelColor;
	cell.textLabel.font = [UIFont systemFontOfSize:17.0];
	cell.imageView.image = nil;
	cell.tintColor = UIColor.systemBlueColor;

	if (ip.section == 0) {
		NSDictionary *lang = self.languages[ip.row];
		NSString *code = lang[@"code"] ?: @"system";
		NSString *native = [code isEqualToString:@"system"] ? RYGLocalized(@"settings.language.system") : (lang[@"native"] ?: code);
		NSString *english = nil;
		if (![code isEqualToString:@"system"] && ![code isEqualToString:@"en"]) {
			NSLocale *en = [NSLocale localeWithLocaleIdentifier:@"en"];
			english = [en localizedStringForLocaleIdentifier:code] ?: [en localizedStringForLanguageCode:code];
			if (english.length) english = [[[english substringToIndex:1] uppercaseString] stringByAppendingString:[english substringFromIndex:1]];
			if ([english isEqualToString:native]) english = nil;
		}
		cell.textLabel.text = english.length ? [NSString stringWithFormat:@"%@  ·  %@", native, english] : native;
		if ([code isEqualToString:self.currentCode]) {
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
			cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
		}
	} else {
		cell.textLabel.text = RYGLocalized(@"settings.language.help_translate");
		cell.textLabel.textColor = UIColor.systemPinkColor;
		cell.imageView.image = [UIImage systemImageNamed:@"heart.fill"];
		cell.imageView.tintColor = UIColor.systemPinkColor;
	}
	return cell;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	return s == 0 ? [NSString stringWithFormat:@"%@  ·  %lu", RYGLocalized(@"settings.language.available"), (unsigned long)self.languages.count] : nil;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	if (ip.section == 0) {
		NSString *code = self.languages[ip.row][@"code"] ?: @"system";
		void (^pick)(NSString *) = self.onPick;
		[self dismissViewControllerAnimated:YES completion:^{ if (pick) pick(code); }];
	} else {
		NSURL *url = [NSURL URLWithString:RYGRepoTranslateURL];
		if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
	}
}

@end

#pragma mark - Settings View Controller

@interface RYGSettingsViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, strong, readwrite) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic, copy) NSArray<NSDictionary *> *searchIndex;
@property (nonatomic, copy) NSArray<NSDictionary *> *searchResults;
@property (nonatomic, assign) BOOL reduceMargin;
@property (nonatomic, assign) BOOL isRoot;
@property (nonatomic, assign) BOOL scopedSearch;
@property (nonatomic, assign) BOOL searchBarStyled;
@end

@implementation RYGSettingsViewController

- (instancetype)init {
	return [self initWithTitle:[RYGTweakSettings title] sections:[RYGTweakSettings sections] reduceMargin:YES];
}

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray *)sections reduceMargin:(BOOL)reduceMargin {
	if (!(self = [super init])) return nil;
	self.title = title;
	self.reduceMargin = reduceMargin;
	self.isRoot = reduceMargin;
	self.sections = [self filteredSections:sections];
	self.searchResults = @[];
	if (self.isRoot) self.searchIndex = [self buildSearchIndexFromSections:self.sections breadcrumb:@""];
	return self;
}

- (instancetype)initWithTitle:(NSString *)title {
	return [self initWithTitle:title sections:@[] reduceMargin:NO];
}

- (void)applySettingSections:(NSArray *)sections {
	self.sections = [self filteredSections:sections];
	[self.tableView reloadData];
}

- (void)rebuildSections {}

+ (NSDictionary *)sectionWithHeader:(NSString *)header footer:(NSString *)footer rows:(NSArray<RYGSetting *> *)rows {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	if (header) d[@"header"] = header;
	if (footer) d[@"footer"] = footer;
	d[@"rows"] = rows ?: @[];
	return d.copy;
}

- (NSArray<NSDictionary *> *)rygSearchableSettingsEntries {
	if (!self.sections.count) [self rebuildSections];
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *section in self.sections) {
		if (![section isKindOfClass:NSDictionary.class]) continue;
		NSString *header = section[@"header"] ?: @"";
		for (RYGSetting *row in section[@"rows"]) {
			if (![row isKindOfClass:RYGSetting.class] || row.type == RYGTableCellCustom) continue;
			NSString *title = row.dynamicTitle ? row.dynamicTitle() : row.title;
			id child = row.navViewController;
			BOOL childSearchable = [child conformsToProtocol:@protocol(RYGSettingsSearchable)];

			if (title.length) {
				NSString *sub = (row.dynamicSubtitle ? row.dynamicSubtitle() : row.subtitle) ?: @"";
				NSMutableDictionary *e = [@{ @"title": title, @"subtitle": sub, @"section": header } mutableCopy];
				if (childSearchable) e[@"target"] = child;
				[out addObject:e];
			}

			if (childSearchable) {
				NSString *prefix = title.length ? (header.length ? [NSString stringWithFormat:@"%@ › %@", header, title] : title) : header;
				for (NSDictionary *ce in [(id<RYGSettingsSearchable>)child rygSearchableSettingsEntries]) {
					NSMutableDictionary *e = ce.mutableCopy;
					NSString *cs = ce[@"section"] ?: @"";
					e[@"section"] = cs.length ? (prefix.length ? [NSString stringWithFormat:@"%@ › %@", prefix, cs] : cs) : prefix;
					if (!e[@"target"]) e[@"target"] = child;
					[out addObject:e];
				}
			}
		}
	}
	return out;
}

- (NSArray *)filteredSections:(NSArray *)sections {
	NSMutableArray *out = [NSMutableArray array];
	NSString *ver = [RYGUtils IGVersionString];
	for (NSDictionary *section in sections) {
		if (![section isKindOfClass:NSDictionary.class]) continue;
		NSString *header = section[@"header"] ?: @"";
		NSString *footer = section[@"footer"] ?: @"";
		if ([header hasPrefix:@"_"] && [footer hasPrefix:@"_"] && ![ver isEqualToString:@"0.0.0"]) continue;
		if ([header isEqualToString:@"Experimental"] && ![ver hasSuffix:@"-dev"]) continue;
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
		for (RYGSetting *row in rows) {
			if (![row isKindOfClass:RYGSetting.class]) continue;
			[out addObject:@{
				@"setting": row,
				@"breadcrumb": sectionCrumb ?: @"",
				@"haystack": [NSString stringWithFormat:@"%@ %@ %@", row.title ?: @"", row.subtitle ?: @"", sectionCrumb ?: @""]
			}];
			NSString *childCrumb = sectionCrumb.length ? [NSString stringWithFormat:@"%@ › %@", sectionCrumb, row.title ?: @""] : (row.title ?: @"");
			if (row.navSections.count) {
				[out addObjectsFromArray:[self buildSearchIndexFromSections:row.navSections breadcrumb:childCrumb]];
			} else if ([row.navViewController conformsToProtocol:@protocol(RYGSettingsSearchable)]) {
				for (NSDictionary *child in [(id<RYGSettingsSearchable>)row.navViewController rygSearchableSettingsEntries]) {
					NSString *title = child[@"title"] ?: @"";
					NSString *sub = child[@"subtitle"] ?: @"";
					NSString *sec = child[@"section"] ?: @"";
					UIViewController *target = child[@"target"] ?: row.navViewController;
					NSString *entryCrumb = sec.length ? [NSString stringWithFormat:@"%@ › %@", childCrumb, sec] : childCrumb;
					RYGSetting *proxy = [RYGSetting navigationCellWithTitle:title subtitle:@"" icon:row.icon viewController:target];
					[out addObject:@{
						@"setting": proxy,
						@"breadcrumb": entryCrumb,
						@"haystack": [NSString stringWithFormat:@"%@ %@ %@", title, sub, entryCrumb]
					}];
				}
			}
		}
	}
	return out.copy;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationController.navigationBar.prefersLargeTitles = NO;
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	[self setupTableView];
	if (self.isRoot) [self setupRootNavigation];
	else if (self.scopedSearch) [self setupScopedSearch];
	NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
	[nc addObserver:self selector:@selector(rygCacheSizeDidUpdate) name:RYGCacheSizeDidUpdateNotification object:nil];
	[nc addObserver:self selector:@selector(rygReloadFromNotification) name:@"RYGSettingsShouldReload" object:nil];
}

- (void)rygReloadFromNotification {
	CGPoint offset = self.tableView.contentOffset;
	if (self.isRoot) self.sections = [self filteredSections:[RYGTweakSettings sections]];
	[self.tableView reloadData];
	self.tableView.contentOffset = offset;
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

- (void)installSearchControllerWithPlaceholder:(NSString *)placeholder {
	UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
	sc.searchResultsUpdater = self;
	sc.delegate = self;
	sc.obscuresBackgroundDuringPresentation = NO;
	sc.searchBar.placeholder = placeholder;
	self.searchController = sc;
	self.navigationItem.searchController = sc;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = ![RYGSearchBarStyler shouldUseNativeGlass];
}

- (void)setupRootNavigation {
	[self installSearchControllerWithPlaceholder:RYGLocalized(@"settings.search.placeholder")];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(rygDismissSettings)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"] style:UIBarButtonItemStylePlain target:self action:@selector(rygPresentLanguagePicker)];
}

- (void)setupScopedSearch {
	self.searchIndex = [self buildSearchIndexFromSections:self.sections breadcrumb:@""];
	[self installSearchControllerWithPlaceholder:RYGLocalized(@"settings.search.placeholder")];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isRoot) self.sections = [self filteredSections:[RYGTweakSettings sections]];
	[self.tableView reloadData];
	[self rygStyleSearchBar];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (self.isRoot) [RYGDonatePrompt presentIfDueFrom:self];
	if (self.scrollToSectionHeader.length) {
		NSString *target = self.scrollToSectionHeader;
		self.scrollToSectionHeader = nil;
		for (NSInteger i = 0; i < (NSInteger)self.sections.count; i++) {
			if ([self.sections[i][@"header"] isEqualToString:target]) {
				[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:i] atScrollPosition:UITableViewScrollPositionTop animated:YES];
				break;
			}
		}
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (!self.searchBarStyled) [self rygStyleSearchBar];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (![RYGSearchBarStyler shouldUseNativeGlass] && self.searchController.isActive) self.searchController.active = NO;
	if (self.isRoot) [self rygShowFirstRunAlertIfNeeded];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

#pragma mark - Language

- (void)rygPresentLanguagePicker {
	RYGLanguagePickerViewController *picker = [RYGLanguagePickerViewController new];
	__weak typeof(self) weakSelf = self;
	picker.onPick = ^(NSString *code) {
		NSString *prev = [NSUserDefaults.standardUserDefaults stringForKey:RYGLanguagePrefKey] ?: @"system";
		if ([prev isEqualToString:code]) return;
		[NSUserDefaults.standardUserDefaults setObject:code forKey:RYGLanguagePrefKey];
		RYGLocalizationReset();
		[weakSelf rygApplyLanguageChange];
		[RYGUtils showRestartConfirmationWithTitle:RYGLocalized(@"settings.language.restart.title") message:RYGLocalized(@"settings.language.restart.message")];
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	if (@available(iOS 15.0, *)) {
		UISheetPresentationController *sheet = nav.sheetPresentationController;
		sheet.detents = @[UISheetPresentationControllerDetent.largeDetent, UISheetPresentationControllerDetent.mediumDetent];
		sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
		sheet.prefersGrabberVisible = YES;
		sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
	}
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)rygApplyLanguageChange {
	self.title = RYGLocalized(@"settings.title");
	self.searchController.searchBar.placeholder = RYGLocalized(@"settings.search.placeholder");
	self.sections = [self filteredSections:[RYGTweakSettings sections]];
	self.searchIndex = [self buildSearchIndexFromSections:self.sections breadcrumb:@""];
	[self.tableView reloadData];
	[NSNotificationCenter.defaultCenter postNotificationName:@"RYGLanguageDidChange" object:nil];
}

#pragma mark - Events

- (void)rygDismissSettings { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)rygCacheSizeDidUpdate { [self.tableView reloadData]; }

- (void)rygStyleSearchBar {
	if (!self.searchController.searchBar) return;
	[RYGSearchBarStyler styleSearchBar:self.searchController.searchBar];
	self.searchBarStyled = YES;
}

- (void)willPresentSearchController:(UISearchController *)sc { self.searchBarStyled = NO; [self rygStyleSearchBar]; }

- (void)didPresentSearchController:(UISearchController *)sc {
	self.searchBarStyled = NO;
	[self rygStyleSearchBar];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		self.searchBarStyled = NO;
		[self rygStyleSearchBar];
	});
}

- (void)rygShowFirstRunAlertIfNeeded {
	NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
	if ([[d objectForKey:@"RyukGramFirstRun"] isEqualToString:RYGVersionString]) return;
	[d setObject:RYGVersionString forKey:@"RyukGramFirstRun"];
	UIViewController *presenter = self.presentingViewController;
	if (!presenter) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"settings.firstrun.title") message:RYGLocalized(@"settings.firstrun.message") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"settings.firstrun.ok") style:UIAlertActionStyleDefault handler:nil]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (BOOL)isSearching { return self.searchController.isActive && self.searchController.searchBar.text.length > 0; }

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
	NSString *q = sc.searchBar.text ?: @"";
	if (!q.length) { self.searchResults = @[]; [self.tableView reloadData]; return; }
	NSMutableArray *out = [NSMutableArray array];
	NSStringCompareOptions opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
	for (NSDictionary *entry in self.searchIndex)
		if ([(entry[@"haystack"] ?: @"") rangeOfString:q options:opts].location != NSNotFound) [out addObject:entry];
	self.searchResults = out.copy;
	[self.tableView reloadData];
}

- (RYGSetting *)settingForIndexPath:(NSIndexPath *)ip breadcrumbOut:(NSString **)outCrumb {
	if ([self isSearching]) {
		if (ip.row >= (NSInteger)self.searchResults.count) return nil;
		NSDictionary *entry = self.searchResults[ip.row];
		if (outCrumb) *outCrumb = entry[@"breadcrumb"];
		return entry[@"setting"];
	}
	if (ip.section >= (NSInteger)self.sections.count) return nil;
	NSArray *rows = self.sections[ip.section][@"rows"];
	return ip.row >= (NSInteger)rows.count ? nil : rows[ip.row];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [self isSearching] ? 1 : self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [self isSearching] ? self.searchResults.count : [self.sections[s][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return [self isSearching] ? nil : self.sections[s][@"footer"]; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	if ([self isSearching]) {
		NSUInteger c = self.searchResults.count;
		if (!c) return RYGLocalized(@"No results");
		return [NSString stringWithFormat:RYGLocalized(c == 1 ? @"settings.results.one" : @"settings.results.many"), (unsigned long)c];
	}
	return self.sections[s][@"header"];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	NSString *breadcrumb = nil;
	RYGSetting *row = [self settingForIndexPath:ip breadcrumbOut:&breadcrumb];
	if (!row) return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];

	if (row.type == RYGTableCellCustom && row.customCellProvider && ![self isSearching])
		return row.customCellProvider(tv, ip);

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	UIListContentConfiguration *config = cell.defaultContentConfiguration;
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.contentView.alpha = (row.disabled || (row.lockedOnProvider && row.lockedOnProvider()) || (row.disabledProvider && row.disabledProvider())) ? 0.4 : 1.0;

	config.text = row.dynamicTitle ? row.dynamicTitle() : row.title;
	config.textProperties.color = row.titleColor ?: UIColor.labelColor;

	// Search results keep the normal layout so the breadcrumb still has a place.
	if (row.centeredTitle && ![self isSearching]) {
		config.textProperties.alignment = UIListContentTextAlignmentCenter;
		cell.contentConfiguration = config;
		return cell;
	}

	NSString *rowSubtitle = row.dynamicSubtitle ? row.dynamicSubtitle() : row.subtitle;
	NSString *subtitle = ([self isSearching] && breadcrumb.length) ? breadcrumb : rowSubtitle;
	if (subtitle.length) {
		config.secondaryText = subtitle;
		config.textToSecondaryTextVerticalPadding = 4.5;
	}

	[self configureIconForRow:row config:config indexPath:ip tableView:tv];
	config = [self configuredContent:config forCell:cell row:row indexPath:ip];
	cell.contentConfiguration = config;
	if (![self isSearching] && [self rowHasWhatsNew:row]) [self addWhatsNewDotToCell:cell];
	if (row.badgeCount) [self addBadgeCount:row.badgeCount() toCell:cell];
	return cell;
}

- (void)addBadgeCount:(NSInteger)count toCell:(UITableViewCell *)cell {
	if (count <= 0) return;
	NSString *txt = count > 99 ? @"99+" : [@(count) stringValue];
	UILabel *badge = [UILabel new];
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	badge.text = txt;
	badge.font = [UIFont boldSystemFontOfSize:13];
	badge.textColor = UIColor.whiteColor;
	badge.textAlignment = NSTextAlignmentCenter;
	badge.backgroundColor = UIColor.systemRedColor;
	badge.layer.cornerRadius = 10;
	badge.clipsToBounds = YES;
	CGFloat textW = ceil([txt sizeWithAttributes:@{ NSFontAttributeName: badge.font }].width);
	[cell.contentView addSubview:badge];
	[NSLayoutConstraint activateConstraints:@[
		[badge.heightAnchor constraintEqualToConstant:20],
		[badge.widthAnchor constraintEqualToConstant:MAX(20.0, textW + 14.0)],
		[badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[badge.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
	]];
}
- (BOOL)rowHasWhatsNew:(RYGSetting *)row {
	if ([RYGWhatsNew isUnseen:[RYGWhatsNew identifierForRow:row]]) return YES;
	return row.navSections.count && [RYGWhatsNew sectionsHaveUnseen:row.navSections];
}

- (void)addWhatsNewDotToCell:(UITableViewCell *)cell {
	UIView *dot = [UIView new];
	dot.translatesAutoresizingMaskIntoConstraints = NO;
	dot.backgroundColor = UIColor.systemBlueColor;
	dot.layer.cornerRadius = 3.5;
	[cell.contentView addSubview:dot];
	[NSLayoutConstraint activateConstraints:@[
		[dot.widthAnchor constraintEqualToConstant:7.0],
		[dot.heightAnchor constraintEqualToConstant:7.0],
		[dot.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
		[dot.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:5.0],
	]];
}

- (void)configureIconForRow:(RYGSetting *)row config:(UIListContentConfiguration *)config indexPath:(NSIndexPath *)ip tableView:(UITableView *)tv {
	if (row.iconImage) {
		config.image = row.iconImage;
		config.imageToTextPadding = 14.0;
	}
	if (row.icon) {
		config.image = [row.icon image];
		config.imageProperties.tintColor = row.icon.color;
	}
	if (row.imageUrl) {
		config.imageToTextPadding = 14.0;
		[self loadImageFromURL:row.imageUrl atIndexPath:ip forTableView:tv];
	}
	if (row.bundleImageName.length) {
		UIImage *img = [UIImage imageNamed:row.bundleImageName inBundle:RYGLocalizationBundle() compatibleWithTraitCollection:nil];
		if (!img) return;
		config.image = img;
		config.imageProperties.maximumSize = CGSizeMake(45.0, 45.0);
		config.imageProperties.cornerRadius = 10.0;
		config.imageToTextPadding = 14.0;
	}
}

- (UILabel *)valueLabel:(NSString *)text {
	UILabel *l = UILabel.new;
	l.text = text;
	l.font = [UIFont systemFontOfSize:16.0];
	l.textColor = UIColor.secondaryLabelColor;
	[l sizeToFit];
	return l;
}

- (UIView *)valueLabel:(NSString *)text withChevron:(BOOL)chevron {
	UILabel *l = [self valueLabel:text];
	if (!chevron) return l;

	UIImageView *arrow = [[UIImageView alloc] initWithImage:
		[UIImage systemImageNamed:@"chevron.right"
				withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold]]];
	arrow.tintColor = UIColor.tertiaryLabelColor;
	[arrow sizeToFit];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[l, arrow]];
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.spacing = 6;
	CGFloat w = CGRectGetWidth(l.bounds) + 6 + CGRectGetWidth(arrow.bounds);
	stack.frame = CGRectMake(0, 0, w, MAX(CGRectGetHeight(l.bounds), CGRectGetHeight(arrow.bounds)));
	return stack;
}

- (UIListContentConfiguration *)configuredContent:(UIListContentConfiguration *)config forCell:(UITableViewCell *)cell row:(RYGSetting *)row indexPath:(NSIndexPath *)ip {
	switch (row.type) {
		case RYGTableCellStatic: {
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			if (row.valueText.length && ![self isSearching]) cell.accessoryView = [self valueLabel:row.valueText];
			break;
		}
		case RYGTableCellLink: {
			config.textProperties.color = UIColor.systemBlueColor;
			config.textProperties.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightMedium];
			UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"safari"]];
			icon.tintColor = UIColor.systemGray3Color;
			cell.accessoryView = icon;
			break;
		}
		case RYGTableCellSwitch: {
			UISwitch *t = UISwitch.new;
			BOOL on = row.switchValueProvider ? row.switchValueProvider() : [NSUserDefaults.standardUserDefaults boolForKey:row.defaultsKey];
			BOOL locked = row.lockedOnProvider ? row.lockedOnProvider() : NO;
			t.on = locked ? YES : (row.disabled ? NO : on);
			t.onTintColor = [RYGUtils RYGColor_Primary];
			t.enabled = !row.disabled && !locked && !(row.disabledProvider && row.disabledProvider());
			objc_setAssociatedObject(t, &kRYGRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[t addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = t;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;
		}
		case RYGTableCellStepper: {
			UIStepper *s = UIStepper.new;
			s.minimumValue = row.min;
			s.maximumValue = row.max;
			s.stepValue = row.step;
			s.value = [NSUserDefaults.standardUserDefaults doubleForKey:row.defaultsKey];
			objc_setAssociatedObject(s, &kRYGRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[s addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
			if (row.subtitle.length) config.secondaryText = [self formatString:row.subtitle withValue:s.value label:row.label singularLabel:row.singularLabel];
			cell.accessoryView = s;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;
		}
		case RYGTableCellButton:
		case RYGTableCellNavigation: {
			NSString *valueText = row.dynamicValueText ? row.dynamicValueText() : row.valueText;
			BOOL wantsChevron = row.type == RYGTableCellNavigation && !row.hidesDisclosureIndicator;
			if (valueText.length && ![self isSearching]) cell.accessoryView = [self valueLabel:valueText withChevron:wantsChevron];
			else if (!row.hidesDisclosureIndicator) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			break;
		}
		case RYGTableCellMenu: {
			UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
			[b setTitle:@"•••" forState:UIControlStateNormal];
			b.menu = [row menuForButton:b];
			b.showsMenuAsPrimaryAction = YES;
			b.enabled = !row.disabled && !(row.disabledProvider && row.disabledProvider());
			b.titleLabel.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize weight:UIFontWeightMedium];
			UIButtonConfiguration *bc = b.configuration ?: UIButtonConfiguration.plainButtonConfiguration;
			bc.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 8.0, 8.0, 8.0);
			b.configuration = bc;
			[b sizeToFit];
			cell.accessoryView = b;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			break;
		}
		case RYGTableCellColor:
			cell.accessoryView = [RYGColorPicker swatchViewForKey:row.defaultsKey defaultColor:row.defaultColor];
			break;
		case RYGTableCellCustom:
			break;
	}
	return config;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
	if ([self isSearching]) return UITableViewAutomaticDimension;
	RYGSetting *row = [self settingForIndexPath:ip breadcrumbOut:NULL];
	if (row.type == RYGTableCellCustom && row.customHeight > 0) return row.customHeight;
	return UITableViewAutomaticDimension;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
	if ([self isSearching]) return;
	RYGSetting *row = [self settingForIndexPath:ip breadcrumbOut:NULL];
	// Clears this row's own dot once seen; a nav cell's bubble-up dot is separate.
	if (row) [RYGWhatsNew markSeen:[RYGWhatsNew identifierForRow:row]];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	RYGSetting *row = [self settingForIndexPath:ip breadcrumbOut:NULL];
	if (!row || row.disabled || (row.disabledProvider && row.disabledProvider())) { [tv deselectRowAtIndexPath:ip animated:YES]; return; }
	switch (row.type) {
		case RYGTableCellLink: if (row.url) [UIApplication.sharedApplication openURL:row.url options:@{} completionHandler:nil]; break;
		case RYGTableCellButton: if (row.action) row.action(); break;
		case RYGTableCellColor: [self presentColorPickerForRow:row indexPath:ip]; break;
		case RYGTableCellNavigation: [self pushNavigationForRow:row]; break;
		default: break;
	}
	[tv deselectRowAtIndexPath:ip animated:YES];
}

- (void)presentColorPickerForRow:(RYGSetting *)row indexPath:(NSIndexPath *)ip {
	__weak typeof(self) weakSelf = self;
	[RYGColorPicker presentFrom:self title:row.title defaultsKey:row.defaultsKey defaultColor:row.defaultColor onChange:^(__unused UIColor *color) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		[self.tableView cellForRowAtIndexPath:ip].accessoryView = [RYGColorPicker swatchViewForKey:row.defaultsKey defaultColor:row.defaultColor];
	}];
}

- (void)pushNavigationForRow:(RYGSetting *)row {
	if (row.navSections.count) {
		RYGSettingsViewController *child = [[RYGSettingsViewController alloc] initWithTitle:row.title sections:row.navSections reduceMargin:NO];
		child.scopedSearch = row.localSearch;
		[self.navigationController pushViewController:child animated:YES];
		return;
	}
	if (row.navViewController) [self.navigationController pushViewController:row.navViewController animated:YES];
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch *)sender {
	RYGSetting *row = objc_getAssociatedObject(sender, &kRYGRowKey);
	if (row.switchAction) { row.switchAction(sender.isOn); return; }
	if (!row.defaultsKey.length) return;
	[NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:row.defaultsKey];
	if (row.requiresRestart) [RYGUtils showRestartConfirmation];
	if ([row.defaultsKey isEqualToString:@"hide_suggested_stories"])
		[NSNotificationCenter.defaultCenter postNotificationName:@"RYGSuggestedStoriesReload" object:nil];
	if ([row.defaultsKey isEqualToString:@"show_fake_location_map_button"])
		[NSNotificationCenter.defaultCenter postNotificationName:@"RYGFakeLocationMapBtnPrefChanged" object:nil];
	if ([row.defaultsKey isEqualToString:@"adv_encoding_enabled"]) {
		self.sections = [RYGTweakSettings rebuildAdvancedEncodingSlotInSections:self.sections];
		[self rygReloadFromNotification];
	}
	if ([row.defaultsKey isEqualToString:@"instants_confirm_toggle_btn"]) {
		if (sender.isOn) [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"instants_advance_confirm"];
		[self.tableView reloadData];
	}
}

- (void)stepperChanged:(UIStepper *)sender {
	RYGSetting *row = objc_getAssociatedObject(sender, &kRYGRowKey);
	if (!row.defaultsKey.length) return;
	[NSUserDefaults.standardUserDefaults setDouble:sender.value forKey:row.defaultsKey];
	[self reloadCellForView:sender animated:NO];
}

- (void)menuChanged:(UICommand *)command {
	NSDictionary *props = [command.propertyList isKindOfClass:NSDictionary.class] ? command.propertyList : nil;
	NSString *key = props[@"defaultsKey"];
	id value = props[@"value"];
	if (key.length && value) [NSUserDefaults.standardUserDefaults setValue:value forKey:key];
	[self rygReloadFromNotification];

	NSString *pickerKey = props[@"presentColorPickerForKey"];
	if (pickerKey.length) {
		__weak typeof(self) weakSelf = self;
		[RYGColorPicker presentFrom:self title:command.title defaultsKey:pickerKey defaultColor:UIColor.blackColor onChange:^(__unused UIColor *color) {
			[weakSelf rygReloadFromNotification];
		}];
	}
	if ([props[@"requiresRestart"] boolValue]) [RYGUtils showRestartConfirmation];
}

#pragma mark - Helpers

- (NSString *)formatString:(NSString *)template withValue:(double)value label:(NSString *)label singularLabel:(NSString *)singularLabel {
	if (fabs(value) < 0.00001) value = 0.0;
	NSString *unit = fabs(value - 1.0) < 0.00001 ? singularLabel : label;
	static NSNumberFormatter *f;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ f = NSNumberFormatter.new; f.numberStyle = NSNumberFormatterDecimalStyle; f.minimumFractionDigits = 0; });
	f.maximumFractionDigits = [RYGUtils decimalPlacesInDouble:value];
	return [NSString stringWithFormat:template, [f stringFromNumber:@(value)] ?: @"0", unit ?: @""];
}

- (void)reloadCellForView:(UIView *)view animated:(BOOL)animated {
	UIView *cur = view;
	while (cur && ![cur isKindOfClass:UITableViewCell.class]) cur = cur.superview;
	if (!cur) return;
	NSIndexPath *ip = [self.tableView indexPathForCell:(UITableViewCell *)cur];
	if (ip) [self.tableView reloadRowsAtIndexPaths:@[ip] withRowAnimation:animated ? UITableViewRowAnimationAutomatic : UITableViewRowAnimationNone];
}

- (void)reloadCellForView:(UIView *)view { [self reloadCellForView:view animated:NO]; }

- (void)loadImageFromURL:(NSURL *)url atIndexPath:(NSIndexPath *)ip forTableView:(UITableView *)tv {
	if (!url) return;
	[RYGImageCache loadImageFromURL:url completion:^(UIImage *image) {
		if (!image) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
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