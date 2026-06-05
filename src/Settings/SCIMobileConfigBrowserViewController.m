#import "SCIMobileConfigBrowserViewController.h"
#import "GlassUI/SCIAdaptiveGlass.h"
#import "../Features/MobileConfig/SCIMobileConfigRuntime.h"
#import "../Utils.h"
#include <stdlib.h>

static unsigned long long SCIULLFromObject(id obj) {
    if (!obj || obj == (id)kCFNull) return 0;
    const char *s = [[obj description] UTF8String];
    return s ? strtoull(s, NULL, 10) : 0;
}

typedef NS_ENUM(NSInteger, SCIMobileConfigBrowserMode) {
    SCIMobileConfigBrowserModeDogfood = 0,
    SCIMobileConfigBrowserModeContexts = 1,
    SCIMobileConfigBrowserModeParams = 2,
    SCIMobileConfigBrowserModeOverrides = 3,
};

@interface SCIMobileConfigBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) SCIGlassSearchBar *glassSearchBar;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) SCIAdaptiveGlassPanelView *modePanel;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@property (nonatomic, copy) NSArray<NSDictionary *> *dogfoodRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredDogfood;
@property (nonatomic, copy) NSArray<NSDictionary *> *filtered;
@property (nonatomic, copy) NSArray<NSDictionary *> *contexts;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredContexts;
@property (nonatomic, copy) NSDictionary *overrides;
@property (nonatomic, copy) NSArray<NSDictionary *> *overrideRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredOverrides;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) SCIMobileConfigBrowserMode mode;
@end

@implementation SCIMobileConfigBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig Runtime";
    SCIApplyGlassBackdropToViewController(self);
    self.mode = SCIMobileConfigBrowserModeDogfood;

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshAll)];
    UIBarButtonItem *trash = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(confirmClear)];
    UIBarButtonItem *export = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(exportSnapshot)];
    self.navigationItem.rightBarButtonItems = @[refresh, export, trash];

    self.glassSearchBar = [[SCIGlassSearchBar alloc] initWithRadius:22.0];
    self.glassSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar = self.glassSearchBar.searchBar;
    self.searchBar.placeholder = @"Filter id, stable id, selector, class, session, live context";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    [self.view addSubview:self.glassSearchBar];

    self.modePanel = [[SCIAdaptiveGlassPanelView alloc] initWithRadius:18.0];
    self.modePanel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.modePanel];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Dogfood", @"Live", @"Params", @"Overrides"]];
    self.modeControl.selectedSegmentIndex = 0;
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    SCIStyleSegmentedControlForGlass(self.modeControl);
    [self.modePanel.contentView addSubview:self.modeControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    SCIStyleTableViewForGlass(self.tableView);
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:SCIGlassParamCell.class forCellReuseIdentifier:@"mc"];
    [self.tableView registerClass:SCIGlassParamCell.class forCellReuseIdentifier:@"ctx"];
    [self.tableView registerClass:SCIGlassParamCell.class forCellReuseIdentifier:@"status"];
    [self.tableView registerClass:SCIGlassSectionHeaderView.class forHeaderFooterViewReuseIdentifier:@"glassHeader"];
    [self.view addSubview:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.glassSearchBar.topAnchor constraintEqualToAnchor:g.topAnchor constant:8.0],
        [self.glassSearchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14.0],
        [self.glassSearchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14.0],
        [self.glassSearchBar.heightAnchor constraintEqualToConstant:52.0],
        [self.modePanel.topAnchor constraintEqualToAnchor:self.glassSearchBar.bottomAnchor constant:10.0],
        [self.modePanel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16.0],
        [self.modePanel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16.0],
        [self.modeControl.topAnchor constraintEqualToAnchor:self.modePanel.contentView.topAnchor constant:8.0],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:self.modePanel.contentView.leadingAnchor constant:10.0],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:self.modePanel.contentView.trailingAnchor constant:-10.0],
        [self.modeControl.bottomAnchor constraintEqualToAnchor:self.modePanel.contentView.bottomAnchor constant:-8.0],
        [self.tableView.topAnchor constraintEqualToAnchor:self.modePanel.bottomAnchor constant:6.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 12.0, 0);
    self.tableView.verticalScrollIndicatorInsets = self.tableView.contentInset;
    [self configureToolbarItems];
    [self reloadRows];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    SCIApplyGlassBackdropToViewController(self);
    [SCIMobileConfigRuntime setRuntimeCaptureActive:YES];
    SCIInstallMobileConfigRuntimeHooksIfNeeded();
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self configureToolbarItems];
    [self reloadRows];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [SCIMobileConfigRuntime setRuntimeCaptureActive:NO];
    if (self.navigationController.topViewController == self) [self.navigationController setToolbarHidden:YES animated:animated];
}

