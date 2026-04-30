#import "SCIMCFocusedLabViewController.h"
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Features/ExpFlags/SCIMobileConfigMapping.h"
#import "../Utils.h"
#import <objc/runtime.h>

extern void SCIInstallFocusedObjCGetterObserver(void);

static NSString *const kSCIMCFocusEnabledKey = @"sci_exp_mc_objc_focus_enabled";
static NSString *const kSCIMCFocusTargetKey = @"sci_exp_mc_objc_focus_target";
static const void *kSCIMCFocusSwitchKey = &kSCIMCFocusSwitchKey;

typedef NS_ENUM(NSInteger, SCIMCFocusedResultMode) {
    SCIMCFocusedResultModeAll = 0,
    SCIMCFocusedResultModeWouldChange,
    SCIMCFocusedResultModeForced,
};

@interface SCIMCFocusedLabRow : NSObject
@property (nonatomic, assign) unsigned long long paramID;
@property (nonatomic, copy) NSString *paramHex;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *resolvedName;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *gate;
@property (nonatomic, copy) NSString *contextClass;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *original;
@property (nonatomic, copy) NSString *overrideKey;
@property (nonatomic, assign) NSUInteger hits;
@property (nonatomic, assign) BOOL wouldChange;
@property (nonatomic, assign) BOOL hasOriginal;
@property (nonatomic, assign) BOOL originalValue;
@end
@implementation SCIMCFocusedLabRow
@end

@interface SCIMCFocusedLabViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISegmentedControl *resultSeg;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray<NSDictionary *> *targets;
@property (nonatomic, strong) NSArray<SCIMCFocusedLabRow *> *rows;
@end

@implementation SCIMCFocusedLabViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MC Override Lab";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.targets = [self buildTargets];
    self.rows = @[];

    NSUserDefaults *udInit = [NSUserDefaults standardUserDefaults];
    if (![udInit objectForKey:kSCIMCFocusTargetKey]) {
        [udInit setObject:@"c|all" forKey:kSCIMCFocusTargetKey];
    }
    [udInit setBool:YES forKey:@"sci_exp_flags_enabled"];
    [udInit setBool:YES forKey:@"sci_exp_mc_c_hooks_enabled"];
    [udInit setBool:YES forKey:@"igt_runtime_mc_symbol_observer_enabled"];
    [udInit synchronize];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Bulk" style:UIBarButtonItemStylePlain target:self action:@selector(showBulkMenu)];

    self.resultSeg = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Would", @"Forced"]];
    self.resultSeg.selectedSegmentIndex = SCIMCFocusedResultModeAll;
    self.resultSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resultSeg addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.resultSeg];

    self.searchBar = [UISearchBar new];
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = @"Search focused dump";
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
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
    self.emptyLabel.hidden = YES;
    self.emptyLabel.userInteractionEnabled = NO;
    [self.view addSubview:self.emptyLabel];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.resultSeg.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.resultSeg.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.resultSeg.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.searchBar.topAnchor constraintEqualToAnchor:self.resultSeg.bottomAnchor constant:4],
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

