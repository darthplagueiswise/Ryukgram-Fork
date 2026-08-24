#import "RYGCFunctionsViewController.h"
#import "RYGCFunctionResolver.h"
#import "RYGRuntimeBrowserEngine.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGCFunctionsViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSArray<RYGCFunctionRow *> *functions;
@property (nonatomic, copy) NSArray<RYGCFunctionRow *> *visibleFunctions;
@property (nonatomic, assign) NSUInteger loadGeneration;
@end

@implementation RYGCFunctionsViewController

- (instancetype)initWithImagePath:(NSString *)imagePath {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _imagePath = [imagePath copy];
    return self;
}

- (instancetype)init { return [self initWithImagePath:nil]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"C Functions";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 62.0;
    RYGLiquidGlassApplyToViewController(self);

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Imported C symbol";
    self.navigationItem.searchController = search;
    self.definesPresentationContext = YES;

    NSArray<NSString *> *images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    if (!self.imagePath.length) self.imagePath = images.firstObject;
    [self rebuildImageMenu];
    [self reloadFunctions:NO];
}

- (void)rebuildImageMenu {
    NSArray<NSString *> *images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSString *path in images) {
        UIAction *action = [UIAction actionWithTitle:[RYGRuntimeBrowserEngine shortNameForImagePath:path]
                                               image:nil
                                          identifier:nil
                                             handler:^(__unused UIAction *selected) {
            weakSelf.imagePath = path;
            [weakSelf rebuildImageMenu];
            [weakSelf reloadFunctions:NO];
        }];
        action.state = [path isEqualToString:self.imagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    UIMenu *menu = [UIMenu menuWithTitle:@"Image" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = self.imagePath.length ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.imagePath] : @"Image";
        button.configuration = configuration;
    } else {
        [button setTitle:self.imagePath.length ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.imagePath] : @"Image" forState:UIControlStateNormal];
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)reloadFunctions:(BOOL)invalidate {
    NSString *path = self.imagePath;
    if (!path.length) {
        self.functions = @[];
        self.visibleFunctions = @[];
        [self.tableView reloadData];
        return;
    }
    if (invalidate) [RYGCFunctionResolver invalidateImagePath:path];
    NSUInteger generation = ++self.loadGeneration;
    self.functions = @[];
    self.visibleFunctions = @[];
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *resolved = [RYGCFunctionResolver functionsForImagePath:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.loadGeneration || ![path isEqualToString:self.imagePath]) return;
            self.functions = resolved ?: @[];
            [self applyFilter:self.navigationItem.searchController.searchBar.text ?: @""];
        });
    });
}

- (void)applyFilter:(NSString *)query {
    NSString *needle = query.lowercaseString ?: @"";
    if (!needle.length) self.visibleFunctions = self.functions ?: @[];
    else self.visibleFunctions = [self.functions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGCFunctionRow *row, __unused NSDictionary *bindings) {
        return [row.symbolName.lowercaseString containsString:needle] || [row.evidence.lowercaseString containsString:needle];
    }]];
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter:searchController.searchBar.text ?: @""];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.visibleFunctions.count; }

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (!self.functions.count) return @"Resolving import stubs and direct ARM64 call sites on demand…";
    NSUInteger hookable = 0;
    for (RYGCFunctionRow *row in self.functions) if (row.predicateHookable) hookable++;
    return [NSString stringWithFormat:@"%lu imported functions · %lu ABI-verified predicate hooks. Local/exported C functions are intentionally not patched through fishhook.", (unsigned long)self.functions.count, (unsigned long)hookable];
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"C hook unavailable" message:error.localizedDescription ?: @"The import could not be rebound safely." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIButton *)buttonForFunction:(RYGCFunctionRow *)row {
    NSNumber *forced = row.overrideValue;
    __weak typeof(self) weakSelf = self;
    UIAction *native = [UIAction actionWithTitle:@"Use Native" image:nil identifier:nil handler:^(__unused UIAction *action) {
        NSError *error = nil;
        if (![RYGCFunctionResolver setOverride:nil forFunction:row error:&error]) [weakSelf showError:error];
        [weakSelf.tableView reloadData];
    }];
    UIAction *on = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *action) {
        NSError *error = nil;
        if (![RYGCFunctionResolver setOverride:@YES forFunction:row error:&error]) [weakSelf showError:error];
        [weakSelf.tableView reloadData];
    }];
    UIAction *off = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *action) {
        NSError *error = nil;
        if (![RYGCFunctionResolver setOverride:@NO forFunction:row error:&error]) [weakSelf showError:error];
        [weakSelf.tableView reloadData];
    }];
    native.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    on.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    off.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.menu = [UIMenu menuWithTitle:row.symbolName image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[native, on, off]];
    button.showsMenuAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    NSString *title = forced ? (forced.boolValue ? @"On" : @"Off") : @"Native";
    if (configuration) { configuration.title = title; button.configuration = configuration; }
    else [button setTitle:title forState:UIControlStateNormal];
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGCFunction"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGCFunction"];
    RYGCFunctionRow *row = self.visibleFunctions[(NSUInteger)indexPath.row];
    cell.textLabel.text = row.symbolName;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = row.evidence;
    cell.detailTextLabel.numberOfLines = 3;
    cell.detailTextLabel.textColor = row.predicateHookable ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = row.predicateHookable ? [self buttonForFunction:row] : nil;
    return cell;
}

@end