- (void)configureToolbarItems {
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshAll)];
    UIBarButtonItem *export = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(exportSnapshot)];
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(confirmClear)];
    NSString *captureTitle = [SCIMobileConfigRuntime runtimeHooksEnabled] ? @"Capture ON" : @"Capture OFF";
    UIBarButtonItem *capture = [[UIBarButtonItem alloc] initWithTitle:captureTitle style:UIBarButtonItemStylePlain target:self action:@selector(toggleCapturePreference)];
    if (@available(iOS 26.0, *)) capture.style = UIBarButtonItemStyleProminent;
    self.toolbarItems = @[refresh, flex, export, flex, clear, flex, capture];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    self.mode = (SCIMobileConfigBrowserMode)sender.selectedSegmentIndex;
    [self.tableView reloadData];
}

- (void)refreshAll {
    [SCIMobileConfigRuntime reloadParamsMapIndex];
    [self reloadRows];
}

- (void)toggleCapturePreference {
    BOOL next = ![SCIMobileConfigRuntime runtimeHooksEnabled];
    [SCIMobileConfigRuntime setRuntimeCaptureActive:next];
    if (next) SCIInstallMobileConfigRuntimeHooksIfNeeded();
    [self configureToolbarItems];
    [self reloadRows];
}

- (NSArray<NSDictionary *> *)overrideRowsFromDictionary:(NSDictionary *)dict {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *keys = [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        id value = dict[key];
        NSArray *parts = [key componentsSeparatedByString:@"|"];
        NSString *type = parts.count > 0 ? parts.firstObject : @"unknown";
        NSString *pid = parts.count > 1 ? parts.lastObject : key;
        [out addObject:@{@"key": key ?: @"", @"type": type ?: @"unknown", @"paramID": pid ?: @"", @"value": [value description] ?: @""}];
    }
    return out;
}

- (void)reloadRows {
    self.rows = [SCIMobileConfigRuntime hotParams];
    self.dogfoodRows = [SCIMobileConfigRuntime dogfoodCandidateParams];
    self.contexts = [SCIMobileConfigRuntime liveContexts];
    self.overrides = [SCIMobileConfigRuntime manualOverrides];
    self.overrideRows = [self overrideRowsFromDictionary:self.overrides ?: @{}];
    [self configureToolbarItems];
    [self applyFilter];
}

- (NSString *)searchHaystackForContext:(NSDictionary *)d {
    NSArray *rolesArr = [d[@"roles"] isKindOfClass:NSArray.class] ? d[@"roles"] : @[];
    NSArray *sourcesArr = [d[@"sources"] isKindOfClass:NSArray.class] ? d[@"sources"] : @[];
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@", d[@"class"] ?: @"", d[@"address"] ?: @"", d[@"description"] ?: @"", d[@"sessionID"] ?: @"", d[@"mc"] ?: @"", d[@"launcherSet"] ?: @"", [rolesArr componentsJoinedByString:@" "], [sourcesArr componentsJoinedByString:@" "]];
    for (NSString *sel in ([d[@"interestingSelectors"] isKindOfClass:NSArray.class] ? d[@"interestingSelectors"] : @[])) [s appendFormat:@" %@", sel];
    for (NSDictionary *iv in ([d[@"ivars"] isKindOfClass:NSArray.class] ? d[@"ivars"] : @[])) [s appendFormat:@" %@ %@ %@ %@", iv[@"name"] ?: @"", iv[@"type"] ?: @"", iv[@"value"] ?: @"", iv[@"description"] ?: @""];
    return s;
}

