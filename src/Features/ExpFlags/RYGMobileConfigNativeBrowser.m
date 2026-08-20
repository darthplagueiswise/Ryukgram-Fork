#import "RYGMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <math.h>

static NSString *const kRYGMobileConfigNamesDidChangeNotification = @"RYGMobileConfigNamesDidChange";
static const void *kRYGMCParamKey = &kRYGMCParamKey;
static NSString *const kRYGMCCanonicalSeparator = @": : ";

typedef NS_ENUM(NSInteger, RYGMCBrowserScope) {
    RYGMCBrowserScopeAll = 0,
    RYGMCBrowserScopeSeen,
    RYGMCBrowserScopeNotSeen,
    RYGMCBrowserScopeOverridden,
};

typedef NS_ENUM(NSInteger, RYGMCDocumentType) {
    RYGMCDocumentTypeUnknown = 0,
    RYGMCDocumentTypeBool,
    RYGMCDocumentTypeInt,
    RYGMCDocumentTypeDouble,
    RYGMCDocumentTypeString,
};

#pragma mark - Search

static NSString *RYGMCNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    BOOL previousSpace = YES;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        BOOL alnum = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        if (alnum) {
            [result appendFormat:@"%C", c];
            previousSpace = NO;
        } else if (!previousSpace) {
            [result appendString:@" "];
            previousSpace = YES;
        }
    }
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSArray<NSString *> *RYGMCTokens(NSString *query) {
    NSString *normalized = RYGMCNormalize(query);
    if (!normalized.length) return @[];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *part in [normalized componentsSeparatedByString:@" "]) {
        if (part.length) [tokens addObject:part];
    }
    return tokens.copy;
}

static BOOL RYGMCMatches(NSString *text, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *normalized = RYGMCNormalize(text);
    NSString *compact = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in tokens) {
        NSString *compactToken = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([normalized rangeOfString:token].location == NSNotFound &&
            [compact rangeOfString:compactToken].location == NSNotFound) return NO;
    }
    return YES;
}

#pragma mark - Resolved model

static RYGMCParam *RYGMCCloneParam(RYGMCParam *source) {
    RYGMCParam *param = [RYGMCParam new];
    param.paramID = source.paramID;
    param.ordinal = source.ordinal;
    param.configNumber = source.configNumber;
    param.paramIndex = source.paramIndex;
    param.type = source.type;
    param.runtimeBacked = source.isRuntimeBacked;
    param.name = source.name ?: @"";
    return param;
}

static NSArray<RYGMCConfig *> *RYGMCResolvedConfigs(void) {
    RYGMobileConfig *engine = RYGMobileConfig.shared;
    [engine prepare];
    NSMutableDictionary<NSNumber *, RYGMCConfig *> *live = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in engine.allConfigs ?: @[]) live[@(config.number)] = config;

    NSDictionary<NSNumber *, NSDictionary *> *mapping = RYGMCLoadCachedNameMappingCatalog(NULL) ?: @{};
    NSMutableSet<NSNumber *> *numbers = [NSMutableSet setWithArray:live.allKeys];
    [numbers addObjectsFromArray:mapping.allKeys];
    NSArray<NSNumber *> *orderedNumbers = [numbers.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<RYGMCConfig *> *resolved = [NSMutableArray arrayWithCapacity:orderedNumbers.count];

    for (NSNumber *number in orderedNumbers) {
        RYGMCConfig *liveConfig = live[number];
        NSDictionary *info = [mapping[number] isKindOfClass:NSDictionary.class] ? mapping[number] : @{};
        NSDictionary<NSNumber *, NSString *> *mappedParams = [info[@"params"] isKindOfClass:NSDictionary.class] ? info[@"params"] : @{};
        NSString *mappedName = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : @"";
        RYGMCConfig *config = [RYGMCConfig new];
        config.number = number.unsignedIntValue;
        config.name = mappedName.length ? mappedName : (liveConfig.name ?: @"");

        NSMutableDictionary<NSNumber *, RYGMCParam *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *liveParam in liveConfig.params ?: @[]) params[@(liveParam.paramIndex)] = RYGMCCloneParam(liveParam);
        [mappedParams enumerateKeysAndObjectsUsingBlock:^(NSNumber *index, NSString *name, BOOL *stop) {
            (void)stop;
            RYGMCParam *param = params[index];
            if (!param) {
                param = [RYGMCParam new];
                param.configNumber = number.unsignedIntValue;
                param.paramIndex = index.unsignedIntValue;
                param.type = RYGMCTypeUnknown;
                param.runtimeBacked = NO;
                params[index] = param;
            }
            if ([name isKindOfClass:NSString.class] && name.length) param.name = name;
        }];

        NSMutableArray *orderedParams = [NSMutableArray array];
        for (NSNumber *index in [params.allKeys sortedArrayUsingSelector:@selector(compare:)]) [orderedParams addObject:params[index]];
        config.params = orderedParams.copy;
        [resolved addObject:config];
    }
    return resolved.copy;
}

