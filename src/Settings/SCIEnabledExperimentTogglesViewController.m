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
    self.title.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.title.numberOfLines = 2;
    self.title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.title];

    self.detail = [UILabel new];
    self.detail.font = [UIFont systemFontOfSize:10];
    self.detail.textColor = UIColor.secondaryLabelColor;
    self.detail.numberOfLines = 2;
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
        [self.toggleSwitch.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.resetButton.centerYAnchor constraintEqualToAnchor:self.toggleSwitch.centerYAnchor],
        [self.resetButton.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor constant:-12],

        [self.title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
        [self.title.trailingAnchor constraintEqualToAnchor:self.resetButton.leadingAnchor constant:-10],
        [self.detail.topAnchor constraintEqualToAnchor:self.title.bottomAnchor constant:3],
        [self.detail.leadingAnchor constraintEqualToAnchor:self.title.leadingAnchor],
        [self.detail.trailingAnchor constraintEqualToAnchor:self.title.trailingAnchor],
        [self.detail.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
    ]];
    return self;
}

- (void)switchChanged { if (self.toggleChanged) self.toggleChanged(self.toggleSwitch.isOn); }
- (void)resetTapped { if (self.resetPressed) self.resetPressed(); }
@end

@interface SCIEnabledGetterHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *detail;
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UIButton *systemButton;
@property (nonatomic, copy) void (^masterChanged)(BOOL on);
@property (nonatomic, copy) void (^systemPressed)(void);
@end

@implementation SCIEnabledGetterHeaderView
- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;

    self.title = [UILabel new];
    self.title.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    self.title.numberOfLines = 2;
    self.title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.title];

    self.detail = [UILabel new];
    self.detail.font = [UIFont systemFontOfSize:10];
    self.detail.textColor = UIColor.secondaryLabelColor;
    self.detail.numberOfLines = 2;
    self.detail.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.detail];

    self.masterSwitch = [UISwitch new];
    self.masterSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.masterSwitch addTarget:self action:@selector(masterSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.masterSwitch];

    self.systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.systemButton setTitle:@"System" forState:UIControlStateNormal];
    self.systemButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.systemButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.systemButton addTarget:self action:@selector(systemTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.systemButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.masterSwitch.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.masterSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [self.systemButton.centerYAnchor constraintEqualToAnchor:self.masterSwitch.centerYAnchor],
        [self.systemButton.trailingAnchor constraintEqualToAnchor:self.masterSwitch.leadingAnchor constant:-12],

        [self.title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [self.title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [self.title.trailingAnchor constraintEqualToAnchor:self.systemButton.leadingAnchor constant:-10],
        [self.detail.topAnchor constraintEqualToAnchor:self.title.bottomAnchor constant:2],
        [self.detail.leadingAnchor constraintEqualToAnchor:self.title.leadingAnchor],
        [self.detail.trailingAnchor constraintEqualToAnchor:self.title.trailingAnchor],
        [self.detail.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-7],
    ]];
    return self;
}
- (void)masterSwitchChanged { if (self.masterChanged) self.masterChanged(self.masterSwitch.isOn); }
- (void)systemTapped { if (self.systemPressed) self.systemPressed(); }
@end

@interface SCIEnabledExperimentTogglesViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<NSString *> *sectionKeys;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<SCIEnabledExperimentEntry *> *> *groupedRows;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *sectionDisplayNames;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *sectionSources;
@end

@implementation SCIEnabledExperimentTogglesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SCI DexKit";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    [SCIEnabledExperimentRuntime install];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Seen", @"ON", @"OFF", @"Forced"]];
    self.filterControl.selectedSegmentIndex = 0;
    [self.filterControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.filterControl];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search getter owner, function, source…";
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
    self.tableView.estimatedRowHeight = 76;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 62;
    [self.tableView registerClass:SCIEnabledExperimentCell.class forCellReuseIdentifier:@"enabledCell"];
    [self.tableView registerClass:SCIEnabledGetterHeaderView.class forHeaderFooterViewReuseIdentifier:@"getterHeader"];
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

    [self reload];
}

- (NSArray<SCIEnabledExperimentEntry *> *)flatRows {
    return [SCIEnabledExperimentRuntime filteredEntriesForQuery:self.query ?: @"" mode:self.filterControl.selectedSegmentIndex];
}

- (NSString *)getterOwnerKeyForEntry:(SCIEnabledExperimentEntry *)entry {
    NSString *owner = entry.className.length ? entry.className : @"UnknownOwner";
    NSString *source = entry.source.length ? entry.source : @"Main Executable";
    return [NSString stringWithFormat:@"%@|%@", source, owner];
}

