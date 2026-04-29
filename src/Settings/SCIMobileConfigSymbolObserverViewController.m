#import "SCIMobileConfigSymbolObserverViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Features/ExpFlags/SCIExpMobileConfigMapping.h"
#import "../Utils.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, SCIMCObserverMode) {
    SCIMCObserverModeAll = 0,
    SCIMCObserverModeWouldChange,
    SCIMCObserverModeObjC,
    SCIMCObserverModeC,
    SCIMCObserverModeUpdate,
};

static const void *kSCIMCObserverSwitchKey = &kSCIMCObserverSwitchKey;

@interface SCIMobileConfigSymbolObserverViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *modeSeg;
@property (nonatomic, strong) UISegmentedControl *categorySeg;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<NSString *> *categories;
@property (nonatomic, strong) NSArray<SCIExpMCObservation *> *rows;
@end

@implementation SCIMobileConfigSymbolObserverViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MC Override Lab";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.categories = @[@"All", @"Dogfood", @"Direct", @"QuickSnap", @"Prism", @"TabBar", @"Feed", @"Infra", @"Unknown"];

    // Do not use leftBarButtonItem here: it suppresses the navigation back button.
    UIBarButtonItem *exportItem = [[UIBarButtonItem alloc] initWithTitle:@"Export" style:UIBarButtonItemStylePlain target:self action:@selector(exportMenu)];
    UIBarButtonItem *importItem = [[UIBarButtonItem alloc] initWithTitle:@"Import JSON" style:UIBarButtonItemStylePlain target:self action:@selector(importRuntimeJSON)];
    self.navigationItem.rightBarButtonItems = @[exportItem, importItem];

    self.modeSeg = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Would change", @"ObjC", @"C", @"Update"]];
    self.modeSeg.selectedSegmentIndex = SCIMCObserverModeAll;
    self.modeSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeSeg addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeSeg];

    self.categorySeg = [[UISegmentedControl alloc] initWithItems:self.categories];
    self.categorySeg.selectedSegmentIndex = 0;
    self.categorySeg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.categorySeg addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.categorySeg];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search name / category / selector / source";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.emptyLabel = [UILabel new];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont systemFontOfSize:14];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.modeSeg.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.modeSeg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.modeSeg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.categorySeg.topAnchor constraintEqualToAnchor:self.modeSeg.bottomAnchor constant:6],
        [self.categorySeg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.categorySeg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.categorySeg.bottomAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
    ]];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (void)filterChanged { [self refresh]; }
- (void)refresh {
    self.rows = [self filteredRows];
    [self.tableView reloadData];
    self.emptyLabel.hidden = self.rows.count > 0;
    self.emptyLabel.text = self.query.length ? @"No matching gates." : @"Enable MC hooks, restart, then browse Instagram screens to populate gates.";
}

#pragma mark - Runtime schema import/debug

- (NSArray<NSString *> *)runtimeJSONCandidatePaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *bundle = [NSBundle mainBundle].bundlePath;
    if (bundle.length) {
        [paths addObject:[bundle stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/igios-instagram-schema_client-persist.json"]];
        [paths addObject:[bundle stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/igios-facebook-schema_client-persist.json"]];
        [paths addObject:[bundle stringByAppendingPathComponent:@"igios-instagram-schema_client-persist.json"]];
    }
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.firstObject) [paths addObject:[docs.firstObject stringByAppendingPathComponent:@"igios-instagram-schema_client-persist.json"]];
    NSArray<NSString *> *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (appSupport.firstObject) [paths addObject:[[appSupport.firstObject stringByAppendingPathComponent:@"RyukGram"] stringByAppendingPathComponent:@"igios-instagram-schema_client-persist.json"]];
    return paths;
}

- (NSString *)persistedRuntimeJSONPath {
    NSArray<NSString *> *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = appSupport.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [base stringByAppendingPathComponent:@"RyukGram"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"igios-instagram-schema_client-persist.json"];
}

- (NSDictionary *)runtimeJSONStatus {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSMutableArray *checked = [NSMutableArray array];
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *path in [self runtimeJSONCandidatePaths]) {
        if (!path.length) continue;
        [checked addObject:path];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] ?: @{};
            [found addObject:@{@"path": path, @"size": attrs[NSFileSize] ?: @0}];
        }
    }
    out[@"checked"] = checked;
    out[@"found"] = found;
    out[@"mapping"] = [SCIExpMobileConfigMapping mappingSourceDescription] ?: @"none";
    out[@"persisted"] = [self persistedRuntimeJSONPath] ?: @"";
    return out;
}