- (void)applyFilter {
    NSString *q = self.query.lowercaseString ?: @"";
    if (!q.length) {
        self.filtered = self.rows;
        self.filteredDogfood = self.dogfoodRows;
        self.filteredContexts = self.contexts;
        self.filteredOverrides = self.overrideRows;
    } else {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *d in self.rows) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@", d[@"paramID"] ?: @"", d[@"hex"] ?: @"", d[@"low32"] ?: @"", d[@"stableID"] ?: @"", d[@"stableHex"] ?: @"", d[@"type"] ?: @"", d[@"returned"] ?: @"", d[@"selector"] ?: @"", d[@"sourceClass"] ?: @"", d[@"sessionID"] ?: @"", d[@"map"] ?: @""];
            if ([hay.lowercaseString containsString:q]) [out addObject:d];
        }
        self.filtered = out;
        NSMutableArray *dog = [NSMutableArray array];
        for (NSDictionary *d in self.dogfoodRows) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@", d[@"paramID"] ?: @"", d[@"hex"] ?: @"", d[@"stableID"] ?: @"", d[@"type"] ?: @"", d[@"returned"] ?: @"", d[@"selector"] ?: @"", d[@"sourceClass"] ?: @"", d[@"sessionID"] ?: @"", d[@"map"] ?: @"", d[@"tags"] ?: @"", d[@"nativeMeta"] ?: @"", d[@"callerSymbols"] ?: @"", d[@"mapCandidates"] ?: @""];
            if ([hay.lowercaseString containsString:q]) [dog addObject:d];
        }
        self.filteredDogfood = dog;
        NSMutableArray *ctx = [NSMutableArray array];
        for (NSDictionary *d in self.contexts) if ([[self searchHaystackForContext:d].lowercaseString containsString:q]) [ctx addObject:d];
        self.filteredContexts = ctx;
        NSMutableArray *ovs = [NSMutableArray array];
        for (NSDictionary *d in self.overrideRows) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@", d[@"key"] ?: @"", d[@"type"] ?: @"", d[@"paramID"] ?: @"", d[@"value"] ?: @""];
            if ([hay.lowercaseString containsString:q]) [ovs addObject:d];
        }
        self.filteredOverrides = ovs;
    }
    [self.tableView reloadData];
}

- (void)confirmClear {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Clear captured params?" message:@"Manual overrides and live contexts are not removed." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
        [SCIMobileConfigRuntime clearObservations];
        [self reloadRows];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)sectionVisible:(NSInteger)section {
    if (self.mode == SCIMobileConfigBrowserModeDogfood) return section == 0 || section == 1;
    if (self.mode == SCIMobileConfigBrowserModeContexts) return section == 2;
    if (self.mode == SCIMobileConfigBrowserModeParams) return section == 3;
    if (self.mode == SCIMobileConfigBrowserModeOverrides) return section == 4;
    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 5; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (![self sectionVisible:section]) return 0;
    if (section == 0) return 4;
    if (section == 1) return self.filteredDogfood.count;
    if (section == 2) return self.filteredContexts.count;
    if (section == 3) return self.filtered.count;
    return self.filteredOverrides.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (![self sectionVisible:section]) return nil;
    SCIGlassSectionHeaderView *h = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"glassHeader"];
    if (section == 0) [h configureWithTitle:@"Dogfood discovery status" subtitle:@"Use this first: native dogfood menu, deep caller symbols, resolver and captured dogfood/internal candidates."];
    else if (section == 1) [h configureWithTitle:[NSString stringWithFormat:@"Dogfood/Internal candidates · %lu", (unsigned long)self.filteredDogfood.count] subtitle:@"Filtered by caller symbols, native metadata, tags and params_map hints. No manual ID hunting."];
    else if (section == 2) [h configureWithTitle:[NSString stringWithFormat:@"Live contexts · %lu", (unsigned long)self.filteredContexts.count] subtitle:@"IGDogfooderProd, IGUserLauncherSet and MobileConfig contexts captured by named hooks."];
    else if (section == 3) [h configureWithTitle:[NSString stringWithFormat:@"All hot params · %lu", (unsigned long)self.filtered.count] subtitle:@"Raw runtime getter calls. This is the numeric fallback view, not the main workflow."];
    else [h configureWithTitle:[NSString stringWithFormat:@"Overrides · %lu", (unsigned long)self.filteredOverrides.count] subtitle:@"Manual only. Values are applied only when the guarded runtime hook path is enabled."];
    return h;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self sectionVisible:section] ? 76.0 : CGFLOAT_MIN;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != 0 || ![self sectionVisible:section]) return nil;
    return @"_specifierToMetadata is reported as a native C++ map and is not dereferenced directly. Use getStableIdFromParamSpecifier: + live getter traffic as source of truth.";
}

