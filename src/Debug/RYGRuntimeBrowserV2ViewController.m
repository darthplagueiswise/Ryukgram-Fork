#import "RYGRuntimeBrowserV2ViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import <mach-o/dyld.h>

// These controllers are canonical typed/C surfaces already compiled in the
// current Developer runtime implementation. The V2 root only fixes discovery.
@interface RYGPortedRuntimeImageViewController : UITableViewController
- (instancetype)initWithImagePath:(NSString *)path query:(NSString *)query;
@end
@interface RYGRuntimeCSymbolBrowserViewController : UITableViewController
- (instancetype)initWithImagePath:(NSString *)imagePath query:(NSString *)query;
@end

static NSString *RYGV2StandardPath(NSString *path) {
    return path.length ? path.stringByStandardizingPath : @"";
}

static NSArray<NSString *> *RYGV2Tokens(NSString *query) {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in [(query ?: @"").lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
        if (part.length) [tokens addObject:part];
    return tokens.copy;
}

static BOOL RYGV2Matches(NSString *haystack, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *lower = haystack.lowercaseString ?: @"";
    NSString *compact = [[lower componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
    for (NSString *group in tokens) {
        BOOL hit = NO;
        for (NSString *token in [group componentsSeparatedByString:@"|"]) {
            if (!token.length) continue;
            NSString *compactToken = [[token componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
            if ([lower containsString:token] || (compactToken.length && [compact containsString:compactToken])) { hit = YES; break; }
        }
        if (!hit) return NO;
    }
    return YES;
}

static NSArray<NSString *> *RYGV2LoadedAppImages(void) {
    uint32_t count = _dyld_image_count();
    if (!count) return @[];

    const char *rawMain = _dyld_get_image_name(0);
    NSString *mainPath = rawMain ? RYGV2StandardPath([NSString stringWithUTF8String:rawMain]) : @"";
    NSString *appRoot = mainPath.stringByDeletingLastPathComponent;
    NSString *appPrefix = appRoot.length ? [appRoot stringByAppendingString:@"/"] : @"";
    const struct mach_header *mainHeader = _dyld_get_image_header(0);

    NSMutableOrderedSet<NSString *> *images = [NSMutableOrderedSet orderedSet];
    for (uint32_t index = 0; index < count; index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw || !*raw) continue;
        NSString *path = RYGV2StandardPath([NSString stringWithUTF8String:raw]);
        if (!path.length) continue;
        const struct mach_header *header = _dyld_get_image_header(index);
        BOOL isMain = index == 0 || (mainHeader && header == mainHeader);
        BOOL inAppBundle = appPrefix.length && [path hasPrefix:appPrefix];
        if (isMain || inAppBundle) [images addObject:path];
    }

    // Defensive fallback: image zero is the process executable by dyld contract.
    // This guarantees the browser can never report zero solely because an iOS
    // /private/var vs /var pathname differs from NSBundle's spelling.
    if (!images.count && mainPath.length) [images addObject:mainPath];

    return [images.array sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        BOOL leftMain = mainPath.length && [left isEqualToString:mainPath];
        BOOL rightMain = mainPath.length && [right isEqualToString:mainPath];
        if (leftMain != rightMain) return leftMain ? NSOrderedAscending : NSOrderedDescending;
        NSString *ln = left.lastPathComponent.lowercaseString ?: @"";
        NSString *rn = right.lastPathComponent.lowercaseString ?: @"";
        BOOL leftFB = [ln containsString:@"fbsharedframework"];
        BOOL rightFB = [rn containsString:@"fbsharedframework"];
        if (leftFB != rightFB) return leftFB ? NSOrderedAscending : NSOrderedDescending;
        return [left.lastPathComponent localizedCaseInsensitiveCompare:right.lastPathComponent];
    }];
}

@interface RYGRuntimeBrowserV2ViewController () <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *browserTitle;
@property(nonatomic, copy) NSString *initialQuery;
@property(nonatomic, copy) NSArray<NSString *> *images;
@property(nonatomic, copy) NSArray<NSString *> *visibleImages;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, assign) NSUInteger generation;
@property(nonatomic, assign) BOOL started;
@end

@implementation RYGRuntimeBrowserV2ViewController

- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        NSString *copy = [title copy];
        _browserTitle = copy.length ? copy : @"Runtime Browser";
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
    waiting.text = @"Reading dyld images after the browser is visible…";
    waiting.textColor = UIColor.secondaryLabelColor;
    waiting.textAlignment = NSTextAlignmentCenter;
    waiting.numberOfLines = 0;
    self.tableView.backgroundView = waiting;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(loadImages)];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.started) { self.started = YES; [self loadImages]; }
}

- (void)loadImages {
    NSUInteger generation = ++self.generation;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSString *> *images = RYGV2LoadedAppImages();
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.images = images ?: @[];
            [self.spinner stopAnimating];
            [self applyFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    NSArray<NSString *> *tokens = RYGV2Tokens(self.search.searchBar.text ?: @"");
    if (!tokens.count) self.visibleImages = self.images ?: @[];
    else self.visibleImages = [self.images filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *path, NSDictionary *bindings) {
        (void)bindings;
        return RYGV2Matches([NSString stringWithFormat:@"%@ %@", path.lastPathComponent ?: @"", path], tokens);
    }]];

    if (self.visibleImages.count) self.tableView.backgroundView = nil;
    else {
        UILabel *empty = [UILabel new];
        empty.text = self.images.count ? @"No loaded image matches this filter." : @"dyld returned no app-bundle image. Refresh to retry.";
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
    return @"The root list comes directly from dyld image 0 and the same .app path, so NSBundle pathname aliases cannot hide Instagram or FBSharedFramework. Getter/symbol scans remain off the main thread.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGRuntimeV2Image"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGRuntimeV2Image"];
    NSString *path = self.visibleImages[(NSUInteger)indexPath.row];
    cell.textLabel.text = path.lastPathComponent.length ? path.lastPathComponent : @"Runtime image";
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

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:path.lastPathComponent ?: @"Runtime image"
                                                                    message:self.initialQuery.length ? [NSString stringWithFormat:@"Initial filter: %@", self.initialQuery] : @"Choose runtime surface"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Typed Objective-C getters" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGPortedRuntimeImageViewController *detail = [[RYGPortedRuntimeImageViewController alloc] initWithImagePath:path query:self.initialQuery];
        [self.navigationController pushViewController:detail animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"C symbols / imports" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeCSymbolBrowserViewController *detail = [[RYGRuntimeCSymbolBrowserViewController alloc] initWithImagePath:path query:self.initialQuery];
        [self.navigationController pushViewController:detail animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
