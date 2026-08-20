#import "RYGMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigNameMappingStore.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <math.h>

static NSString *const kRYGMobileConfigNamesDidChangeNotification = @"RYGMobileConfigNamesDidChange";
static const void *kRYGMCParamSwitchKey = &kRYGMCParamSwitchKey;

typedef NS_ENUM(NSInteger, RYGMCBrowserScope) { RYGMCBrowserScopeAll = 0, RYGMCBrowserScopeSeen, RYGMCBrowserScopeNotSeen, RYGMCBrowserScopeOverridden };

static NSString *RYGMCNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length]; BOOL previousSpace = YES;
    NSString *lower = value.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) { unichar c = [lower characterAtIndex:i]; if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) { [result appendFormat:@"%C", c]; previousSpace = NO; } else if (!previousSpace) { [result appendString:@" "]; previousSpace = YES; } }
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}
static NSArray<NSString *> *RYGMCTokens(NSString *query) { NSString *normalized = RYGMCNormalize(query); if (!normalized.length) return @[]; NSMutableArray *tokens = [NSMutableArray array]; for (NSString *part in [normalized componentsSeparatedByString:@" "]) if (part.length) [tokens addObject:part]; return tokens.copy; }
static BOOL RYGMCMatches(NSString *text, NSArray<NSString *> *tokens) { if (!tokens.count) return YES; NSString *normalized = RYGMCNormalize(text); NSString *compact = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""]; for (NSString *token in tokens) if ([normalized rangeOfString:token].location == NSNotFound && [compact rangeOfString:token].location == NSNotFound) return NO; return YES; }

static RYGMCParam *RYGMCCloneParam(RYGMCParam *source) {
    RYGMCParam *param = [RYGMCParam new]; param.paramID = source.paramID; param.ordinal = source.ordinal; param.configNumber = source.configNumber; param.paramIndex = source.paramIndex; param.type = source.type; param.runtimeBacked = source.isRuntimeBacked; param.name = source.name ?: @""; return param;
}

static NSArray<RYGMCConfig *> *RYGMCResolvedConfigs(void) {
    RYGMobileConfig *engine = RYGMobileConfig.shared; [engine prepare];
    NSMutableDictionary<NSNumber *, RYGMCConfig *> *liveByNumber = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in engine.allConfigs ?: @[]) liveByNumber[@(config.number)] = config;
    NSError *mappingError = nil; NSDictionary<NSNumber *, NSDictionary *> *mapping = RYGMCLoadCachedNameMappingCatalog(&mappingError) ?: @{};
    NSMutableSet<NSNumber *> *numbers = [NSMutableSet setWithArray:liveByNumber.allKeys]; [numbers addObjectsFromArray:mapping.allKeys];
    NSArray<NSNumber *> *ordered = [numbers.allObjects sortedArrayUsingSelector:@selector(compare:)]; NSMutableArray<RYGMCConfig *> *resolved = [NSMutableArray arrayWithCapacity:ordered.count];
    for (NSNumber *number in ordered) {
        RYGMCConfig *live = liveByNumber[number]; NSDictionary *nameInfo = [mapping[number] isKindOfClass:NSDictionary.class] ? mapping[number] : @{};
        NSString *mappedName = [nameInfo[@"name"] isKindOfClass:NSString.class] ? nameInfo[@"name"] : @"";
        NSDictionary<NSNumber *, NSString *> *mappedParams = [nameInfo[@"params"] isKindOfClass:NSDictionary.class] ? nameInfo[@"params"] : @{};
        RYGMCConfig *config = [RYGMCConfig new]; config.number = number.unsignedIntValue; config.name = mappedName.length ? mappedName : (live.name ?: @"");
        NSMutableDictionary<NSNumber *, RYGMCParam *> *params = [NSMutableDictionary dictionary]; for (RYGMCParam *liveParam in live.params ?: @[]) params[@(liveParam.paramIndex)] = RYGMCCloneParam(liveParam);
        [mappedParams enumerateKeysAndObjectsUsingBlock:^(NSNumber *paramIndex, NSString *paramName, BOOL *stop) { (void)stop; RYGMCParam *param = params[paramIndex]; if (!param) { param = [RYGMCParam new]; param.configNumber = number.unsignedIntValue; param.paramIndex = paramIndex.unsignedIntValue; param.type = RYGMCTypeUnknown; param.runtimeBacked = NO; params[paramIndex] = param; } if ([paramName isKindOfClass:NSString.class] && paramName.length) param.name = paramName; }];
        NSArray<NSNumber *> *indexes = [params.allKeys sortedArrayUsingSelector:@selector(compare:)]; NSMutableArray<RYGMCParam *> *orderedParams = [NSMutableArray arrayWithCapacity:indexes.count]; for (NSNumber *index in indexes) [orderedParams addObject:params[index]]; config.params = orderedParams.copy; [resolved addObject:config];
    }
    return resolved.copy;
}

