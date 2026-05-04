#import "TweakSettings.h"
#import "SCIExperimentRuntimeBrowserViewController.h"
#import "SCIEnabledExperimentTogglesViewController.h"
#import "../Features/ExpFlags/SCIEnabledExperimentRuntime.h"
#import "../Features/ExpFlags/SCIAutofillInternalDevMode.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

typedef NS_ENUM(NSInteger, SCIDexKitFilterMode) {
    SCIDexKitFilterAll = 0,
    SCIDexKitFilterSeen,
    SCIDexKitFilterOn,
    SCIDexKitFilterOff,
    SCIDexKitFilterForced,
};

@interface SCIDexKitProbeCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIButton *systemButton;
@property (nonatomic, copy) void (^toggleChanged)(BOOL on);
@property (nonatomic, copy) void (^systemPressed)(void);
@end

@implementation SCIDexKitProbeCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _titleLabel.numberOfLines = 0;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    _detailLabel = [UILabel new];
    _detailLabel.font = [UIFont systemFontOfSize:10];
    _detailLabel.textColor = UIColor.secondaryLabelColor;
    _detailLabel.numberOfLines = 0;
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_detailLabel];

    _toggleSwitch = [UISwitch new];
    _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_toggleSwitch addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_toggleSwitch];

    _systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_systemButton setTitle:@"System" forState:UIControlStateNormal];
    _systemButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _systemButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_systemButton addTarget:self action:@selector(systemTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_systemButton];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
        [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_toggleSwitch.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:8.0],
        [_toggleSwitch.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_toggleSwitch.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],
        [_systemButton.centerYAnchor constraintEqualToAnchor:_toggleSwitch.centerYAnchor],
        [_systemButton.leadingAnchor constraintEqualToAnchor:_toggleSwitch.trailingAnchor constant:18.0],
    ]];
    return self;
}
- (void)switchChanged { if (self.toggleChanged) self.toggleChanged(self.toggleSwitch.isOn); }
- (void)systemTapped { if (self.systemPressed) self.systemPressed(); }
@end

@interface SCIDexKitViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<NSString *> *probeSectionTitles;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<SCIEnabledExperimentEntry *> *> *probeGroups;
@end

@implementation SCIDexKitViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SCI DexKit";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [SCIEnabledExperimentRuntime install];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Seen", @"ON", @"OFF", @"Forced"]];
    self.filterControl.selectedSegmentIndex = SCIDexKitFilterAll;
    [self.filterControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.filterControl];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search controller, provider, getter, class, MobileConfig…";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.summaryLabel = [UILabel new];
    self.summaryLabel.font = [UIFont systemFontOfSize:11.0];
    self.summaryLabel.textColor = UIColor.secondaryLabelColor;
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.summaryLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 118.0;
    [self.tableView registerClass:SCIDexKitProbeCell.class forCellReuseIdentifier:@"probeCell"];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(reload)];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:g.topAnchor constant:8.0],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12.0],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12.0],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:4.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8.0],
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:2.0],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14.0],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14.0],
        [self.tableView.topAnchor constraintEqualToAnchor:self.summaryLabel.bottomAnchor constant:4.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
    ]];

    [self reload];
}

- (void)reload {
    [self rebuildProbeGroups];
    [self updateSummary];
    [self.tableView reloadData];
}

- (NSArray<NSString *> *)preferredSourceOrder {
    return @[
        @"Autofill/Internal",
        @"Dogfood/Internal",
        @"MobileConfig/EasyGating",
        @"FBCustomExperimentManager",
        @"FDIDExperimentGenerator",
        @"LID/MetaLocalExperiment",
        @"MetaLocalExperiment",
        @"IGUserLauncherSet",
        @"QuickSnap/Direct",
        @"Friending/FriendsTab",
        @"Feed",
        @"Direct/Inbox",
        @"Blend",
        @"GenAI/MagicMod",
        @"Main Executable",
        @"Other / Main Executable"
    ];
}