- (NSString *)compactGetterOwnerName:(NSString *)className {
    if (!className.length) return @"UnknownOwner";
    NSArray<NSString *> *parts = [className componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : className;
}

- (NSArray<NSString *> *)preferredSourceOrder {
    return @[
        @"Autofill/Internal", @"Prism/Menu", @"Direct Notes", @"QuickSnap/Direct", @"Homecoming", @"LiquidGlass/TabBar",
        @"FBCustomExperimentManager", @"FDIDExperimentGenerator", @"LID/MetaLocalExperiment", @"MetaLocalExperiment",
        @"MobileConfig/EasyGating", @"IGUserLauncherSet", @"Dogfood/Internal", @"Friending/FriendsTab",
        @"Feed", @"Direct/Inbox", @"Blend", @"GenAI/MagicMod", @"Main Executable", @"Other / Main Executable"
    ];
}

- (NSInteger)sourceRank:(NSString *)source {
    NSUInteger idx = [[self preferredSourceOrder] indexOfObject:source ?: @""];
    return idx == NSNotFound ? 999 : (NSInteger)idx;
}

- (void)rebuildGroups {
    NSArray<SCIEnabledExperimentEntry *> *rows = [self flatRows];
    NSMutableDictionary<NSString *, NSMutableArray<SCIEnabledExperimentEntry *> *> *groups = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *sources = [NSMutableDictionary dictionary];

    for (SCIEnabledExperimentEntry *entry in rows) {
        NSString *key = [self getterOwnerKeyForEntry:entry];
        if (!groups[key]) groups[key] = [NSMutableArray array];
        [groups[key] addObject:entry];
        names[key] = [self compactGetterOwnerName:entry.className];
        sources[key] = entry.source.length ? entry.source : @"Main Executable";
    }

    NSArray *ordered = [[groups allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *sa = sources[a] ?: @"";
        NSString *sb = sources[b] ?: @"";
        NSInteger ra = [self sourceRank:sa];
        NSInteger rb = [self sourceRank:sb];
        if (ra < rb) return NSOrderedAscending;
        if (ra > rb) return NSOrderedDescending;
        return [names[a] caseInsensitiveCompare:names[b]];
    }];

    NSMutableDictionary *immutableGroups = [NSMutableDictionary dictionary];
    for (NSString *key in ordered) {
        NSArray *bucket = groups[key] ?: @[];
        immutableGroups[key] = [bucket sortedArrayUsingComparator:^NSComparisonResult(SCIEnabledExperimentEntry *a, SCIEnabledExperimentEntry *b) {
            return [a.methodName caseInsensitiveCompare:b.methodName];
        }];
    }

    self.sectionKeys = ordered;
    self.groupedRows = immutableGroups;
    self.sectionDisplayNames = names;
    self.sectionSources = sources;
}

- (NSArray<SCIEnabledExperimentEntry *> *)rowsForSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.sectionKeys.count) return @[];
    NSString *key = self.sectionKeys[(NSUInteger)section];
    return self.groupedRows[key] ?: @[];
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
    self.footerLabel.text = [NSString stringWithFormat:@"Grouped by getter owner · main exec only · installed=%lu · total=%lu · showing=%lu · getters=%lu · header switch is master override for that getter owner.", (unsigned long)installed, (unsigned long)total, (unsigned long)shown, (unsigned long)self.sectionKeys.count];
}

- (BOOL)effectiveSwitchValueForEntry:(SCIEnabledExperimentEntry *)entry {
    SCIExpFlagOverride state = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    if (state == SCIExpFlagOverrideTrue) return YES;
    if (state == SCIExpFlagOverrideFalse) return NO;
    return entry.defaultKnown ? entry.defaultValue : NO;
}

- (NSDictionary *)statsForRows:(NSArray<SCIEnabledExperimentEntry *> *)rows {
    NSUInteger observed = 0, systemOn = 0, forced = 0, forcedOn = 0, forcedOff = 0, effectiveOn = 0;
    for (SCIEnabledExperimentEntry *entry in rows) {
        if (entry.defaultKnown) {
            observed++;
            if (entry.defaultValue) systemOn++;
        }
        SCIExpFlagOverride state = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
        if (state != SCIExpFlagOverrideOff) forced++;
        if (state == SCIExpFlagOverrideTrue) forcedOn++;
        if (state == SCIExpFlagOverrideFalse) forcedOff++;
        if ([self effectiveSwitchValueForEntry:entry]) effectiveOn++;
    }
    return @{@"observed": @(observed), @"systemOn": @(systemOn), @"forced": @(forced), @"forcedOn": @(forcedOn), @"forcedOff": @(forcedOff), @"effectiveOn": @(effectiveOn)};
}

- (BOOL)masterSwitchValueForRows:(NSArray<SCIEnabledExperimentEntry *> *)rows {
    NSDictionary *s = [self statsForRows:rows];
    return [s[@"effectiveOn"] unsignedIntegerValue] > 0;
}