#pragma mark - Canonical mc_overrides document

static BOOL RYGMCParseCanonicalLine(NSString *line, unsigned int *paramIndex, NSString **valueText) {
    if (![line isKindOfClass:NSString.class]) return NO;
    NSRange separator = [line rangeOfString:kRYGMCCanonicalSeparator];
    if (separator.location == NSNotFound) return NO;
    NSString *indexText = [[line substringToIndex:separator.location]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const char *raw = indexText.UTF8String;
    if (!raw || !*raw || *raw == '-') return NO;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 10);
    if (end == raw || *end != '\0' || value > UINT32_MAX) return NO;
    if (paramIndex) *paramIndex = (unsigned int)value;
    if (valueText) *valueText = [line substringFromIndex:NSMaxRange(separator)];
    return YES;
}

static NSMutableDictionary<NSString *, id> *RYGMCCurrentDocument(NSError **error) {
    NSData *data = [RYGMobileConfig.shared ryg_exportOverridesData:error];
    if (!data.length) return [NSMutableDictionary dictionary];
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    return [root isKindOfClass:NSMutableDictionary.class] ? root :
           ([root isKindOfClass:NSDictionary.class] ? [(NSDictionary *)root mutableCopy] : [NSMutableDictionary dictionary]);
}

static NSString *RYGMCConfigDocumentKey(unsigned int configNumber) {
    return [NSString stringWithFormat:@"%u:", configNumber];
}

static NSString *RYGMCDocumentValueText(RYGMCParam *param) {
    if (!param) return nil;
    NSDictionary *root = RYGMCCurrentDocument(NULL);
    NSArray *lines = [root[RYGMCConfigDocumentKey(param.configNumber)] isKindOfClass:NSArray.class]
        ? root[RYGMCConfigDocumentKey(param.configNumber)] : @[];
    for (id raw in lines) {
        unsigned int index = 0;
        NSString *value = nil;
        if (RYGMCParseCanonicalLine(raw, &index, &value) && index == param.paramIndex) return value;
    }
    return nil;
}

static NSComparisonResult RYGMCCompareCanonicalLines(NSString *left, NSString *right) {
    unsigned int li = UINT32_MAX, ri = UINT32_MAX;
    RYGMCParseCanonicalLine(left, &li, NULL);
    RYGMCParseCanonicalLine(right, &ri, NULL);
    if (li < ri) return NSOrderedAscending;
    if (li > ri) return NSOrderedDescending;
    return [left compare:right];
}