- (void)importRuntimeJSON {
    NSDictionary *status = [self runtimeJSONStatus];
    NSArray *found = status[@"found"];
    NSString *source = nil;
    for (NSDictionary *entry in found) {
        NSString *p = entry[@"path"];
        if ([p containsString:@"FBSharedFramework.framework/igios-instagram-schema_client-persist.json"]) { source = p; break; }
        if (!source.length) source = p;
    }
    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"Resolver atual:\n%@\n\n", status[@"mapping"] ?: @"none"];
    [msg appendFormat:@"Destino importado:\n%@\n\n", status[@"persisted"] ?: @""];
    if (!source.length) {
        [msg appendString:@"Nenhum JSON runtime encontrado.\n\nChecked:\n"];
        for (NSString *p in status[@"checked"]) [msg appendFormat:@"- %@\n", p];
        [self presentText:msg title:@"Import JSON"];
        return;
    }
    NSString *dest = [self persistedRuntimeJSONPath];
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    BOOL ok = [[NSFileManager defaultManager] copyItemAtPath:source toPath:dest error:&err];
    if (ok) {
        [SCIExpMobileConfigMapping reloadMapping];
        [msg appendFormat:@"Importado de:\n%@\n\n", source];
        [msg appendString:@"Cópia local pronta; o caminho runtime resolve o UUID mutável da instalação.\n\n"];
    } else {
        [msg appendFormat:@"Falha ao copiar:\n%@\n", err.localizedDescription ?: @"unknown"];
    }
    [msg appendString:[SCIExpMobileConfigMapping mappingDebugDescription] ?: @""];
    [self presentText:msg title:ok ? @"JSON importado" : @"Import JSON"];
}

- (void)presentText:(NSString *)text title:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title ?: @"Debug" message:text ?: @"" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = text ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Filtering

- (NSArray<SCIExpMCObservation *> *)filteredRows {
    NSArray<SCIExpMCObservation *> *all = [SCIExpFlags allMCObservations] ?: @[];
    NSMutableArray<SCIExpMCObservation *> *out = [NSMutableArray array];
    NSUInteger categoryIndex = (NSUInteger)MAX(0, self.categorySeg.selectedSegmentIndex);
    if (categoryIndex >= self.categories.count) categoryIndex = 0;
    NSString *selectedCategory = self.categories[categoryIndex];
    NSString *q = self.query.lowercaseString ?: @"";
    SCIMCObserverMode mode = (SCIMCObserverMode)self.modeSeg.selectedSegmentIndex;
    for (SCIExpMCObservation *o in all) {
        NSString *detail = o.lastDefault ?: @"";
        NSString *display = [self displayNameForObservation:o];
        NSString *category = [self categoryForObservation:o];
        if (![self observation:o detail:detail matchesMode:mode]) continue;
        if (![selectedCategory isEqualToString:@"All"] && ![category isEqualToString:selectedCategory]) continue;
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@", display ?: @"", category ?: @"", detail ?: @"", o.resolvedName ?: @"", o.source ?: @"", o.contextClass ?: @"", o.selectorName ?: @"", [self specifierHex:o.paramID]].lowercaseString;
        if (q.length && ![haystack containsString:q]) continue;
        [out addObject:o];
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(SCIExpMCObservation *a, SCIExpMCObservation *b) {
        BOOL ac = [self wouldChangeObservation:a];
        BOOL bc = [self wouldChangeObservation:b];
        if (ac != bc) return ac ? NSOrderedAscending : NSOrderedDescending;
        if (a.hitCount != b.hitCount) return a.hitCount > b.hitCount ? NSOrderedAscending : NSOrderedDescending;
        return [[self displayNameForObservation:a] compare:[self displayNameForObservation:b]];
    }];
}

