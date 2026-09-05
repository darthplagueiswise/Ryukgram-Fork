#import "RYGRuntimeBrowserEntryViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeValueStore.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

@interface RYGPortedRuntimeImageViewController : UITableViewController
- (instancetype)initWithImagePath:(NSString *)path query:(NSString *)query;
@end

static NSArray<NSString *> *RYGRuntimeEntryTokens(NSString *query) {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in [(query ?: @"").lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
        if (part.length) [tokens addObject:part];
    return tokens.copy;
}

static BOOL RYGRuntimeEntryMatches(NSString *haystack, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *lower = haystack.lowercaseString ?: @"";
    NSString *compact = [[lower componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
    for (NSString *group in tokens) {
        BOOL matched = NO;
        for (NSString *token in [group componentsSeparatedByString:@"|"]) {
            if (!token.length) continue;
            NSString *compactToken = [[token componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
            if ([lower containsString:token] || (compactToken.length && [compact containsString:compactToken])) { matched = YES; break; }
        }
        if (!matched) return NO;
    }
    return YES;
}

static void RYGRuntimePushOrPresent(UIViewController *owner, UIViewController *next) {
    if (!owner || !next) return;
    if (owner.navigationController) {
        [owner.navigationController pushViewController:next animated:YES];
        return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:next];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}

#pragma mark - C symbol surface

@interface RYGRuntimeCSymbolBrowserViewController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *imagePath;
@property(nonatomic, copy) NSString *initialQuery;
@property(nonatomic, copy) NSArray<RYGMachOSymbol *> *symbols;
@property(nonatomic, copy) NSArray<RYGMachOSymbol *> *visibleSymbols;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, assign) NSUInteger generation;
- (instancetype)initWithImagePath:(NSString *)imagePath query:(NSString *)query;
@end

@implementation RYGRuntimeCSymbolBrowserViewController

- (instancetype)initWithImagePath:(NSString *)imagePath query:(NSString *)query {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _imagePath = [imagePath copy] ?: @"";
        _initialQuery = [query copy] ?: @"";
        _symbols = @[];
        _visibleSymbols = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [RYGRuntimeBrowserEngine shortNameForImagePath:self.imagePath];
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"C symbol";
    search.searchBar.text = self.initialQuery;
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.search = search;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadSymbols)];
    RYGLiquidGlassApplyToViewController(self);
    [self loadSymbols];
}

- (void)loadSymbols {
    NSUInteger generation = ++self.generation;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    NSString *image = self.imagePath.copy;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGMachOSymbol *> *symbols = [RYGRuntimeBrowserEngine machOSymbolsForImagePath:image] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.symbols = symbols;
            [self.spinner stopAnimating];
            [self applyFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    NSArray<NSString *> *tokens = RYGRuntimeEntryTokens(self.search.searchBar.text ?: @"");
    if (!tokens.count) self.visibleSymbols = self.symbols ?: @[];
    else self.visibleSymbols = [self.symbols filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMachOSymbol *symbol, NSDictionary *bindings) {
        (void)bindings;
        return RYGRuntimeEntryMatches([NSString stringWithFormat:@"%@ %@", symbol.name ?: @"", symbol.kind ?: @""], tokens);
    }]];
    if (self.visibleSymbols.count) self.tableView.backgroundView = nil;
    else {
        UILabel *empty = [UILabel new];
        empty.text = @"No C symbol matches this filter.";
        empty.textColor = UIColor.secondaryLabelColor;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.numberOfLines = 0;
        self.tableView.backgroundView = empty;
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.visibleSymbols.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    NSUInteger rebindable = 0;
    for (RYGMachOSymbol *symbol in self.visibleSymbols) if (symbol.isRebindableImport) rebindable++;
    return [NSString stringWithFormat:@"%lu symbols · %lu rebindable imports", (unsigned long)self.visibleSymbols.count, (unsigned long)rebindable];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"Mach-O does not encode C prototypes. Only imported pointer slots are writable here, and BOOL ABI must be selected explicitly; signed __TEXT is never patched.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGRuntimeCEntry"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGRuntimeCEntry"];
    RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
    cell.textLabel.text = symbol.name ?: @"symbol";
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;
    NSString *override = symbol.overrideValue ? (symbol.overrideValue.boolValue ? @"forced true" : @"forced false") : @"native";
    cell.detailTextLabel.text = symbol.isRebindableImport
        ? [NSString stringWithFormat:@"rebindable import · %@", override]
        : [NSString stringWithFormat:@"%@ · 0x%llx", symbol.kind ?: @"symbol", (unsigned long long)symbol.address];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = symbol.isRebindableImport ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle = symbol.isRebindableImport ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)applyValue:(NSNumber *)value symbol:(RYGMachOSymbol *)symbol abi:(RYGCFunctionABI)abi {
    if (![RYGRuntimeBrowserEngine setCOverride:value forSymbol:symbol abi:abi]) {
        [RYGUtils showErrorHUDWithDescription:@"C import rebinding failed for this image/ABI"];
        return;
    }
    [self.tableView reloadData];
}

- (void)presentABIForValue:(NSNumber *)value symbol:(RYGMachOSymbol *)symbol source:(UIView *)source {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:value.boolValue ? @"Force C BOOL true" : @"Force C BOOL false"
                                                                    message:@"Choose only an ABI confirmed by disassembly. Arguments are integer/pointer-register classes only."
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"BOOL f(void)", @"BOOL f(x0)", @"BOOL f(x0,x1)", @"BOOL f(x0,x1,x2)", @"BOOL f(x0,x1,x2,x3)"];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        [sheet addAction:[UIAlertAction actionWithTitle:titles[(NSUInteger)i] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self applyValue:value symbol:symbol abi:(RYGCFunctionABI)(RYGCFunctionABIBool0 + i)];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = source ?: self.view;
        sheet.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
    if (!symbol.isRebindableImport) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name message:@"C import output" preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self applyValue:nil symbol:symbol abi:RYGCFunctionABIUnknown];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force True…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self presentABIForValue:@YES symbol:symbol source:cell];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force False…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self presentABIForValue:@NO symbol:symbol source:cell];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Immediate runtime entry