static BOOL RYGMCWriteDocumentValueText(RYGMCParam *param, NSString *valueText, NSError **error) {
    if (!param) return NO;
    NSMutableDictionary<NSString *, id> *root = RYGMCCurrentDocument(error);
    if (!root) return NO;
    NSString *key = RYGMCConfigDocumentKey(param.configNumber);
    NSArray *existing = [root[key] isKindOfClass:NSArray.class] ? root[key] : @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (id raw in existing) {
        if (![raw isKindOfClass:NSString.class]) continue;
        unsigned int index = 0;
        if (RYGMCParseCanonicalLine(raw, &index, NULL) && index == param.paramIndex) continue;
        [lines addObject:raw];
    }
    if (valueText) {
        [lines addObject:[NSString stringWithFormat:@"%u%@%@", param.paramIndex, kRYGMCCanonicalSeparator, valueText]];
    }
    [lines sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        return RYGMCCompareCanonicalLines(left, right);
    }];
    if (lines.count) root[key] = lines.copy;
    else [root removeObjectForKey:key];

    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
    if (!data) return NO;
    NSUInteger applied = 0;
    return [RYGMobileConfig.shared ryg_importAndApplyOverridesData:data appliedCount:&applied error:error];
}

static RYGMCDocumentType RYGMCTypeFromNative(RYGMCParam *param) {
    if (!param.isRuntimeBacked) return RYGMCDocumentTypeUnknown;
    switch (param.type) {
        case RYGMCTypeBool: return RYGMCDocumentTypeBool;
        case RYGMCTypeInt: return RYGMCDocumentTypeInt;
        case RYGMCTypeDouble: return RYGMCDocumentTypeDouble;
        case RYGMCTypeString: return RYGMCDocumentTypeString;
        default: return RYGMCDocumentTypeUnknown;
    }
}

static RYGMCDocumentType RYGMCInferTypeFromText(NSString *text) {
    if (!text) return RYGMCDocumentTypeUnknown;
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *lower = trim.lowercaseString;
    if ([lower isEqualToString:@"true"] || [lower isEqualToString:@"false"]) return RYGMCDocumentTypeBool;
    const char *raw = trim.UTF8String;
    if (!raw || !*raw) return RYGMCDocumentTypeString;
    char *intEnd = NULL;
    (void)strtoll(raw, &intEnd, 10);
    if (intEnd != raw && *intEnd == '\0') return RYGMCDocumentTypeInt;
    char *doubleEnd = NULL;
    double number = strtod(raw, &doubleEnd);
    if (doubleEnd != raw && *doubleEnd == '\0' && isfinite(number)) return RYGMCDocumentTypeDouble;
    return RYGMCDocumentTypeString;
}

static BOOL RYGMCNameLooksBoolean(NSString *name) {
    NSString *normalized = RYGMCNormalize(name);
    if (!normalized.length) return NO;
    NSArray<NSString *> *prefixes = @[
        @"is ", @"has ", @"can ", @"should ", @"use ", @"show ", @"hide ",
        @"enable ", @"enabled ", @"disable ", @"allow ", @"supports "
    ];
    for (NSString *prefix in prefixes) if ([normalized hasPrefix:prefix]) return YES;
    return [normalized hasSuffix:@" enabled"] || [normalized hasSuffix:@" disabled"];
}

static RYGMCDocumentType RYGMCDisplayType(RYGMCParam *param, NSString *documentText) {
    RYGMCDocumentType native = RYGMCTypeFromNative(param);
    if (native != RYGMCDocumentTypeUnknown) return native;
    RYGMCDocumentType existing = RYGMCInferTypeFromText(documentText);
    if (existing != RYGMCDocumentTypeUnknown) return existing;
    return RYGMCNameLooksBoolean(param.name) ? RYGMCDocumentTypeBool : RYGMCDocumentTypeUnknown;
}

static NSString *RYGMCTextForValue(id value, RYGMCDocumentType type) {
    if (type == RYGMCDocumentTypeBool) return [value boolValue] ? @"true" : @"false";
    if (type == RYGMCDocumentTypeInt) return [NSString stringWithFormat:@"%lld", [value longLongValue]];
    if (type == RYGMCDocumentTypeDouble) return [NSString stringWithFormat:@"%.17g", [value doubleValue]];
    return [value isKindOfClass:NSString.class] ? value : [value description];
}