- (BOOL)observation:(SCIExpMCObservation *)o detail:(NSString *)detail matchesMode:(SCIMCObserverMode)mode {
    switch (mode) {
        case SCIMCObserverModeAll: return YES;
        case SCIMCObserverModeWouldChange: return [self wouldChangeObservation:o];
        case SCIMCObserverModeObjC: return [detail containsString:@"ObjC MobileConfig getter"] || o.contextClass.length > 0;
        case SCIMCObserverModeC: return ![detail containsString:@"ObjC MobileConfig getter"] && !o.contextClass.length && ![self isUpdatePathObservation:o];
        case SCIMCObserverModeUpdate: return [self isUpdatePathObservation:o];
    }
    return YES;
}

- (BOOL)isUpdatePathObservation:(SCIExpMCObservation *)o {
    NSString *s = [NSString stringWithFormat:@"%@ %@ %@ %@", o.lastDefault ?: @"", o.resolvedName ?: @"", o.contextClass ?: @"", o.selectorName ?: @""].lowercaseString;
    return [s containsString:@"updateconfigs"] || [s containsString:@"forceupdate"] || [s containsString:@"setconfigoverrides"] || [s containsString:@"refresh"] || [s containsString:@"override path"];
}

- (BOOL)wouldChangeObservation:(SCIExpMCObservation *)o {
    NSString *detail = o.lastDefault ?: @"";
    NSString *orig = o.lastOriginalValue ?: @"";
    return [detail containsString:@"wouldChangeIfTrue=1"] || [detail containsString:@"wouldChange=1"] || [orig isEqualToString:@"NO"] || [orig isEqualToString:@"0"];
}

- (BOOL)effectiveValueForObservation:(SCIExpMCObservation *)o {
    SCIExpFlagOverride ov = [self overrideForObservation:o];
    if (ov == SCIExpFlagOverrideTrue) return YES;
    if (ov == SCIExpFlagOverrideFalse) return NO;
    NSString *orig = o.lastOriginalValue ?: @"";
    if ([orig isEqualToString:@"YES"] || [orig isEqualToString:@"1"]) return YES;
    if ([orig isEqualToString:@"NO"] || [orig isEqualToString:@"0"]) return NO;
    return ![self wouldChangeObservation:o];
}

- (NSString *)displayNameForObservation:(SCIExpMCObservation *)o {
    if (o.resolvedName.length) return o.resolvedName;
    NSString *detail = o.lastDefault ?: @"";
    NSString *symbol = [self symbolNameFromDetail:detail];
    if (symbol.length) return symbol;
    if (o.contextClass.length || o.selectorName.length) return [NSString stringWithFormat:@"%@ %@", o.contextClass.length ? o.contextClass : @"ObjC", o.selectorName.length ? o.selectorName : @""];
    return [self fallbackOverrideKeyForObservation:o];
}

- (NSString *)fallbackOverrideKeyForObservation:(SCIExpMCObservation *)o { return [NSString stringWithFormat:@"mc:0x%016llx", o.paramID]; }

- (NSString *)categoryForObservation:(SCIExpMCObservation *)o {
    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", o.resolvedName ?: @"", o.lastDefault ?: @"", o.contextClass ?: @"", o.selectorName ?: @"", [self symbolNameFromDetail:o.lastDefault ?: @""] ?: @""].lowercaseString;
    if ([self string:hay containsAny:@[@"employee", @"dogfood", @"dogfooding", @"internal", @"test_user", @"devoptions"]]) return @"Dogfood";
    if ([self string:hay containsAny:@[@"directnotes", @"direct_notes", @"friendmap", @"locationnotes", @"notestray"]]) return @"Direct";
    if ([self string:hay containsAny:@[@"quicksnap", @"quick_snap", @"instants", @"instant", @"mshquicksnap"]]) return @"QuickSnap";
    if ([self string:hay containsAny:@[@"prism", @"igdsprism", @"prismmenu"]]) return @"Prism";
    if ([self string:hay containsAny:@[@"tabbar", @"homecoming", @"launcher", @"navigation", @"sundial"]]) return @"TabBar";
    if ([self string:hay containsAny:@[@"feed", @"reels", @"story", @"stories", @"explore"]]) return @"Feed";
    if ([self string:hay containsAny:@[@"mobileconfig", @"startupconfigs", @"easygating", @"override", @"refresh", @"updateconfigs", @"sessionless", @"objc mobileconfig getter", @"mci", @"metaextensions", @"msgc"]]) return @"Infra";
    return @"Unknown";
}