@interface RYGRuntimeBrowserEntryViewController () <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *browserTitle;
@property(nonatomic, copy) NSString *initialQuery;
@property(nonatomic, copy) NSArray<NSString *> *images;
@property(nonatomic, copy) NSArray<NSString *> *visibleImages;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, assign) NSUInteger generation;
@property(nonatomic, assign) BOOL started;
@end

@implementation RYGRuntimeBrowserEntryViewController

- (instancetype)init { return [self initWithTitle:@"Runtime Browser" initialQuery:@""]; }

- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        NSString *copied = [title copy];
        _browserTitle = copied.length ? copied : @"Runtime Browser";
        _initialQuery = [initialQuery copy] ?: @"";
        _images = @[];
        _visibleImages = @[];
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
    self.tableView.estimatedRowHeight = 62.0;

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Loaded executable or framework";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.search = search;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    UILabel *waiting = [UILabel new];
    waiting.text = @"Runtime discovery starts after this screen is visible.";
    waiting.textColor = UIColor.secondaryLabelColor;
    waiting.textAlignment = NSTextAlignmentCenter;
    waiting.numberOfLines = 0;
    self.tableView.backgroundView = waiting;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(forceReload)];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.started) {
        self.started = YES;
        [self loadImages];
    }
}

- (void)forceReload {
    [RYGRuntimeBrowserEngine invalidateRuntimeCaches];
    [self loadImages];
}

- (void)loadImages {
    NSUInteger generation = ++self.generation;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *images = [RYGRuntimeBrowserEngine runtimeImagePaths] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.images = images;
            [self.spinner stopAnimating];
            [self applyFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    NSArray<NSString *> *tokens = RYGRuntimeEntryTokens(self.search.searchBar.text ?: @"");
    if (!tokens.count) self.visibleImages = self.images ?: @[];
    else self.visibleImages = [self.images filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *path, NSDictionary *bindings) {
        (void)bindings;
        return RYGRuntimeEntryMatches([NSString stringWithFormat:@"%@ %@", [RYGRuntimeBrowserEngine shortNameForImagePath:path], path], tokens);
    }]];
    if (self.visibleImages.count) self.tableView.backgroundView = nil;
    else {
        UILabel *empty = [UILabel new];
        empty.text = self.images.count ? @"No loaded image matches this filter." : @"No bundled runtime image is currently loaded.";
        empty.textColor = UIColor.secondaryLabelColor;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.numberOfLines = 0;
        self.tableView.backgroundView = empty;
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.visibleImages.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; (void)section; return [NSString stringWithFormat:@"%lu loaded images", (unsigned long)self.visibleImages.count]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return @"Opening this screen never scans Objective-C classes on the main thread. Pick an image, then choose typed getters or C symbols. Typed getter enumeration stays off the main thread as well.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGRuntimeImageEntry"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGRuntimeImageEntry"];
    NSString *path = self.visibleImages[(NSUInteger)indexPath.row];
    cell.textLabel.text = [RYGRuntimeBrowserEngine shortNameForImagePath:path];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    cell.detailTextLabel.text = path;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *path = self.visibleImages[(NSUInteger)indexPath.row];
    if (!path.length) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[RYGRuntimeBrowserEngine shortNameForImagePath:path]
                                                                    message:self.initialQuery.length ? [NSString stringWithFormat:@"Initial filter: %@", self.initialQuery] : @"Choose runtime surface"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Typed Objective-C getters" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGPortedRuntimeImageViewController *detail = [[RYGPortedRuntimeImageViewController alloc] initWithImagePath:path query:self.initialQuery];
        RYGRuntimePushOrPresent(self, detail);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"C symbols / imports" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeCSymbolBrowserViewController *detail = [[RYGRuntimeCSymbolBrowserViewController alloc] initWithImagePath:path query:self.initialQuery];
        RYGRuntimePushOrPresent(self, detail);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
