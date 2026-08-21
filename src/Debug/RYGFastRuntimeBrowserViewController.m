#import "RYGFastRuntimeBrowserViewController.h"
#import "RYGRuntimeIndex.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "RYGCImportIndex.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

#import "RYGFastRuntimeClassViewController.h"

typedef NS_ENUM(NSInteger, RYGFastRuntimeMode) {
    RYGFastRuntimeModeObjC = 0,
    RYGFastRuntimeModeCImports,
};

static NSString *const kRYGFastRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";

static NSString *RYGFastImageID(NSString *path) {
    NSString *standard = path.stringByStandardizingPath;
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    return [standard hasPrefix:prefix] ? [standard substringFromIndex:prefix.length] : (standard.lastPathComponent ?: @"");
}

static NSString *RYGFastNormalize(NSString *value) {
    if (!value.length) return @"";
    NSString *lower = value.lowercaseString;
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    BOOL emittedSpace = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar c = [lower characterAtIndex:index];
        BOOL alnum = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        if (alnum) {
            [out appendFormat:@"%C", c];
            emittedSpace = NO;
        } else if (!emittedSpace) {
            [out appendString:@" "];
            emittedSpace = YES;
        }
    }
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSArray<NSString *> *RYGFastTokens(NSString *query) {
    NSString *normalized = RYGFastNormalize(query);
    if (!normalized.length) return @[];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *token in [normalized componentsSeparatedByString:@" "]) if (token.length) [tokens addObject:token];
    return tokens.copy;
}

static BOOL RYGFastMatches(NSString *text, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *normalized = RYGFastNormalize(text);
    NSString *compact = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in tokens) {
        NSString *compactToken = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([normalized rangeOfString:token].location == NSNotFound &&
            [compact rangeOfString:compactToken].location == NSNotFound) return NO;
    }
    return YES;
}

