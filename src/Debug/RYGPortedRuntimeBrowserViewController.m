#import "RYGPortedRuntimeBrowserViewController.h"
#import "RYGRuntimeSurface.h"
#import "RYGRuntimeSurfaceBrowserViewController.h"
#import "RYGRuntimeValueStore.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGPortedRuntimeBrowserViewController ()
@property(nonatomic, copy) NSString *browserTitle;
@property(nonatomic, copy) NSString *initialQuery;
@property(nonatomic, copy) NSArray<RYGRuntimeSurfaceSpec *> *surfaces;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) BOOL pushedInitialQuery;
@property(nonatomic, assign) BOOL loading;
@property(nonatomic, assign) NSUInteger generation;
@end

@implementation RYGPortedRuntimeBrowserViewController

- (instancetype)init {
    return [self initWithTitle:@"Runtime Browser" initialQuery:@""];
}

- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery {
    return [self initWithTitle:title initialQuery:initialQuery allowsBulkVisibilityOverride:NO];
}

- (instancetype)initWithTitle:(NSString *)title
                 initialQuery:(NSString *)initialQuery
allowsBulkVisibilityOverride:(BOOL)allowsBulkVisibilityOverride {
    (void)allowsBulkVisibilityOverride;
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        NSString *copy = [title copy];
        _browserTitle = copy.length ? copy : @"Runtime Browser";
        _initialQuery = [initialQuery copy] ?: @"";
        _surfaces = @[];
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
    self.tableView.estimatedRowHeight = 58.0;

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                             target:self
                             action:@selector(loadSurfaces)];
    UIBarButtonItem *apply = [[UIBarButtonItem alloc]
        initWithTitle:@"Apply"
                style:UIBarButtonItemStyleDone
               target:self
               action:@selector(applyAllPersisted)];
    self.navigationItem.rightBarButtonItems = @[apply, refresh];

    UIRefreshControl *pull = [UIRefreshControl new];
    [pull addTarget:self action:@selector(loadSurfaces) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = pull;

    RYGLiquidGlassApplyToViewController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Feature-domain routes use the same WAT-derived detail browser but skip the
    // raw image picker. The expensive cross-image getter scan begins only after
    // the user has explicitly entered that domain screen.
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
    if (self.loading) return;
    self.loading = YES;
    NSUInteger generation = ++self.generation;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [spinner startAnimating];
    self.tableView.backgroundView = spinner;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Unlike the previous rewrite, this is image-first. It does not enumerate
        // every getter in Instagram just to populate the WAT raw-surface list.
        NSArray<RYGRuntimeSurfaceSpec *> *surfaces = [RYGRuntimeScanner runtimeImageSurfaces] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.loading = NO;
            [self.refreshControl endRefreshing];
            self.surfaces = surfaces;

            if (surfaces.count) {
                self.tableView.backgroundView = nil;
            } else {
                UILabel *empty = [UILabel new];
                empty.text = @"No Instagram-owned Objective-C runtime images were resolved.";
                empty.textColor = UIColor.secondaryLabelColor;
                empty.textAlignment = NSTextAlignmentCenter;
                empty.numberOfLines = 0;
                self.tableView.backgroundView = empty;
            }
            [self.tableView reloadData];
        });
    });
}

- (void)applyAllPersisted {
    NSUInteger persisted = RYGRuntimeValueAllOverrideSpecs().count;
    NSUInteger installed = RYGRuntimeValueReinstallPersistedHooks();
    NSUInteger pending = persisted >= installed ? persisted - installed : 0;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apply Saved Runtime"
                                                                   message:[NSString stringWithFormat:
        @"Persisted typed overrides: %lu\nInstalled/reapplied: %lu\nPending: %lu",
        (unsigned long)persisted,
        (unsigned long)installed,
        (unsigned long)pending]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)self.surfaces.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if (self.loading) return @"Reading loaded Objective-C images…";
    if (!self.surfaces.count) return @"Runtime surfaces";
    return [NSString stringWithFormat:@"Runtime surfaces · %lu loaded images",
            (unsigned long)self.surfaces.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return @"WAT dogfood2 raw-runtime hierarchy adapted to Instagram scale: the root lists loaded Mach-O images first. Typed getters are enumerated only after a surface is opened; Refresh rebuilds the live image inventory.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGWATRawSurface";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }

    RYGRuntimeSurfaceSpec *surface = self.surfaces[(NSUInteger)indexPath.row];
    cell.textLabel.text = surface.title ?: @"Runtime";
    cell.detailTextLabel.text = surface.subtitle ?: @"";
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 1;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = [UIImage systemImageNamed:surface.icon ?: @"shippingbox"];
    cell.imageView.tintColor = UIColor.secondaryLabelColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.surfaces.count) return;
    RYGRuntimeSurfaceSpec *surface = self.surfaces[(NSUInteger)indexPath.row];
    RYGRuntimeSurfaceBrowserViewController *detail = [[RYGRuntimeSurfaceBrowserViewController alloc]
        initWithSpec:surface initialQuery:@""];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
