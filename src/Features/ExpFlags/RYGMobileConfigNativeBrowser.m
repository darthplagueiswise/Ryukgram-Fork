#import "RYGMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <objc/runtime.h>

static const void *kRYGMCParamKey = &kRYGMCParamKey;

static NSString *RYGMCTrimmedQuery(UISearchController *controller) {
    return [controller.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static NSString *RYGMCNormalized(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString string];
    NSString *lower = value.lowercaseString;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        if ((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')) [result appendFormat:@"%C", character];
    }
    return result;
}

static BOOL RYGMCTextMatches(NSString *value, NSString *query) {
    NSString *needle = RYGMCNormalized(query);
    if (!needle.length) return YES;
    return [RYGMCNormalized(value) containsString:needle];
}

static BOOL RYGMCParamMatches(RYGMCParam *param, NSString *query) {
    if (!query.length) return YES;
    if (RYGMCTextMatches(param.name, query)) return YES;
    if ([[NSString stringWithFormat:@"%u", param.paramIndex] isEqualToString:query]) return YES;
    if (param.paramID && (RYGMCTextMatches([NSString stringWithFormat:@"%llu", param.paramID], query) ||
                          RYGMCTextMatches([NSString stringWithFormat:@"0x%llx", param.paramID], query))) return YES;
    return NO;
}

static BOOL RYGMCConfigMatchesDirectly(RYGMCConfig *config, NSString *query) {
    if (!query.length) return YES;
    return RYGMCTextMatches(config.name, query) || [[NSString stringWithFormat:@"%u", config.number] isEqualToString:query];
}

static void RYGMCPersistOverrides(RYGMobileConfig *mobileConfig) {
    NSError *error = nil;
    NSData *data = [mobileConfig ryg_exportOverridesData:&error];
    NSString *path = [mobileConfig ryg_nativeOverridesJSONPath];
    if (!path.length || !data.length) return;
    [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

@interface RYGMobileConfigBrowserViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGMCConfig *> *visibleConfigs;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *expandedConfigIDs;
@end

@implementation RYGMobileConfigBrowserViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig";
    self.expandedConfigIDs = [NSMutableSet set];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56.0;
    self.tableView.sectionHeaderTopPadding = 8.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Config or parameter";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(refreshRuntime)];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(mappingChanged:)
                                               name:@"RYGMobileConfigNamesDidChange"
                                             object:nil];
    [[RYGMobileConfig shared] prepare];
    [self rebuildVisibleConfigs];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)mappingChanged:(NSNotification *)notification {
    (void)notification;
    [self rebuildVisibleConfigs];
}

- (void)refreshRuntime {
    [[RYGMobileConfig shared] reloadFromRuntime];
    [self rebuildVisibleConfigs];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self rebuildVisibleConfigs];
}

- (void)rebuildVisibleConfigs {
    NSString *query = RYGMCTrimmedQuery(self.searchController);
    NSMutableArray<RYGMCConfig *> *configs = [NSMutableArray array];
    for (RYGMCConfig *config in [RYGMobileConfig shared].allConfigs) {
        BOOL direct = RYGMCConfigMatchesDirectly(config, query);
        BOOL paramHit = NO;
        if (query.length && !direct) {
            for (RYGMCParam *param in config.params) {
                if (RYGMCParamMatches(param, query)) { paramHit = YES; break; }
            }
        }
        if (!query.length || direct || paramHit) [configs addObject:config];
    }
    self.visibleConfigs = configs.copy;
    [self.tableView reloadData];
}

- (NSArray<RYGMCParam *> *)displayedParamsForConfig:(RYGMCConfig *)config {
    NSString *query = RYGMCTrimmedQuery(self.searchController);
    if (!query.length) {
        return [self.expandedConfigIDs containsObject:@(config.number)] ? config.params : @[];
    }

    BOOL directConfigMatch = RYGMCConfigMatchesDirectly(config, query);
    NSMutableArray<RYGMCParam *> *matches = [NSMutableArray array];
    for (RYGMCParam *param in config.params) {
        if (directConfigMatch || RYGMCParamMatches(param, query)) [matches addObject:param];
    }
    return matches.copy;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return self.visibleConfigs.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    RYGMCConfig *config = self.visibleConfigs[(NSUInteger)section];
    NSArray *params = [self displayedParamsForConfig:config];
    if (params.count) return params.count;
    return RYGMCTrimmedQuery(self.searchController).length ? 0 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    RYGMCConfig *config = self.visibleConfigs[(NSUInteger)section];
    return [NSString stringWithFormat:@"%@  ·  %u", config.displayName, config.number];
}

- (UITableViewCell *)collapsedCellForConfig:(RYGMCConfig *)config {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @"Parameters";
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = [UIImage systemImageNamed:@"list.bullet"];
    cell.imageView.tintColor = UIColor.secondaryLabelColor;
    cell.accessibilityValue = [NSString stringWithFormat:@"%lu", (unsigned long)config.params.count];
    return cell;
}

- (UITableViewCell *)cellForParam:(RYGMCParam *)param {
    RYGMobileConfig *mobileConfig = [RYGMobileConfig shared];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"Parameter %u", param.paramIndex];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 1;

    if (!param.runtimeBacked) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Index %u · mapping only", param.paramIndex];
        cell.imageView.image = [UIImage systemImageNamed:@"tag"];
        cell.imageView.tintColor = UIColor.tertiaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    cell.detailTextLabel.text = [NSString stringWithFormat:@"Index %u · %@", param.paramIndex, param.typeName];
    BOOL overridden = [mobileConfig overrideStateFor:param] == RYGMCOverrideSet;
    if (param.type == RYGMCTypeBool) {
        NSNumber *displayed = overridden ? [mobileConfig overrideValueFor:param] : [mobileConfig liveValueFor:param];
        UISwitch *toggle = [UISwitch new];
        toggle.on = displayed.boolValue;
        objc_setAssociatedObject(toggle, kRYGMCParamKey, param, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(boolToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.imageView.image = [UIImage systemImageNamed:overridden ? @"slider.horizontal.3" : @"switch.2"];
        cell.imageView.tintColor = overridden ? [RYGUtils RYGColor_Primary] : UIColor.secondaryLabelColor;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.2.square"];
        cell.imageView.tintColor = overridden ? [RYGUtils RYGColor_Primary] : UIColor.secondaryLabelColor;
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    RYGMCConfig *config = self.visibleConfigs[(NSUInteger)indexPath.section];
    NSArray<RYGMCParam *> *params = [self displayedParamsForConfig:config];
    if (!params.count) return [self collapsedCellForConfig:config];
    return [self cellForParam:params[(NSUInteger)indexPath.row]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGMCConfig *config = self.visibleConfigs[(NSUInteger)indexPath.section];
    NSArray<RYGMCParam *> *params = [self displayedParamsForConfig:config];
    if (!params.count) {
        NSNumber *key = @(config.number);
        if ([self.expandedConfigIDs containsObject:key]) [self.expandedConfigIDs removeObject:key];
        else [self.expandedConfigIDs addObject:key];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:(NSUInteger)indexPath.section]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
        return;
    }
    RYGMCParam *param = params[(NSUInteger)indexPath.row];
    if (!param.runtimeBacked) return;
    if (param.type == RYGMCTypeBool) [self presentBoolActions:param source:[tableView cellForRowAtIndexPath:indexPath]];
    else [self promptValueForParam:param];
}

- (void)boolToggleChanged:(UISwitch *)toggle {
    RYGMCParam *param = objc_getAssociatedObject(toggle, kRYGMCParamKey);
    if (!param || !param.runtimeBacked || param.type != RYGMCTypeBool) return;
    RYGMobileConfig *mobileConfig = [RYGMobileConfig shared];
    if (![mobileConfig setOverride:@(toggle.isOn) for:param]) {
        [toggle setOn:!toggle.isOn animated:YES];
        return;
    }
    RYGMCPersistOverrides(mobileConfig);
    [self.tableView reloadData];
}

- (void)presentBoolActions:(RYGMCParam *)param source:(UIView *)source {
    RYGMobileConfig *mobileConfig = [RYGMobileConfig shared];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:param.name ?: @"Boolean parameter"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force On" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [mobileConfig setOverride:@YES for:param]; RYGMCPersistOverrides(mobileConfig); [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force Off" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [mobileConfig setOverride:@NO for:param]; RYGMCPersistOverrides(mobileConfig); [weakSelf.tableView reloadData];
    }]];
    if ([mobileConfig overrideStateFor:param] == RYGMCOverrideSet) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native Value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [mobileConfig clearOverrideFor:param]; RYGMCPersistOverrides(mobileConfig); [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = source ?: self.view;
        sheet.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptValueForParam:(RYGMCParam *)param {
    RYGMobileConfig *mobileConfig = [RYGMobileConfig shared];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:param.name ?: @"Override"
                                                                    message:param.typeName
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        id current = [mobileConfig overrideStateFor:param] == RYGMCOverrideSet ? [mobileConfig overrideValueFor:param] : [mobileConfig liveValueFor:param];
        field.text = current ? [current description] : @"";
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
        if (!value || ![mobileConfig setOverride:value for:param]) {
            [RYGUtils showErrorHUDWithDescription:@"Value does not match this runtime MobileConfig type"];
            return;
        }
        RYGMCPersistOverrides(mobileConfig);
        [weakSelf.tableView reloadData];
    }]];
    if ([mobileConfig overrideStateFor:param] == RYGMCOverrideSet) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Use Native Value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [mobileConfig clearOverrideFor:param]; RYGMCPersistOverrides(mobileConfig); [weakSelf.tableView reloadData];
        }]];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

@end