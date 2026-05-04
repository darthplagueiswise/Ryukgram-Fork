#import "SCIEnabledExperimentTogglesViewController.h"
#import "../Features/ExpFlags/SCIEnabledExperimentRuntime.h"
#import "../Utils.h"
#import <objc/runtime.h>

@interface SCIEnabledExperimentCell : UITableViewCell
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *detail;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, copy) void (^toggleChanged)(BOOL on);
@property (nonatomic, copy) void (^resetPressed)(void);
@end

@implementation SCIEnabledExperimentCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    self.title = [UILabel new];
    self.title.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.title.numberOfLines = 0;
    self.title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.title];

    self.detail = [UILabel new];
    self.detail.font = [UIFont systemFontOfSize:10];
    self.detail.textColor = UIColor.secondaryLabelColor;
    self.detail.numberOfLines = 0;
    self.detail.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.detail];

    self.toggleSwitch = [UISwitch new];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleSwitch addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.toggleSwitch];

    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"System" forState:UIControlStateNormal];
    self.resetButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.resetButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
        [self.title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.detail.topAnchor constraintEqualToAnchor:self.title.bottomAnchor constant:4],
        [self.detail.leadingAnchor constraintEqualToAnchor:self.title.leadingAnchor],
        [self.detail.trailingAnchor constraintEqualToAnchor:self.title.trailingAnchor],
        [self.toggleSwitch.topAnchor constraintEqualToAnchor:self.detail.bottomAnchor constant:8],
        [self.toggleSwitch.leadingAnchor constraintEqualToAnchor:self.title.leadingAnchor],
        [self.toggleSwitch.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        [self.resetButton.centerYAnchor constraintEqualToAnchor:self.toggleSwitch.centerYAnchor],
        [self.resetButton.leadingAnchor constraintEqualToAnchor:self.toggleSwitch.trailingAnchor constant:18],
    ]];
    return self;
}

- (void)switchChanged {
    if (self.toggleChanged) self.toggleChanged(self.toggleSwitch.isOn);
}

- (void)resetTapped {
    if (self.resetPressed) self.resetPressed();
}

@end

@interface SCIEnabledExperimentTogglesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<SCIEnabledExperimentEntry *> *> *groupedRows;
@end

@implementation SCIEnabledExperimentTogglesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Enabled Experiments";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [SCIEnabledExperimentRuntime install];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Seen", @"ON", @"OFF", @"Forced"]];
    self.filterControl.selectedSegmentIndex = 0;
    [self.filterControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.filterControl];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search getter group, source, class, method…";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.footerLabel = [UILabel new];
    self.footerLabel.font = [UIFont systemFontOfSize:11];
    self.footerLabel.textColor = UIColor.secondaryLabelColor;
    self.footerLabel.numberOfLines = 0;
    self.footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.footerLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 118;
    [self.tableView registerClass:SCIEnabledExperimentCell.class forCellReuseIdentifier:@"enabledCell"];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(reload)];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.filterControl.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [self.footerLabel.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:2],
        [self.footerLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [self.footerLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [self.tableView.topAnchor constraintEqualToAnchor:self.footerLabel.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
    ]];

    [self rebuildGroups];
    [self updateFooter];
}

- (NSArray<SCIEnabledExperimentEntry *> *)flatRows {
    return [SCIEnabledExperimentRuntime filteredEntriesForQuery:self.query ?: @"" mode:self.filterControl.selectedSegmentIndex];
}

- (NSString *)getterGroupForEntry:(SCIEnabledExperimentEntry *)entry {
    if (entry.source.length) return entry.source;
    return @"Other / Main Executable";
}

- (NSArray<NSString *> *)preferredGroupOrder {
    return @[
        @"Autofill/Internal",
        @"FBCustomExperimentManager",
        @"FDIDExperimentGenerator",
        @"LID/MetaLocalExperiment",
        @"MetaLocalExperiment",
        @"MobileConfig/EasyGating",
        @"IGUserLauncherSet",
        @"Dogfood/Internal",
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

- (void)rebuildGroups {
    NSArray<SCIEnabledExperimentEntry *> *rows = [self flatRows];
    NSMutableDictionary<NSString *, NSMutableArray<SCIEnabledExperimentEntry *> *> *groups = [NSMutableDictionary dictionary];

    for (SCIEnabledExperimentEntry *entry in rows) {
        NSString *group = [self getterGroupForEntry:entry];
        NSMutableArray *bucket = groups[group];
        if (!bucket) {
            bucket = [NSMutableArray array];
            groups[group] = bucket;
        }
        [bucket addObject:entry];
    }

    NSMutableArray<NSString *> *orderedTitles = [NSMutableArray array];
    for (NSString *preferred in [self preferredGroupOrder]) {
        if (groups[preferred].count) [orderedTitles addObject:preferred];
    }

    NSArray *remaining = [[groups allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    for (NSString *title in remaining) {
        if (![orderedTitles containsObject:title]) [orderedTitles addObject:title];
    }

    NSMutableDictionary *immutableGroups = [NSMutableDictionary dictionary];
    for (NSString *title in orderedTitles) {
        NSArray *bucket = groups[title] ?: @[];
        immutableGroups[title] = [bucket sortedArrayUsingComparator:^NSComparisonResult(SCIEnabledExperimentEntry *a, SCIEnabledExperimentEntry *b) {
            NSComparisonResult c = [a.className caseInsensitiveCompare:b.className];
            if (c != NSOrderedSame) return c;
            return [a.methodName caseInsensitiveCompare:b.methodName];
        }];
    }

    self.sectionTitles = orderedTitles;
    self.groupedRows = immutableGroups;
}

- (NSArray<SCIEnabledExperimentEntry *> *)rowsForSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.sectionTitles.count) return @[];
    NSString *title = self.sectionTitles[(NSUInteger)section];
    return self.groupedRows[title] ?: @[];
}

- (SCIEnabledExperimentEntry *)entryAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = [self rowsForSection:indexPath.section];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)indexPath.row];
}

