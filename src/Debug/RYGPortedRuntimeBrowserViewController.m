#import "RYGPortedRuntimeBrowserViewController.h"
#import "RYGRuntimeSurface.h"
#import "RYGCompleteRuntimeSurfaceBrowserViewController.h"
#import "RYGRuntimeValueStore.h"
#import "RYGRuntimeMachOInspector.h"
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

- (instancetype)init { return [self initWithTitle:@"Runtime Browser" initialQuery:@""]; }
- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery {
    return [self initWithTitle:title initialQuery:initialQuery allowsBulkVisibilityOverride:NO];
}
- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery allowsBulkVisibilityOverride:(BOOL)allowsBulkVisibilityOverride {
    (void)allowsBulkVisibilityOverride;
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        NSString *copy=[title copy]; _browserTitle=copy.length?copy:@"Runtime Browser"; _initialQuery=[initialQuery copy]?:@""; _surfaces=@[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad]; self.title=self.browserTitle; self.navigationItem.titleView=RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor=[RYGPopupChrome backgroundColor]; self.tableView.backgroundColor=[RYGPopupChrome backgroundColor];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=58.0;
    UIBarButtonItem *refresh=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadSurfaces)];
    UIBarButtonItem *apply=[[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(applyAllPersisted)];
    self.navigationItem.rightBarButtonItems=@[apply,refresh];
    UIRefreshControl *pull=[UIRefreshControl new]; [pull addTarget:self action:@selector(loadSurfaces) forControlEvents:UIControlEventValueChanged]; self.refreshControl=pull;
    RYGLiquidGlassApplyToViewController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(self.initialQuery.length&&!self.pushedInitialQuery){
        self.pushedInitialQuery=YES;
        RYGRuntimeSurfaceSpec *spec=[RYGRuntimeScanner allAppSurfaceWithTitle:self.browserTitle query:self.initialQuery];
        // Critical contract: domain text is presentation-only. The scanner first
        // builds the complete whole-host catalog; this initial query is applied
        // afterwards by the WAT-derived browser.
        RYGCompleteRuntimeSurfaceBrowserViewController *detail=[[RYGCompleteRuntimeSurfaceBrowserViewController alloc] initWithSpec:spec initialQuery:self.initialQuery];
        [self.navigationController pushViewController:detail animated:YES]; return;
    }
    if(!self.started){self.started=YES;[self loadSurfaces];}
}

- (void)loadSurfaces {
    if(self.loading)return; self.loading=YES; NSUInteger generation=++self.generation;
    UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; [spinner startAnimating]; self.tableView.backgroundView=spinner; [self.tableView reloadData];
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSArray *surfaces=[RYGRuntimeScanner runtimeImageSurfaces]?:@[];
        dispatch_async(dispatch_get_main_queue(), ^{__strong typeof(weakSelf) self=weakSelf;if(!self||generation!=self.generation)return;self.loading=NO;[self.refreshControl endRefreshing];self.surfaces=surfaces;
            if(surfaces.count)self.tableView.backgroundView=nil;else{UILabel *empty=[UILabel new];empty.text=@"No Instagram-owned Mach-O image is currently loaded.";empty.textColor=UIColor.secondaryLabelColor;empty.textAlignment=NSTextAlignmentCenter;empty.numberOfLines=0;self.tableView.backgroundView=empty;}[self.tableView reloadData];});
    });
}

- (void)applyAllPersisted {
    NSUInteger objcPersisted=RYGRuntimeValueAllOverrideSpecs().count;
    NSUInteger objcInstalled=RYGRuntimeValueReinstallPersistedHooks();
    NSUInteger cPersisted=RYGRuntimeMachOPersistedOverrideCount();
    NSUInteger cInstalled=RYGRuntimeMachOApplyPersistedOverrides();
    NSUInteger persisted=objcPersisted+cPersisted, installed=objcInstalled+cInstalled, pending=persisted>=installed?persisted-installed:0;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Apply Saved Runtime"
                                                                 message:[NSString stringWithFormat:@"Objective-C: %lu saved · %lu installed\nC imports: %lu saved · %lu rebound\nPending/build-mismatch: %lu",(unsigned long)objcPersisted,(unsigned long)objcInstalled,(unsigned long)cPersisted,(unsigned long)cInstalled,(unsigned long)pending]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{(void)tableView;return 1;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{(void)tableView;(void)section;return self.surfaces.count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{(void)tableView;(void)section;if(self.loading)return @"Reading loaded Mach-O images…";return [NSString stringWithFormat:@"Runtime surfaces · %lu loaded images",(unsigned long)self.surfaces.count];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{(void)tableView;(void)section;return @"WAT dogfood2 image-first runtime, adapted for Instagram. Opening an image builds its complete Objective-C ABI catalog. The image inspector also exposes C symbols/import bind slots/stubs/function starts and the build-aware static inventory. Feature-domain text never constrains discovery.";}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"RYGWATRawSurface"];if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGWATRawSurface"];
    RYGRuntimeSurfaceSpec *surface=self.surfaces[(NSUInteger)indexPath.row];cell.textLabel.text=surface.title?:@"Runtime";cell.detailTextLabel.text=surface.subtitle?:@"";cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;cell.detailTextLabel.numberOfLines=1;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.imageView.image=[UIImage systemImageNamed:surface.icon?:@"shippingbox"];cell.imageView.tintColor=UIColor.secondaryLabelColor;return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];if(indexPath.row<0||indexPath.row>=(NSInteger)self.surfaces.count)return;
    RYGRuntimeSurfaceSpec *surface=self.surfaces[(NSUInteger)indexPath.row];
    RYGCompleteRuntimeSurfaceBrowserViewController *detail=[[RYGCompleteRuntimeSurfaceBrowserViewController alloc] initWithSpec:surface initialQuery:@""];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