- (NSArray<NSDictionary *> *)buildTargets {

    NSMutableArray *t = [NSMutableArray array];

    [t addObject:@{@"title": @"All dump/runtime", @"subtitle": @"Tudo observado pelo runtime + filtros do dump completo", @"key": @"all"}];

    [t addObject:@{@"title": @"Patched/stubbed/restored", @"subtitle": @"Só gates que foram testados nos reports offline", @"key": @"status|active"}];

    [t addObject:@{@"title": @"C bool brokers / symbols", @"subtitle": @"Todos os C gates bool testáveis do dump", @"key": @"kind|c"}];

    [t addObject:@{@"title": @"ObjC MobileConfig getters", @"subtitle": @"Todos os ObjC bool getters do dump; para captura ao vivo selecione um getter específico", @"key": @"kind|objc"}];

    [t addObject:@{@"title": @"Update / refresh / override paths", @"subtitle": @"Observe-only; não são bool gates", @"key": @"category|update_refresh_override_paths"}];

    NSArray<NSString *> *categories = @[@"c_bool_brokers", @"objc_mobileconfig_getters_contexts", @"objc_mapped_mobileconfig_class", @"startupconfigs_boot_getters", @"update_refresh_override_paths", @"direct_notes", @"direct_msys_e2ee", @"dogfood_internal_employee", @"quicksnap_instants", @"prism_ui", @"tabbar_navigation_homecoming", @"eligibility_monetization", @"feature_family", @"other_candidates", @"other"];

    for (NSString *cat in categories) {

        [t addObject:@{@"title": @"Category", @"subtitle": cat, @"key": [@"category|" stringByAppendingString:cat]}];

    }

    NSArray<NSString *> *groups = @[@"safe_global_boolean_gates", @"setA_v1_c_brokers", @"setA_objc_getBool", @"v2_1_plus_startupconfigs", @"default_only_v1", @"update_override_paths_restored", @"missing_gates", @"global_broker", @"persisted_query", @"feature_family", @"tabbar_navigation", @"direct_notes", @"direct_msys_e2ee", @"prism_ui", @"eligibility_monetization", @"objc_mapped_mobileconfig_class", @"other"];

    for (NSString *grp in groups) {

        [t addObject:@{@"title": @"Group", @"subtitle": grp, @"key": [@"group|" stringByAppendingString:grp]}];

    }

    NSArray<NSString *> *cSymbols = @[@"_IGMobileConfigBooleanValueForInternalUse", @"_IGMobileConfigSessionlessBooleanValueForInternalUse", @"_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", @"_EasyGatingGetBoolean_Internal_DoNotUseOrMock", @"_EasyGatingPlatformGetBoolean", @"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", @"_MCQEasyGatingGetBooleanInternalDoNotUseOrMock", @"_MCIMobileConfigGetBoolean", @"_MCIExperimentCacheGetMobileConfigBoolean", @"_MCIExtensionExperimentCacheGetMobileConfigBoolean", @"_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter", @"_METAExtensionsExperimentGetBoolean", @"_METAExtensionsExperimentGetBooleanWithoutExposure", @"_MSGCSessionedMobileConfigGetBoolean", @"_MEBIsMinosDogfoodMekEncryptionVersionEnabled", @"_IGDirectNotesFriendMapEnabled", @"_IGDirectNotesEnableAudioNoteReplyType", @"_IGDirectNotesEnableAvatarReplyTypes", @"_IGDirectNotesEnableGifsStickersReplyTypes", @"_IGDirectNotesEnablePhotoNoteReplyType", @"_IGTabBarStyleForLauncherSet", @"_IGTabBarShouldEnableBlurDebugListener", @"_IGTabBarDynamicSizingEnabled", @"_IGTabBarHomecomingWithFloatingTabEnabled", @"_IGTabBarEnhancedDynamicSizingEnabled"];

    for (NSString *sym in cSymbols) {

        [t addObject:@{@"title": @"C gate", @"subtitle": sym, @"key": [@"c|" stringByAppendingString:sym]}];

    }

    NSArray<NSArray<NSString *> *> *objcPairs = @[

        @[@"FBMobileConfigStartupConfigsDeprecated", @"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:"],
        @[@"FBMobileConfigStartupConfigs", @"getBool:withDefault:"],
        @[@"FBMobileConfigStartupConfigs", @"getBool:withOptions:withDefault:"],
        @[@"FBMobileConfigStartupConfigs", @"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:"],
        @[@"IGMobileConfigContextManager", @"getBool:"],
        @[@"IGMobileConfigContextManager", @"getBool:withDefault:"],
        @[@"IGMobileConfigContextManager", @"getBool:withOptions:"],
        @[@"IGMobileConfigContextManager", @"getBool:withOptions:withDefault:"],
        @[@"IGMobileConfigUserSessionContextManager", @"getBool:"],
        @[@"IGMobileConfigUserSessionContextManager", @"getBool:withOptions:"],
        @[@"IGMobileConfigSessionlessContextManager", @"getBool:"],
        @[@"IGMobileConfigSessionlessContextManager", @"getBool:withOptions:"],
        @[@"FBMobileConfigContextManager", @"getBool:"],
        @[@"FBMobileConfigContextManager", @"getBool:withDefault:"],
        @[@"FBMobileConfigContextManager", @"getBool:withOptions:"],
        @[@"FBMobileConfigContextManager", @"getBool:withOptions:withDefault:"],
        @[@"FBMobileConfigContextManager", @"getBoolWithoutLogging:"],
        @[@"FBMobileConfigContextManager", @"getBoolWithoutLogging:withDefault:"],
        @[@"FBMobileConfigUserSessionContextManager", @"getBool:"],
        @[@"FBMobileConfigUserSessionContextManager", @"getBool:withOptions:"],
        @[@"FBMobileConfigSessionlessContextManager", @"getBool:"],
        @[@"FBMobileConfigSessionlessContextManager", @"getBool:withOptions:"],
        @[@"FBMobileConfigContextObjcImpl", @"getBool:"],
        @[@"FBMobileConfigContextObjcImpl", @"getBool:withDefault:"],
        @[@"FBMobileConfigContextObjcImpl", @"getBool:withOptions:"],
        @[@"FBMobileConfigContextObjcImpl", @"getBool:withOptions:withDefault:"],
        @[@"FBMobileConfigEmptyImpl", @"getBool:"],
        @[@"FBMobileConfigEmptyImpl", @"getBool:withDefault:"],
        @[@"FBMobileConfigEmptyImpl", @"getBool:withOptions:"],
        @[@"FBMobileConfigEmptyImpl", @"getBool:withOptions:withDefault:"],
    ];

    for (NSArray<NSString *> *pair in objcPairs) {

        NSString *cls = pair.firstObject ?: @"";

        NSString *sel = pair.count > 1 ? pair[1] : @"";

        [t addObject:@{

            @"title": cls,

            @"subtitle": sel,

            @"key": [NSString stringWithFormat:@"objc|%@|%@", cls, sel]

        }];

    }

    return t;

}