static BOOL RYGMCConfigSeen(RYGMCConfig *config) {
    for (RYGMCParam *param in config.params) {
        if (param.isRuntimeBacked && [RYGMobileConfig.shared callSiteFor:param].length) return YES;
    }
    return NO;
}

static BOOL RYGMCParamHasDocumentOverride(RYGMCParam *param) {
    return RYGMCDocumentValueText(param) != nil;
}

static BOOL RYGMCConfigOverridden(RYGMCConfig *config) {
    for (RYGMCParam *param in config.params) if (RYGMCParamHasDocumentOverride(param)) return YES;
    return NO;
}

#pragma mark - Controllers

@interface RYGMCResolvedConfigDetailViewController : UITableViewController
@property (nonatomic, strong) RYGMCConfig *config;
@end

@interface RYGMobileConfigBrowserViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGMCConfig *> *allConfigs;
@property (nonatomic, copy) NSArray<RYGMCConfig *> *visibleConfigs;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSArray<RYGMCParam *> *> *searchMatches;
@property (nonatomic, assign) RYGMCBrowserScope scope;
@end

@implementation RYGMobileConfigBrowserViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig";
    self.scope = RYGMCBrowserScopeAll;
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Config, parameter or ID";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                 menu:[self scopeMenu]];

    self.tableView.refreshControl = [UIRefreshControl new];
    [self.tableView.refreshControl addTarget:self action:@selector(refreshRuntime) forControlEvents:UIControlEventValueChanged];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(namesDidChange:)
                                               name:kRYGMobileConfigNamesDidChangeNotification
                                             object:nil];
    RYGLiquidGlassApplyToViewController(self);
    [self reloadModel:NO];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadModel:NO]; }
- (void)namesDidChange:(NSNotification *)notification { (void)notification; [self reloadModel:NO]; }
- (void)refreshRuntime { [RYGMobileConfig.shared reloadFromRuntime]; [self reloadModel:NO]; [self.tableView.refreshControl endRefreshing]; }

- (UIMenu *)scopeMenu {
    NSArray *titles = @[@"All", @"Seen at runtime", @"Not seen", @"Overridden"];
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSInteger index = 0; index < (NSInteger)titles.count; index++) {
        UIAction *action = [UIAction actionWithTitle:titles[(NSUInteger)index] image:nil identifier:nil handler:^(__unused UIAction *item) {
            weakSelf.scope = (RYGMCBrowserScope)index;
            weakSelf.navigationItem.rightBarButtonItem.menu = [weakSelf scopeMenu];
            [weakSelf rebuildVisibleConfigs];
        }];
        action.state = self.scope == index ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:@"Filter" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
}

- (void)reloadModel:(BOOL)forceRuntimeReload {
    if (forceRuntimeReload) [RYGMobileConfig.shared reloadFromRuntime];
    self.allConfigs = RYGMCResolvedConfigs();
    [self rebuildVisibleConfigs];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self rebuildVisibleConfigs];
}

- (BOOL)configPassesScope:(RYGMCConfig *)config {
    if (self.scope == RYGMCBrowserScopeSeen) return RYGMCConfigSeen(config);
    if (self.scope == RYGMCBrowserScopeNotSeen) return !RYGMCConfigSeen(config);
    if (self.scope == RYGMCBrowserScopeOverridden) return RYGMCConfigOverridden(config);
    return YES;
}