- (UITableViewCell *)statusCell:(NSInteger)idx indexPath:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"status" forIndexPath:ip];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (idx == 0) {
        [cell configureWithTitle:@"Runtime capture" subtitle:([SCIMobileConfigRuntime runtimeHooksEnabled] ? @"Active for this browser session" : @"Paused until you turn it back on") badge:([SCIMobileConfigRuntime runtimeHooksEnabled] ? @"ON" : @"OFF") emphasized:YES];
    } else if (idx == 1) {
        NSUInteger c = [SCIMobileConfigRuntime manualOverrides].count;
        [cell configureWithTitle:@"Manual overrides" subtitle:[NSString stringWithFormat:@"%@ · %lu active", [SCIMobileConfigRuntime manualOverridesEnabled] ? @"Enabled" : @"Disabled", (unsigned long)c] badge:([SCIMobileConfigRuntime manualOverridesEnabled] ? @"ON" : @"OFF") emphasized:NO];
    } else if (idx == 2) {
        BOOL deep = [SCIMobileConfigRuntime deepCallerSymbolsEnabled];
        [cell configureWithTitle:@"Deep dogfood caller symbols" subtitle:(deep ? @"Enabled — captures filtered call stack frames containing dogfood/internal/employee/launcher terms" : @"Disabled — enable this to turn numeric params into dogfood/internal candidates") badge:(deep ? @"ON" : @"OFF") emphasized:YES];
    } else {
        NSUInteger c = [SCIMobileConfigRuntime paramsMapIndex].count;
        [cell configureWithTitle:@"params_map + native resolver" subtitle:[NSString stringWithFormat:@"%lu token buckets · %lu live contexts · %lu dogfood candidates. Refresh after Instagram rewrites MobileConfig.", (unsigned long)c, (unsigned long)self.contexts.count, (unsigned long)self.dogfoodRows.count] badge:@"IDX" emphasized:NO];
    }
    return cell;
}

- (UITableViewCell *)contextCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"ctx" forIndexPath:ip];
    NSDictionary *d = self.filteredContexts[ip.row];
    NSString *cls = [d[@"class"] description] ?: @"";
    NSString *addr = [d[@"address"] description] ?: @"";
    NSArray *rolesArr = [d[@"roles"] isKindOfClass:NSArray.class] ? d[@"roles"] : @[];
    NSString *roles = [rolesArr componentsJoinedByString:@", "];
    NSString *session = [d[@"sessionID"] description] ?: @"";
    NSString *mc = [d[@"mc"] description] ?: @"";
    NSString *subtitle = [NSString stringWithFormat:@"%@%@%@%@%@", roles.length ? roles : @"live object", session.length ? @" · session " : @"", session.length ? session : @"", mc.length ? @" · mc " : @"", mc.length ? mc : @""];
    [cell configureWithTitle:[NSString stringWithFormat:@"%@ %@", cls, addr] subtitle:subtitle badge:@"LIVE" emphasized:NO];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)paramCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"mc" forIndexPath:ip];
    NSDictionary *d = self.filtered[ip.row];
    NSString *pid = [d[@"paramID"] description] ?: @"";
    NSString *type = [d[@"type"] description] ?: @"";
    NSString *ret = [d[@"returned"] description] ?: @"";
    NSString *cnt = [d[@"count"] description] ?: @"0";
    NSString *map = [d[@"map"] description] ?: @"";
    NSString *stable = [d[@"stableID"] description] ?: @"";
    NSString *session = [d[@"sessionID"] description] ?: @"";
    NSArray *tags = [d[@"tags"] isKindOfClass:NSArray.class] ? d[@"tags"] : @[];
    NSDictionary *meta = [d[@"nativeMeta"] isKindOfClass:NSDictionary.class] ? d[@"nativeMeta"] : @{};
    NSString *tagText = tags.count ? [tags componentsJoinedByString:@", "] : @"";
    NSString *creator = [meta[@"latestCreator"] description] ?: @"";
    NSString *creation = [meta[@"latestCreationSource"] description] ?: @"";
    NSString *title = [NSString stringWithFormat:@"%@%@%@  %@%@%@", tagText.length ? [tagText stringByAppendingString:@" · "] : @"", pid, stable.length ? [NSString stringWithFormat:@" stable %@", stable] : @"", type, creator.length ? @" · creator " : @"", creator.length ? creator : @""];
    NSString *subtitle = [NSString stringWithFormat:@"count %@ · value %@%@%@%@%@%@%@", cnt, ret.length ? ret : @"(nil)", creation.length ? @" · source " : @"", creation.length ? creation : @"", session.length ? @" · session " : @"", session.length ? session : @"", map.length ? @" · " : @"", map.length ? map : @""];
    [cell configureWithTitle:title subtitle:subtitle badge:(tags.count ? @"DOG" : (type.length ? type.uppercaseString : @"MC")) emphasized:tags.count > 0];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)overrideCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"mc" forIndexPath:ip];
    NSDictionary *d = self.filteredOverrides[ip.row];
    [cell configureWithTitle:[NSString stringWithFormat:@"%@  %@", d[@"paramID"] ?: @"", d[@"type"] ?: @"unknown"] subtitle:[NSString stringWithFormat:@"override value: %@", d[@"value"] ?: @""] badge:@"OVR" emphasized:YES];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) return [self statusCell:ip.row indexPath:ip];
    if (ip.section == 1) { SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"mc" forIndexPath:ip]; NSArray *saved = self.filtered; self.filtered = self.filteredDogfood; UITableViewCell *built = [self paramCell:ip]; self.filtered = saved; return built ?: cell; }
    if (ip.section == 2) return [self contextCell:ip];
    if (ip.section == 3) return [self paramCell:ip];
    return [self overrideCell:ip];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 2) { [SCIUtils setPref:@(![SCIMobileConfigRuntime deepCallerSymbolsEnabled]) forKey:@"sci_mc_runtime_deep_symbols_enabled"]; [self reloadRows]; return; }
    if (ip.section == 1 && ip.row < (NSInteger)self.filteredDogfood.count) [self presentActionsForParam:self.filteredDogfood[ip.row]];
    else if (ip.section == 2 && ip.row < (NSInteger)self.filteredContexts.count) [self presentActionsForContext:self.filteredContexts[ip.row]];
    else if (ip.section == 3 && ip.row < (NSInteger)self.filtered.count) [self presentActionsForParam:self.filtered[ip.row]];
    else if (ip.section == 4 && ip.row < (NSInteger)self.filteredOverrides.count) [self presentActionsForOverride:self.filteredOverrides[ip.row]];
}