- (NSString *)activeTargetKey { return [[NSUserDefaults standardUserDefaults] stringForKey:kSCIMCFocusTargetKey] ?: @"all"; }

- (NSDictionary *)activeTarget {
    NSString *key = [self activeTargetKey];
    for (NSDictionary *d in self.targets) if ([d[@"key"] isEqualToString:key]) return d;
    return self.targets.firstObject;
}

- (BOOL)isCRow:(SCIExpMCObservation *)o {
    NSString *detail = (o.lastDefault ?: @"").lowercaseString;
    if (o.contextClass.length) return NO;
    if ([detail containsString:@"updateconfigs"] || [detail containsString:@"forceupdate"] || [detail containsString:@"setconfigoverrides"]) return NO;
    return YES;
}

- (BOOL)observation:(SCIExpMCObservation *)o matchesTarget:(NSString *)target {

    if (!target.length || [target isEqualToString:@"all"]) return YES;

    NSString *detail = o.lastDefault ?: @"";

    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@",

                     o.resolvedName ?: @"",

                     detail,

                     o.contextClass ?: @"",

                     o.selectorName ?: @"",

                     [self symbolNameFromDetail:detail] ?: @""].lowercaseString;

    if ([target isEqualToString:@"kind|c"]) return [self isCRow:o];

    if ([target isEqualToString:@"kind|objc"]) return o.contextClass.length > 0;

    if ([target isEqualToString:@"status|active"]) {

        return [hay containsString:@"patched"] ||

               [hay containsString:@"stubbed"] ||

               [hay containsString:@"restored"] ||

               [self isCRow:o] ||

               o.contextClass.length > 0;

    }

    if ([target hasPrefix:@"category|"]) {

        NSString *cat = [target substringFromIndex:9].lowercaseString;

        return [[self categoryForText:hay].lowercaseString isEqualToString:cat] || [hay containsString:cat];

    }

    if ([target hasPrefix:@"group|"]) {

        NSString *grp = [target substringFromIndex:6].lowercaseString;

        return [hay containsString:grp];

    }

    if ([target hasPrefix:@"c|"]) {

        NSString *sym = [target substringFromIndex:2];

        return [self isCRow:o] && ([o.selectorName isEqualToString:sym] || [detail containsString:sym]);

    }

    if ([target hasPrefix:@"objc|"]) {

        NSArray<NSString *> *parts = [target componentsSeparatedByString:@"|"];

        if (parts.count != 3) return NO;

        return [o.contextClass isEqualToString:parts[1]] && [o.selectorName isEqualToString:parts[2]];

    }

    return YES;

}

