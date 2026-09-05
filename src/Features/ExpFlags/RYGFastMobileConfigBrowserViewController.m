#import "RYGFastMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#include <math.h>
#include <stdlib.h>

static const void *kRYGFastMCParamKey = &kRYGFastMCParamKey;

typedef NS_ENUM(NSInteger, RYGFastMCScope) {
    RYGFastMCScopeAll = 0,
    RYGFastMCScopeRuntimeLinked,
    RYGFastMCScopeMappingOnly,
    RYGFastMCScopeObserved,
    RYGFastMCScopeOverridden,
};

static NSString *RYGFastMCNormalize(NSString *value) {
    NSString *lower = value.lowercaseString ?: @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    BOOL separated = YES;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        BOOL alnum = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        if (alnum) { [out appendFormat:@"%C", c]; separated = NO; }
        else if (!separated) { [out appendString:@" "]; separated = YES; }
    }
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSArray<NSString *> *RYGFastMCTokens(NSString *query) {
    NSString *normalized = RYGFastMCNormalize(query);
    if (!normalized.length) return @[];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *token in [normalized componentsSeparatedByString:@" "]) if (token.length) [tokens addObject:token];
    return tokens.copy;
}

static BOOL RYGFastMCMatches(NSString *blob, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *text = blob ?: @"";
    NSString *compact = [text stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in tokens) {
        NSString *compactToken = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([text rangeOfString:token].location == NSNotFound && [compact rangeOfString:compactToken].location == NSNotFound) return NO;
    }
    return YES;
}

static NSString *RYGFastMCValueString(id value) {
    if (!value) return @"—";
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue] ?: @"—";
    return [value description] ?: @"—";
}

static BOOL RYGFastMCConfigHasOverride(RYGMCConfig *config) {
    for (RYGMCParam *param in config.params ?: @[])
        if ([RYGMobileConfig.shared overrideStateFor:param] == RYGMCOverrideSet) return YES;
    return NO;
}

static BOOL RYGFastMCConfigObserved(RYGMCConfig *config) {
    for (RYGMCParam *param in config.params ?: @[])
        if (param.isRuntimeBacked && [RYGMobileConfig.shared callSiteFor:param].length) return YES;
    return NO;
}

@interface RYGFastMCConfigDetailViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) RYGMCConfig *config;
@property (nonatomic, copy) NSArray<RYGMCParam *> *visibleParams;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) void (^didMutate)(void);
@end

@interface RYGFastMobileConfigBrowserViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<RYGMCConfig *> *allConfigs;
@property (nonatomic, copy) NSArray<RYGMCConfig *> *visibleConfigs;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *searchBlobs;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) RYGFastMCScope scope;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) NSUInteger searchGeneration;
@property (nonatomic, assign) BOOL loading;
@end

@implementation RYGFastMobileConfigBrowserViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig Runtime";
    self.scope = RYGFastMCScopeAll;
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Config, parameter or stable ID";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                menu:[self scopeMenu]];
    self.tableView.refreshControl = [UIRefreshControl new];
    [self.tableView.refreshControl addTarget:self action:@selector(forceReload) forControlEvents:UIControlEventValueChanged];
    RYGLiquidGlassApplyToViewController(self);
    [self loadModel:NO];
}