static BOOL RYGMCConfigSeen(RYGMCConfig *config) { for (RYGMCParam *param in config.params) if (param.isRuntimeBacked && [RYGMobileConfig.shared callSiteFor:param].length) return YES; return NO; }
static BOOL RYGMCConfigOverridden(RYGMCConfig *config) { for (RYGMCParam *param in config.params) if (param.isRuntimeBacked && [RYGMobileConfig.shared overrideStateFor:param] == RYGMCOverrideSet) return YES; return NO; }

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
    [super viewDidLoad]; self.title = @"MobileConfig"; self.scope = RYGMCBrowserScopeAll; self.view.backgroundColor = [RYGPopupChrome backgroundColor]; self.tableView.backgroundColor = [RYGPopupChrome backgroundColor]; self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 58.0;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil]; self.searchController.searchResultsUpdater = self; self.searchController.obscuresBackgroundDuringPresentation = NO; self.searchController.searchBar.placeholder = @"Config, ID or parameter"; self.navigationItem.searchController = self.searchController; self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self scopeMenu]];
    self.tableView.refreshControl = [UIRefreshControl new]; [self.tableView.refreshControl addTarget:self action:@selector(refreshRuntime) forControlEvents:UIControlEventValueChanged];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(namesDidChange:) name:kRYGMobileConfigNamesDidChangeNotification object:nil]; [self reloadModel:NO]; RYGLiquidGlassApplyToViewController(self);
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)namesDidChange:(NSNotification *)notification { (void)notification; [self reloadModel:NO]; }
- (void)refreshRuntime { [RYGMobileConfig.shared reloadFromRuntime]; [self reloadModel:NO]; [self.tableView.refreshControl endRefreshing]; }

- (UIMenu *)scopeMenu {
    NSArray<NSString *> *titles = @[@"All", @"Seen at runtime", @"Not seen", @"Overridden"]; NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array]; __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) { UIAction *action = [UIAction actionWithTitle:titles[(NSUInteger)i] image:nil identifier:nil handler:^(__unused UIAction *a) { weakSelf.scope = (RYGMCBrowserScope)i; weakSelf.navigationItem.rightBarButtonItem.menu = [weakSelf scopeMenu]; [weakSelf rebuildVisibleConfigs]; }]; action.state = self.scope == i ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action]; }
    return [UIMenu menuWithTitle:@"Filter" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
}
- (void)reloadModel:(BOOL)forceRuntimeReload { if (forceRuntimeReload) [RYGMobileConfig.shared reloadFromRuntime]; self.allConfigs = RYGMCResolvedConfigs(); [self rebuildVisibleConfigs]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self rebuildVisibleConfigs]; }
- (BOOL)configPassesScope:(RYGMCConfig *)config { if (self.scope == RYGMCBrowserScopeSeen) return RYGMCConfigSeen(config); if (self.scope == RYGMCBrowserScopeNotSeen) return !RYGMCConfigSeen(config); if (self.scope == RYGMCBrowserScopeOverridden) return RYGMCConfigOverridden(config); return YES; }

