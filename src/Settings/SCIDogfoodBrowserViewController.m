#import "SCIDogfoodBrowserViewController.h"
#import "GlassUI/SCIAdaptiveGlass.h"
#import "../Features/MobileConfig/SCIMobileConfigRuntime.h"
#import "../Features/Dogfooding/SCIDogfoodObjectRuntime.h"
#import "../Features/Dogfooding/SCILauncherOverride.h"
#import "../Features/Dogfooding/SCIInternalActions.h"
#import "../Utils.h"

@interface SCIDogfoodBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) SCIGlassSearchBar *glassSearchBar;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSDictionary *state;
@property (nonatomic, copy) NSArray<NSDictionary *> *stubs;
@property (nonatomic, copy) NSArray<NSDictionary *> *objects;
@property (nonatomic, copy) NSArray<NSDictionary *> *settingsTargets;
@property (nonatomic, copy) NSArray<NSDictionary *> *actions;
@property (nonatomic, copy) NSArray<NSDictionary *> *params;
@property (nonatomic, copy) NSArray<NSDictionary *> *notesChanges;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredStubs;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredObjects;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredSettingsTargets;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredParams;
@property (nonatomic, copy) NSArray<NSDictionary *> *filteredNotesChanges;
@property (nonatomic, copy) NSString *query;
@end