- (void)refresh {
    NSString *target = [self activeTargetKey];
    NSMutableArray<SCIMCFocusedLabRow *> *rows = [NSMutableArray array];
    NSString *q = self.query.lowercaseString ?: @"";
    NSInteger mode = self.resultSeg.selectedSegmentIndex;

    for (SCIExpMCObservation *o in [SCIExpFlags allMCObservations] ?: @[]) {
        if (![self observation:o matchesTarget:target]) continue;
        SCIMCFocusedLabRow *r = [self rowFromObservation:o];
        SCIExpFlagOverride ov = [SCIExpFlags overrideForName:r.overrideKey];
        if (mode == SCIMCFocusedResultModeWouldChange && !r.wouldChange) continue;
        if (mode == SCIMCFocusedResultModeForced && ov == SCIExpFlagOverrideOff) continue;
        if (q.length && ![[self searchableStringForRow:r] containsString:q]) continue;
        [rows addObject:r];
    }

    self.rows = [rows sortedArrayUsingComparator:^NSComparisonResult(SCIMCFocusedLabRow *a, SCIMCFocusedLabRow *b) {
        if (a.wouldChange != b.wouldChange) return a.wouldChange ? NSOrderedAscending : NSOrderedDescending;
        if (a.hits != b.hits) return a.hits > b.hits ? NSOrderedAscending : NSOrderedDescending;
        return [a.name caseInsensitiveCompare:b.name];
    }];
    [self.tableView reloadData];
    self.emptyLabel.hidden = YES;
    if (!self.rows.count) {
        self.emptyLabel.text = @"";
    }
}

- (SCIMCFocusedLabRow *)rowFromObservation:(SCIExpMCObservation *)o {
    SCIMCFocusedLabRow *r = [SCIMCFocusedLabRow new];
    r.paramID = o.paramID;
    r.paramHex = [self specifierHex:o.paramID];
    r.resolvedName = [SCIMobileConfigMapping resolvedNameForParamID:o.paramID];
    r.name = r.resolvedName.length ? r.resolvedName : [NSString stringWithFormat:@"mc:%@", r.paramHex];
    r.contextClass = o.contextClass ?: @"";
    r.selectorName = o.selectorName ?: @"";
    r.source = o.source ?: @"";
    r.detail = o.lastDefault ?: @"";
    r.original = o.lastOriginalValue ?: @"";
    r.hits = o.hitCount;
    r.gate = r.contextClass.length ? [NSString stringWithFormat:@"%@ %@", r.contextClass, r.selectorName ?: @""] : [self symbolNameFromDetail:r.detail] ?: @"C MobileConfig broker";
    r.category = [self categoryForText:[self searchableStringSeedForRow:r]];
    r.overrideKey = r.resolvedName.length ? r.resolvedName : [NSString stringWithFormat:@"mc:%@", r.paramHex];
    BOOL parsed = NO;
    r.originalValue = [self boolValueFromString:r.original parsed:&parsed];
    r.hasOriginal = parsed;
    r.wouldChange = [r.detail containsString:@"wouldChangeIfTrue=1"] || (parsed && !r.originalValue);
    return r;
}