- (void)rebuildVisibleConfigs {
    NSArray *tokens = RYGMCTokens(self.searchController.searchBar.text ?: @"");
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableDictionary *matches = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in self.allConfigs ?: @[]) {
        if (![self configPassesScope:config]) continue;
        NSString *configText = [NSString stringWithFormat:@"%@ %u", config.name ?: @"", config.number];
        BOOL configMatch = RYGMCMatches(configText, tokens);
        NSMutableArray *paramMatches = [NSMutableArray array];
        for (RYGMCParam *param in config.params) {
            // Include config AND param text in the same haystack. This makes a
            // query such as "ig dev enable ui" match
            // ig_dev_options_redesign -> enable_ui_redesign instead of requiring
            // all words to live exclusively in either the config or param name.
            NSString *text = [NSString stringWithFormat:@"%@ %u %@ %u %llu",
                              config.name ?: @"", config.number,
                              param.name ?: @"", param.paramIndex, param.paramID];
            if (!tokens.count || RYGMCMatches(text, tokens)) [paramMatches addObject:param];
        }
        if (!tokens.count || configMatch || paramMatches.count) {
            [visible addObject:config];
            if (tokens.count && paramMatches.count) matches[@(config.number)] = paramMatches.copy;
        }
    }
    self.visibleConfigs = visible.copy;
    self.searchMatches = matches.copy;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.visibleConfigs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGMCConfig"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGMCConfig"];
    RYGMCConfig *config = self.visibleConfigs[(NSUInteger)indexPath.row];
    cell.textLabel.text = config.name.length ? config.name : [NSString stringWithFormat:@"Config %u", config.number];
    cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSArray<RYGMCParam *> *matched = self.searchMatches[@(config.number)];
    if (matched.count) {
        NSMutableArray *names = [NSMutableArray array];
        for (RYGMCParam *param in matched) [names addObject:param.name.length ? param.name : [NSString stringWithFormat:@"#%u", param.paramIndex]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · %@", config.number, [names componentsJoinedByString:@", "]];
        cell.detailTextLabel.numberOfLines = 2;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u", config.number];
        cell.detailTextLabel.numberOfLines = 1;
    }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = RYGMCConfigOverridden(config) ? [UIImage systemImageNamed:@"circle.fill"] : nil;
    cell.imageView.tintColor = [RYGUtils RYGColor_Primary];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGMCResolvedConfigDetailViewController *detail = [[RYGMCResolvedConfigDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    detail.config = self.visibleConfigs[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:detail animated:YES];
}

@end

@implementation RYGMCResolvedConfigDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *title = self.config.name.length ? self.config.name : [NSString stringWithFormat:@"Config %u", self.config.number];
    self.title = title;
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(title);
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;
    RYGLiquidGlassApplyToViewController(self);
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.config.params.count; }

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"Every row edits the canonical mc_overrides.json by config + parameter index. Rows with a validated native PID are also applied immediately through FBMobileConfigStartupConfigs.";
}