@implementation SCIDogfoodBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Dogfood Runtime";
    SCIApplyGlassBackdropToViewController(self);
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshAll)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(exportSnapshot)]
    ];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clearRuntime)];

    self.glassSearchBar = [[SCIGlassSearchBar alloc] initWithRadius:22.0];
    self.glassSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar = self.glassSearchBar.searchBar;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"stub class/method, live object, userSession, settings, dogfood";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.view addSubview:self.glassSearchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    SCIStyleTableViewForGlass(self.tableView);
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView registerClass:SCIGlassParamCell.class forCellReuseIdentifier:@"cell"];
    [self.tableView registerClass:SCIGlassSectionHeaderView.class forHeaderFooterViewReuseIdentifier:@"header"];
    [self.view addSubview:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.glassSearchBar.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.glassSearchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [self.glassSearchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [self.glassSearchBar.heightAnchor constraintEqualToConstant:52],
        [self.tableView.topAnchor constraintEqualToAnchor:self.glassSearchBar.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [self refreshAll];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    SCIApplyGlassBackdropToViewController(self);
    [self refreshRuntimeStateOnly];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [SCIMobileConfigRuntime setRuntimeCaptureActive:NO];
}

- (void)refreshRuntimeStateOnly {
    self.state = [SCIDogfoodObjectRuntime runtimeState];
    self.stubs = [SCIDogfoodObjectRuntime runtimeStubsMatching:self.query limit:160];
    self.objects = [SCIDogfoodObjectRuntime liveObjectGraph];
    self.settingsTargets = [SCIDogfoodObjectRuntime settingsInjectionTargets];
    self.actions = [SCIDogfoodObjectRuntime recentActions];
    self.notesChanges = [SCIDogfoodObjectRuntime dogfoodingSettingChanges];
    if (![SCIMobileConfigRuntime runtimeHooksEnabled]) self.params = @[];
    [self applyFilter];
}

- (void)refreshAll {
    BOOL capture = [SCIMobileConfigRuntime runtimeHooksEnabled];
    if (capture) [SCIMobileConfigRuntime reloadParamsMapIndex];
    [self refreshRuntimeStateOnly];
    self.params = capture ? [SCIMobileConfigRuntime dogfoodCandidateParams] : @[];
    [self applyFilter];
}

- (void)clearRuntime {
    [SCIDogfoodObjectRuntime clear];
    [SCIMobileConfigRuntime clearObservations];
    [self refreshAll];
}

- (void)applyFilter {
    NSString *q = self.query.lowercaseString ?: @"";
    if (!q.length) {
        self.filteredStubs = self.stubs;
        self.filteredObjects = self.objects;
        self.filteredSettingsTargets = self.settingsTargets;
        self.filteredParams = self.params;
        self.filteredNotesChanges = self.notesChanges;
        [self.tableView reloadData];
        return;
    }
    self.filteredStubs = [SCIDogfoodObjectRuntime runtimeStubsMatching:self.query limit:160];
    NSMutableArray *objs = [NSMutableArray array];
    for (NSDictionary *d in self.objects) if ([[d description].lowercaseString containsString:q]) [objs addObject:d];
    self.filteredObjects = objs;
    NSMutableArray *sets = [NSMutableArray array];
    for (NSDictionary *d in self.settingsTargets) if ([[d description].lowercaseString containsString:q]) [sets addObject:d];
    self.filteredSettingsTargets = sets;
    NSMutableArray *ps = [NSMutableArray array];
    for (NSDictionary *d in self.params) if ([[d description].lowercaseString containsString:q]) [ps addObject:d];
    self.filteredParams = ps;
    NSMutableArray *ns = [NSMutableArray array];
    for (NSDictionary *d in self.notesChanges) if ([[d description].lowercaseString containsString:q]) [ns addObject:d];
    self.filteredNotesChanges = ns;
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { self.query = searchText ?: @""; [self applyFilter]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 7; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 13;
    if (section == 1) return self.filteredStubs.count;
    if (section == 2) return self.filteredObjects.count;
    if (section == 3) return self.filteredSettingsTargets.count;
    if (section == 4) return self.filteredNotesChanges.count;
    if (section == 5) return self.filteredParams.count;
    return MIN((NSInteger)self.actions.count, 25);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    SCIGlassSectionHeaderView *h = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
    if (section == 0) [h configureWithTitle:@"Native actions, internal setters + runtime state" subtitle:[self.state description]];
    else if (section == 1) [h configureWithTitle:[NSString stringWithFormat:@"Runtime Stubs · %lu", (unsigned long)self.filteredStubs.count] subtitle:@"Safe class/method/ivar stubs from ObjC metadata. No heap scan, no method invocation, no observer overhead."];
    else if (section == 2) [h configureWithTitle:[NSString stringWithFormat:@"Live Object Graph · %lu", (unsigned long)self.filteredObjects.count] subtitle:@"Only objects captured by named hooks. Full details are lazy when tapped."];
    else if (section == 3) [h configureWithTitle:[NSString stringWithFormat:@"Settings Injection Targets · %lu", (unsigned long)self.filteredSettingsTargets.count] subtitle:@"Captured Settings2/settings targets only. No floating overlay injection."];
    else if (section == 4) [h configureWithTitle:[NSString stringWithFormat:@"Notes Persistence · %lu", (unsigned long)self.filteredNotesChanges.count] subtitle:@"Captured native DogfoodingSettings toggle/selection updates."];
    else if (section == 5) [h configureWithTitle:[NSString stringWithFormat:@"MobileConfig Reads · %lu", (unsigned long)self.filteredParams.count] subtitle:@"Secondary tracer only. Keep off unless investigating a specific getter."];
    else [h configureWithTitle:[NSString stringWithFormat:@"Recent actions · %lu", (unsigned long)self.actions.count] subtitle:@"Open attempts, exceptions and diagnostics."];
    return h;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 82; }

- (UITableViewCell *)actionCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    NSArray *rows = @[
        @[@"Open Native Dogfood Settings", @"Disabled here: this reflected entrypoint blocks this IG build. Use Notes/Internal Actions.", @"OFF"],
        @[@"Open Notes Dogfooding", @"Uses native IGDirectNotesDogfoodingSettingsStaticFuncs with the live IGUserSession.", @"NOTES"],
        @[@"Open MetaLocalExperiment Browser", @"Disabled here: config construction is heavy/unsafe from a tap on this build.", @"OFF"],
        @[@"Copy Auto-FLEX snapshot", @"Exports state + live object graph + settings targets + config reads.", @"JSON"],
        @[@"MobileConfig runtime capture", ([SCIMobileConfigRuntime runtimeHooksEnabled] ? @"ON for this browser session. Lightweight getter capture only." : @"Paused for this browser session."), ([SCIMobileConfigRuntime runtimeHooksEnabled] ? @"ON" : @"OFF")],
        @[@"Deep caller symbols", ([SCIMobileConfigRuntime deepCallerSymbolsEnabled] ? @"ON. Delayed/throttled stack sampling; do not leave permanent." : @"OFF. Usually keep off; object runtime does not need it."), ([SCIMobileConfigRuntime deepCallerSymbolsEnabled] ? @"ON" : @"OFF")],
        @[@"Captured launcher overrides", [NSString stringWithFormat:@"%lu launchers / %lu values", (unsigned long)[SCILauncherOverride allOverrides].count, (unsigned long)[SCILauncherOverride totalOverrideCount]], @"LCH"],
        @[@"Autofill Internal state", [[SCIInternalActions state] description], @"STATE"],
        @[@"Force Bloks Experience ON", @"Calls native setForceBloksExperienceOn on IGAutofillInternalSettings initialized with the live IGUserSession.", @"BLOKS"],
        @[@"Force Bloks Experience OFF", @"Calls native setForceBloksExperienceOff.", @"BLOKS"],
        @[@"Enable Bloks Prefetch", @"Calls native setBloksPrefetchEnabledWithEnabled:YES.", @"PREF"],
        @[@"Enable Debug Footer", @"Calls native setDebugFooterEnabledWithEnabled:YES.", @"DBG"],
        @[@"Clear Force Bloks Experience", @"Calls native clearForceBloksExperience.", @"CLR"]
    ];
    NSArray *r = rows[ip.row];
    [cell configureWithTitle:r[0] subtitle:r[1] badge:r[2] emphasized:(ip.row == 1 || ip.row == 3)];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)stubCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    NSDictionary *d = self.filteredStubs[ip.row];
    NSString *title = d[@"display"] ?: d[@"class"] ?: @"";
    NSString *subtitle = [NSString stringWithFormat:@"methods %@/%@ · props %@ · ivars %@", d[@"methodCountPreview"] ?: @0, d[@"classMethodCountPreview"] ?: @0, d[@"propertyCountPreview"] ?: @0, d[@"ivarCountPreview"] ?: @0];
    [cell configureWithTitle:title subtitle:subtitle badge:@"STUB" emphasized:YES];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)objectCell:(NSIndexPath *)ip settings:(BOOL)settings {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    NSDictionary *d = settings ? self.filteredSettingsTargets[ip.row] : self.filteredObjects[ip.row];
    NSString *subtitle = [NSString stringWithFormat:@"roles %@ · sources %@ · ivars %@", d[@"roles"] ?: @[], d[@"sources"] ?: @[], @([d[@"ivars"] count])];
    [cell configureWithTitle:[NSString stringWithFormat:@"%@ %@", d[@"class"] ?: @"", d[@"address"] ?: @""] subtitle:subtitle badge:(settings ? @"SET" : @"LIVE") emphasized:!settings];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}


- (UITableViewCell *)notesChangeCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    NSDictionary *d = self.filteredNotesChanges[ip.row];
    NSString *title = [NSString stringWithFormat:@"%@ %@", [d[@"canReplayLauncherOverride"] boolValue] ? @"Replayable" : @"Snapshot", d[@"source"] ?: @""];
    NSString *subtitle = [NSString stringWithFormat:@"launcher %@ · parameter %@ · value %@ · item %@", d[@"launcher"] ?: @"?", d[@"parameter"] ?: @"?", d[@"value"] ?: @"?", d[@"itemClass"] ?: @""];
    [cell configureWithTitle:title subtitle:subtitle badge:@"SAVE" emphasized:[d[@"canReplayLauncherOverride"] boolValue]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)paramCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    NSDictionary *d = self.filteredParams[ip.row];
    NSArray *tags = [d[@"tags"] isKindOfClass:NSArray.class] ? d[@"tags"] : @[];
    NSString *title = [NSString stringWithFormat:@"%@%@ %@", tags.count ? [[tags componentsJoinedByString:@", "] stringByAppendingString:@" · "] : @"", d[@"paramID"] ?: @"", d[@"type"] ?: @""];
    NSString *subtitle = [NSString stringWithFormat:@"count %@ · value %@ · %@", d[@"count"] ?: @0, d[@"returned"] ?: @"", d[@"map"] ?: @""];
    [cell configureWithTitle:title subtitle:subtitle badge:@"MC" emphasized:NO];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)actionLogCell:(NSIndexPath *)ip {
    SCIGlassParamCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    NSDictionary *d = self.actions[ip.row];
    [cell configureWithTitle:[NSString stringWithFormat:@"%@ · %@", d[@"action"] ?: @"", d[@"status"] ?: @""] subtitle:d[@"detail"] ?: @"" badge:@"LOG" emphasized:NO];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) return [self actionCell:ip];
    if (ip.section == 1) return [self stubCell:ip];
    if (ip.section == 2) return [self objectCell:ip settings:NO];
    if (ip.section == 3) return [self objectCell:ip settings:YES];
    if (ip.section == 4) return [self notesChangeCell:ip];
    if (ip.section == 5) return [self paramCell:ip];
    return [self actionLogCell:ip];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        BOOL needsFullRefresh = NO;
        if (ip.row == 0) {
            [SCIDogfoodObjectRuntime noteAction:@"Open Native Dogfood Settings" status:@"disabled" detail:@"Reflected openWithConfig entrypoint blocks this IG build; not called."];
            [SCIUtils showToastForDuration:1.4 title:@"Disabled here" subtitle:@"Use Notes/Internal Actions."];
        }
        else if (ip.row == 1) {
            NSError *err = nil;
            if (![SCIInternalActions openNotesDogfoodSettings:&err]) {
                NSString *msg = err.localizedDescription ?: @"Notes dogfooding unavailable.";
                [SCIDogfoodObjectRuntime noteAction:@"Open Notes Dogfooding" status:@"failed" detail:msg];
                [SCIUtils showErrorHUDWithDescription:msg];
            } else {
                [SCIDogfoodObjectRuntime noteAction:@"Open Notes Dogfooding" status:@"sent native opener" detail:nil];
            }
        }
        else if (ip.row == 2) {
            [SCIDogfoodObjectRuntime noteAction:@"Open MetaLocalExperiment" status:@"disabled" detail:@"Unsafe heavy config construction from tap; not called."];
            [SCIUtils showToastForDuration:1.4 title:@"Disabled here" subtitle:@"Avoiding main-thread hang."];
        }
        else if (ip.row == 3) [self exportSnapshot];
        else if (ip.row == 4) { BOOL next = ![SCIMobileConfigRuntime runtimeHooksEnabled]; [SCIMobileConfigRuntime setRuntimeCaptureActive:next]; if (next) SCIInstallMobileConfigRuntimeHooksIfNeeded(); needsFullRefresh = YES; }
        else if (ip.row == 5) { [SCIUtils setPref:@(![SCIMobileConfigRuntime deepCallerSymbolsEnabled]) forKey:@"sci_mc_runtime_deep_symbols_enabled"]; needsFullRefresh = YES; }
        else if (ip.row == 6) { UIPasteboard.generalPasteboard.string = [[SCILauncherOverride allOverrides] description]; [SCIUtils showToastForDuration:1.2 title:@"Copied"]; }
        else if (ip.row == 7) { UIPasteboard.generalPasteboard.string = [[SCIInternalActions state] description]; [SCIUtils showToastForDuration:1.2 title:@"Copied"]; }
        else if (ip.row == 8) [SCIInternalActions forceBloksExperienceOn];
        else if (ip.row == 9) [SCIInternalActions forceBloksExperienceOff];
        else if (ip.row == 10) [SCIInternalActions setBloksPrefetchEnabled:YES];
        else if (ip.row == 11) [SCIInternalActions setDebugFooterEnabled:YES];
        else if (ip.row == 12) [SCIInternalActions clearForceBloksExperience];
        if (needsFullRefresh) [self refreshAll];
        else [self refreshRuntimeStateOnly];
        return;
    }
    id obj = nil;
    if (ip.section == 1 && ip.row < (NSInteger)self.filteredStubs.count) obj = self.filteredStubs[ip.row];
    else if (ip.section == 2 && ip.row < (NSInteger)self.filteredObjects.count) obj = self.filteredObjects[ip.row];
    else if (ip.section == 3 && ip.row < (NSInteger)self.filteredSettingsTargets.count) obj = self.filteredSettingsTargets[ip.row];
    else if (ip.section == 4 && ip.row < (NSInteger)self.filteredNotesChanges.count) obj = self.filteredNotesChanges[ip.row];
    else if (ip.section == 5 && ip.row < (NSInteger)self.filteredParams.count) obj = self.filteredParams[ip.row];
    else if (ip.section == 6 && ip.row < (NSInteger)self.actions.count) obj = self.actions[ip.row];
    [self presentDetails:obj];
}