- (NSString *)detailsTextForContext:(NSDictionary *)d {
    NSArray *rolesArr = [d[@"roles"] isKindOfClass:NSArray.class] ? d[@"roles"] : @[];
    NSArray *sourcesArr = [d[@"sources"] isKindOfClass:NSArray.class] ? d[@"sources"] : @[];
    NSMutableString *msg = [NSMutableString stringWithFormat:@"class: %@\naddress: %@\nroles: %@\nsources: %@\nsession: %@\nmc: %@\nlauncherSet: %@\ndescription: %@\n", d[@"class"] ?: @"", d[@"address"] ?: @"", [rolesArr componentsJoinedByString:@", "], [sourcesArr componentsJoinedByString:@", "], d[@"sessionID"] ?: @"", d[@"mc"] ?: @"", d[@"launcherSet"] ?: @"", d[@"description"] ?: @""];
    NSArray *sels = [d[@"interestingSelectors"] isKindOfClass:NSArray.class] ? d[@"interestingSelectors"] : @[];
    if (sels.count) [msg appendFormat:@"\ninteresting selectors:\n- %@\n", [sels componentsJoinedByString:@"\n- "]];
    NSArray *ivars = [d[@"ivars"] isKindOfClass:NSArray.class] ? d[@"ivars"] : @[];
    if (ivars.count) [msg appendString:@"\nivars:\n"];
    for (NSDictionary *iv in ivars) [msg appendFormat:@"- %@ off %@ %@ = %@%@%@\n", iv[@"name"] ?: @"", iv[@"offset"] ?: @0, iv[@"type"] ?: @"", iv[@"value"] ?: @"", iv[@"hint"] ? @" · " : @"", iv[@"hint"] ?: @""];
    return msg;
}