@interface RYGFastRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, strong) RYGRuntimeImageIndex *objcIndex;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *visibleClasses;
@property (nonatomic, copy) NSArray<RYGCImportSymbol *> *cImports;
@property (nonatomic, copy) NSArray<RYGCImportSymbol *> *visibleCImports;
@property (nonatomic, assign) NSTimeInterval cIndexBuildDuration;
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation RYGFastRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Runtime Browser";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.visibleClasses = @[];
    self.cImports = @[];
    self.visibleCImports = @[];

    self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageButton.showsMenuAsPrimaryAction = YES;
    [self.view addSubview:self.imageButton];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Objective-C", @"C Imports"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = RYGFastRuntimeModeObjC;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.imageButton.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8],
        [self.imageButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [self.imageButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [self.modeControl.topAnchor constraintEqualToAnchor:self.imageButton.bottomAnchor constant:8],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [self.tableView.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.searchController = [UISearchController new];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class or BOOL selector";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.emptyLabel = [UILabel new];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(refreshTapped)];

    [self refreshImages];
    [self rebuildImageMenu];
    RYGLiquidGlassApplyToViewController(self);

    // Let the navigation transition complete before the first index build.
    dispatch_async(dispatch_get_main_queue(), ^{ [self loadSelectedImage]; });
}

- (void)refreshImages {
    self.images = [RYGRuntimeBrowserEngine runtimeImagePaths] ?: @[];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kRYGFastRuntimeSelectedImageKey];
    NSString *mainExecutable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if (self.selectedImagePath.length && [self.images containsObject:self.selectedImagePath]) return;

    self.selectedImagePath = nil;
    for (NSString *path in self.images) {
        if (stored.length && [RYGFastImageID(path) isEqualToString:stored]) {
            self.selectedImagePath = path;
            break;
        }
    }
    if (!self.selectedImagePath.length) {
        for (NSString *path in self.images) {
            if ([path.stringByStandardizingPath isEqualToString:mainExecutable]) {
                self.selectedImagePath = path;
                break;
            }
        }
    }
    if (!self.selectedImagePath.length) self.selectedImagePath = self.images.firstObject;
}

- (void)rebuildImageMenu {
    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSString *path in self.images) {
        UIAction *action = [UIAction actionWithTitle:[RYGRuntimeBrowserEngine shortNameForImagePath:path]
                                              image:nil
                                         identifier:nil
                                            handler:^(__unused UIAction *item) {
            weakSelf.selectedImagePath = path;
            [NSUserDefaults.standardUserDefaults setObject:RYGFastImageID(path) forKey:kRYGFastRuntimeSelectedImageKey];
            [weakSelf rebuildImageMenu];
            [weakSelf loadSelectedImage];
        }];
        action.state = [path isEqualToString:self.selectedImagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.imageButton.menu = [UIMenu menuWithTitle:@"Loaded executable and frameworks"
                                           image:nil
                                      identifier:nil
                                         options:UIMenuOptionsSingleSelection
                                        children:actions];
    RYGLiquidGlassConfigureButton(self.imageButton, NO);
    UIButtonConfiguration *configuration = self.imageButton.configuration;
    if (configuration) {
        configuration.title = [NSString stringWithFormat:@"Image: %@",
                               self.selectedImagePath.length ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath] : @"None"];
        configuration.baseForegroundColor = UIColor.labelColor;
        self.imageButton.configuration = configuration;
    }
}

- (void)modeChanged:(UISegmentedControl *)sender {
    (void)sender;
    self.searchController.searchBar.text = @"";
    self.searchController.searchBar.placeholder = self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC
        ? @"Class or BOOL selector"
        : @"Imported C symbol";
    [self loadSelectedImage];
}

- (void)refreshTapped {
    [RYGRuntimeIndex invalidate];
    [RYGCImportIndex invalidate];
    self.objcIndex = nil;
    self.cImports = @[];
    self.visibleClasses = @[];
    self.visibleCImports = @[];
    [self refreshImages];
    [self rebuildImageMenu];
    [self loadSelectedImage];
}

- (void)loadSelectedImage {
    NSString *path = self.selectedImagePath.copy;
    NSUInteger generation = ++self.generation;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    if (!path.length) {
        [self.spinner stopAnimating];
        self.emptyLabel.text = @"No loaded image.";
        self.tableView.backgroundView = self.emptyLabel;
        return;
    }

    __weak typeof(self) weakSelf = self;
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        RYGRuntimeImageIndex *cached = [RYGRuntimeIndex cachedIndexForImagePath:path];
        if (cached) {
            self.objcIndex = cached;
            [self.spinner stopAnimating];
            [self applyFilter];
            return;
        }
        [RYGRuntimeIndex requestIndexForImagePath:path completion:^(RYGRuntimeImageIndex *index) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation || ![self.selectedImagePath isEqualToString:path]) return;
            self.objcIndex = index;
            [self.spinner stopAnimating];
            [self applyFilter];
        }];
        return;
    }

    NSArray<RYGCImportSymbol *> *cachedImports = [RYGCImportIndex cachedIndexForImagePath:path];
    if (cachedImports) {
        self.cImports = cachedImports;
        self.cIndexBuildDuration = 0;
        [self.spinner stopAnimating];
        [self applyFilter];
        return;
    }
    [RYGCImportIndex requestIndexForImagePath:path completion:^(NSArray<RYGCImportSymbol *> *symbols, NSTimeInterval buildDuration) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.generation || ![self.selectedImagePath isEqualToString:path]) return;
        self.cImports = symbols ?: @[];
        self.cIndexBuildDuration = buildDuration;
        [self.spinner stopAnimating];
        [self applyFilter];
    }];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyFilter];
}

