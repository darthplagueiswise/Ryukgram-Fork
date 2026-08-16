#import "RYGDeveloperFeatureViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../Features/ExpFlags/RYGMobileConfig.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <QuartzCore/QuartzCore.h>

@interface RYGDeveloperFeatureViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSString *> *keywords;
@property (nonatomic, assign) BOOL wordmarkPreview;
@property (nonatomic, assign) BOOL allowsRecommendedApply;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *runtimeRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *mobileConfigRows;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *visibleRuntimeRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *visibleMobileConfigRows;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

static NSString *RYGDevNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString string];
    NSString *lower = value.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) [result appendFormat:@"%C", c];
    }
    return result;
}

static NSNumber *RYGRecommendedBoolForName(NSString *name) {
    NSString *n = RYGDevNormalize(name);
    for (NSString *negative in @[@"hide", @"hidden", @"suppress", @"disable", @"blocked", @"exclude", @"lockout"]) {
        if ([n containsString:negative]) return @NO;
    }
    for (NSString *positive in @[@"enable", @"enabled", @"available", @"eligible", @"show", @"visible", @"internal", @"employee", @"dogfood", @"igonly", @"prism", @"glass", @"throwback", @"storytray", @"storygrid", @"wordmark"]) {
        if ([n containsString:positive]) return @YES;
    }
    return nil;
}

@implementation RYGDeveloperFeatureViewController

- (instancetype)initWithTitle:(NSString *)title keywords:(NSArray<NSString *> *)keywords wordmarkPreview:(BOOL)wordmarkPreview allowsRecommendedApply:(BOOL)allowsRecommendedApply {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = title;
        _keywords = keywords.copy ?: @[];
        _wordmarkPreview = wordmarkPreview;
        _allowsRecommendedApply = allowsRecommendedApply;
        _runtimeRows = @[];
        _mobileConfigRows = @[];
        _visibleRuntimeRows = @[];
        _visibleMobileConfigRows = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Filter live results";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(refreshLiveData)];
    NSMutableArray *items = [NSMutableArray arrayWithObject:refresh];
    if (self.allowsRecommendedApply) {
        UIAction *apply = [UIAction actionWithTitle:@"Apply recommended BOOL gates" image:[UIImage systemImageNamed:@"bolt.fill"] identifier:nil handler:^(__kindof UIAction *action) { [self applyRecommendedGates]; }];
        UIAction *clear = [UIAction actionWithTitle:@"Restore native values" image:[UIImage systemImageNamed:@"arrow.uturn.backward"] identifier:nil handler:^(__kindof UIAction *action) { [self clearFeatureOverrides]; }];
        UIBarButtonItem *actions = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"bolt.circle"] menu:[UIMenu menuWithTitle:@"Feature gates" children:@[apply, clear]]];
        [items addObject:actions];
    }
    self.navigationItem.rightBarButtonItems = items;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(runtimeValueChanged:) name:RYGRuntimeNativeValueDidChangeNotification object:nil];
    if (self.wordmarkPreview) [self installWordmarkPreview];
    RYGLiquidGlassApplyToViewController(self);
    [self refreshLiveData];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)installWordmarkPreview {
    UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 126.0)];
    UIVisualEffectView *glass = RYGLiquidGlassView(NO, NO, nil);
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.layer.cornerRadius = 24.0;
    glass.clipsToBounds = YES;
    [holder addSubview:glass];

    UIImageView *image = [UIImageView new];
    image.translatesAutoresizingMaskIntoConstraints = NO;
    image.tag = 7744;
    image.contentMode = UIViewContentModeScaleAspectFit;
    image.tintColor = UIColor.labelColor;
    [glass.contentView addSubview:image];

    UISegmentedControl *variant = [[UISegmentedControl alloc] initWithItems:@[@"1A", @"1B"]];
    variant.translatesAutoresizingMaskIntoConstraints = NO;
    variant.selectedSegmentIndex = 0;
    [variant addTarget:self action:@selector(wordmarkVariantChanged:) forControlEvents:UIControlEventValueChanged];
    [glass.contentView addSubview:variant];

    [NSLayoutConstraint activateConstraints:@[
        [glass.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor constant:16.0],
        [glass.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-16.0],
        [glass.topAnchor constraintEqualToAnchor:holder.topAnchor constant:8.0],
        [glass.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor constant:-8.0],
        [image.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:18.0],
        [image.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:14.0],
        [image.bottomAnchor constraintEqualToAnchor:variant.topAnchor constant:-10.0],
        [image.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-18.0],
        [variant.centerXAnchor constraintEqualToAnchor:glass.contentView.centerXAnchor],
        [variant.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-12.0],
    ]];
    self.tableView.tableHeaderView = holder;
    [self updateWordmarkImageForVariant:0];
}

- (void)wordmarkVariantChanged:(UISegmentedControl *)sender { [self updateWordmarkImageForVariant:sender.selectedSegmentIndex]; }

