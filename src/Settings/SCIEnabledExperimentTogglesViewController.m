#import "SCIEnabledExperimentTogglesViewController.h"
#import "../Features/ExpFlags/SCIEnabledExperimentRuntime.h"
#import <UIKit/UIKit.h>

@interface SCIDexKitGetterCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIButton *systemButton;
@property (nonatomic, copy) void (^toggleChanged)(BOOL on);
@property (nonatomic, copy) void (^systemPressed)(void);
@end

@implementation SCIDexKitGetterCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _titleLabel.numberOfLines = 2;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    _stateLabel = [UILabel new];
    _stateLabel.font = [UIFont systemFontOfSize:11];
    _stateLabel.textColor = UIColor.secondaryLabelColor;
    _stateLabel.numberOfLines = 1;
    _stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_stateLabel];

    _toggleSwitch = [UISwitch new];
    _toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_toggleSwitch addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_toggleSwitch];

    _systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_systemButton setTitle:@"System" forState:UIControlStateNormal];
    _systemButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _systemButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_systemButton addTarget:self action:@selector(systemTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_systemButton];

    [NSLayoutConstraint activateConstraints:@[
        [_toggleSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [_systemButton.centerYAnchor constraintEqualToAnchor:_toggleSwitch.centerYAnchor],
        [_systemButton.trailingAnchor constraintEqualToAnchor:_toggleSwitch.leadingAnchor constant:-12],

        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_systemButton.leadingAnchor constant:-10],
        [_stateLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3],
        [_stateLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_stateLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_stateLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9],
    ]];
    return self;
}
- (void)switchChanged { if (self.toggleChanged) self.toggleChanged(self.toggleSwitch.isOn); }
- (void)systemTapped { if (self.systemPressed) self.systemPressed(); }
@end

@interface SCIDexKitGetterHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UIButton *systemButton;
@property (nonatomic, copy) void (^masterChanged)(BOOL on);
@property (nonatomic, copy) void (^systemPressed)(void);
@end

