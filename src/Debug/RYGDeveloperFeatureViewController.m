#import "RYGDeveloperFeatureViewController.h"
#import "RYGDeveloperRuntimeScanner.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../Features/ExpFlags/RYGMobileConfig.h"
#import "../UI/RYGLiquidGlass.h"
#import "../Utils.h"
#import <QuartzCore/QuartzCore.h>

@interface RYGDeveloperFeatureViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<NSString *> *keywords;
@property (nonatomic, assign) BOOL wordmarkPreview;
@property (nonatomic, assign) BOOL allowsRecommendedApply;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *runtimeRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *mobileConfigRows;
@property (nonatomic, strong) UISearchController *developerSearchController;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, assign) BOOL scanning;
@end

static NSString *RYGDevNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
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

- (instancetype)initWithTitle:(NSString *)title
                      keywords:(NSArray<NSString *> *)keywords
               wordmarkPreview:(BOOL)wordmarkPreview
        allowsRecommendedApply:(BOOL)allowsRecommendedApply {
    if ((self = [super initWithTitle:title])) {
        _keywords = keywords.copy ?: @[];
        _wordmarkPreview = wordmarkPreview;
        _allowsRecommendedApply = allowsRecommendedApply;
        _runtimeRows = @[];
        _mobileConfigRows = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Filter this developer surface";
    self.developerSearchController = search;
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    UIImage *refreshImage = [[RYGSymbol symbolWithName:@"arrow_cw"] image];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:refreshImage
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(refreshLiveData)];
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray arrayWithObject:refresh];

    if (self.allowsRecommendedApply) {
        __weak typeof(self) weakSelf = self;
        UIAction *apply = [UIAction actionWithTitle:@"Apply recommended BOOL gates"
                                              image:[[RYGSymbol symbolWithName:@"circle_check"] image]
                                         identifier:nil
                                            handler:^(__kindof UIAction *action) {
            [weakSelf applyRecommendedGates];
        }];
        UIAction *clear = [UIAction actionWithTitle:@"Restore native values"
                                              image:[[RYGSymbol symbolWithName:@"history"] image]
                                         identifier:nil
                                            handler:^(__kindof UIAction *action) {
            [weakSelf clearFeatureOverrides];
        }];
        UIBarButtonItem *actions = [[UIBarButtonItem alloc] initWithImage:[[RYGSymbol symbolWithName:@"toolbox"] image]
                                                                     menu:[UIMenu menuWithTitle:@"Feature gates" children:@[apply, clear]]];
        [items addObject:actions];
    }
    self.navigationItem.rightBarButtonItems = items;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(runtimeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    [[RYGMobileConfig shared] prepare];
    [self rebuildSections];
    [self refreshLiveData];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Data

- (void)refreshLiveData {
    NSUInteger generation = ++self.scanGeneration;
    self.scanning = YES;
    [self rebuildSections];

    NSArray<NSString *> *keywords = self.keywords.copy;
    NSArray<NSString *> *imagePaths = [RYGDeveloperRuntimeScanner primaryDeveloperImagePaths];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGRuntimeBoolMethod *> *runtime = [RYGDeveloperRuntimeScanner boolMethodsForImagePaths:imagePaths
                                                                                               keywords:keywords];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.scanGeneration) return;
            self.runtimeRows = runtime ?: @[];
            self.mobileConfigRows = [self matchingMobileConfigRowsForKeywords:keywords];
            self.scanning = NO;
            [self rebuildSections];
        });
    });
}

- (NSArray<NSDictionary *> *)matchingMobileConfigRowsForKeywords:(NSArray<NSString *> *)keywords {
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    for (RYGMCConfig *config in mc.allConfigs) {
        NSString *configHay = RYGDevNormalize(config.displayName ?: config.name);
        BOOL configHit = NO;
        for (NSString *keyword in keywords) {
            NSString *needle = RYGDevNormalize(keyword);
            if (needle.length && [configHay containsString:needle]) {
                configHit = YES;
                break;
            }
        }
        for (RYGMCParam *param in config.params) {
            BOOL hit = configHit;
            if (!hit) {
                NSString *paramHay = RYGDevNormalize(param.name);
                for (NSString *keyword in keywords) {
                    NSString *needle = RYGDevNormalize(keyword);
                    if (needle.length && [paramHay containsString:needle]) {
                        hit = YES;
                        break;
                    }
                }
            }
            if (hit) [matches addObject:@{@"config":config, @"param":param}];
        }
    }
    return matches.copy;
}

- (void)runtimeValueChanged:(NSNotification *)note {
    NSString *key = note.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (!key.length) return;
    for (RYGRuntimeBoolMethod *row in self.runtimeRows) {
        if ([row.overrideKey isEqualToString:key]) {
            [self rebuildSections];
            break;
        }
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self rebuildSections];
}

