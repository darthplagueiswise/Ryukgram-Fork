#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigToolsViewController.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface RYGMobileConfig (RYGNativeBrowserPrivate)
- (unsigned long long)bestParamIDFor:(RYGMCParam *)param;
- (void *)overridesTableForPid:(unsigned long long)pid;
- (NSString *)ryg_nativePersistenceStatus;
- (NSString *)ryg_nativePersistencePath;
@end

typedef NS_ENUM(NSInteger, RYGMCScope) {
    RYGMCScopeAll = 0,
    RYGMCScopeSeen,
    RYGMCScopeUnseen,
    RYGMCScopeOverridden,
};

static const void *kRYGMCNativePersistPathKey = &kRYGMCNativePersistPathKey;
static const void *kRYGMCNativePersistStatusKey = &kRYGMCNativePersistStatusKey;
static NSUInteger gRYGMCPersistGeneration;

static BOOL RYGMCHasNativeTable(RYGMobileConfig *mc, RYGMCParam *param) {
    if (!mc || !param) return NO;
    unsigned long long pid = param.paramID;
    SEL bestSelector = NSSelectorFromString(@"bestParamIDFor:");
    if ([mc respondsToSelector:bestSelector]) {
        pid = ((unsigned long long (*)(id, SEL, id))objc_msgSend)(mc, bestSelector, param);
    }
    SEL tableSelector = NSSelectorFromString(@"overridesTableForPid:");
    if (![mc respondsToSelector:tableSelector] || !pid) return NO;
    return ((void *(*)(id, SEL, unsigned long long))objc_msgSend)(mc, tableSelector, pid) != NULL;
}

static BOOL RYGMCParamSeen(RYGMobileConfig *mc, RYGMCParam *param) {
    return [mc callSiteFor:param].length > 0;
}

static NSUInteger RYGMCSeenCount(RYGMobileConfig *mc, RYGMCConfig *config) {
    NSUInteger count = 0;
    for (RYGMCParam *param in config.params) if (RYGMCParamSeen(mc, param)) count++;
    return count;
}

static NSUInteger RYGMCOverrideCount(RYGMobileConfig *mc, RYGMCConfig *config) {
    NSUInteger count = 0;
    for (RYGMCParam *param in config.params) if ([mc overrideStateFor:param] == RYGMCOverrideSet) count++;
    return count;
}

