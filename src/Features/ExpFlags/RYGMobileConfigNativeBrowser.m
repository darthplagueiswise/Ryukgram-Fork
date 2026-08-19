#import "RYGMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <math.h>

static NSString *const kRYGMobileConfigNamesDidChangeNotification = @"RYGMobileConfigNamesDidChange";
static const void *kRYGMCParamSwitchKey = &kRYGMCParamSwitchKey;

static NSString *RYGMCNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    BOOL previousSpace = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        BOOL alpha = character >= 'a' && character <= 'z';
        BOOL digit = character >= '0' && character <= '9';
        if (alpha || digit) {
            [result appendFormat:@"%C", character];
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
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in [normalized componentsSeparatedByString:@" "]) if (part.length) [tokens addObject:part];
    return tokens.copy;
}

static BOOL RYGMCTextMatchesTokens(NSString *text, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *normalized = RYGMCNormalize(text);
    NSString *compact = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in tokens) {
        if ([normalized rangeOfString:token].location == NSNotFound &&
            [compact rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

static NSString *RYGMCConfigSearchText(RYGMCConfig *config) {
    return [NSString stringWithFormat:@"%@ %u", config.name ?: @"", config.number];
}

static NSString *RYGMCParamSearchText(RYGMCParam *param) {
    return [NSString stringWithFormat:@"%@ %u %llu %@", param.name ?: @"", param.paramIndex,
            param.paramID, param.typeName ?: @""];
}

@interface RYGMCConfigHeaderView : UITableViewHeaderFooterView
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *idLabel;
@property (nonatomic, strong) UIImageView *chevron;
@property (nonatomic, copy) void (^tapHandler)(void);
- (void)configureWithConfig:(RYGMCConfig *)config expanded:(BOOL)expanded searching:(BOOL)searching;
@end

@implementation RYGMCConfigHeaderView

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    if (!(self = [super initWithReuseIdentifier:reuseIdentifier])) return nil;
    self.contentView.backgroundColor = UIColor.clearColor;

    self.button = [UIButton buttonWithType:UIButtonTypeSystem];
    self.button.translatesAutoresizingMaskIntoConstraints = NO;
    self.button.backgroundColor = UIColor.clearColor;
    self.button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    [self.button addTarget:self action:@selector(didTap) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.button];
    RYGLiquidGlassConfigureButton(self.button, NO);

    self.nameLabel = [UILabel new];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.nameLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    self.nameLabel.textColor = UIColor.labelColor;
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    self.idLabel = [UILabel new];
    self.idLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.idLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular];
    self.idLabel.textColor = UIColor.secondaryLabelColor;

    self.chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    self.chevron.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevron.tintColor = UIColor.tertiaryLabelColor;
    self.chevron.contentMode = UIViewContentModeScaleAspectFit;

    [self.button addSubview:self.nameLabel];
    [self.button addSubview:self.idLabel];
    [self.button addSubview:self.chevron];

    [NSLayoutConstraint activateConstraints:@[
        [self.button.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
        [self.button.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
        [self.button.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.button.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.button.leadingAnchor constant:12.0],
        [self.nameLabel.centerYAnchor constraintEqualToAnchor:self.button.centerYAnchor],
        [self.idLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.nameLabel.trailingAnchor constant:8.0],
        [self.idLabel.centerYAnchor constraintEqualToAnchor:self.button.centerYAnchor],
        [self.idLabel.trailingAnchor constraintEqualToAnchor:self.chevron.leadingAnchor constant:-8.0],
        [self.chevron.trailingAnchor constraintEqualToAnchor:self.button.trailingAnchor constant:-12.0],
        [self.chevron.centerYAnchor constraintEqualToAnchor:self.button.centerYAnchor],
        [self.chevron.widthAnchor constraintEqualToConstant:12.0],
        [self.chevron.heightAnchor constraintEqualToConstant:16.0],
    ]];
    return self;
}

- (void)didTap { if (self.tapHandler) self.tapHandler(); }

- (void)configureWithConfig:(RYGMCConfig *)config expanded:(BOOL)expanded searching:(BOOL)searching {
    self.nameLabel.text = config.displayName;
    self.idLabel.text = [NSString stringWithFormat:@"#%u", config.number];
    self.button.enabled = !searching;
    self.chevron.hidden = searching;
    self.chevron.transform = expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI_2) : CGAffineTransformIdentity;
    RYGLiquidGlassConfigureButton(self.button, NO);
}

@end

@interface RYGMobileConfigBrowserViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGMCConfig *> *allConfigs;
@property (nonatomic, copy) NSArray<RYGMCConfig *> *visibleConfigs;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *expandedConfigNumbers;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSArray<RYGMCParam *> *> *searchMatches;
@end

@implementation RYGMobileConfigBrowserViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 48.0;
    self.tableView.sectionHeaderHeight = 42.0;
    self.expandedConfigNumbers = [NSMutableSet set];
    [self.tableView registerClass:RYGMCConfigHeaderView.class forHeaderFooterViewReuseIdentifier:@"RYGMCConfigHeader"];

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

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(namesDidChange:)
                                               name:kRYGMobileConfigNamesDidChangeNotification object:nil];
    [self reloadModel:NO];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (BOOL)isSearching { return self.searchController.searchBar.text.length > 0; }
- (void)namesDidChange:(NSNotification *)notification { (void)notification; [self reloadModel:NO]; }
- (void)refreshRuntime { [self reloadModel:YES]; }

- (void)reloadModel:(BOOL)forceRuntimeReload {
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    if (forceRuntimeReload) [mobileConfig reloadFromRuntime]; else [mobileConfig prepare];
    self.allConfigs = mobileConfig.allConfigs ?: @[];
    [self rebuildVisibleConfigs];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self rebuildVisibleConfigs];
}