- (void)applyFilter {
    NSArray<NSString *> *tokens = RYGFastTokens(self.searchController.searchBar.text ?: @"");
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeCImports) {
        if (!tokens.count) self.visibleCImports = self.cImports;
        else {
            self.visibleCImports = [self.cImports filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGCImportSymbol *symbol, NSDictionary *bindings) {
                (void)bindings;
                NSString *text = [NSString stringWithFormat:@"%@ %@ %@",
                                  symbol.name ?: @"",
                                  symbol.rawName ?: @"",
                                  symbol.bindingKind ?: @""];
                return RYGFastMatches(text, tokens);
            }]];
        }
        self.emptyLabel.text = @"No patchable lazy/non-lazy C import matches.";
        self.tableView.backgroundView = self.visibleCImports.count ? nil : self.emptyLabel;
        [self.tableView reloadData];
        return;
    }

    NSArray<RYGRuntimeClassRow *> *classes = self.objcIndex.classes ?: @[];
    if (!tokens.count) self.visibleClasses = classes;
    else {
        self.visibleClasses = [classes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeClassRow *row, NSDictionary *bindings) {
            (void)bindings;
            if (RYGFastMatches(row.className ?: @"", tokens)) return YES;
            for (RYGRuntimeBoolMethod *method in [self.objcIndex methodsForClassName:row.className]) {
                NSString *text = [NSString stringWithFormat:@"%@ %@ %@",
                                  row.className ?: @"",
                                  method.selectorName ?: @"",
                                  method.typeEncoding ?: @""];
                if (RYGFastMatches(text, tokens)) return YES;
            }
            return NO;
        }]];
    }
    self.emptyLabel.text = @"No ABI-validated BOOL method matched this loaded image.";
    self.tableView.backgroundView = self.visibleClasses.count ? nil : self.emptyLabel;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC
        ? self.visibleClasses.count
        : self.visibleCImports.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeCImports) {
        return [NSString stringWithFormat:@"%lu cached import symbols · %.2fs initial index",
                (unsigned long)self.visibleCImports.count,
                self.cIndexBuildDuration];
    }
    return [NSString stringWithFormat:@"%lu classes · %lu scanned · %lu methods · %.2fs",
            (unsigned long)self.visibleClasses.count,
            (unsigned long)self.objcIndex.classesScanned,
            (unsigned long)self.objcIndex.methodsScanned,
            self.objcIndex.buildDuration];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGFastRuntimeRoot"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastRuntimeRoot"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        RYGRuntimeClassRow *row = self.visibleClasses[(NSUInteger)indexPath.row];
        cell.textLabel.text = row.className;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu instance · %lu class BOOL methods",
                                    (unsigned long)row.instanceMethodCount,
                                    (unsigned long)row.classMethodCount];
    } else {
        RYGCImportSymbol *symbol = self.visibleCImports[(NSUInteger)indexPath.row];
        NSNumber *forced = symbol.overrideValue;
        cell.textLabel.text = symbol.name;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
        NSString *state = forced ? (forced.boolValue ? @"x0=1" : @"x0=0") : @"native";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu slot%@ · %@",
                                    symbol.bindingKind ?: @"import",
                                    (unsigned long)symbol.slotCount,
                                    symbol.slotCount == 1 ? @"" : @"s",
                                    state];
    }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}

- (void)presentCImportActionsForSymbol:(RYGCImportSymbol *)symbol fromCell:(UITableViewCell *)cell {
    NSNumber *forced = symbol.overrideValue;
    NSString *state = forced ? (forced.boolValue ? @"Forced x0 = 1" : @"Forced x0 = 0") : @"Native import pointer";
    NSString *message = [NSString stringWithFormat:
        @"%@\n%lu import slot%@\nfirst slot 0x%llx\ncurrent target 0x%llx\n\n%@\n\nThe patch uses fishhook on this image's lazy/non-lazy import pointers only. It never writes __TEXT. Use Force only when the function returns a scalar in ARM64 x0 (BOOL/integer/pointer-sized result).",
        symbol.bindingKind ?: @"C import",
        (unsigned long)symbol.slotCount,
        symbol.slotCount == 1 ? @"" : @"s",
        (unsigned long long)symbol.firstSlotAddress,
        (unsigned long long)symbol.currentTarget,
        state];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        NSError *error = nil;
        if (![RYGCImportIndex setScalarOverride:nil forSymbol:symbol error:&error]) {
            if (forced) [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not restore C import"];
        }
        [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force x0 = 1"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        NSError *error = nil;
        if (![RYGCImportIndex setScalarOverride:@YES forSymbol:symbol error:&error])
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not patch C import"];
        [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force x0 = 0"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        NSError *error = nil;
        if (![RYGCImportIndex setScalarOverride:@NO forSymbol:symbol error:&error])
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not patch C import"];
        [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = symbol.name ?: @"";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        RYGRuntimeClassRow *row = self.visibleClasses[(NSUInteger)indexPath.row];
        RYGFastRuntimeClassViewController *controller = [[RYGFastRuntimeClassViewController alloc]
            initWithIndex:self.objcIndex
                 classRow:row
             initialQuery:self.searchController.searchBar.text];
        [self.navigationController pushViewController:controller animated:YES];
        return;
    }
    [self presentCImportActionsForSymbol:self.visibleCImports[(NSUInteger)indexPath.row] fromCell:cell];
}

@end