static BOOL RYGMCWriteCanonicalOverrides(RYGMobileConfig *mc) {
    NSError *error = nil;
    NSData *data = [mc ryg_exportOverridesData:&error];
    NSString *path = [mc ryg_nativeOverridesJSONPath];
    if (!path.length) {
        objc_setAssociatedObject(mc, kRYGMCNativePersistPathKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(mc, kRYGMCNativePersistStatusKey,
                                 @"Native MobileConfig *.data directory is not available yet",
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        return NO;
    }
    if (!data.length) {
        data = [NSJSONSerialization dataWithJSONObject:@{} options:0 error:&error];
    }
    if (!data.length || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        objc_setAssociatedObject(mc, kRYGMCNativePersistPathKey, path, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(mc, kRYGMCNativePersistStatusKey,
                                 error.localizedDescription ?: @"Could not persist mc_overrides.json",
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        return NO;
    }
    objc_setAssociatedObject(mc, kRYGMCNativePersistPathKey, path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(mc, kRYGMCNativePersistStatusKey,
                             @"Canonical mc_overrides.json persisted",
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    return YES;
}

static void RYGMCScheduleCanonicalPersistence(RYGMobileConfig *mc) {
    if (!mc) return;
    NSUInteger generation = ++gRYGMCPersistGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != gRYGMCPersistGeneration) return;
        RYGMCWriteCanonicalOverrides(mc);
    });
}

@implementation RYGMobileConfig (RYGNativeContainerPersistence)

- (BOOL)ryg_native_setOverride:(id)value for:(RYGMCParam *)param {
    BOOL result = [self ryg_native_setOverride:value for:param];
    RYGMCScheduleCanonicalPersistence(self);
    return result;
}

- (void)ryg_native_clearOverrideFor:(RYGMCParam *)param {
    [self ryg_native_clearOverrideFor:param];
    RYGMCScheduleCanonicalPersistence(self);
}

- (void)ryg_native_resetAllOverrides {
    [self ryg_native_resetAllOverrides];
    RYGMCScheduleCanonicalPersistence(self);
}

- (void)ryg_native_reapplyOverridesToNativeTable {
    [self ryg_native_reapplyOverridesToNativeTable];
    RYGMCScheduleCanonicalPersistence(self);
}

- (NSString *)ryg_nativePersistenceStatus {
    return objc_getAssociatedObject(self, kRYGMCNativePersistStatusKey)
        ?: ([self ryg_nativeOverridesJSONPath].length ? @"Ready to persist in native *.data directory" : @"Native *.data directory not resolved");
}

- (NSString *)ryg_nativePersistencePath {
    return objc_getAssociatedObject(self, kRYGMCNativePersistPathKey) ?: [self ryg_nativeOverridesJSONPath];
}

@end

static BOOL RYGMCTokenMatch(NSString *haystack, NSString *query) {
    if (!query.length) return YES;
    return [haystack rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
}

static BOOL RYGMCParamMatchesQuery(RYGMCParam *param, NSString *query) {
    if (!query.length) return YES;
    NSString *decimal = [NSString stringWithFormat:@"%llu", param.paramID];
    NSString *hex = [NSString stringWithFormat:@"0x%llx", param.paramID];
    NSString *index = [NSString stringWithFormat:@"%u", param.paramIndex];
    return RYGMCTokenMatch(param.name ?: @"", query) || RYGMCTokenMatch(decimal, query) ||
           RYGMCTokenMatch(hex, query) || [index isEqualToString:query];
}

static BOOL RYGMCConfigMatchesQuery(RYGMCConfig *config, NSString *query) {
    if (!query.length) return YES;
    if (RYGMCTokenMatch(config.displayName, query) ||
        RYGMCTokenMatch([NSString stringWithFormat:@"%u", config.number], query)) return YES;
    for (RYGMCParam *param in config.params) if (RYGMCParamMatchesQuery(param, query)) return YES;
    return NO;
}

static BOOL RYGMCConfigMatchesScope(RYGMobileConfig *mc, RYGMCConfig *config, RYGMCScope scope) {
    NSUInteger seen = RYGMCSeenCount(mc, config);
    switch (scope) {
        case RYGMCScopeSeen: return seen > 0;
        case RYGMCScopeUnseen: return seen == 0;
        case RYGMCScopeOverridden: return RYGMCOverrideCount(mc, config) > 0;
        case RYGMCScopeAll: default: return YES;
    }
}

static BOOL RYGMCParamMatchesScope(RYGMobileConfig *mc, RYGMCParam *param, RYGMCScope scope) {
    BOOL seen = RYGMCParamSeen(mc, param);
    switch (scope) {
        case RYGMCScopeSeen: return seen;
        case RYGMCScopeUnseen: return !seen;
        case RYGMCScopeOverridden: return [mc overrideStateFor:param] == RYGMCOverrideSet;
        case RYGMCScopeAll: default: return YES;
    }
}

static NSString *RYGMCScopeTitle(RYGMCScope scope) {
    switch (scope) {
        case RYGMCScopeSeen: return @"Seen at runtime";
        case RYGMCScopeUnseen: return @"Not seen";
        case RYGMCScopeOverridden: return @"Overridden";
        case RYGMCScopeAll: default: return @"All";
    }
}

@class RYGMobileConfigNativeDetailController;

@interface RYGMobileConfigNativeBrowserController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGMCConfig *> *rows;
@property (nonatomic, assign) RYGMCScope scope;
@end

@interface RYGMobileConfigNativeDetailController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) RYGMCConfig *config;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGMCParam *> *rows;
@property (nonatomic, assign) RYGMCScope scope;
@end

@implementation RYGMobileConfigNativeBrowserController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 82.0;
    self.scope = RYGMCScopeAll;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Config name, config ID, param name/index/PID";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(refreshRuntime)];
    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self filterMenu]];
    self.navigationItem.rightBarButtonItems = @[refresh, filter];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadRows) name:@"RYGMobileConfigNamesDidChange" object:nil];
    [[RYGMobileConfig shared] prepare];
    [self reloadRows];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (UIMenu *)filterMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSNumber *number in @[@(RYGMCScopeAll), @(RYGMCScopeSeen), @(RYGMCScopeUnseen), @(RYGMCScopeOverridden)]) {
        RYGMCScope value = number.integerValue;
        UIAction *action = [UIAction actionWithTitle:RYGMCScopeTitle(value) image:nil identifier:nil handler:^(__unused UIAction *item) {
            weakSelf.scope = value;
            weakSelf.navigationItem.rightBarButtonItems.lastObject.menu = [weakSelf filterMenu];
            [weakSelf reloadRows];
        }];
        action.state = self.scope == value ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:@"Runtime / override filter" children:actions];
}