- (BOOL)writeBoolean:(BOOL)value param:(RYGMCParam *)param {
    if (param.isRuntimeBacked && param.type == RYGMCTypeBool) {
        return [RYGMobileConfig.shared setOverride:@(value) for:param];
    }
    NSError *error = nil;
    BOOL ok = RYGMCWriteDocumentValueText(param, value ? @"true" : @"false", &error);
    if (!ok) [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not save mc_overrides.json"];
    return ok;
}

- (void)boolSwitchChanged:(UISwitch *)toggle {
    RYGMCParam *param = objc_getAssociatedObject(toggle, kRYGMCParamKey);
    if (!param) return;
    if (![self writeBoolean:toggle.isOn param:param]) toggle.on = !toggle.isOn;
    [self.tableView reloadData];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGMCParam"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGMCParam"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    RYGMCParam *param = self.config.params[(NSUInteger)indexPath.row];
    NSString *documentText = RYGMCDocumentValueText(param);
    RYGMCDocumentType type = RYGMCDisplayType(param, documentText);
    cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"Parameter %u", param.paramIndex];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    if (documentText) cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · override %@", param.paramIndex, documentText];
    else cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u", param.paramIndex];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.numberOfLines = 1;

    if (type == RYGMCDocumentTypeBool) {
        UISwitch *toggle = [UISwitch new];
        BOOL visible = NO;
        if (documentText) visible = [documentText.lowercaseString isEqualToString:@"true"];
        else if (param.isRuntimeBacked) {
            id forced = [RYGMobileConfig.shared overrideValueFor:param];
            id native = [RYGMobileConfig.shared liveValueFor:param];
            visible = forced ? [forced boolValue] : ([native isKindOfClass:NSNumber.class] ? [native boolValue] : NO);
        }
        toggle.on = visible;
        toggle.onTintColor = [RYGUtils RYGColor_Primary];
        objc_setAssociatedObject(toggle, kRYGMCParamKey, param, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (BOOL)writeText:(NSString *)text type:(RYGMCDocumentType)type param:(RYGMCParam *)param {
    id value = nil;
    NSString *canonical = nil;
    if (type == RYGMCDocumentTypeString) {
        value = text ?: @"";
        canonical = text ?: @"";
    } else if (type == RYGMCDocumentTypeInt) {
        const char *raw = text.UTF8String;
        char *end = NULL;
        long long number = raw ? strtoll(raw, &end, 10) : 0;
        if (!raw || end == raw || *end != '\0') return NO;
        value = @(number);
        canonical = RYGMCTextForValue(value, type);
    } else if (type == RYGMCDocumentTypeDouble) {
        const char *raw = text.UTF8String;
        char *end = NULL;
        double number = raw ? strtod(raw, &end) : 0;
        if (!raw || end == raw || *end != '\0' || !isfinite(number)) return NO;
        value = @(number);
        canonical = RYGMCTextForValue(value, type);
    }

    if (param.isRuntimeBacked) {
        RYGMCDocumentType nativeType = RYGMCTypeFromNative(param);
        if (nativeType != type || !value) return NO;
        return [RYGMobileConfig.shared setOverride:value for:param];
    }
    NSError *error = nil;
    BOOL ok = canonical && RYGMCWriteDocumentValueText(param, canonical, &error);
    if (!ok && error) [RYGUtils showErrorHUDWithDescription:error.localizedDescription];
    return ok;
}

- (void)presentValueEditorForParam:(RYGMCParam *)param type:(RYGMCDocumentType)type {
    NSString *documentText = RYGMCDocumentValueText(param);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:param.name.length ? param.name : @"MobileConfig value"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = documentText ?: @"";
        if (type == RYGMCDocumentTypeInt || type == RYGMCDocumentTypeDouble) field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (documentText) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Use native / remove" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            if (param.isRuntimeBacked) [RYGMobileConfig.shared clearOverrideFor:param];
            else {
                NSError *error = nil;
                if (!RYGMCWriteDocumentValueText(param, nil, &error)) [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not remove override"];
            }
            [weakSelf.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        if (![weakSelf writeText:text type:type param:param]) [RYGUtils showErrorHUDWithDescription:@"Invalid value for the selected MobileConfig type"];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentTypePickerForParam:(RYGMCParam *)param source:(UIView *)source {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:param.name.length ? param.name : @"Set override"
                                                                    message:@"No native type exists for this mapped row. Choose the mc_overrides.json value type; no PID or runtime ABI will be fabricated."
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Boolean: On" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf writeBoolean:YES param:param]; [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Boolean: Off" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf writeBoolean:NO param:param]; [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Integer" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf presentValueEditorForParam:param type:RYGMCDocumentTypeInt];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Double" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf presentValueEditorForParam:param type:RYGMCDocumentTypeDouble];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"String" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [weakSelf presentValueEditorForParam:param type:RYGMCDocumentTypeString];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = source ?: self.view;
        sheet.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGMCParam *param = self.config.params[(NSUInteger)indexPath.row];
    NSString *documentText = RYGMCDocumentValueText(param);
    RYGMCDocumentType type = RYGMCDisplayType(param, documentText);
    if (type == RYGMCDocumentTypeBool) return;
    if (type == RYGMCDocumentTypeUnknown) {
        [self presentTypePickerForParam:param source:cell];
        return;
    }
    [self presentValueEditorForParam:param type:type];
}

@end