- (void)rebuildVisibleConfigs {
    NSArray<NSString *> *tokens = RYGMCTokens(self.searchController.searchBar.text ?: @"");
    if (!tokens.count) {
        self.visibleConfigs = self.allConfigs ?: @[];
        self.searchMatches = @{};
        [self.tableView reloadData];
        return;
    }

    NSMutableArray<RYGMCConfig *> *visible = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSArray<RYGMCParam *> *> *matches = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in self.allConfigs) {
        BOOL configMatches = RYGMCTextMatchesTokens(RYGMCConfigSearchText(config), tokens);
        NSMutableArray<RYGMCParam *> *paramMatches = [NSMutableArray array];
        if (configMatches) {
            [paramMatches addObjectsFromArray:config.params ?: @[]];
        } else {
            for (RYGMCParam *param in config.params) {
                if (RYGMCTextMatchesTokens(RYGMCParamSearchText(param), tokens)) [paramMatches addObject:param];
            }
        }
        if (configMatches || paramMatches.count) {
            [visible addObject:config];
            matches[@(config.number)] = paramMatches.copy;
        }
    }
    self.visibleConfigs = visible.copy;
    self.searchMatches = matches.copy;
    [self.tableView reloadData];
}

- (RYGMCConfig *)configForSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.visibleConfigs.count) return nil;
    return self.visibleConfigs[(NSUInteger)section];
}

- (NSArray<RYGMCParam *> *)paramsForSection:(NSInteger)section {
    RYGMCConfig *config = [self configForSection:section];
    if (!config) return @[];
    if (self.isSearching) return self.searchMatches[@(config.number)] ?: @[];
    return [self.expandedConfigNumbers containsObject:@(config.number)] ? (config.params ?: @[]) : @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return self.visibleConfigs.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; return [self paramsForSection:section].count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    RYGMCConfigHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:@"RYGMCConfigHeader"];
    RYGMCConfig *config = [self configForSection:section];
    BOOL expanded = self.isSearching || [self.expandedConfigNumbers containsObject:@(config.number)];
    [header configureWithConfig:config expanded:expanded searching:self.isSearching];
    __weak typeof(self) weakSelf = self;
    header.tapHandler = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.isSearching) return;
        NSNumber *key = @(config.number);
        if ([self.expandedConfigNumbers containsObject:key]) [self.expandedConfigNumbers removeObject:key];
        else [self.expandedConfigNumbers addObject:key];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:(NSUInteger)section]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    };
    return header;
}