- (void)setOverride:(SCIExpFlagOverride)state forRows:(NSArray<SCIEnabledExperimentEntry *> *)rows {
    for (SCIEnabledExperimentEntry *entry in rows) {
        [SCIEnabledExperimentRuntime setSavedState:state forEntry:entry];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sectionKeys.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self rowsForSection:section].count; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    SCIEnabledGetterHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"getterHeader"];
    NSArray<SCIEnabledExperimentEntry *> *rows = [self rowsForSection:section];
    NSString *key = self.sectionKeys[(NSUInteger)section];
    NSString *name = self.sectionDisplayNames[key] ?: key;
    NSString *source = self.sectionSources[key] ?: @"Main Executable";
    NSDictionary *stats = [self statsForRows:rows];
    NSUInteger observed = [stats[@"observed"] unsignedIntegerValue];
    NSUInteger systemOn = [stats[@"systemOn"] unsignedIntegerValue];
    NSUInteger forced = [stats[@"forced"] unsignedIntegerValue];
    NSUInteger effectiveOn = [stats[@"effectiveOn"] unsignedIntegerValue];

    header.title.text = name;
    header.detail.text = [NSString stringWithFormat:@"%@ · funcs=%lu · observed=%lu · systemON=%lu · effectiveON=%lu · forced=%lu", source, (unsigned long)rows.count, (unsigned long)observed, (unsigned long)systemOn, (unsigned long)effectiveOn, (unsigned long)forced];
    [header.masterSwitch setOn:[self masterSwitchValueForRows:rows] animated:NO];
    header.masterSwitch.enabled = rows.count > 0;
    header.systemButton.enabled = forced > 0;
    header.systemButton.alpha = forced > 0 ? 1.0 : 0.35;

    __weak typeof(self) weakSelf = self;
    __block NSArray<SCIEnabledExperimentEntry *> *capturedRows = [rows copy];
    header.masterChanged = ^(BOOL on) {
        [weakSelf setOverride:(on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forRows:capturedRows];
        [weakSelf reload];
    };
    header.systemPressed = ^{
        [weakSelf setOverride:SCIExpFlagOverrideOff forRows:capturedRows];
        [weakSelf reload];
    };
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 66.0; }

- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSString *key in self.sectionKeys) {
        NSString *name = self.sectionDisplayNames[key] ?: key;
        NSString *clean = [name stringByReplacingOccurrencesOfString:@"IG" withString:@""];
        [titles addObject:[clean substringToIndex:MIN((NSUInteger)3, clean.length)]];
    }
    return titles;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SCIEnabledExperimentCell *cell = [tv dequeueReusableCellWithIdentifier:@"enabledCell" forIndexPath:ip];
    SCIEnabledExperimentEntry *entry = [self entryAtIndexPath:ip];
    cell.title.text = entry.methodName ?: @"?";

    NSString *system = [SCIEnabledExperimentRuntime defaultLabelForEntry:entry];
    NSString *state = [SCIEnabledExperimentRuntime stateLabelForEntry:entry];
    cell.detail.text = [NSString stringWithFormat:@"system=%@ · state=%@ · hits=%lu · %@", system, state, (unsigned long)entry.hitCount, entry.typeEncoding ?: @""];
    if (!entry.defaultKnown && [SCIEnabledExperimentRuntime savedStateForEntry:entry] == SCIExpFlagOverrideOff) {
        cell.detail.text = [cell.detail.text stringByAppendingString:@" · waiting for call"];
    }

    SCIExpFlagOverride override = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    [cell.toggleSwitch setOn:[self effectiveSwitchValueForEntry:entry] animated:NO];
    cell.toggleSwitch.enabled = entry.defaultKnown || override != SCIExpFlagOverrideOff;
    cell.resetButton.enabled = override != SCIExpFlagOverrideOff;
    cell.resetButton.alpha = cell.resetButton.enabled ? 1.0 : 0.35;

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
    NSString *message = [NSString stringWithFormat:@"Getter owner:\n%@\n\nFunction:\n%@\n\nSource: %@\nSystem: %@\nOverride: %@\nSwitch value: %@\nHits: %lu\nEncoding: %@\n\nKey:\n%@", entry.className ?: @"?", entry.methodName ?: @"?", entry.source ?: @"?", [SCIEnabledExperimentRuntime defaultLabelForEntry:entry], [SCIEnabledExperimentRuntime stateLabelForEntry:entry], [self effectiveSwitchValueForEntry:entry] ? @"ON" : @"OFF", (unsigned long)entry.hitCount, entry.typeEncoding ?: @"", entry.key ?: @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:entry.methodName message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideTrue forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideFalse forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"System default" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideOff forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.key ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy getter owner" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.className ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy function" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.methodName ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