- (BOOL)string:(NSString *)s containsAny:(NSArray<NSString *> *)needles { for (NSString *n in needles) if ([s containsString:n]) return YES; return NO; }

- (NSString *)symbolNameFromDetail:(NSString *)detail {
    NSArray<NSString *> *symbols = @[@"_IGMobileConfigBooleanValueForInternalUse", @"_IGMobileConfigSessionlessBooleanValueForInternalUse", @"_EasyGatingGetBoolean_Internal_DoNotUseOrMock", @"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", @"_MCQEasyGatingGetBooleanInternalDoNotUseOrMock", @"_EasyGatingPlatformGetBoolean", @"_MSGCSessionedMobileConfigGetBoolean", @"_MCIMobileConfigGetBoolean", @"_MCIExperimentCacheGetMobileConfigBoolean", @"_MCIExtensionExperimentCacheGetMobileConfigBoolean", @"_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter", @"_METAExtensionsExperimentGetBooleanWithoutExposure", @"_METAExtensionsExperimentGetBoolean", @"_MEBIsMinosDogfoodMekEncryptionVersionEnabled", @"_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", @"_IGMobileConfigTryUpdateConfigsWithCompletion", @"_IGMobileConfigForceUpdateConfigs", @"_IGMobileConfigSetConfigOverrides"];
    for (NSString *s in symbols) if ([detail containsString:s]) return s;
    return nil;
}

- (NSString *)specifierHex:(unsigned long long)specifier { return [NSString stringWithFormat:@"0x%016llx", specifier]; }
- (NSString *)overrideKeyForObservation:(SCIExpMCObservation *)o { return o.resolvedName.length ? o.resolvedName : [self fallbackOverrideKeyForObservation:o]; }
- (SCIExpFlagOverride)overrideForObservation:(SCIExpMCObservation *)o { return [SCIExpFlags overrideForName:[self overrideKeyForObservation:o]]; }

#pragma mark - Export

- (NSArray<NSDictionary *> *)exportRows {
    NSMutableArray<NSDictionary *> *arr = [NSMutableArray array];
    for (SCIExpMCObservation *o in self.rows ?: @[]) {
        NSString *key = [self overrideKeyForObservation:o] ?: @"";
        SCIExpFlagOverride ov = key.length ? [SCIExpFlags overrideForName:key] : SCIExpFlagOverrideOff;
        [arr addObject:@{@"param_id_hex": [self specifierHex:o.paramID], @"param_id": @(o.paramID), @"name": [self displayNameForObservation:o] ?: @"", @"resolved_name": o.resolvedName ?: @"", @"category": [self categoryForObservation:o] ?: @"Unknown", @"source": o.source ?: @"", @"context_class": o.contextClass ?: @"", @"selector": o.selectorName ?: @"", @"default_or_detail": o.lastDefault ?: @"", @"original": o.lastOriginalValue ?: @"", @"effective": @([self effectiveValueForObservation:o]), @"would_change_if_true": @([self wouldChangeObservation:o]), @"override_key": key, @"override": @(ov), @"hits": @(o.hitCount)}];
    }
    return arr;
}