- (void)refreshRuntime {
    [[RYGMobileConfig shared] reloadFromRuntime];
    [self reloadRows];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reloadRows]; }

- (void)reloadRows {
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *rows = [NSMutableArray array];
    for (RYGMCConfig *config in mc.allConfigs) {
        if (!RYGMCConfigMatchesScope(mc, config, self.scope) || !RYGMCConfigMatchesQuery(config, query)) continue;
        [rows addObject:config];
    }
    self.rows = rows.copy;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    RYGMCConfig *config = self.rows[indexPath.row];
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    NSUInteger seen = RYGMCSeenCount(mc, config);
    NSUInteger overridden = RYGMCOverrideCount(mc, config);

    cell.textLabel.text = config.displayName;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    NSMutableString *detail = [NSMutableString stringWithFormat:@"Config ID %u · %lu params · %lu seen",
                               config.number, (unsigned long)config.params.count, (unsigned long)seen];
    if (overridden) [detail appendFormat:@" · %lu overridden", (unsigned long)overridden];

    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length) {
        NSMutableArray *matches = [NSMutableArray array];
        for (RYGMCParam *param in config.params) {
            if (RYGMCParamMatchesQuery(param, query) && param.name.length) {
                [matches addObject:param.name];
                if (matches.count == 3) break;
            }
        }
        if (matches.count) [detail appendFormat:@"\n%@", [matches componentsJoinedByString:@" · "]];
    }
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = [UIImage systemImageNamed:overridden ? @"slider.horizontal.3" : (seen ? @"eye" : @"circle")];
    cell.imageView.tintColor = overridden || seen ? [RYGUtils RYGColor_Primary] : UIColor.tertiaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGMobileConfigNativeDetailController *detail = [[RYGMobileConfigNativeDetailController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    detail.config = self.rows[indexPath.row];
    [self.navigationController pushViewController:detail animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    NSString *path = [mc ryg_nativePersistencePath];
    return [NSString stringWithFormat:@"%lu configs · filter: %@\n%@%@",
            (unsigned long)self.rows.count, RYGMCScopeTitle(self.scope),
            [mc ryg_nativePersistenceStatus], path.length ? [NSString stringWithFormat:@"\n%@", path] : @""];
}

@end

@implementation RYGMobileConfigNativeDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.config.displayName;
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 94.0;
    self.scope = RYGMCScopeAll;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Param name, index or full PID";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    UIBarButtonItem *filter = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self filterMenu]];
    UIBarButtonItem *reapply = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"] style:UIBarButtonItemStylePlain target:self action:@selector(reapply)];
    self.navigationItem.rightBarButtonItems = @[reapply, filter];
    [self reloadRows];
    RYGLiquidGlassApplyToViewController(self);
}

- (UIMenu *)filterMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSNumber *number in @[@(RYGMCScopeAll), @(RYGMCScopeSeen), @(RYGMCScopeUnseen), @(RYGMCScopeOverridden)]) {
        RYGMCScope value = number.integerValue;
        UIAction *action = [UIAction actionWithTitle:RYGMCScopeTitle(value) image:nil identifier:nil handler:^(__unused UIAction *item) {
            weakSelf.scope = value;
            weakSelf.navigationItem.rightBarButtonItems.lastObject.menu = [weakSelf filterMenu];
            [weakSelf reloadRows];
        }];
        action.state = self.scope == value ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:@"Parameter filter" children:actions];
}

