#import "RYGDeveloperFeatureCatalogViewController.h"
#import "RYGDeveloperFeatureCatalog.h"
#import "RYGDeveloperHookRegistry.h"
#import "RYGRuntimeBrowserEngine.h" // model types only; no Runtime Browser hook state
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGDeveloperFeatureCatalogViewController () <UISearchResultsUpdating>
@property (nonatomic, assign) NSInteger surfaceValue;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *methods;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *visibleMethods;
@end

@implementation RYGDeveloperFeatureCatalogViewController

- (instancetype)init { if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) _surfaceValue=-1; return self; }
- (instancetype)initWithSurface:(RYGDeveloperRuntimeSurface)surface { if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) _surfaceValue=surface; return self; }

static NSString *RYGCatalogTitle(RYGDeveloperRuntimeSurface surface) {
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism: return @"Prism / IGDS / BSLDS";
        case RYGDeveloperRuntimeSurfaceLiquidGlass: return @"Liquid Glass / Throwback";
        case RYGDeveloperRuntimeSurfaceStories: return @"Story Tray / Story Grid";
        case RYGDeveloperRuntimeSurfaceConsumerSubs: return @"Aura / IGPlus";
        case RYGDeveloperRuntimeSurfaceInternalOnly: return @"IG-only / Internal-only";
        case RYGDeveloperRuntimeSurfaceDirectDogfood: return @"Dogfooding";
        case RYGDeveloperRuntimeSurfaceBugReport: return @"Bug Report / Sandbox";
        case RYGDeveloperRuntimeSurfaceSettingsRows: return @"Hidden Settings Rows";
    }
    return @"Developer Features";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.surfaceValue < 0 ? @"Live Feature Catalog" : RYGCatalogTitle((RYGDeveloperRuntimeSurface)self.surfaceValue);
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;
    RYGLiquidGlassApplyToViewController(self);

    [[RYGDeveloperFeatureCatalog sharedCatalog] startIfNeeded];
    [[RYGDeveloperHookRegistry sharedRegistry] startIfNeeded];
    if (self.surfaceValue >= 0) {
        UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
        search.searchResultsUpdater = self;
        search.obscuresBackgroundDuringPresentation = NO;
        search.searchBar.placeholder = @"Class or selector";
        self.navigationItem.searchController = search;
        self.definesPresentationContext = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(catalogUpdated:) name:RYGDeveloperFeatureCatalogDidUpdateNotification object:RYGDeveloperFeatureCatalog.sharedCatalog];
        [self reloadSnapshot];
        [[RYGDeveloperFeatureCatalog sharedCatalog] requestRefreshForSurface:(RYGDeveloperRuntimeSurface)self.surfaceValue discoverAdditionalClasses:YES];
    }
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)catalogUpdated:(NSNotification *)note {
    NSNumber *surface = note.userInfo[RYGDeveloperFeatureCatalogSurfaceUserInfoKey];
    if (surface.integerValue != self.surfaceValue) return;
    [self reloadSnapshot];
}

- (void)reloadSnapshot {
    self.methods = [[RYGDeveloperFeatureCatalog sharedCatalog] snapshotForSurface:(RYGDeveloperRuntimeSurface)self.surfaceValue];
    [self applyFilter:self.navigationItem.searchController.searchBar.text ?: @""];
}

- (void)applyFilter:(NSString *)query {
    NSString *needle = query.lowercaseString ?: @"";
    if (!needle.length) self.visibleMethods = self.methods ?: @[];
    else self.visibleMethods = [self.methods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeBoolMethod *method, __unused NSDictionary *bindings) {
        return [method.className.lowercaseString containsString:needle] || [method.selectorName.lowercaseString containsString:needle];
    }]];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter:searchController.searchBar.text ?: @""]; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.surfaceValue < 0 ? 8 : self.visibleMethods.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.surfaceValue < 0) return @"Known owners prewarm only after Developer opens. A scoped app-image class walk runs on a private queue only when a domain is opened; Runtime Browser is not required.";
    BOOL busy = [[RYGDeveloperFeatureCatalog sharedCatalog] isRefreshingSurface:(RYGDeveloperRuntimeSurface)self.surfaceValue];
    return busy ? @"Refreshing loaded app classes in background…" : @"Only BOOL-compatible direct methods with live Objective-C encodings are shown. Overrides are persisted against LC_UUID + class + +/-selector + encoding.";
}

- (void)showHookError:(NSError *)error {
    if (!error) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Override unavailable" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIButton *)buttonForMethod:(RYGRuntimeBoolMethod *)method {
    RYGDeveloperHookRegistry *registry = RYGDeveloperHookRegistry.sharedRegistry;
    NSNumber *forced = [registry overrideValueForMethod:method];
    NSString *title = forced ? (forced.boolValue ? @"Forced On" : @"Forced Off") : @"Native";
    __weak typeof(self) weakSelf = self;

    UIAction *useNative = [UIAction actionWithTitle:@"Use Native" image:nil identifier:nil handler:^(__unused UIAction *action) {
        NSError *error = nil;
        if (![registry setOverrideValue:nil forMethod:method error:&error]) [weakSelf showHookError:error];
        [weakSelf.tableView reloadData];
    }];
    UIAction *forceOn = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *action) {
        NSError *error = nil;
        if (![registry setOverrideValue:@YES forMethod:method error:&error]) [weakSelf showHookError:error];
        [weakSelf.tableView reloadData];
    }];
    UIAction *forceOff = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *action) {
        NSError *error = nil;
        if (![registry setOverrideValue:@NO forMethod:method error:&error]) [weakSelf showHookError:error];
        [weakSelf.tableView reloadData];
    }];
    useNative.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    forceOn.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    forceOff.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIMenu *output = [UIMenu menuWithTitle:@"Output" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[useNative, forceOn, forceOff]];
    button.menu = [UIMenu menuWithTitle:method.selectorName ?: @"BOOL" image:nil identifier:nil options:0 children:@[output]];
    button.showsMenuAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = title;
        configuration.baseForegroundColor = UIColor.labelColor;
        button.configuration = configuration;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
    }
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGDevCatalog"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGDevCatalog"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (self.surfaceValue < 0) {
        RYGDeveloperRuntimeSurface surface = (RYGDeveloperRuntimeSurface)indexPath.row;
        cell.textLabel.text = RYGCatalogTitle(surface);
        cell.detailTextLabel.text = @"Live Developer catalogue";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    RYGRuntimeBoolMethod *method = self.visibleMethods[(NSUInteger)indexPath.row];
    cell.textLabel.text = method.selectorName;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", method.className, method.classMethod ? @"class" : @"instance", method.typeEncoding ?: @""];
    cell.detailTextLabel.numberOfLines = 3;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = [self buttonForMethod:method];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.surfaceValue >= 0) return;
    RYGDeveloperFeatureCatalogViewController *next = [[RYGDeveloperFeatureCatalogViewController alloc] initWithSurface:(RYGDeveloperRuntimeSurface)indexPath.row];
    [self.navigationController pushViewController:next animated:YES];
}

@end