- (NSString *)detailTextForParam:(RYGMCParam *)param {
    if (!param.isRuntimeBacked) return [NSString stringWithFormat:@"#%u · imported name", param.paramIndex];
    id live = [RYGMobileConfig.shared liveValueFor:param];
    id forced = [RYGMobileConfig.shared overrideValueFor:param];
    if (forced) {
        return [NSString stringWithFormat:@"#%u · %@ → %@", param.paramIndex,
                [live description] ?: @"native", [forced description]];
    }
    return [NSString stringWithFormat:@"#%u · %@", param.paramIndex, [live description] ?: @"native"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGMCParamCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.imageView.image = nil;

    NSArray<RYGMCParam *> *params = [self paramsForSection:indexPath.section];
    RYGMCParam *param = params[(NSUInteger)indexPath.row];
    cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"Parameter %u", param.paramIndex];
    cell.textLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = [self detailTextForParam:param];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 1;

    if (!param.isRuntimeBacked) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (param.type == RYGMCTypeBool) {
        UISwitch *toggle = [UISwitch new];
        id forced = [RYGMobileConfig.shared overrideValueFor:param];
        id live = [RYGMobileConfig.shared liveValueFor:param];
        toggle.on = forced ? [forced boolValue] : (live ? [live boolValue] : NO);
        toggle.onTintColor = [RYGUtils RYGColor_Primary];
        objc_setAssociatedObject(toggle, kRYGMCParamSwitchKey, param, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(boolSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (NSIndexPath *)indexPathContainingView:(UIView *)view {
    UIView *cursor = view;
    while (cursor && ![cursor isKindOfClass:UITableViewCell.class]) cursor = cursor.superview;
    return cursor ? [self.tableView indexPathForCell:(UITableViewCell *)cursor] : nil;
}

- (void)boolSwitchChanged:(UISwitch *)toggle {
    RYGMCParam *param = objc_getAssociatedObject(toggle, kRYGMCParamSwitchKey);
    if (!param || !param.isRuntimeBacked || param.type != RYGMCTypeBool) return;
    [RYGMobileConfig.shared setOverride:@(toggle.isOn) for:param];
    NSIndexPath *indexPath = [self indexPathContainingView:toggle];
    if (indexPath) [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<RYGMCParam *> *params = [self paramsForSection:indexPath.section];
    if ((NSUInteger)indexPath.row >= params.count) return;
    RYGMCParam *param = params[(NSUInteger)indexPath.row];
    if (!param.isRuntimeBacked) return;
    if (param.type == RYGMCTypeBool) [self presentBoolActionsForParam:param];
    else [self presentValueEditorForParam:param];
}

- (void)presentBoolActionsForParam:(RYGMCParam *)param {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:param.name ?: @"Boolean parameter"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force On" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGMobileConfig.shared setOverride:@YES for:param]; [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force Off" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGMobileConfig.shared setOverride:@NO for:param]; [weakSelf.tableView reloadData];
    }]];
    if ([RYGMobileConfig.shared overrideStateFor:param] == RYGMCOverrideSet) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native Value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGMobileConfig.shared clearOverrideFor:param]; [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentValueEditorForParam:(RYGMCParam *)param {
    NSString *title = param.name.length ? param.name : [NSString stringWithFormat:@"Parameter %u", param.paramIndex];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:param.typeName preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        id current = [RYGMobileConfig.shared overrideValueFor:param] ?: [RYGMobileConfig.shared liveValueFor:param];
        field.text = current ? [current description] : @"";
        if (param.type == RYGMCTypeInt || param.type == RYGMCTypeDouble) field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if ([RYGMobileConfig.shared overrideStateFor:param] == RYGMCOverrideSet) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Use Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGMobileConfig.shared clearOverrideFor:param]; [weakSelf.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        id value = nil;
        if (param.type == RYGMCTypeString) value = text;
        else if (param.type == RYGMCTypeInt) {
            char *end = NULL; long long parsed = strtoll(text.UTF8String, &end, 10);
            if (end != text.UTF8String && *end == '\0') value = @(parsed);
        } else if (param.type == RYGMCTypeDouble) {
            char *end = NULL; double parsed = strtod(text.UTF8String, &end);
            if (end != text.UTF8String && *end == '\0' && isfinite(parsed)) value = @(parsed);
        }
        if (!value || ![RYGMobileConfig.shared setOverride:value for:param])
            [RYGUtils showErrorHUDWithDescription:@"Invalid value for this MobileConfig type"];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