- (void)reapply {
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    [mc reapplyOverridesToNativeTable];
    RYGMCScheduleCanonicalPersistence(mc);
    [RYGUtils showToastForDuration:1.5 title:@"MobileConfig reapplied" subtitle:[mc ryg_nativePersistenceStatus]];
    [self reloadRows];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self reloadRows]; }

- (void)reloadRows {
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *rows = [NSMutableArray array];
    for (RYGMCParam *param in self.config.params) {
        if (RYGMCParamMatchesScope(mc, param, self.scope) && RYGMCParamMatchesQuery(param, query)) [rows addObject:param];
    }
    self.rows = rows.copy;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"Config" : @"Parameters"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = indexPath.row == 0 ? @"Name" : @"Config ID";
        cell.detailTextLabel.text = indexPath.row == 0 ? self.config.displayName : [NSString stringWithFormat:@"%u", self.config.number];
        cell.detailTextLabel.numberOfLines = 0;
        return cell;
    }

    RYGMobileConfig *mc = [RYGMobileConfig shared];
    RYGMCParam *param = self.rows[indexPath.row];
    BOOL seen = RYGMCParamSeen(mc, param);
    BOOL overridden = [mc overrideStateFor:param] == RYGMCOverrideSet;
    id native = [mc liveValueFor:param];
    id forced = overridden ? [mc overrideValueFor:param] : nil;
    NSString *pidHex = [NSString stringWithFormat:@"0x%016llx", param.paramID];
    NSString *callSite = [mc callSiteFor:param];

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"Parameter #%u", param.paramIndex];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    NSMutableString *detail = [NSMutableString stringWithFormat:@"index %u · %@ · %@\n%@ · native %@",
                               param.paramIndex, param.typeName, pidHex, seen ? @"seen at runtime" : @"not seen", native ?: @"—"];
    if (forced) [detail appendFormat:@" · override %@", forced];
    if (callSite.length) [detail appendFormat:@"\ncaller %@", callSite];
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = [UIImage systemImageNamed:overridden ? @"checkmark.circle.fill" : (seen ? @"eye.fill" : @"circle")];
    cell.imageView.tintColor = overridden || seen ? [RYGUtils RYGColor_Primary] : UIColor.tertiaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        UIPasteboard.generalPasteboard.string = indexPath.row == 0 ? self.config.displayName : [NSString stringWithFormat:@"%u", self.config.number];
        return;
    }
    [self presentActionsForParam:self.rows[indexPath.row]];
}