- (void)reload {
    [self rebuildGroups];
    [self updateFooter];
    [self.tableView reloadData];
}

- (void)updateFooter {
    NSUInteger total = [SCIEnabledExperimentRuntime allEntries].count;
    NSUInteger shown = [self flatRows].count;
    NSUInteger installed = [SCIEnabledExperimentRuntime installedCount];
    self.footerLabel.text = [NSString stringWithFormat:@"Grouped by getter/source · main exec only · installed=%lu · total=%lu · showing=%lu · groups=%lu · switch shows system ON/OFF when observed; System clears override.", (unsigned long)installed, (unsigned long)total, (unsigned long)shown, (unsigned long)self.sectionTitles.count];
}

- (BOOL)effectiveSwitchValueForEntry:(SCIEnabledExperimentEntry *)entry {
    SCIExpFlagOverride state = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    if (state == SCIExpFlagOverrideTrue) return YES;
    if (state == SCIExpFlagOverrideFalse) return NO;
    return entry.defaultKnown ? entry.defaultValue : NO;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sectionTitles.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self rowsForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *rows = [self rowsForSection:section];
    NSString *title = self.sectionTitles[(NSUInteger)section];
    return [NSString stringWithFormat:@"%@  (%lu)", title, (unsigned long)rows.count];
}

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSString *title in self.sectionTitles) {
        if ([title hasPrefix:@"Autofill"]) [titles addObject:@"Auto"];
        else if ([title hasPrefix:@"FBCustom"]) [titles addObject:@"FB"];
        else if ([title hasPrefix:@"FDID"]) [titles addObject:@"FDID"];
        else if ([title hasPrefix:@"LID"]) [titles addObject:@"LID"];
        else if ([title hasPrefix:@"Meta"]) [titles addObject:@"Meta"];
        else if ([title hasPrefix:@"Mobile"]) [titles addObject:@"MC"];
        else if ([title hasPrefix:@"IGUser"]) [titles addObject:@"LS"];
        else if ([title hasPrefix:@"Dogfood"]) [titles addObject:@"Dog"];
        else if ([title hasPrefix:@"Quick"]) [titles addObject:@"QS"];
        else if ([title hasPrefix:@"Friending"]) [titles addObject:@"Fr"];
        else if ([title hasPrefix:@"Direct"]) [titles addObject:@"DM"];
        else if (title.length > 0) [titles addObject:[title substringToIndex:MIN((NSUInteger)3, title.length)]];
    }
    return titles;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SCIEnabledExperimentCell *cell = [tv dequeueReusableCellWithIdentifier:@"enabledCell" forIndexPath:ip];
    SCIEnabledExperimentEntry *entry = [self entryAtIndexPath:ip];
    NSString *prefix = entry.classMethod ? @"+" : @"-";
    cell.title.text = [NSString stringWithFormat:@"%@[%@ %@]", prefix, entry.className, entry.methodName];
    cell.detail.text = [SCIEnabledExperimentRuntime summaryTextForEntry:entry];

    SCIExpFlagOverride state = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    [cell.toggleSwitch setOn:[self effectiveSwitchValueForEntry:entry] animated:NO];
    cell.toggleSwitch.enabled = entry.defaultKnown || state != SCIExpFlagOverrideOff;
    cell.resetButton.enabled = state != SCIExpFlagOverrideOff;
    cell.resetButton.alpha = cell.resetButton.enabled ? 1.0 : 0.35;

    if (!entry.defaultKnown && state == SCIExpFlagOverrideOff) {
        cell.detail.text = [NSString stringWithFormat:@"%@ · waiting for app to call getter before showing system ON/OFF", cell.detail.text ?: @""];
    }

    __weak typeof(self) weakSelf = self;
    __weak SCIEnabledExperimentEntry *weakEntry = entry;
    cell.toggleChanged = ^(BOOL on) {
        [SCIEnabledExperimentRuntime setSavedState:(on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forEntry:weakEntry];
        [weakSelf reload];
    };
    cell.resetPressed = ^{
        [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideOff forEntry:weakEntry];
        [weakSelf reload];
    };
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SCIEnabledExperimentEntry *entry = [self entryAtIndexPath:ip];
    if (!entry) return;
    NSString *message = [NSString stringWithFormat:@"%@\n\nGroup:\n%@\n\nSwitch value: %@\nOverride: %@\n\nKey:\n%@", [SCIEnabledExperimentRuntime summaryTextForEntry:entry], [self getterGroupForEntry:entry], [self effectiveSwitchValueForEntry:entry] ? @"ON" : @"OFF", [SCIEnabledExperimentRuntime stateLabelForEntry:entry], entry.key ?: @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:entry.methodName message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideTrue forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideFalse forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"System default" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideOff forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.key ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy class.method" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@", entry.className ?: @"", entry.methodName ?: @""]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