- (NSString *)specifierHex:(unsigned long long)specifier { return [NSString stringWithFormat:@"0x%016llx", specifier]; }

- (BOOL)boolValueFromString:(NSString *)s parsed:(BOOL *)parsed {
    NSString *v = s.uppercaseString ?: @"";
    if ([v isEqualToString:@"YES"] || [v isEqualToString:@"1"] || [v isEqualToString:@"TRUE"]) { if (parsed) *parsed = YES; return YES; }
    if ([v isEqualToString:@"NO"] || [v isEqualToString:@"0"] || [v isEqualToString:@"FALSE"]) { if (parsed) *parsed = YES; return NO; }
    if (parsed) *parsed = NO;
    return NO;
}

- (BOOL)effectiveValueForRow:(SCIMCFocusedLabRow *)r {
    SCIExpFlagOverride ov = [SCIExpFlags overrideForName:r.overrideKey];
    if (ov == SCIExpFlagOverrideTrue) return YES;
    if (ov == SCIExpFlagOverrideFalse) return NO;
    return r.hasOriginal ? r.originalValue : !r.wouldChange;
}

- (NSString *)searchableStringSeedForRow:(SCIMCFocusedLabRow *)r {
    return [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@", r.name ?: @"", r.resolvedName ?: @"", r.gate ?: @"", r.contextClass ?: @"", r.selectorName ?: @"", r.paramHex ?: @"", r.detail ?: @""].lowercaseString;
}

- (NSString *)searchableStringForRow:(SCIMCFocusedLabRow *)r { return [[self searchableStringSeedForRow:r] stringByAppendingFormat:@" %@", r.category.lowercaseString ?: @""]; }

- (NSString *)categoryForText:(NSString *)hay {
    if ([self string:hay containsAny:@[@"employee", @"dogfood", @"dogfooding", @"internal", @"test_user", @"devoptions"]]) return @"Dogfood";
    if ([self string:hay containsAny:@[@"directnotes", @"direct_notes", @"friendmap", @"locationnotes", @"notestray"]]) return @"Direct";
    if ([self string:hay containsAny:@[@"quicksnap", @"quick_snap", @"instants", @"instant", @"mshquicksnap"]]) return @"QuickSnap";
    if ([self string:hay containsAny:@[@"prism", @"igdsprism", @"prismmenu"]]) return @"Prism";
    if ([self string:hay containsAny:@[@"tabbar", @"homecoming", @"launcher", @"navigation", @"sundial"]]) return @"TabBar";
    if ([self string:hay containsAny:@[@"feed", @"reels", @"story", @"stories", @"explore"]]) return @"Feed";
    return @"Infra";
}

- (BOOL)string:(NSString *)s containsAny:(NSArray<NSString *> *)needles { for (NSString *n in needles) if ([s containsString:n]) return YES; return NO; }

- (NSString *)symbolNameFromDetail:(NSString *)detail {

    NSArray *symbols = @[@"_IGMobileConfigBooleanValueForInternalUse", @"_IGMobileConfigSessionlessBooleanValueForInternalUse", @"_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", @"_EasyGatingGetBoolean_Internal_DoNotUseOrMock", @"_EasyGatingPlatformGetBoolean", @"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", @"_MCQEasyGatingGetBooleanInternalDoNotUseOrMock", @"_MCIMobileConfigGetBoolean", @"_MCIExperimentCacheGetMobileConfigBoolean", @"_MCIExtensionExperimentCacheGetMobileConfigBoolean", @"_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter", @"_METAExtensionsExperimentGetBoolean", @"_METAExtensionsExperimentGetBooleanWithoutExposure", @"_MSGCSessionedMobileConfigGetBoolean", @"_MEBIsMinosDogfoodMekEncryptionVersionEnabled", @"_IGDirectNotesFriendMapEnabled", @"_IGDirectNotesEnableAudioNoteReplyType", @"_IGDirectNotesEnableAvatarReplyTypes", @"_IGDirectNotesEnableGifsStickersReplyTypes", @"_IGDirectNotesEnablePhotoNoteReplyType", @"_IGTabBarStyleForLauncherSet", @"_IGTabBarShouldEnableBlurDebugListener", @"_IGTabBarDynamicSizingEnabled", @"_IGTabBarHomecomingWithFloatingTabEnabled", @"_IGTabBarEnhancedDynamicSizingEnabled"];

    for (NSString *s in symbols) if ([detail containsString:s]) return s;

    return nil;

}

#pragma mark - Export / bulk

- (NSArray<NSDictionary *> *)exportRows {
    NSMutableArray *out = [NSMutableArray array];
    for (SCIMCFocusedLabRow *r in self.rows ?: @[]) {
        SCIExpFlagOverride ov = [SCIExpFlags overrideForName:r.overrideKey];
        [out addObject:@{@"scope": [self activeTargetKey] ?: @"", @"gate": r.gate ?: @"", @"param_id_hex": r.paramHex ?: @"", @"param_id": @(r.paramID), @"name": r.name ?: @"", @"category": r.category ?: @"", @"original": r.original ?: @"", @"effective": @([self effectiveValueForRow:r]), @"would_change_if_true": @(r.wouldChange), @"override_key": r.overrideKey ?: @"", @"override": @(ov), @"hits": @(r.hits), @"detail": r.detail ?: @""}];
    }
    return out;
}

- (NSString *)exportJSON { NSData *d = [NSJSONSerialization dataWithJSONObject:[self exportRows] options:NSJSONWritingPrettyPrinted error:nil]; return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"[]"; }
- (NSString *)csvEscape:(id)obj { NSString *s = [obj respondsToSelector:@selector(description)] ? [obj description] : @""; s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]; return [NSString stringWithFormat:@"\"%@\"", s]; }
- (NSString *)exportCSV {
    NSArray *keys = @[@"scope", @"gate", @"param_id_hex", @"name", @"category", @"original", @"effective", @"would_change_if_true", @"override_key", @"override", @"hits", @"detail"];
    NSMutableArray *lines = [NSMutableArray arrayWithObject:[keys componentsJoinedByString:@","]];
    for (NSDictionary *row in [self exportRows]) { NSMutableArray *cols = [NSMutableArray array]; for (NSString *k in keys) [cols addObject:[self csvEscape:row[k] ?: @""]]; [lines addObject:[cols componentsJoinedByString:@","]]; }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)showBulkMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Focused MC bulk" message:[NSString stringWithFormat:@"%@\n%lu visible rows", [self activeTargetKey], (unsigned long)self.rows.count] preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy JSON dump" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { UIPasteboard.generalPasteboard.string = [self exportJSON]; [SCIUtils showSuccessHUDWithDescription:@"JSON copied"]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy CSV dump" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { UIPasteboard.generalPasteboard.string = [self exportCSV]; [SCIUtils showSuccessHUDWithDescription:@"CSV copied"]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force ON visible would-change" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self bulkForceWouldChange]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear overrides in visible rows" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [self bulkClearVisible]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy id_name_mapping status" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { UIPasteboard.generalPasteboard.string = [SCIMobileConfigMapping mappingStatusLine] ?: @""; [SCIUtils showSuccessHUDWithDescription:@"Mapping status copied"]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)bulkForceWouldChange {
    NSUInteger n = 0;
    for (SCIMCFocusedLabRow *r in self.rows) {
        if (!r.wouldChange || !r.overrideKey.length) continue;
        [SCIExpFlags setOverride:SCIExpFlagOverrideTrue forName:r.overrideKey];
        n++;
    }
    [self refresh];
    [SCIUtils showSuccessHUDWithDescription:[NSString stringWithFormat:@"Forced %lu row(s)", (unsigned long)n]];
}