- (void)presentDetails:(id)obj {
    if (!obj) return;
    id detail = obj;
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSString *addr = [(NSDictionary *)obj objectForKey:@"address"];
        NSString *cls = [(NSDictionary *)obj objectForKey:@"class"];
        NSDictionary *rich = addr.length ? [SCIDogfoodObjectRuntime detailsForObjectAddress:addr] : @{};
        if (!rich.count && cls.length) rich = [SCIDogfoodObjectRuntime detailsForRuntimeStubClass:cls];
        if (rich.count) detail = rich;
    }
    NSString *text = nil;
    if ([NSJSONSerialization isValidJSONObject:detail]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:detail options:NSJSONWritingPrettyPrinted error:nil];
        text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    }
    if (!text.length) text = [detail description] ?: @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Auto-FLEX details" message:text preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) { UIPasteboard.generalPasteboard.string = text; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)exportSnapshot {
    NSDictionary *snapshot = @{ @"dogfoodObjectRuntime": [SCIDogfoodObjectRuntime fullSnapshotIncludingDetails:NO], @"runtimeStubs": self.stubs ?: @[], @"notesDogfoodingPersistence": self.notesChanges ?: @[], @"mobileConfigReads": self.params ?: @[], @"launcherOverrides": [SCILauncherOverride allOverrides] ?: @{} };
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
    UIPasteboard.generalPasteboard.string = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : [snapshot description];
    [SCIDogfoodObjectRuntime noteAction:@"Copy Auto-FLEX snapshot" status:@"copied" detail:nil];
}

@end