- (void)presentActionsForParam:(RYGMCParam *)param {
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    BOOL seen = RYGMCParamSeen(mc, param);
    BOOL nativeTable = RYGMCHasNativeTable(mc, param);
    BOOL overridden = [mc overrideStateFor:param] == RYGMCOverrideSet;
    NSString *message = [NSString stringWithFormat:@"Config %u · param %u\nPID 0x%016llx\n%@\nNative override table: %@\n%@",
                         param.configNumber, param.paramIndex, param.paramID,
                         seen ? @"Seen at runtime" : @"Not seen at runtime",
                         nativeTable ? @"available" : @"not captured yet",
                         [mc ryg_nativePersistenceStatus]];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:param.name ?: @"MobileConfig parameter"
                                                                    message:message preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    void (^applyValue)(id) = ^(id value) {
        BOOL tableReady = RYGMCHasNativeTable(mc, param);
        [mc setOverride:value for:param];
        RYGMCScheduleCanonicalPersistence(mc);
        [RYGUtils showToastForDuration:1.7
                                title:tableReady ? @"Applied through native MobileConfig" : @"Override saved; native table pending"
                             subtitle:[mc ryg_nativePersistencePath] ?: [mc ryg_nativePersistenceStatus]];
        [weakSelf reloadRows];
    };

    if (param.type == RYGMCTypeBool) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { applyValue(@YES); }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { applyValue(@NO); }]];
    } else {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Set override…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [weakSelf promptValueForParam:param];
        }]];
    }
    if (overridden) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Clear override" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [mc clearOverrideFor:param];
            RYGMCScheduleCanonicalPersistence(mc);
            [weakSelf reloadRows];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy full parameter ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%llu", param.paramID];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptValueForParam:(RYGMCParam *)param {
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:param.name ?: @"Override"
                                                                    message:param.typeName
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        id current = [mc overrideStateFor:param] == RYGMCOverrideSet ? [mc overrideValueFor:param] : [mc liveValueFor:param];
        field.text = current ? [current description] : @"";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.keyboardType = param.type == RYGMCTypeString ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        id value = nil;
        if (param.type == RYGMCTypeString) value = text;
        else if (param.type == RYGMCTypeInt) {
            NSScanner *scanner = [NSScanner scannerWithString:text]; long long number = 0;
            if ([scanner scanLongLong:&number] && scanner.isAtEnd) value = @(number);
        } else if (param.type == RYGMCTypeDouble) {
            NSScanner *scanner = [NSScanner scannerWithString:text]; double number = 0;
            if ([scanner scanDouble:&number] && scanner.isAtEnd) value = @(number);
        }
        if (!value) {
            [RYGUtils showErrorHUDWithDescription:@"Value does not match the MobileConfig parameter type"];
            return;
        }
        BOOL tableReady = RYGMCHasNativeTable(mc, param);
        [mc setOverride:value for:param];
        RYGMCScheduleCanonicalPersistence(mc);
        [RYGUtils showToastForDuration:1.7 title:tableReady ? @"Applied through native MobileConfig" : @"Override saved; native table pending" subtitle:[mc ryg_nativePersistencePath]];
        [weakSelf reloadRows];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Names and IDs are never truncated. Tap to copy.";
    return [NSString stringWithFormat:@"%lu parameters · filter: %@", (unsigned long)self.rows.count, RYGMCScopeTitle(self.scope)];
}

@end

@implementation RYGMobileConfigToolsViewController (RYGNativeBrowserRouting)

- (void)ryg_nativeBrowser_rebuildSections {
    [self ryg_nativeBrowser_rebuildSections];
    NSArray *sections = nil;
    @try { sections = [self valueForKey:@"sections"]; } @catch (__unused id exception) {}
    if (!sections.count) return;

    NSMutableArray *patchedSections = [NSMutableArray arrayWithCapacity:sections.count];
    BOOL changed = NO;
    for (NSDictionary *section in sections) {
        NSMutableDictionary *patched = [section mutableCopy];
        NSMutableArray *rows = [NSMutableArray array];
        for (RYGSetting *row in section[@"rows"]) {
            if ([row.title isEqualToString:@"Open live MobileConfig browser"]) {
                row.navViewController = [RYGMobileConfigNativeBrowserController new];
                row.subtitle = @"Full names/IDs, runtime-seen filters, native apply status and canonical container persistence";
                changed = YES;
            }
            [rows addObject:row];
        }
        patched[@"rows"] = rows.copy;
        [patchedSections addObject:patched.copy];
    }
    if (changed) [self applySettingSections:patchedSections.copy];
}

@end

static void RYGSwapMobileConfigInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

__attribute__((constructor(135))) static void RYGInstallMobileConfigNativeBrowser(void) {
    @autoreleasepool {
        RYGSwapMobileConfigInstanceMethod(RYGMobileConfig.class,
                                          @selector(setOverride:for:),
                                          @selector(ryg_native_setOverride:for:));
        RYGSwapMobileConfigInstanceMethod(RYGMobileConfig.class,
                                          @selector(clearOverrideFor:),
                                          @selector(ryg_native_clearOverrideFor:));
        RYGSwapMobileConfigInstanceMethod(RYGMobileConfig.class,
                                          @selector(resetAllOverrides),
                                          @selector(ryg_native_resetAllOverrides));
        RYGSwapMobileConfigInstanceMethod(RYGMobileConfig.class,
                                          @selector(reapplyOverridesToNativeTable),
                                          @selector(ryg_native_reapplyOverridesToNativeTable));
        RYGSwapMobileConfigInstanceMethod(RYGMobileConfigToolsViewController.class,
                                          @selector(rebuildSections),
                                          @selector(ryg_nativeBrowser_rebuildSections));
    }
}