- (void)bulkClearVisible {
    NSUInteger n = 0;
    for (SCIMCFocusedLabRow *r in self.rows) {
        if (!r.overrideKey.length) continue;
        [SCIExpFlags setOverride:SCIExpFlagOverrideOff forName:r.overrideKey];
        n++;
    }
    [self refresh];
    [SCIUtils showSuccessHUDWithDescription:[NSString stringWithFormat:@"Cleared %lu row(s)", (unsigned long)n]];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.targets.count : self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"Gate / getter target" : @"Observed bools for selected target"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Selecione UM getter/gate por vez. Depois abra a tela relevante no Instagram e volte aqui para ver só os bools que passaram por esse caminho.";
    return @"O switch mostra o valor efetivo. Tocar no switch cria override só para aquele param/nome. Use Bulk para exportar ou forçar linhas visíveis.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mc-focused"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mc-focused"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (indexPath.section == 0) {
        NSDictionary *t = self.targets[(NSUInteger)indexPath.row];
        BOOL active = [t[@"key"] isEqualToString:[self activeTargetKey]];
        cell.textLabel.text = t[@"title"] ?: @"";
        cell.detailTextLabel.text = t[@"subtitle"] ?: @"";
        cell.accessoryType = active ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return cell;
    }

    SCIMCFocusedLabRow *r = self.rows[(NSUInteger)indexPath.row];
    SCIExpFlagOverride ov = [SCIExpFlags overrideForName:r.overrideKey];
    NSString *ovText = ov == SCIExpFlagOverrideTrue ? @"FORCED ON" : (ov == SCIExpFlagOverrideFalse ? @"FORCED OFF" : @"default");
    cell.textLabel.text = [NSString stringWithFormat:@"[%@] %@ %@%@", r.category ?: @"", r.name ?: @"", r.paramHex ?: @"", r.wouldChange ? @" WOULD_TRUE" : @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · original=%@ · effective=%@ · override=%@ · ×%lu", r.gate ?: @"", r.original ?: @"?", [self effectiveValueForRow:r] ? @"YES" : @"NO", ovText, (unsigned long)r.hits];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    UISwitch *sw = [UISwitch new];
    sw.on = [self effectiveValueForRow:r];
    objc_setAssociatedObject(sw, kSCIMCFocusSwitchKey, r.overrideKey ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, kSCIMCFocusSwitchKey);
    if (!key.length) return;
    [SCIExpFlags setOverride:(sender.on ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forName:key];
    [self refresh];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        NSDictionary *target = self.targets[(NSUInteger)indexPath.row];
        [self setActiveTargetKey:target[@"key"] ?: @"c|all"];
        [self refresh];
        [SCIUtils showSuccessHUDWithDescription:@"Focused target selected"];
        return;
    }

    SCIMCFocusedLabRow *r = self.rows[(NSUInteger)indexPath.row];
    NSString *msg = [NSString stringWithFormat:@"gate=%@\nparam=%@\nname=%@\ncategory=%@\noriginal=%@\neffective=%@\noverrideKey=%@\nhits=%lu\n\n%@", r.gate ?: @"", r.paramHex ?: @"", r.name ?: @"", r.category ?: @"", r.original ?: @"", [self effectiveValueForRow:r] ? @"YES" : @"NO", r.overrideKey ?: @"", (unsigned long)r.hits, r.detail ?: @""];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:r.name ?: @"MC param" message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy row" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { UIPasteboard.generalPasteboard.string = msg; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"No override" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [SCIExpFlags setOverride:SCIExpFlagOverrideOff forName:r.overrideKey]; [self refresh]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [SCIExpFlags setOverride:SCIExpFlagOverrideTrue forName:r.overrideKey]; [self refresh]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [SCIExpFlags setOverride:SCIExpFlagOverrideFalse forName:r.overrideKey]; [self refresh]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { self.query = searchText ?: @""; [self refresh]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }

@end