@implementation SCIDexKitGetterHeaderView
- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _titleLabel.numberOfLines = 2;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_titleLabel];

    _stateLabel = [UILabel new];
    _stateLabel.font = [UIFont systemFontOfSize:10];
    _stateLabel.textColor = UIColor.secondaryLabelColor;
    _stateLabel.numberOfLines = 1;
    _stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_stateLabel];

    _masterSwitch = [UISwitch new];
    _masterSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [_masterSwitch addTarget:self action:@selector(masterSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_masterSwitch];

    _systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_systemButton setTitle:@"System" forState:UIControlStateNormal];
    _systemButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _systemButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_systemButton addTarget:self action:@selector(systemTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_systemButton];

    [NSLayoutConstraint activateConstraints:@[
        [_masterSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_masterSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [_systemButton.centerYAnchor constraintEqualToAnchor:_masterSwitch.centerYAnchor],
        [_systemButton.trailingAnchor constraintEqualToAnchor:_masterSwitch.leadingAnchor constant:-12],

        [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_systemButton.leadingAnchor constant:-10],
        [_stateLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3],
        [_stateLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_stateLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_stateLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8],
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

    // Intentionally menu-scoped. This scans metadata when the DexKit screen opens.
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
    self.tableView.estimatedRowHeight = 58;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 54;
    [self.tableView registerClass:SCIDexKitGetterCell.class forCellReuseIdentifier:@"getterCell"];
    [self.tableView registerClass:SCIDexKitGetterHeaderView.class forHeaderFooterViewReuseIdentifier:@"getterHeader"];
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
    NSString *image = entry.imageName.length ? entry.imageName : @"?";
    return [NSString stringWithFormat:@"%@|%@|%@", image, source, owner];
}

- (NSString *)compactGetterOwnerName:(NSString *)className {
    if (!className.length) return @"UnknownOwner";
    NSArray<NSString *> *parts = [className componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : className;
}

- (NSArray<NSString *> *)preferredSourceOrder {
    return @[@"Autofill/Internal", @"Prism/Menu", @"Direct Notes", @"QuickSnap/Direct", @"Homecoming", @"LiquidGlass/TabBar", @"FBCustomExperimentManager", @"FDIDExperimentGenerator", @"LID/MetaLocalExperiment", @"MetaLocalExperiment", @"MobileConfig/EasyGating", @"IGUserLauncherSet", @"Dogfood/Internal", @"Friending/FriendsTab", @"Feed", @"Direct/Inbox", @"Blend", @"GenAI/MagicMod", @"Main Executable", @"FBSharedFramework / Autofill/Internal", @"FBSharedFramework / Prism/Menu", @"FBSharedFramework / Direct Notes", @"FBSharedFramework / QuickSnap/Direct", @"FBSharedFramework / MobileConfig/EasyGating", @"FBSharedFramework / Bool Getter"];
}

- (NSInteger)sourceRank:(NSString *)source {
    NSUInteger idx = [[self preferredSourceOrder] indexOfObject:source ?: @""];
    return idx == NSNotFound ? 999 : (NSInteger)idx;
}

- (void)rebuildGroups {
    NSMutableDictionary<NSString *, NSMutableArray<SCIEnabledExperimentEntry *> *> *groups = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *sources = [NSMutableDictionary dictionary];
    for (SCIEnabledExperimentEntry *entry in [self flatRows]) {
        NSString *key = [self getterOwnerKeyForEntry:entry];
        if (!groups[key]) groups[key] = [NSMutableArray array];
        [groups[key] addObject:entry];
        names[key] = [self compactGetterOwnerName:entry.className];
        sources[key] = entry.source.length ? entry.source : @"Main Executable";
    }
    self.sectionKeys = [[groups allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ra = [self sourceRank:sources[a]];
        NSInteger rb = [self sourceRank:sources[b]];
        if (ra < rb) return NSOrderedAscending;
        if (ra > rb) return NSOrderedDescending;
        return [names[a] caseInsensitiveCompare:names[b]];
    }];
    NSMutableDictionary *immutable = [NSMutableDictionary dictionary];
    for (NSString *key in self.sectionKeys) {
        immutable[key] = [(groups[key] ?: @[]) sortedArrayUsingComparator:^NSComparisonResult(SCIEnabledExperimentEntry *a, SCIEnabledExperimentEntry *b) {
            return [a.methodName caseInsensitiveCompare:b.methodName];
        }];
    }
    self.groupedRows = immutable;
    self.sectionDisplayNames = names;
    self.sectionSources = sources;
}

- (NSArray<SCIEnabledExperimentEntry *> *)rowsForSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.sectionKeys.count) return @[];
    return self.groupedRows[self.sectionKeys[(NSUInteger)section]] ?: @[];
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
    NSUInteger live = [SCIEnabledExperimentRuntime installedCount];
    self.footerLabel.text = [NSString stringWithFormat:@"Getter owner groups · Instagram + FBSharedFramework · total=%lu · showing=%lu · groups=%lu · live hooks=%lu", (unsigned long)total, (unsigned long)shown, (unsigned long)self.sectionKeys.count, (unsigned long)live];
}

- (BOOL)effectiveSwitchValueForEntry:(SCIEnabledExperimentEntry *)entry {
    SCIExpFlagOverride state = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    if (state == SCIExpFlagOverrideTrue) return YES;
    if (state == SCIExpFlagOverrideFalse) return NO;
    return entry.defaultKnown ? entry.defaultValue : NO;
}

- (NSDictionary *)statsForRows:(NSArray<SCIEnabledExperimentEntry *> *)rows {
    NSUInteger observed = 0, effectiveOn = 0, forced = 0;
    for (SCIEnabledExperimentEntry *entry in rows) {
        if (entry.defaultKnown) observed++;
        if ([self effectiveSwitchValueForEntry:entry]) effectiveOn++;
        if ([SCIEnabledExperimentRuntime savedStateForEntry:entry] != SCIExpFlagOverrideOff) forced++;
    }
    return @{@"observed": @(observed), @"effectiveOn": @(effectiveOn), @"forced": @(forced)};
}

- (BOOL)masterSwitchValueForRows:(NSArray<SCIEnabledExperimentEntry *> *)rows {
    if (!rows.count) return NO;
    return [[self statsForRows:rows][@"effectiveOn"] unsignedIntegerValue] == rows.count;
}

- (void)setOverride:(SCIExpFlagOverride)state forRows:(NSArray<SCIEnabledExperimentEntry *> *)rows {
    for (SCIEnabledExperimentEntry *entry in rows) [SCIEnabledExperimentRuntime setSavedState:state forEntry:entry];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sectionKeys.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self rowsForSection:section].count; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    SCIDexKitGetterHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"getterHeader"];
    NSArray<SCIEnabledExperimentEntry *> *rows = [self rowsForSection:section];
    NSString *key = self.sectionKeys[(NSUInteger)section];
    NSString *name = self.sectionDisplayNames[key] ?: key;
    NSString *source = self.sectionSources[key] ?: @"Main Executable";
    NSDictionary *stats = [self statsForRows:rows];
    NSUInteger observed = [stats[@"observed"] unsignedIntegerValue];
    NSUInteger effectiveOn = [stats[@"effectiveOn"] unsignedIntegerValue];
    NSUInteger forced = [stats[@"forced"] unsignedIntegerValue];
    NSString *mix = effectiveOn == 0 ? @"all OFF" : (effectiveOn == rows.count ? @"all ON" : @"mixed");

    header.titleLabel.text = name;
    header.stateLabel.text = [NSString stringWithFormat:@"%@ · %@ · funcs %lu · observed %lu · forced %lu", source, mix, (unsigned long)rows.count, (unsigned long)observed, (unsigned long)forced];
    [header.masterSwitch setOn:[self masterSwitchValueForRows:rows] animated:NO];
    header.systemButton.enabled = forced > 0;
    header.systemButton.alpha = forced > 0 ? 1.0 : 0.35;

    __weak typeof(self) weakSelf = self;
    NSArray<SCIEnabledExperimentEntry *> *capturedRows = [rows copy];
    header.masterChanged = ^(BOOL on) { [weakSelf setOverride:(on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forRows:capturedRows]; [weakSelf reload]; };
    header.systemPressed = ^{ [weakSelf setOverride:SCIExpFlagOverrideOff forRows:capturedRows]; [weakSelf reload]; };
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 56.0; }

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
    SCIDexKitGetterCell *cell = [tv dequeueReusableCellWithIdentifier:@"getterCell" forIndexPath:ip];
    SCIEnabledExperimentEntry *entry = [self entryAtIndexPath:ip];
    cell.titleLabel.text = entry.methodName ?: @"?";

    NSString *system = [SCIEnabledExperimentRuntime defaultLabelForEntry:entry];
    NSString *state = [SCIEnabledExperimentRuntime stateLabelForEntry:entry];
    NSString *router = [[SCIEnabledExperimentRuntime summaryTextForEntry:entry] containsString:@"router=live"] ? @"live" : @"off";
    cell.stateLabel.text = [NSString stringWithFormat:@"system %@ · %@ · %@", system, state, router];

    SCIExpFlagOverride override = [SCIEnabledExperimentRuntime savedStateForEntry:entry];
    [cell.toggleSwitch setOn:[self effectiveSwitchValueForEntry:entry] animated:NO];
    cell.toggleSwitch.enabled = entry.defaultKnown || override != SCIExpFlagOverrideOff;
    cell.systemButton.enabled = override != SCIExpFlagOverrideOff;
    cell.systemButton.alpha = cell.systemButton.enabled ? 1.0 : 0.35;

    __weak typeof(self) weakSelf = self;
    __weak SCIEnabledExperimentEntry *weakEntry = entry;
    cell.toggleChanged = ^(BOOL on) { [SCIEnabledExperimentRuntime setSavedState:(on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forEntry:weakEntry]; [weakSelf reload]; };
    cell.systemPressed = ^{ [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideOff forEntry:weakEntry]; [weakSelf reload]; };
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SCIEnabledExperimentEntry *entry = [self entryAtIndexPath:ip];
    if (!entry) return;
    NSString *message = [NSString stringWithFormat:@"Getter owner:\n%@\n\nFunction:\n%@\n\nImage: %@\nSource: %@\nSystem: %@\nOverride: %@\nSwitch: %@\nType: %@\n\nKey:\n%@", entry.className ?: @"?", entry.methodName ?: @"?", entry.imageName ?: @"?", entry.source ?: @"?", [SCIEnabledExperimentRuntime defaultLabelForEntry:entry], [SCIEnabledExperimentRuntime stateLabelForEntry:entry], [self effectiveSwitchValueForEntry:entry] ? @"ON" : @"OFF", entry.typeEncoding ?: @"", entry.key ?: @""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:entry.methodName message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideTrue forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideFalse forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"System" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { [SCIEnabledExperimentRuntime setSavedState:SCIExpFlagOverrideOff forEntry:entry]; [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) { UIPasteboard.generalPasteboard.string = entry.key ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    if (a.popoverPresentationController) { a.popoverPresentationController.sourceView = cell; a.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { self.query = text; [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