- (NSArray<SCIEnabledExperimentEntry *> *)filteredProbeRows {
    return [SCIEnabledExperimentRuntime filteredEntriesForQuery:self.query ?: @"" mode:self.filterControl.selectedSegmentIndex];
}

- (void)rebuildProbeGroups {
    NSMutableDictionary<NSString *, NSMutableArray<SCIEnabledExperimentEntry *> *> *groups = [NSMutableDictionary dictionary];
    for (SCIEnabledExperimentEntry *entry in [self filteredProbeRows]) {
        NSString *source = entry.source.length ? entry.source : @"Other / Main Executable";
        if (!groups[source]) groups[source] = [NSMutableArray array];
        [groups[source] addObject:entry];
    }

    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *source in [self preferredSourceOrder]) {
        if (groups[source].count) [titles addObject:source];
    }
    for (NSString *source in [[groups allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        if (![titles containsObject:source]) [titles addObject:source];
    }

    NSMutableDictionary *immutable = [NSMutableDictionary dictionary];
    for (NSString *source in titles) {
        immutable[source] = [groups[source] sortedArrayUsingComparator:^NSComparisonResult(SCIEnabledExperimentEntry *a, SCIEnabledExperimentEntry *b) {
            NSComparisonResult c = [a.className caseInsensitiveCompare:b.className];
            if (c != NSOrderedSame) return c;
            return [a.methodName caseInsensitiveCompare:b.methodName];
        }];
    }
    self.probeSectionTitles = titles;
    self.probeGroups = immutable;
}

- (void)updateSummary {
    NSArray<SCIEnabledExperimentEntry *> *all = [SCIEnabledExperimentRuntime allEntries];
    NSUInteger observed = 0;
    NSUInteger forced = 0;
    for (SCIEnabledExperimentEntry *entry in all) {
        if (entry.defaultKnown) observed++;
        if ([SCIEnabledExperimentRuntime savedStateForEntry:entry] != SCIExpFlagOverrideOff) forced++;
    }
    self.summaryLabel.text = [NSString stringWithFormat:@"Unified registry · providers: native controllers + main-exec ObjC getter probes + Autofill defaults/tools · probes=%lu · observed=%lu · forced=%lu · showing=%lu · groups=%lu", (unsigned long)all.count, (unsigned long)observed, (unsigned long)forced, (unsigned long)[self filteredProbeRows].count, (unsigned long)self.probeSectionTitles.count];
}

- (UIViewController *)topPresenter {
    UIViewController *vc = self;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

- (void)showText:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
        UIPasteboard.generalPasteboard.string = message ?: @"";
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [[self topPresenter] presentViewController:a animated:YES completion:nil];
}

- (void)sendNativeDogfoodSelector:(SEL)sel {
    if (![self respondsToSelector:sel]) {
        [self showText:@"Native Controller" message:[NSString stringWithFormat:@"%@ is not installed on this object. SCIDogfoodingMainLauncher hook may not be loaded.", NSStringFromSelector(sel)]];
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
}

- (NSString *)nativeControllerStatusText {
    NSMutableArray *lines = [NSMutableArray array];
    NSArray<NSArray<NSString *> *> *checks = @[
        @[@"Main Dogfood opener", @"IGDogfoodingSettings.IGDogfoodingSettings", @"openWithConfig:onViewController:userSession:"],
        @[@"Direct Notes Dogfood opener", @"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs", @"notesDogfoodingSettingsOpenOnViewController:userSession:"],
        @[@"Dogfood VC", @"IGDogfoodingSettings.IGDogfoodingSettingsViewController", @"initWithConfig:userSession:"],
        @[@"MetaLocalExperiment List", @"MetaLocalExperimentListViewController", @"initWithExperimentConfigs:experimentGenerator:"],
        @[@"IG Experimental Navigation", @"IGExperimentalNavigationSelectionViewController", @"init"]
    ];
    for (NSArray<NSString *> *check in checks) {
        Class cls = NSClassFromString(check[1]);
        SEL sel = NSSelectorFromString(check[2]);
        BOOL hasClass = cls != Nil;
        BOOL hasMethod = hasClass && (class_getClassMethod(cls, sel) || class_getInstanceMethod(cls, sel));
        [lines addObject:[NSString stringWithFormat:@"%@: class=%@ method=%@ · %@ %@", check[0], hasClass ? @"YES" : @"NO", hasMethod ? @"YES" : @"NO", check[1], check[2]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (BOOL)effectiveSwitchValueForEntry:(SCIEnabledExperimentEntry *)entry {
    SCIExpFlagOverride state = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    if (state == SCIExpFlagOverrideTrue) return YES;
    if (state == SCIExpFlagOverrideFalse) return NO;
    return entry.defaultKnown ? entry.defaultValue : NO;
}

- (NSArray<NSDictionary *> *)controllerRows {
    return @[
        @{@"title": @"Open Direct Notes Dogfooding", @"subtitle": @"Native opener: notesDogfoodingSettingsOpenOnViewController:userSession:. Uses cached/live IGUserSession like the existing Dogfood launcher.", @"kind": @"notes"},
        @{@"title": @"Open Main Dogfood Settings", @"subtitle": @"Native opener: openWithConfig:onViewController:userSession:. Requires a real cached IGDogfoodingSettingsConfig; no fake fallback.", @"kind": @"main"},
        @{@"title": @"Native Controller Status", @"subtitle": @"Shows whether known native controller/open selectors exist in this build.", @"kind": @"status"}
    ];
}

- (NSArray<NSDictionary *> *)toolRows {
    return @[
        @{@"title": @"Runtime Browser", @"subtitle": @"Raw runtime browser for classes/properties/ivars. Kept as a low-level fallback; DexKit is the primary UI.", @"kind": @"runtime"},
        @{@"title": @"Legacy Enabled Getter List", @"subtitle": @"Old focused getter list, backed by the same SCIEnabledExperimentRuntime registry.", @"kind": @"enabled"},
        @{@"title": @"Apply Autofill Defaults", @"subtitle": @"Writes Autofill backing defaults, but getter overrides should be managed above under Autofill/Internal.", @"kind": @"autofillApply"},
        @{@"title": @"Autofill Status", @"subtitle": @"Safe status: backing defaults + selector availability; no direct Swift getter calls.", @"kind": @"autofillStatus"}
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2 + self.probeSectionTitles.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return [self controllerRows].count;
    if (section == 1) return [self toolRows].count;
    NSString *title = self.probeSectionTitles[(NSUInteger)section - 2];
    return [self.probeGroups[title] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Native Controllers";
    if (section == 1) return @"Unified Tools / Fallbacks";
    NSString *source = self.probeSectionTitles[(NSUInteger)section - 2];
    return [NSString stringWithFormat:@"%@ (%lu)", source, (unsigned long)[self.probeGroups[source] count]];
}

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    NSMutableArray *titles = [NSMutableArray arrayWithObjects:@"Ctl", @"Tools", nil];
    for (NSString *title in self.probeSectionTitles) {
        if ([title hasPrefix:@"Autofill"]) [titles addObject:@"Auto"];
        else if ([title hasPrefix:@"Dogfood"]) [titles addObject:@"Dog"];
        else if ([title hasPrefix:@"Mobile"]) [titles addObject:@"MC"];
        else if ([title hasPrefix:@"FBCustom"]) [titles addObject:@"FB"];
        else if ([title hasPrefix:@"FDID"]) [titles addObject:@"FDID"];
        else if ([title hasPrefix:@"Meta"]) [titles addObject:@"Meta"];
        else if ([title hasPrefix:@"IGUser"]) [titles addObject:@"LS"];
        else if ([title hasPrefix:@"Direct"]) [titles addObject:@"DM"];
        else [titles addObject:[title substringToIndex:MIN((NSUInteger)3, title.length)]];
    }
    return titles;
}

- (SCIEnabledExperimentEntry *)entryAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section < 2) return nil;
    NSString *source = self.probeSectionTitles[(NSUInteger)indexPath.section - 2];
    NSArray *rows = self.probeGroups[source] ?: @[];
    if (indexPath.row >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)indexPath.row];
}

- (UITableViewCell *)actionCellForTableView:(UITableView *)tv title:(NSString *)title subtitle:(NSString *)subtitle {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"actionCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"actionCell"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.text = title;
    cell.detailTextLabel.text = subtitle;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        NSDictionary *row = [self controllerRows][(NSUInteger)indexPath.row];
        return [self actionCellForTableView:tv title:row[@"title"] subtitle:row[@"subtitle"]];
    }
    if (indexPath.section == 1) {
        NSDictionary *row = [self toolRows][(NSUInteger)indexPath.row];
        return [self actionCellForTableView:tv title:row[@"title"] subtitle:row[@"subtitle"]];
    }

    SCIDexKitProbeCell *cell = [tv dequeueReusableCellWithIdentifier:@"probeCell" forIndexPath:indexPath];
    SCIEnabledExperimentEntry *entry = [self entryAtIndexPath:indexPath];
    NSString *prefix = entry.classMethod ? @"+" : @"-";
    cell.titleLabel.text = [NSString stringWithFormat:@"%@[%@ %@]", prefix, entry.className ?: @"?", entry.methodName ?: @"?"];
    cell.detailLabel.text = [SCIEnabledExperimentRuntime summaryTextForEntry:entry];
    if (!entry.defaultKnown && [SCIEnabledExperimentRuntime savedStateForEntry:entry] == SCIExpFlagOverrideOff) {
        cell.detailLabel.text = [cell.detailLabel.text stringByAppendingString:@" · waiting for app to call getter"];
    }

    SCIExpFlagOverride state = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    [cell.toggleSwitch setOn:[self effectiveSwitchValueForEntry:entry] animated:NO];
    cell.toggleSwitch.enabled = entry.defaultKnown || state != SCIExpFlagOverrideOff;
    cell.systemButton.enabled = state != SCIExpFlagOverrideOff;
    cell.systemButton.alpha = cell.systemButton.enabled ? 1.0 : 0.35;

    __weak typeof(self) weakSelf = self;
    __weak SCIEnabledExperimentEntry *weakEntry = entry;
    cell.toggleChanged = ^(BOOL on) {
        [SCIEnabledExperimentRuntime setSavedState:(on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forEntry:weakEntry];
        [weakSelf reload];
    };
    cell.systemPressed = ^{
        [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideOff forEntry:weakEntry];
        [weakSelf reload];
    };
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        NSString *kind = [self controllerRows][(NSUInteger)indexPath.row][@"kind"];
        if ([kind isEqualToString:@"notes"]) [self sendNativeDogfoodSelector:@selector(ryDogOpenNotesButtonTapped:)];
        else if ([kind isEqualToString:@"main"]) [self sendNativeDogfoodSelector:@selector(ryDogOpenMainButtonTapped:)];
        else [self showText:@"Native Controller Status" message:[self nativeControllerStatusText]];
        return;
    }

    if (indexPath.section == 1) {
        NSString *kind = [self toolRows][(NSUInteger)indexPath.row][@"kind"];
        if ([kind isEqualToString:@"runtime"]) {
            [self.navigationController pushViewController:[SCIExperimentRuntimeBrowserViewController new] animated:YES];
        } else if ([kind isEqualToString:@"enabled"]) {
            [self.navigationController pushViewController:[SCIEnabledExperimentTogglesViewController new] animated:YES];
        } else if ([kind isEqualToString:@"autofillApply"]) {
            [SCIAutofillInternalDevMode applyEnabledToggles];
            [self showText:@"Autofill" message:[SCIAutofillInternalDevMode statusText]];
        } else if ([kind isEqualToString:@"autofillStatus"]) {
            [self showText:@"Autofill" message:[SCIAutofillInternalDevMode statusText]];
        }
        return;
    }

    SCIEnabledExperimentEntry *entry = [self entryAtIndexPath:indexPath];
    if (!entry) return;
    NSString *message = [NSString stringWithFormat:@"%@\n\nProvider: %@\nSwitch value: %@\nOverride: %@\n\nKey:\n%@", [SCIEnabledExperimentRuntime summaryTextForEntry:entry], entry.source ?: @"?", [self effectiveSwitchValueForEntry:entry] ? @"ON" : @"OFF", [SCIEnabledExperimentRuntime stateLabelForEntry:entry], entry.key ?: @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:entry.methodName message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideTrue forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideFalse forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"System default" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideOff forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.key ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy class.method" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@", entry.className ?: @"", entry.methodName ?: @""]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:indexPath];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end

static NSArray *(*orig_sections_runtime_exp)(id, SEL);

static NSDictionary *RYRuntimeExperimentSection(void) {
    return @{
        @"header": @"SCI DexKit",
        @"footer": @"Unified developer/runtime surface. Native controller openers, main-executable ObjC getter probes, Autofill/Internal, grouped providers, observed system ON/OFF, and override routing are exposed from one primary screen. Old tools remain inside DexKit as fallbacks.",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"SCI DexKit"
                                       subtitle:@"One place for native controllers, runtime getters, observed defaults, source grouping, and ON/OFF overrides."
                                           icon:[SCISymbol symbolWithName:@"square.stack.3d.up"]
                                 viewController:[SCIDexKitViewController new]]
        ]
    };
}

static BOOL RYRuntimeSectionAlreadyPresent(NSArray *navSections) {
    for (NSDictionary *section in navSections) {
        if (![section isKindOfClass:NSDictionary.class]) continue;
        NSString *header = [section[@"header"] isKindOfClass:NSString.class] ? section[@"header"] : @"";
        if ([header isEqualToString:@"SCI DexKit"]) return YES;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : @[];
        for (id rowObj in rows) {
            SCISetting *row = [rowObj isKindOfClass:SCISetting.class] ? rowObj : nil;
            if ([row.title isEqualToString:@"SCI DexKit"]) return YES;
        }
    }
    return NO;
}

static NSArray *RYRuntimeAugmentSections(NSArray *sections) {
    NSMutableArray *outSections = [sections mutableCopy] ?: [NSMutableArray array];

    for (NSUInteger i = 0; i < outSections.count; i++) {
        NSDictionary *section = [outSections[i] isKindOfClass:NSDictionary.class] ? outSections[i] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        BOOL changedRows = NO;

        for (NSUInteger r = 0; r < newRows.count; r++) {
            SCISetting *row = [newRows[r] isKindOfClass:SCISetting.class] ? newRows[r] : nil;
            if (!row) continue;
            if (![row.title isEqualToString:@"Developer Mode"]) continue;

            NSArray *navSections = [row.navSections isKindOfClass:NSArray.class] ? row.navSections : @[];
            if (RYRuntimeSectionAlreadyPresent(navSections)) return outSections;

            NSMutableArray *newNavSections = [navSections mutableCopy] ?: [NSMutableArray array];
            [newNavSections insertObject:RYRuntimeExperimentSection() atIndex:0];
            row.navSections = newNavSections;
            newRows[r] = row;
            changedRows = YES;
            break;
        }

        if (changedRows) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = newRows;
            outSections[i] = newSection;
            return outSections;
        }
    }

    return outSections;
}

static NSArray *new_sections_runtime_exp(id self, SEL _cmd) {
    NSArray *sections = orig_sections_runtime_exp ? orig_sections_runtime_exp(self, _cmd) : @[];
    return RYRuntimeAugmentSections(sections);
}

static void RYInstallRuntimeExperimentMenuHook(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_runtime_exp, (IMP *)&orig_sections_runtime_exp);
}

%ctor {
    [SCIAutofillInternalDevMode registerDefaults];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RYInstallRuntimeExperimentMenuHook();
    });
}