- (void)presentActionsForContext:(NSDictionary *)d {
    NSString *msg = [self detailsTextForContext:d];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[d[@"class"] description] ?: @"Live Context" message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { UIPasteboard.generalPasteboard.string = msg; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy address" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { UIPasteboard.generalPasteboard.string = [d[@"address"] description] ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)presentActionsForParam:(NSDictionary *)d {
    unsigned long long pid = SCIULLFromObject(d[@"paramID"]);
    NSString *type = [d[@"type"] description] ?: @"unknown";
    NSArray *cands = [d[@"mapCandidates"] isKindOfClass:NSArray.class] ? d[@"mapCandidates"] : @[];
    NSMutableString *candText = [NSMutableString string];
    for (NSDictionary *m in cands) [candText appendFormat:@"\n- %@:%@ %@ %@", m[@"file"] ?: @"params_map", m[@"line"] ?: m[@"offset"] ?: @0, m[@"match"] ?: @"", m[@"raw"] ?: @""];
    NSString *msg = [NSString stringWithFormat:@"tags: %@\nnativeMeta: %@\ncallerSymbols: %@\ntype: %@\nhex: %@\nlow32: %@ / %@\nstableID: %@ %@\nsession: %@\nreturned: %@\ndefault: %@\nselector: %@\nclass: %@\nresolver: %@\nmap: %@%@", d[@"tags"] ?: @[], d[@"nativeMeta"] ?: @{}, d[@"callerSymbols"] ?: @[], type, d[@"hex"] ?: @"", d[@"low32"] ?: @"", d[@"low32Hex"] ?: @"", d[@"stableID"] ?: @"", d[@"stableHex"] ?: @"", d[@"sessionID"] ?: @"", d[@"returned"] ?: @"", d[@"default"] ?: @"", d[@"selector"] ?: @"", d[@"sourceClass"] ?: @"", d[@"stableResolver"] ?: @"", d[@"map"] ?: @"", candText];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@", d[@"paramID"] ?: @""] message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy specifier ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { UIPasteboard.generalPasteboard.string = [d[@"paramID"] description] ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy stable ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { UIPasteboard.generalPasteboard.string = [d[@"stableID"] description].length ? [d[@"stableID"] description] : ([d[@"paramID"] description] ?: @""); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@\n%@", d, msg]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Set manual override…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { [self promptOverrideForParamID:pid type:type current:[d[@"returned"] description] ?: @""]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove manual override" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) { [SCIMobileConfigRuntime removeManualOverrideForParamID:pid type:type]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)presentActionsForOverride:(NSDictionary *)d {
    unsigned long long pid = SCIULLFromObject(d[@"paramID"]);
    NSString *type = [d[@"type"] description] ?: @"unknown";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Manual override" message:[NSString stringWithFormat:@"%@\n%@\nvalue: %@", d[@"paramID"] ?: @"", type, d[@"value"] ?: @""] preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { UIPasteboard.generalPasteboard.string = [d description]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) { [SCIMobileConfigRuntime removeManualOverrideForParamID:pid type:type]; [self reloadRows]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptOverrideForParamID:(unsigned long long)pid type:(NSString *)type current:(NSString *)current {
    if ([type isEqualToString:@"bool"]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Bool override" message:@"Applies only while runtime hooks + manual overrides are enabled." preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:@"Force YES" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { [SCIMobileConfigRuntime setManualOverride:@(YES) paramID:pid type:type]; [self reloadRows]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Force NO" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { [SCIMobileConfigRuntime setManualOverride:@(NO) paramID:pid type:type]; [self reloadRows]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = self.view;
        a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Manual override" message:@"Use carefully. Wrong MobileConfig values can crash startup; the crash guard disables capture after repeated bad launches." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = current.length ? current : @"value";
        tf.text = current;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        if ([type isEqualToString:@"int"] || [type isEqualToString:@"double"]) tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
        NSString *raw = a.textFields.firstObject.text ?: @"";
        id val = raw;
        if ([type isEqualToString:@"int"]) val = @([raw longLongValue]);
        else if ([type isEqualToString:@"double"]) val = @([raw doubleValue]);
        [SCIMobileConfigRuntime setManualOverride:val paramID:pid type:type];
        [self reloadRows];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)exportSnapshot {
    NSDictionary *payload = @{
        @"capturedAt": @([[NSDate date] timeIntervalSince1970]),
        @"runtimeCapture": @([SCIMobileConfigRuntime runtimeHooksEnabled]),
        @"manualOverridesEnabled": @([SCIMobileConfigRuntime manualOverridesEnabled]),
        @"hotParams": self.rows ?: @[],
        @"liveContexts": self.contexts ?: @[],
        @"manualOverrides": self.overrides ?: @{},
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : [payload description];
    UIPasteboard.generalPasteboard.string = text ?: @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Export copied" message:@"Runtime Browser snapshot copied as JSON." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.query = searchText ?: @"";
    [self applyFilter];
}

@end