- (void)updateWordmarkImageForVariant:(NSInteger)variant {
    UIImageView *image = [self.tableView.tableHeaderView viewWithTag:7744];
    NSString *name = variant == 1 ? @"instagram-wordmark-1b" : @"instagram-wordmark-1a";
    UIImage *asset = [UIImage imageNamed:name];
    if (!asset) asset = [UIImage systemImageNamed:@"camera.aperture"];
    image.image = [asset imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (void)runtimeValueChanged:(NSNotification *)note {
    NSString *key = note.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGRuntimeBoolMethod *row in self.visibleRuntimeRows) {
        if ([row.overrideKey isEqualToString:key]) { [self.tableView reloadData]; break; }
    }
}

- (void)refreshLiveData {
    NSUInteger generation = ++self.scanGeneration;
    self.tableView.backgroundView = self.spinner;
    [self.spinner startAnimating];
    NSArray<NSString *> *keywords = self.keywords.copy;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<RYGRuntimeBoolMethod *> *runtime = [NSMutableArray array];
        for (NSString *image in [RYGRuntimeBrowserEngine runtimeImagePaths]) {
            for (RYGRuntimeBoolMethod *row in [RYGRuntimeBrowserEngine boolMethodsForImagePath:image scope:RYGRuntimeBrowserScopeAll]) {
                NSString *text = [NSString stringWithFormat:@"%@ %@ %@", row.className ?: @"", row.selectorName ?: @"", image.lastPathComponent ?: @""];
                NSString *hay = RYGDevNormalize(text);
                BOOL hit = NO;
                for (NSString *keyword in keywords) {
                    NSString *needle = RYGDevNormalize(keyword);
                    if (needle.length && [hay containsString:needle]) { hit = YES; break; }
                }
                if (hit) [runtime addObject:row];
            }
        }
        RYGRuntimeBeginLiveObservation(runtime);

        NSMutableArray<NSDictionary *> *mcRows = [NSMutableArray array];
        RYGMobileConfig *mc = [RYGMobileConfig shared];
        for (RYGMCConfig *config in mc.allConfigs) {
            NSString *configHay = RYGDevNormalize(config.displayName);
            BOOL configHit = NO;
            for (NSString *keyword in keywords) {
                NSString *needle = RYGDevNormalize(keyword);
                if (needle.length && [configHay containsString:needle]) { configHit = YES; break; }
            }
            for (RYGMCParam *param in config.params) {
                NSString *paramHay = RYGDevNormalize(param.name);
                BOOL paramHit = configHit;
                if (!paramHit) for (NSString *keyword in keywords) {
                    NSString *needle = RYGDevNormalize(keyword);
                    if (needle.length && [paramHay containsString:needle]) { paramHit = YES; break; }
                }
                if (paramHit) [mcRows addObject:@{@"config":config, @"param":param}];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.scanGeneration) return;
            self.runtimeRows = runtime.copy;
            self.mobileConfigRows = mcRows.copy;
            [self.spinner stopAnimating];
            self.tableView.backgroundView = nil;
            [self applyFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }

- (void)applyFilter {
    NSString *query = RYGDevNormalize(self.searchController.searchBar.text);
    if (!query.length) {
        self.visibleRuntimeRows = self.runtimeRows;
        self.visibleMobileConfigRows = self.mobileConfigRows;
    } else {
        self.visibleRuntimeRows = [self.runtimeRows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeBoolMethod *row, NSDictionary *bindings) {
            NSString *hay = RYGDevNormalize([NSString stringWithFormat:@"%@ %@ %@", row.className, row.selectorName, row.imagePath.lastPathComponent]);
            return [hay containsString:query];
        }]];
        self.visibleMobileConfigRows = [self.mobileConfigRows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
            RYGMCConfig *config = entry[@"config"];
            RYGMCParam *param = entry[@"param"];
            NSString *hay = RYGDevNormalize([NSString stringWithFormat:@"%@ %@", config.displayName, param.name ?: @""]);
            return [hay containsString:query];
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.visibleRuntimeRows.count : self.visibleMobileConfigRows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? [NSString stringWithFormat:@"Runtime BOOL · %lu", (unsigned long)self.visibleRuntimeRows.count] : [NSString stringWithFormat:@"MobileConfig · %lu", (unsigned long)self.visibleMobileConfigRows.count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"Values are observed from real app calls. Scanning never invokes an unknown private method." : @"Values come from Instagram's live MobileConfig manager and are applied through its native overrides table.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    if (indexPath.section == 0) {
        RYGRuntimeBoolMethod *row = self.visibleRuntimeRows[indexPath.row];
        NSNumber *native = row.liveValue;
        NSNumber *forced = row.overrideValue;
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", row.classMethod ? @"+" : @"-", row.selectorName];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
        NSString *nativeText = native ? (native.boolValue ? @"true" : @"false") : @"not observed yet";
        NSString *output = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@\nnative %@ · output %@", row.className, row.imagePath.lastPathComponent, nativeText, output];
        cell.imageView.image = [UIImage systemImageNamed:forced ? @"bolt.circle.fill" : @"waveform.path.ecg"];
    } else {
        NSDictionary *entry = self.visibleMobileConfigRows[indexPath.row];
        RYGMCConfig *config = entry[@"config"];
        RYGMCParam *param = entry[@"param"];
        RYGMobileConfig *mc = [RYGMobileConfig shared];
        id native = [mc liveValueFor:param];
        id forced = [mc overrideValueFor:param];
        cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"param %u", param.paramIndex];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ [%u:%u] · %@\nnative %@%@", config.displayName, config.number, param.paramIndex, param.typeName, native ?: @"?", forced ? [NSString stringWithFormat:@" · override %@", forced] : @""];
        cell.imageView.image = [UIImage systemImageNamed:forced ? @"slider.horizontal.3" : @"switch.2"];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) [self presentRuntimeActions:self.visibleRuntimeRows[indexPath.row] source:[tableView cellForRowAtIndexPath:indexPath]];
    else [self presentMobileConfigActions:self.visibleMobileConfigRows[indexPath.row] source:[tableView cellForRowAtIndexPath:indexPath]];
}

- (void)presentRuntimeActions:(RYGRuntimeBoolMethod *)row source:(UIView *)source {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.selectorName message:[NSString stringWithFormat:@"%@\nNative: %@", row.className, row.liveValue ?: @"not observed yet"] preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [RYGRuntimeBrowserEngine setOverride:@YES forMethod:row]; [self.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [RYGRuntimeBrowserEngine setOverride:@NO forMethod:row]; [self.tableView reloadData]; }]];
    if (row.overrideValue) [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { [RYGRuntimeBrowserEngine setOverride:nil forMethod:row]; [self.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) { sheet.popoverPresentationController.sourceView = source; sheet.popoverPresentationController.sourceRect = source.bounds; }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentMobileConfigActions:(NSDictionary *)entry source:(UIView *)source {
    RYGMCConfig *config = entry[@"config"];
    RYGMCParam *param = entry[@"param"];
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    if (param.type == RYGMCTypeBool) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:param.name ?: @"BOOL" message:config.displayName preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [mc setOverride:@YES for:param]; [self.tableView reloadData]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [mc setOverride:@NO for:param]; [self.tableView reloadData]; }]];
        if ([mc overrideStateFor:param] == RYGMCOverrideSet) [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { [mc clearOverrideFor:param]; [self.tableView reloadData]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) { sheet.popoverPresentationController.sourceView = source; sheet.popoverPresentationController.sourceRect = source.bounds; }
        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:param.name ?: @"MobileConfig" message:[NSString stringWithFormat:@"%@ · %@", config.displayName, param.typeName] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        id current = [mc overrideValueFor:param] ?: [mc liveValueFor:param];
        field.text = current ? [current description] : @"";
        field.keyboardType = param.type == RYGMCTypeString ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        id value = param.type == RYGMCTypeString ? text : (param.type == RYGMCTypeDouble ? @([text doubleValue]) : @([text longLongValue]));
        [mc setOverride:value for:param];
        [self.tableView reloadData];
    }]];
    if ([mc overrideStateFor:param] == RYGMCOverrideSet) [alert addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { [mc clearOverrideFor:param]; [self.tableView reloadData]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyRecommendedGates {
    NSUInteger changed = 0;
    for (RYGRuntimeBoolMethod *row in self.runtimeRows) {
        NSNumber *target = RYGRecommendedBoolForName([NSString stringWithFormat:@"%@ %@", row.className, row.selectorName]);
        if (!target) continue;
        [RYGRuntimeBrowserEngine setOverride:target forMethod:row];
        changed++;
    }
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    for (NSDictionary *entry in self.mobileConfigRows) {
        RYGMCParam *param = entry[@"param"];
        if (param.type != RYGMCTypeBool) continue;
        NSNumber *target = RYGRecommendedBoolForName(param.name);
        if (!target) continue;
        if ([mc setOverride:target for:param]) changed++;
    }
    [mc reapplyOverridesToNativeTable];
    [self.tableView reloadData];
    [RYGUtils showToastForDuration:1.5 title:@"Applied" subtitle:[NSString stringWithFormat:@"%lu semantic BOOL gates", (unsigned long)changed]];
}

- (void)clearFeatureOverrides {
    for (RYGRuntimeBoolMethod *row in self.runtimeRows) if (row.overrideValue) [RYGRuntimeBrowserEngine setOverride:nil forMethod:row];
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    for (NSDictionary *entry in self.mobileConfigRows) {
        RYGMCParam *param = entry[@"param"];
        if ([mc overrideStateFor:param] == RYGMCOverrideSet) [mc clearOverrideFor:param];
    }
    [self.tableView reloadData];
}

@end