- (NSString *)exportJSON { NSData *data = [NSJSONSerialization dataWithJSONObject:[self exportRows] options:NSJSONWritingPrettyPrinted error:nil]; return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]"; }
- (NSString *)csvEscape:(id)obj { NSString *s = [obj respondsToSelector:@selector(description)] ? [obj description] : @""; s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]; return [NSString stringWithFormat:@"\"%@\"", s]; }
- (NSString *)exportCSV {
    NSArray *keys = @[@"param_id_hex", @"name", @"resolved_name", @"category", @"source", @"context_class", @"selector", @"original", @"effective", @"would_change_if_true", @"override_key", @"override", @"hits", @"default_or_detail"];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[keys componentsJoinedByString:@","]];
    for (NSDictionary *row in [self exportRows]) { NSMutableArray *cols = [NSMutableArray array]; for (NSString *k in keys) [cols addObject:[self csvEscape:row[k] ?: @""]]; [lines addObject:[cols componentsJoinedByString:@","]]; }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)exportMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"MC Override Lab" message:[NSString stringWithFormat:@"%lu row(s)", (unsigned long)self.rows.count] preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy JSON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = [self exportJSON]; [SCIUtils showSuccessHUDWithDescription:@"JSON copied"]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy CSV" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = [self exportCSV]; [SCIUtils showSuccessHUDWithDescription:@"CSV copied"]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Share JSON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[self exportJSON]] applicationActivities:nil]; if (vc.popoverPresentationController) vc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem; [self presentViewController:vc animated:YES completion:nil]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Mapping debug" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { NSMutableString *msg = [NSMutableString stringWithString:[SCIExpMobileConfigMapping mappingDebugDescription] ?: @""]; [msg appendString:@"\n\nRuntime JSON candidates:\n"]; for (NSString *p in [self runtimeJSONCandidatePaths]) [msg appendFormat:@"- %@\n", p]; [self presentText:msg title:@"id_name_mapping debug"]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mc-override-lab"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc-override-lab"];
    SCIExpMCObservation *o = self.rows[(NSUInteger)indexPath.row];
    NSString *name = [self displayNameForObservation:o];
    NSString *category = [self categoryForObservation:o];
    NSString *change = [self wouldChangeObservation:o] ? @" WOULD_TRUE" : @"";
    SCIExpFlagOverride ov = [self overrideForObservation:o];
    NSString *ovText = ov == SCIExpFlagOverrideTrue ? @"FORCED ON" : ov == SCIExpFlagOverrideFalse ? @"FORCED OFF" : @"default";
    cell.textLabel.text = [NSString stringWithFormat:@"[%@] %@ %@%@", category, name, [self specifierHex:o.paramID], change];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 0;
    NSMutableArray *parts = [NSMutableArray array];
    if (o.contextClass.length || o.selectorName.length) [parts addObject:[NSString stringWithFormat:@"%@ %@", o.contextClass ?: @"", o.selectorName ?: @""]];
    if (o.lastOriginalValue.length) [parts addObject:[NSString stringWithFormat:@"original=%@", o.lastOriginalValue]];
    [parts addObject:[NSString stringWithFormat:@"effective=%@", [self effectiveValueForObservation:o] ? @"YES" : @"NO"]];
    [parts addObject:[NSString stringWithFormat:@"override=%@", ovText]];
    if (o.lastDefault.length) [parts addObject:o.lastDefault];
    [parts addObject:[NSString stringWithFormat:@"×%lu", (unsigned long)o.hitCount]];
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0;
    UISwitch *sw = [UISwitch new];
    sw.on = [self effectiveValueForObservation:o];
    objc_setAssociatedObject(sw, kSCIMCObserverSwitchKey, [self overrideKeyForObservation:o], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sw addTarget:self action:@selector(overrideSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)overrideSwitchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, kSCIMCObserverSwitchKey);
    if (!key.length) return;
    [SCIExpFlags setOverride:(sender.on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forName:key];
    [self refresh];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    SCIExpMCObservation *o = self.rows[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *key = [self overrideKeyForObservation:o];
    NSString *msg = [NSString stringWithFormat:@"name=%@\ncategory=%@\nparam=%@\nresolved=%@\noverrideKey=%@\nsource=%@\ncontext=%@\nselector=%@\noriginal=%@\neffective=%@\nhits=%lu\n\n%@", [self displayNameForObservation:o], [self categoryForObservation:o], [self specifierHex:o.paramID], o.resolvedName ?: @"", key ?: @"", o.source ?: @"", o.contextClass ?: @"", o.selectorName ?: @"", o.lastOriginalValue ?: @"", [self effectiveValueForObservation:o] ? @"YES" : @"NO", (unsigned long)o.hitCount, o.lastDefault ?: @""];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[self displayNameForObservation:o] message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy row" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = msg; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy override key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = key ?: @""; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy param" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = [self specifierHex:o.paramID]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"No override" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [SCIExpFlags setOverride:SCIExpFlagOverrideOff forName:key]; [self refresh]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [SCIExpFlags setOverride:SCIExpFlagOverrideTrue forName:key]; [self refresh]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [SCIExpFlags setOverride:SCIExpFlagOverrideFalse forName:key]; [self refresh]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = cell; sheet.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { self.query = searchText ?: @""; [self refresh]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
