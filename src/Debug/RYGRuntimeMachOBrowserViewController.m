#import "RYGRuntimeMachOBrowserViewController.h"
#import "RYGRuntimeMachOInspector.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGRuntimeMachOBrowserViewController () <UISearchResultsUpdating, UISearchBarDelegate>
@property(nonatomic, copy) NSString *imagePath;
@property(nonatomic, copy) NSString *imageTitle;
@property(nonatomic, copy) NSArray<RYGRuntimeMachOEntry *> *allEntries;
@property(nonatomic, copy) NSArray<RYGRuntimeMachOEntry *> *visibleEntries;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, assign) BOOL loading;
@end

@implementation RYGRuntimeMachOBrowserViewController

- (instancetype)initWithImagePath:(NSString *)imagePath title:(NSString *)title {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _imagePath=[imagePath copy]?:@""; _imageTitle=[title copy]?:@"Mach-O"; _allEntries=@[]; _visibleEntries=@[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=[NSString stringWithFormat:@"%@ · C",self.imageTitle];
    self.navigationItem.titleView=RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor=[RYGPopupChrome backgroundColor]; self.tableView.backgroundColor=[RYGPopupChrome backgroundColor];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=58.0;
    UISearchController *search=[[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater=self; search.obscuresBackgroundDuringPresentation=NO; search.searchBar.delegate=self;
    search.searchBar.placeholder=@"Symbol, import, stub or function address";
    search.searchBar.scopeButtonTitles=@[@"All",@"Imports",@"Rebindable",@"Stubs",@"Functions"];
    self.navigationItem.searchController=search; self.navigationItem.hidesSearchBarWhenScrolling=NO; self.search=search;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadEntries)];
    self.refreshControl=[UIRefreshControl new]; [self.refreshControl addTarget:self action:@selector(reloadEntries) forControlEvents:UIControlEventValueChanged];
    RYGLiquidGlassApplyToViewController(self); [self reloadEntries];
}

- (void)reloadEntries {
    if(self.loading)return; self.loading=YES;
    UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; [spinner startAnimating]; self.tableView.backgroundView=spinner;
    NSString *path=self.imagePath; __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        [RYGRuntimeBrowserEngine invalidateRuntimeCaches];
        NSArray *entries=RYGRuntimeMachOEntries(path)?:@[];
        dispatch_async(dispatch_get_main_queue(), ^{ __strong typeof(weakSelf) self=weakSelf; if(!self)return; self.loading=NO; [self.refreshControl endRefreshing]; self.allEntries=entries; [self applyFilter]; });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }
- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope { (void)searchBar;(void)selectedScope;[self applyFilter]; }

- (void)applyFilter {
    if(self.loading)return;
    NSString *query=self.search.searchBar.text.lowercaseString?:@""; NSInteger scope=self.search.searchBar.selectedScopeButtonIndex;
    NSMutableArray *out=[NSMutableArray array];
    for(RYGRuntimeMachOEntry *entry in self.allEntries?:@[]) {
        BOOL scopeOK=YES;
        if(scope==1) scopeOK=[entry.kind containsString:@"import"];
        else if(scope==2) scopeOK=entry.isHookableImport;
        else if(scope==3) scopeOK=[entry.kind isEqualToString:@"stub"];
        else if(scope==4) scopeOK=[entry.kind isEqualToString:@"function"];
        if(!scopeOK)continue;
        NSString *blob=[[NSString stringWithFormat:@"%@ %@ %llx",entry.name?:@"",entry.kind?:@"",(unsigned long long)entry.address] lowercaseString];
        if(query.length&&![blob containsString:query])continue;
        [out addObject:entry];
    }
    self.visibleEntries=out.copy;
    if(out.count)self.tableView.backgroundView=nil; else { UILabel *label=[UILabel new]; label.text=@"No Mach-O entry matches this scope."; label.textAlignment=NSTextAlignmentCenter; label.textColor=UIColor.secondaryLabelColor; label.numberOfLines=0; self.tableView.backgroundView=label; }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView;(void)section; return self.visibleEntries.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView;(void)section; return [NSString stringWithFormat:@"%lu Mach-O entries",(unsigned long)self.visibleEntries.count]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;(void)section;
    return @"Symbols/imports come from the live Mach-O. Lazy/non-lazy bind-slot imports may be re-bound with an explicit BOOL integer/pointer-register ABI. Stubs and LC_FUNCTION_STARTS ranges are inspection-only; no prototype is guessed.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"RYGCRuntime"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGCRuntime"];
    RYGRuntimeMachOEntry *entry=self.visibleEntries[(NSUInteger)indexPath.row];
    RYGCFunctionABI abi=RYGCFunctionABIUnknown; NSNumber *forced=RYGRuntimeMachOPersistedOverrideForEntry(entry,&abi);
    cell.textLabel.text=entry.name?:@"?"; cell.textLabel.font=[UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular]; cell.textLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
    NSString *address=entry.address?[NSString stringWithFormat:@"0x%llx",(unsigned long long)entry.address]:@"no address";
    NSString *state=forced?[NSString stringWithFormat:@" · FORCE %@ · ABI %ld",forced.boolValue?@"ON":@"OFF",(long)abi]:@"";
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@%@",entry.kind?:@"symbol",address,state]; cell.detailTextLabel.textColor=forced?UIColor.systemCyanColor:UIColor.secondaryLabelColor;
    cell.accessoryType=entry.isHookableImport?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
    cell.selectionStyle=entry.isHookableImport?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGRuntimeMachOEntry *entry=self.visibleEntries[(NSUInteger)indexPath.row]; if(!entry.isHookableImport)return;
    UIAlertController *abiSheet=[UIAlertController alertControllerWithTitle:entry.name message:@"Mach-O does not carry the C prototype. Choose the exact BOOL ABI explicitly; float/vector/struct ABIs are never guessed." preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf=self;
    for(NSInteger i=0;i<=4;i++) {
        NSString *title=[NSString stringWithFormat:@"BOOL · %ld register arg%@",(long)i,i==1?@"":@"s"];
        RYGCFunctionABI abi=(RYGCFunctionABI)(RYGCFunctionABIBool0+i);
        [abiSheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ [weakSelf presentForceForEntry:entry abi:abi]; }]];
    }
    [abiSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if(UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad){abiSheet.popoverPresentationController.sourceView=self.view;abiSheet.popoverPresentationController.sourceRect=self.view.bounds;}
    [self presentViewController:abiSheet animated:YES completion:nil];
}

- (void)presentForceForEntry:(RYGRuntimeMachOEntry *)entry abi:(RYGCFunctionABI)abi {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:entry.name message:@"Persist first, then rebind the exact lazy/non-lazy import slot." preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf=self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ (void)RYGRuntimeMachOSetPersistedOverride(entry,@YES,abi); [weakSelf.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ (void)RYGRuntimeMachOSetPersistedOverride(entry,@NO,abi); [weakSelf.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Use Original" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){ (void)RYGRuntimeMachOSetPersistedOverride(entry,nil,abi); [weakSelf.tableView reloadData]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if(UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad){sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=self.view.bounds;}
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