- (BOOL)matchesSearchText:(NSString *)text {
    NSString *query = RYGDevNormalize(self.developerSearchController.searchBar.text);
    if (!query.length) return YES;
    return [RYGDevNormalize(text) containsString:query];
}

#pragma mark - RyukGram settings sections

- (RYGSetting *)wordmarkPreviewSetting {
    __weak typeof(self) weakSelf = self;
    return [RYGSetting customCellWithHeight:132.0 provider:^UITableViewCell *(UITableView *tableView, NSIndexPath *indexPath) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = UIColor.clearColor;

        UIView *holder = [UIView new];
        holder.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:holder];

        UIVisualEffectView *glass = RYGLiquidGlassView(NO, NO, nil);
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        // The generic glass helper is non-interactive when used as a background.
        // This preview owns a segmented control inside contentView, so it must
        // participate in hit-testing without enabling UIGlassEffect's morph mode.
        glass.userInteractionEnabled = YES;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.cornerRadius = 22.0;
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
        [variant addTarget:weakSelf action:@selector(wordmarkVariantChanged:) forControlEvents:UIControlEventValueChanged];
        [glass.contentView addSubview:variant];

        [NSLayoutConstraint activateConstraints:@[
            [holder.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:8.0],
            [holder.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-8.0],
            [holder.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6.0],
            [holder.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6.0],
            [glass.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor],
            [glass.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
            [glass.topAnchor constraintEqualToAnchor:holder.topAnchor],
            [glass.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
            [image.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:18.0],
            [image.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-18.0],
            [image.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:12.0],
            [image.bottomAnchor constraintEqualToAnchor:variant.topAnchor constant:-8.0],
            [variant.centerXAnchor constraintEqualToAnchor:glass.contentView.centerXAnchor],
            [variant.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-10.0],
        ]];

        [weakSelf updateWordmarkImage:image variant:0];
        return cell;
    }];
}

- (void)wordmarkVariantChanged:(UISegmentedControl *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:UITableViewCell.class]) view = view.superview;
    UIImageView *image = (UIImageView *)[(UITableViewCell *)view viewWithTag:7744];
    [self updateWordmarkImage:image variant:sender.selectedSegmentIndex];
}

- (void)updateWordmarkImage:(UIImageView *)image variant:(NSInteger)variant {
    if (!image) return;
    NSString *name = variant == 1 ? @"instagram-wordmark-1b" : @"instagram-wordmark-1a";
    UIImage *asset = [UIImage imageNamed:name];
    if (!asset) asset = [[RYGSymbol symbolWithName:@"instagram"] image];
    image.image = [asset imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (RYGSetting *)runtimeSettingForRow:(RYGRuntimeBoolMethod *)row {
    NSNumber *forced = row.overrideValue;
    NSNumber *native = row.liveValue;
    NSString *title = [NSString stringWithFormat:@"%@ %@", row.classMethod ? @"+" : @"-", row.selectorName];
    NSString *nativeText = native ? (native.boolValue ? @"true" : @"false") : @"not observed";
    NSString *outputText = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native";
    NSString *subtitle = [NSString stringWithFormat:@"%@ · %@\noriginal %@ · output %@",
                          row.className, row.imagePath.lastPathComponent, nativeText, outputText];
    __weak typeof(self) weakSelf = self;
    RYGSymbol *icon = forced
        ? [RYGSymbol symbolWithName:(forced.boolValue ? @"circle_check_filled" : @"xmark")]
        : [RYGSymbol symbolWithName:@"function" color:UIColor.secondaryLabelColor];
    return [RYGSetting buttonCellWithTitle:title subtitle:subtitle icon:icon action:^{
        [weakSelf presentRuntimeActions:row];
    }];
}

- (RYGSetting *)mobileConfigSettingForEntry:(NSDictionary *)entry {
    RYGMCConfig *config = entry[@"config"];
    RYGMCParam *param = entry[@"param"];
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    id native = [mc liveValueFor:param];
    id forced = [mc overrideValueFor:param];
    NSString *title = param.name.length ? param.name : [NSString stringWithFormat:@"param %u", param.paramIndex];
    NSString *subtitle = [NSString stringWithFormat:@"%@ [%u:%u] · %@\noriginal %@%@",
                          config.displayName, config.number, param.paramIndex, param.typeName,
                          native ?: @"?", forced ? [NSString stringWithFormat:@" · override %@", forced] : @""];
    __weak typeof(self) weakSelf = self;
    RYGSymbol *icon = [RYGSymbol symbolWithName:(forced ? @"sliders" : @"settings")];
    return [RYGSetting buttonCellWithTitle:title subtitle:subtitle icon:icon action:^{
        [weakSelf presentMobileConfigActions:entry];
    }];
}

- (void)rebuildSections {
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];

    if (self.wordmarkPreview) {
        [sections addObject:[RYGSettingsViewController sectionWithHeader:@"IGWordMark"
                                                                  footer:@"Preview uses RyukGram's live asset lookup; the gates below come from the currently loaded executable/framework and MobileConfig."
                                                                    rows:@[[self wordmarkPreviewSetting]]]];
    }

    if (self.scanning) {
        RYGSetting *status = [RYGSetting staticCellWithTitle:@"Scanning live metadata…"
                                                   subtitle:@"Instagram executable + FBSharedFramework; no private getter is invoked."
                                                       icon:[RYGSymbol symbolWithName:@"search"]];
        [sections addObject:[RYGSettingsViewController sectionWithHeader:@"Runtime"
                                                                  footer:nil
                                                                    rows:@[status]]];
    } else {
        NSMutableArray<RYGSetting *> *runtimeSettings = [NSMutableArray array];
        for (RYGRuntimeBoolMethod *row in self.runtimeRows) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@", row.className, row.selectorName, row.imagePath.lastPathComponent];
            if ([self matchesSearchText:hay]) [runtimeSettings addObject:[self runtimeSettingForRow:row]];
        }
        NSString *runtimeFooter = @"Opening this screen does not hook anything. Tap a row to observe its original return value pass-through, or explicitly force true/false.";
        [sections addObject:[RYGSettingsViewController sectionWithHeader:[NSString stringWithFormat:@"Runtime BOOL · %lu", (unsigned long)runtimeSettings.count]
                                                                  footer:runtimeFooter
                                                                    rows:runtimeSettings]];
    }

    NSMutableArray<RYGSetting *> *mcSettings = [NSMutableArray array];
    for (NSDictionary *entry in self.mobileConfigRows) {
        RYGMCConfig *config = entry[@"config"];
        RYGMCParam *param = entry[@"param"];
        NSString *hay = [NSString stringWithFormat:@"%@ %@", config.displayName, param.name ?: @""];
        if ([self matchesSearchText:hay]) [mcSettings addObject:[self mobileConfigSettingForEntry:entry]];
    }
    [sections addObject:[RYGSettingsViewController sectionWithHeader:[NSString stringWithFormat:@"MobileConfig · %lu", (unsigned long)mcSettings.count]
                                                              footer:@"Values are read and overridden through Instagram's current MobileConfig manager."
                                                                rows:mcSettings]];

    [self applySettingSections:sections];
}