- (UIMenu *)scopeMenu {
    NSArray<NSString *> *titles = @[@"All", @"Runtime linked", @"Mapping only", @"Observed", @"Overridden"];
    NSMutableArray<UIAction *> *actions = [NSMutableArray arrayWithCapacity:titles.count];
    __weak typeof(self) weakSelf = self;
    for (NSInteger index = 0; index < (NSInteger)titles.count; index++) {
        UIAction *action = [UIAction actionWithTitle:titles[(NSUInteger)index] image:nil identifier:nil handler:^(__unused UIAction *item) {
            weakSelf.scope = (RYGFastMCScope)index;
            weakSelf.navigationItem.rightBarButtonItem.menu = [weakSelf scopeMenu];
            [weakSelf applyFilter];
        }];
        action.state = self.scope == index ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:@"MobileConfig rows" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
}

- (void)forceReload { [self loadModel:YES]; }

- (void)loadModel:(BOOL)force {
    if (self.loading && !force) return;
    self.loading = YES;
    NSUInteger generation = ++self.loadGeneration;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.tableView.backgroundView = spinner;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RYGMobileConfig *engine = RYGMobileConfig.shared;
        if (force) [engine reloadFromRuntime];
        NSArray<RYGMCConfig *> *configs = [engine allConfigsIncludingMappingOnly] ?: @[];
        NSMutableDictionary<NSNumber *, NSString *> *blobs = [NSMutableDictionary dictionaryWithCapacity:configs.count];
        for (RYGMCConfig *config in configs) {
            NSMutableString *blob = [NSMutableString stringWithFormat:@"%@ %u ", RYGFastMCNormalize(config.name), config.number];
            for (RYGMCParam *param in config.params ?: @[])
                [blob appendFormat:@"%@ %u %llu %@ ", RYGFastMCNormalize(param.name), param.paramIndex, param.paramID, param.typeName ?: @""];
            blobs[@(config.number)] = blob.copy;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.loadGeneration) return;
            self.loading = NO;
            self.allConfigs = configs;
            self.searchBlobs = blobs.copy;
            [self.tableView.refreshControl endRefreshing];
            [self applyFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    if (self.loading) return;
    NSUInteger generation = ++self.searchGeneration;
    NSArray<NSString *> *tokens = RYGFastMCTokens(self.searchController.searchBar.text ?: @"");
    NSArray<RYGMCConfig *> *configs = self.allConfigs ?: @[];
    NSDictionary<NSNumber *, NSString *> *blobs = self.searchBlobs ?: @{};
    RYGFastMCScope scope = self.scope;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<RYGMCConfig *> *visible = [NSMutableArray array];
        for (RYGMCConfig *config in configs) {
            BOOL linked = config.hasRuntimeBacking;
            BOOL observed = linked && RYGFastMCConfigObserved(config);
            BOOL overridden = linked && RYGFastMCConfigHasOverride(config);
            if (scope == RYGFastMCScopeRuntimeLinked && !linked) continue;
            if (scope == RYGFastMCScopeMappingOnly && linked) continue;
            if (scope == RYGFastMCScopeObserved && !observed) continue;
            if (scope == RYGFastMCScopeOverridden && !overridden) continue;
            if (!RYGFastMCMatches(blobs[@(config.number)], tokens)) continue;
            [visible addObject:config];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.searchGeneration || self.loading) return;
            self.visibleConfigs = visible.copy;
            if (self.visibleConfigs.count) self.tableView.backgroundView = nil;
            else {
                UILabel *label = [UILabel new];
                label.text = @"No MobileConfig row matches this filter.";
                label.textAlignment = NSTextAlignmentCenter;
                label.textColor = UIColor.secondaryLabelColor;
                label.numberOfLines = 0;
                self.tableView.backgroundView = label;
            }
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.visibleConfigs.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; (void)section; return [NSString stringWithFormat:@"%lu configs", (unsigned long)self.visibleConfigs.count]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"Runtime-linked rows use the type encoded by FBSharedFramework. Mapping-only rows are searchable labels from id_name_mapping.json and are deliberately read-only.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGFastMCConfig"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastMCConfig"];
    RYGMCConfig *config = self.visibleConfigs[(NSUInteger)indexPath.row];
    BOOL linked = config.hasRuntimeBacking;
    BOOL observed = linked && RYGFastMCConfigObserved(config);
    BOOL overridden = linked && RYGFastMCConfigHasOverride(config);
    cell.textLabel.text = config.name.length ? config.name : [NSString stringWithFormat:@"Config %u", config.number];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · %lu params · %@%@%@",
        config.number, (unsigned long)config.params.count,
        linked ? @"runtime linked" : @"mapping only",
        observed ? @" · observed" : @"",
        overridden ? @" · overridden" : @""];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = overridden ? [UIImage systemImageNamed:@"circle.fill"] : nil;
    cell.imageView.tintColor = [RYGUtils RYGColor_Primary];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGFastMCConfigDetailViewController *detail = [[RYGFastMCConfigDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    detail.config = self.visibleConfigs[(NSUInteger)indexPath.row];
    __weak typeof(self) weakSelf = self;
    detail.didMutate = ^{ [weakSelf applyFilter]; };
    [self.navigationController pushViewController:detail animated:YES];
}

@end

@implementation RYGFastMCConfigDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.config.name.length ? self.config.name : [NSString stringWithFormat:@"Config %u", self.config.number];
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Parameter or ID";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.visibleParams = self.config.params ?: @[];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSArray<NSString *> *tokens = RYGFastMCTokens(searchController.searchBar.text ?: @"");
    if (!tokens.count) self.visibleParams = self.config.params ?: @[];
    else self.visibleParams = [self.config.params filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMCParam *param, NSDictionary *bindings) {
        (void)bindings;
        NSString *blob = RYGFastMCNormalize([NSString stringWithFormat:@"%@ %u %llu %@", param.name ?: @"", param.paramIndex, param.paramID, param.typeName ?: @""]);
        return RYGFastMCMatches(blob, tokens);
    }]];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.visibleParams.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"No type is inferred from a name or JSON value. Only runtime-backed BOOL/INT64/STRING/DOUBLE parameters are editable; mapping-only rows remain read-only until this iOS build exposes a typed parameter descriptor.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGFastMCParam"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastMCParam"];
    RYGMCParam *param = self.visibleParams[(NSUInteger)indexPath.row];
    BOOL linked = param.isRuntimeBacked && RYGMCTypeIsRuntimeValue(param.type) && param.paramID;
    BOOL observed = linked && [RYGMobileConfig.shared callSiteFor:param].length;
    BOOL overridden = linked && [RYGMobileConfig.shared overrideStateFor:param] == RYGMCOverrideSet;
    id value = overridden ? [RYGMobileConfig.shared overrideValueFor:param] : (linked ? [RYGMobileConfig.shared liveValueFor:param] : nil);

    cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"Parameter %u", param.paramIndex];
    cell.textLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (!linked) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · mapping only · read-only", param.paramIndex];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    cell.detailTextLabel.text = [NSString stringWithFormat:@"#%u · %@%@%@ · %@",
        param.paramIndex, param.typeName ?: @"typed",
        observed ? @" · observed" : @"",
        overridden ? @" · overridden" : @"",
        RYGFastMCValueString(value)];

    if (param.type == RYGMCTypeBool) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
        toggle.onTintColor = [RYGUtils RYGColor_Primary];
        objc_setAssociatedObject(toggle, kRYGFastMCParamKey, param, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(boolChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)boolChanged:(UISwitch *)toggle {
    RYGMCParam *param = objc_getAssociatedObject(toggle, kRYGFastMCParamKey);
    if (!param || !param.isRuntimeBacked || param.type != RYGMCTypeBool) return;
    if (![RYGMobileConfig.shared setOverride:@(toggle.isOn) for:param]) {
        toggle.on = !toggle.isOn;
        [RYGUtils showErrorHUDWithDescription:@"Native MobileConfig rejected this Boolean override"];
        return;
    }
    if (self.didMutate) self.didMutate();
    [self.tableView reloadData];
}

- (id)parsedValue:(NSString *)text forParam:(RYGMCParam *)param valid:(BOOL *)valid {
    if (valid) *valid = YES;
    if (param.type == RYGMCTypeString) return text ?: @"";
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const char *raw = trim.UTF8String;
    if (!raw || !*raw) { if (valid) *valid = NO; return nil; }
    if (param.type == RYGMCTypeInt) {
        char *end = NULL; long long value = strtoll(raw, &end, 10);
        if (end == raw || *end != '\0') { if (valid) *valid = NO; return nil; }
        return @(value);
    }
    if (param.type == RYGMCTypeDouble) {
        char *end = NULL; double value = strtod(raw, &end);
        if (end == raw || *end != '\0' || !isfinite(value)) { if (valid) *valid = NO; return nil; }
        return @(value);
    }
    if (valid) *valid = NO;
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGMCParam *param = self.visibleParams[(NSUInteger)indexPath.row];
    if (!param.isRuntimeBacked || !RYGMCTypeIsRuntimeValue(param.type) || !param.paramID || param.type == RYGMCTypeBool) return;

    RYGMobileConfig *engine = RYGMobileConfig.shared;
    id current = [engine overrideStateFor:param] == RYGMCOverrideSet ? [engine overrideValueFor:param] : [engine liveValueFor:param];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:param.name.length ? param.name : @"MobileConfig value"
                                                                     message:[NSString stringWithFormat:@"%@ · stable PID %llu", param.typeName ?: @"typed", param.paramID]
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = RYGFastMCValueString(current);
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        if (param.type == RYGMCTypeInt) field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        else if (param.type == RYGMCTypeDouble) field.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if ([engine overrideStateFor:param] == RYGMCOverrideSet) {
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"Use Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [engine clearOverrideFor:param];
            if (weakSelf.didMutate) weakSelf.didMutate();
            [weakSelf.tableView reloadData];
        }]];
    }
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        BOOL valid = NO;
        id value = [weakSelf parsedValue:alert.textFields.firstObject.text ?: @"" forParam:param valid:&valid];
        if (!valid || !value || ![engine setOverride:value for:param]) {
            [RYGUtils showErrorHUDWithDescription:@"Value does not match the native MobileConfig type"];
            return;
        }
        if (weakSelf.didMutate) weakSelf.didMutate();
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    RYGMCParam *param = self.visibleParams[(NSUInteger)indexPath.row];
    if (!param.isRuntimeBacked || [RYGMobileConfig.shared overrideStateFor:param] != RYGMCOverrideSet) return nil;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *native = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Native" handler:^(__unused UIContextualAction *action, __unused UIView *sourceView, void (^completion)(BOOL)) {
        [RYGMobileConfig.shared clearOverrideFor:param];
        if (weakSelf.didMutate) weakSelf.didMutate();
        [weakSelf.tableView reloadData];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[native]];
}

@end
