#import "RYGPortedRuntimeBrowserViewController.h"
#import "RYGRuntimeSurface.h"
#import "RYGRuntimeSurfaceBrowserViewController.h"
#import "RYGRuntimeValueStore.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGPortedRuntimeBrowserViewController () <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *browserTitle;
@property(nonatomic, copy) NSString *initialQuery;
@property(nonatomic, copy) NSArray<RYGRuntimeSurfaceSpec *> *surfaces;
@property(nonatomic, copy) NSArray<RYGRuntimeSurfaceSpec *> *visibleSurfaces;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) BOOL pushedInitialQuery;
@property(nonatomic, assign) NSUInteger generation;
@end

@implementation RYGPortedRuntimeBrowserViewController

- (instancetype)init { return [self initWithTitle:@"Runtime Browser" initialQuery:@""]; }

- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery {
    return [self initWithTitle:title initialQuery:initialQuery allowsBulkVisibilityOverride:NO];
}

- (instancetype)initWithTitle:(NSString *)title
                 initialQuery:(NSString *)initialQuery
allowsBulkVisibilityOverride:(BOOL)bulk {
    (void)bulk;
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        NSString *copy = [title copy];
        _browserTitle = copy.length ? copy : @"Runtime Browser";
        _initialQuery = [initialQuery copy] ?: @"";
        _surfaces = @[];
        _visibleSurfaces = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.browserTitle;
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68.0;

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Loaded Instagram runtime image";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.search = search;

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                              target:self
                                                                              action:@selector(loadSurfaces)];
    UIBarButtonItem *apply = [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                                              style:UIBarButtonItemStyleDone
                                                             target:self
                                                             action:@selector(applyAllPersisted)];
    self.navigationItem.rightBarButtonItems = @[apply, refresh];

    UILabel *waiting = [UILabel new];
    waiting.text = @"Runtime discovery starts after this screen is visible.";
    waiting.textColor = UIColor.secondaryLabelColor;
    waiting.textAlignment = NSTextAlignmentCenter;
    waiting.numberOfLines = 0;
    self.tableView.backgroundView = waiting;
    RYGLiquidGlassApplyToViewController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.initialQuery.length && !self.pushedInitialQuery) {
        self.pushedInitialQuery = YES;
        RYGRuntimeSurfaceSpec *spec = [RYGRuntimeScanner allAppSurfaceWithTitle:self.browserTitle
                                                                          query:self.initialQuery];
        RYGRuntimeSurfaceBrowserViewController *detail = [[RYGRuntimeSurfaceBrowserViewController alloc]
            initWithSpec:spec initialQuery:self.initialQuery];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    if (!self.started) {
        self.started = YES;
        [self loadSurfaces];
    }
}

- (void)loadSurfaces {
    NSUInteger generation = ++self.generation;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.tableView.backgroundView = spinner;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGRuntimeSurfaceSpec *> *surfaces = [RYGRuntimeScanner runtimeImageSurfaces] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.surfaces = surfaces;
            [self applyFilter];
        });
    });
}

- (void)applyAllPersisted {
    NSUInteger persisted = RYGRuntimeValueAllOverrideSpecs().count;
    NSUInteger installed = RYGRuntimeValueReinstallPersistedHooks();
    NSUInteger pending = persisted >= installed ? persisted - installed : 0;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apply Saved Runtime"
                                                                   message:[NSString stringWithFormat:@"Persisted typed overrides: %lu\nInstalled/reapplied: %lu\nPending: %lu",
                                                                            (unsigned long)persisted,
                                                                            (unsigned long)installed,
                                                                            (unsigned long)pending]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyFilter];
}

- (void)applyFilter {
    NSString *query = self.search.searchBar.text.lowercaseString ?: @"";
    if (!query.length) {
        self.visibleSurfaces = self.surfaces;
    } else {
        self.visibleSurfaces = [self.surfaces filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(RYGRuntimeSurfaceSpec *surface, NSDictionary *bindings) {
                (void)bindings;
                NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@",
                    surface.title ?: @"", surface.subtitle ?: @"", surface.runtimeImagePath ?: @""].lowercaseString;
                return [haystack containsString:query];
            }]];
    }

    if (self.visibleSurfaces.count) {
        self.tableView.backgroundView = nil;
    } else {
        UILabel *empty = [UILabel new];
        empty.text = self.surfaces.count ? @"No runtime image matches this filter."
                                         : @"No Instagram-owned Objective-C runtime surface is loaded.";
        empty.textColor = UIColor.secondaryLabelColor;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.numberOfLines = 0;
        self.tableView.backgroundView = empty;
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return (NSInteger)self.visibleSurfaces.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    NSUInteger getters = 0;
    for (RYGRuntimeSurfaceSpec *surface in self.visibleSurfaces) getters += surface.runtimeEntryCount;
    return [NSString stringWithFormat:@"%lu loaded surfaces · %lu typed getters",
            (unsigned long)self.visibleSurfaces.count, (unsigned long)getters];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"Ported from WATweaks dogfood2: surfaces are rebuilt from loaded Objective-C classes and class_getImageName. Each surface exposes typed zero-argument getters, exact hook persistence, explicit Apply/PENDING state and live receiver observation.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGWATSurface"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGWATSurface"];
    RYGRuntimeSurfaceSpec *surface = self.visibleSurfaces[(NSUInteger)indexPath.row];
    cell.textLabel.text = surface.title;
    cell.detailTextLabel.text = surface.subtitle;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGRuntimeSurfaceSpec *surface = self.visibleSurfaces[(NSUInteger)indexPath.row];
    RYGRuntimeSurfaceBrowserViewController *detail = [[RYGRuntimeSurfaceBrowserViewController alloc]
        initWithSpec:surface initialQuery:@""];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