#pragma mark - Runtime actions

- (void)presentRuntimeActions:(RYGRuntimeBoolMethod *)row {
    NSNumber *native = row.liveValue;
    NSNumber *forced = row.overrideValue;
    NSString *message = [NSString stringWithFormat:@"%@\n%@\nOriginal: %@\nOutput: %@",
                         row.className,
                         row.imagePath.lastPathComponent,
                         native ? (native.boolValue ? @"true" : @"false") : @"not observed yet",
                         forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.selectorName message:message preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe original live value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[row]);
        [RYGUtils showToastForDuration:1.4 title:@"Live observer installed" subtitle:@"Waiting for Instagram to call this method"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:row];
        [weakSelf rebuildSections];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:row];
        [weakSelf rebuildSections];
    }]];
    if (row.overrideValue) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:row];
            [weakSelf rebuildSections];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy method details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@", row.classMethod ? @"+" : @"-", row.className, row.selectorName, row.typeEncoding];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 100.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - MobileConfig actions

- (void)presentMobileConfigActions:(NSDictionary *)entry {
    RYGMCConfig *config = entry[@"config"];
    RYGMCParam *param = entry[@"param"];
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    __weak typeof(self) weakSelf = self;

    if (param.type == RYGMCTypeBool) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:param.name ?: @"BOOL" message:config.displayName preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [mc setOverride:@YES for:param];
            [weakSelf rebuildSections];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [mc setOverride:@NO for:param];
            [weakSelf rebuildSections];
        }]];
        if ([mc overrideStateFor:param] == RYGMCOverrideSet) {
            [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
                [mc clearOverrideFor:param];
                [weakSelf rebuildSections];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            sheet.popoverPresentationController.sourceView = self.view;
            sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 100.0, 1.0, 1.0);
        }
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
        [weakSelf rebuildSections];
    }]];
    if ([mc overrideStateFor:param] == RYGMCOverrideSet) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
            [mc clearOverrideFor:param];
            [weakSelf rebuildSections];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Bulk explicit actions

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
    [self rebuildSections];
    [RYGUtils showToastForDuration:1.5 title:@"Applied" subtitle:[NSString stringWithFormat:@"%lu explicit BOOL overrides", (unsigned long)changed]];
}

- (void)clearFeatureOverrides {
    for (RYGRuntimeBoolMethod *row in self.runtimeRows) {
        if (row.overrideValue) [RYGRuntimeBrowserEngine setOverride:nil forMethod:row];
    }
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    for (NSDictionary *entry in self.mobileConfigRows) {
        RYGMCParam *param = entry[@"param"];
        if ([mc overrideStateFor:param] == RYGMCOverrideSet) [mc clearOverrideFor:param];
    }
    [self rebuildSections];
}

@end