- (void)rebuildVisibleConfigs {
    NSArray<NSString *> *tokens = RYGMCTokens(self.searchController.searchBar.text ?: @""); NSMutableArray<RYGMCConfig *> *visible = [NSMutableArray array]; NSMutableDictionary<NSNumber *, NSArray<RYGMCParam *> *> *matches = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in self.allConfigs ?: @[]) { if (![self configPassesScope:config]) continue; NSString *configText = [NSString stringWithFormat:@"%@ %u", config.name ?: @"", config.number]; BOOL configMatch = RYGMCMatches(configText, tokens); NSMutableArray<RYGMCParam *> *paramMatches = [NSMutableArray array]; for (RYGMCParam *param in config.params) { NSString *paramText = [NSString stringWithFormat:@"%@ %u %llu", param.name ?: @"", param.paramIndex, param.paramID]; if (tokens.count && RYGMCMatches(paramText, tokens)) [paramMatches addObject:param]; } if (!tokens.count || configMatch || paramMatches.count) { [visible addObject:config]; if (paramMatches.count) matches[@(config.number)] = paramMatches.copy; } }
    self.visibleConfigs = visible.copy; self.searchMatches = matches.copy; [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.visibleConfigs.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGMCConfig"]; if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGMCConfig"];
    RYGMCConfig *config = self.visibleConfigs[(NSUInteger)indexPath.row]; cell.textLabel.text = config.name.length ? config.name : [NSString stringWithFormat:@"Config %u", config.number]; cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold]; cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSArray<RYGMCParam *> *matched = self.searchMatches[@(config.number)]; if (matched.count) { NSMutableArray<NSString *> *names = [NSMutableArray array]; for (RYGMCParam *param in matched) [names addObject:param.name.length ? param.name : [NSString stringWithFormat:@"#%u", param.paramIndex]]; cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · %@", config.number, [names componentsJoinedByString:@", "]]; cell.detailTextLabel.numberOfLines = 2; } else { cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u", config.number]; cell.detailTextLabel.numberOfLines = 1; }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.imageView.image = RYGMCConfigOverridden(config) ? [UIImage systemImageNamed:@"circle.fill"] : nil; cell.imageView.tintColor = [RYGUtils RYGColor_Primary]; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; RYGMCResolvedConfigDetailViewController *detail = [[RYGMCResolvedConfigDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; detail.config = self.visibleConfigs[(NSUInteger)indexPath.row]; [self.navigationController pushViewController:detail animated:YES]; }
@end

@implementation RYGMCResolvedConfigDetailViewController
- (void)viewDidLoad { [super viewDidLoad]; self.title = self.config.name.length ? self.config.name : [NSString stringWithFormat:@"Config %u", self.config.number]; self.tableView.backgroundColor = [RYGPopupChrome backgroundColor]; self.view.backgroundColor = [RYGPopupChrome backgroundColor]; self.tableView.rowHeight = UITableViewAutomaticDimension; RYGLiquidGlassApplyToViewController(self); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.config.params.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGMCParam"]; if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGMCParam"]; cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    RYGMCParam *param = self.config.params[(NSUInteger)indexPath.row]; cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"Parameter %u", param.paramIndex]; cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular]; cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    id forced = param.isRuntimeBacked ? [RYGMobileConfig.shared overrideValueFor:param] : nil; id native = param.isRuntimeBacked ? [RYGMobileConfig.shared liveValueFor:param] : nil;
    if (!param.isRuntimeBacked) cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · mapping only", param.paramIndex]; else if (forced) cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · %@ → %@", param.paramIndex, native ?: @"native", forced]; else cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · %@", param.paramIndex, native ?: @"native"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor; cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    if (!param.isRuntimeBacked) { cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell; }
    if (param.type == RYGMCTypeBool) { UISwitch *toggle = [UISwitch new]; toggle.on = forced ? [forced boolValue] : (native ? [native boolValue] : NO); objc_setAssociatedObject(toggle, kRYGMCParamSwitchKey, param, OBJC_ASSOCIATION_RETAIN_NONATOMIC); [toggle addTarget:self action:@selector(boolChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone; } else cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)boolChanged:(UISwitch *)toggle { RYGMCParam *param = objc_getAssociatedObject(toggle, kRYGMCParamSwitchKey); if (!param) return; if (![RYGMobileConfig.shared setOverride:@(toggle.isOn) for:param]) [RYGUtils showErrorHUDWithDescription:@"MobileConfig rejected this override"]; [self.tableView reloadData]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; RYGMCParam *param = self.config.params[(NSUInteger)indexPath.row]; if (!param.isRuntimeBacked || param.type == RYGMCTypeBool) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:param.name.length ? param.name : @"MobileConfig value" message:nil preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { id current = [RYGMobileConfig.shared overrideValueFor:param] ?: [RYGMobileConfig.shared liveValueFor:param]; field.text = current ? [current description] : @""; if (param.type == RYGMCTypeInt || param.type == RYGMCTypeDouble) field.keyboardType = UIKeyboardTypeNumbersAndPunctuation; }];
    __weak typeof(self) weakSelf = self; [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; if ([RYGMobileConfig.shared overrideStateFor:param] == RYGMCOverrideSet) [alert addAction:[UIAlertAction actionWithTitle:@"Use native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { [RYGMobileConfig.shared clearOverrideFor:param]; [weakSelf.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { NSString *text = alert.textFields.firstObject.text ?: @""; id value = nil; if (param.type == RYGMCTypeString) value = text; else if (param.type == RYGMCTypeInt) { char *end = NULL; long long v = strtoll(text.UTF8String, &end, 10); if (end != text.UTF8String && *end == '\0') value = @(v); } else if (param.type == RYGMCTypeDouble) { char *end = NULL; double v = strtod(text.UTF8String, &end); if (end != text.UTF8String && *end == '\0' && isfinite(v)) value = @(v); } if (!value || ![RYGMobileConfig.shared setOverride:value for:param]) [RYGUtils showErrorHUDWithDescription:@"Invalid MobileConfig value"]; [weakSelf.tableView reloadData]; }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point { (void)tableView; (void)point; RYGMCParam *param = self.config.params[(NSUInteger)indexPath.row]; if (!param.isRuntimeBacked || [RYGMobileConfig.shared overrideStateFor:param] != RYGMCOverrideSet) return nil; __weak typeof(self) weakSelf = self; return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(__unused NSArray<UIMenuElement *> *suggested) { UIAction *native = [UIAction actionWithTitle:@"Use native value" image:[UIImage systemImageNamed:@"arrow.uturn.backward"] identifier:nil handler:^(__unused UIAction *a) { [RYGMobileConfig.shared clearOverrideFor:param]; [weakSelf.tableView reloadData]; }]; return [UIMenu menuWithChildren:@[native]]; }]; }
@end
