#import "RYGFastRuntimeBrowserViewController.h"
#import "RYGRuntimeIndex.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

typedef NS_ENUM(NSInteger, RYGFastRuntimeMode) {
    RYGFastRuntimeModeObjC = 0,
    RYGFastRuntimeModeMachO,
};

static NSString *const kRYGFastRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";

static NSString *RYGFastImageID(NSString *path) {
    NSString *standard = path.stringByStandardizingPath;
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    return [standard hasPrefix:prefix] ? [standard substringFromIndex:prefix.length] : (standard.lastPathComponent ?: @"");
}

static NSArray<NSString *> *RYGFastTokens(NSString *query) {
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *part in [query.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (part.length) [tokens addObject:part];
    }
    return tokens.copy;
}

static BOOL RYGFastMatches(NSString *text, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *lower = text.lowercaseString ?: @"";
    NSString *compact = [[lower componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
    for (NSString *token in tokens) {
        NSString *compactToken = [[token componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
        if ([lower rangeOfString:token].location == NSNotFound && [compact rangeOfString:compactToken].location == NSNotFound) return NO;
    }
    return YES;
}

@interface RYGFastRuntimeClassViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) RYGRuntimeImageIndex *index;
@property (nonatomic, strong) RYGRuntimeClassRow *classRow;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *methods;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *visibleMethods;
@property (nonatomic, strong) UISearchController *searchController;
- (instancetype)initWithIndex:(RYGRuntimeImageIndex *)index classRow:(RYGRuntimeClassRow *)row initialQuery:(NSString *)query;
@end

@implementation RYGFastRuntimeClassViewController

- (instancetype)initWithIndex:(RYGRuntimeImageIndex *)index classRow:(RYGRuntimeClassRow *)row initialQuery:(NSString *)query {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _index = index;
        _classRow = row;
        _methods = [index methodsForClassName:row.className];
        _visibleMethods = _methods;
        _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
        _searchController.searchBar.text = query ?: @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.classRow.className ?: @"Class";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"BOOL selector or ABI";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nativeChanged:) name:RYGRuntimeNativeValueDidChangeNotification object:nil];
    [self applyFilter];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)nativeChanged:(NSNotification *)note {
    NSString *key = note.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (key.length && [key containsString:self.classRow.className ?: @""]) [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    NSArray *tokens = RYGFastTokens(self.searchController.searchBar.text ?: @"");
    if (!tokens.count) self.visibleMethods = self.methods;
    else self.visibleMethods = [self.methods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeBoolMethod *method, NSDictionary *bindings) {
        (void)bindings;
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@", method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
        return RYGFastMatches(text, tokens);
    }]];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.visibleMethods.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return [NSString stringWithFormat:@"%lu ABI-validated BOOL methods", (unsigned long)self.visibleMethods.count];
}

- (UIButton *)buttonForMethod:(RYGRuntimeBoolMethod *)method {
    NSNumber *forced = method.overrideValue;
    NSNumber *native = method.liveValue;
    NSString *title = forced ? (forced.boolValue ? @"Forced On" : @"Forced Off") : native ? (native.boolValue ? @"Native On" : @"Native Off") : @"Native";
    __weak typeof(self) weakSelf = self;
    UIAction *observe = [UIAction actionWithTitle:@"Observe native" image:[UIImage systemImageNamed:@"waveform.path.ecg"] identifier:nil handler:^(__unused UIAction *action) {
        RYGRuntimeBeginLiveObservation(@[method]);
        [weakSelf.tableView reloadData];
    }];
    UIAction *useNative = [UIAction actionWithTitle:@"Use Native" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    UIAction *on = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    UIAction *off = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    useNative.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    on.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    off.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIMenu *output = [UIMenu menuWithTitle:@"Output" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[useNative, on, off]];
    button.menu = [UIMenu menuWithTitle:method.selectorName image:nil identifier:nil options:0 children:@[observe, output]];
    button.showsMenuAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) { configuration.title = title; configuration.baseForegroundColor = UIColor.labelColor; button.configuration = configuration; }
    else [button setTitle:title forState:UIControlStateNormal];
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGFastRuntimeMethod"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastRuntimeMethod"];
    RYGRuntimeBoolMethod *method = self.visibleMethods[(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", method.classMethod ? @"+" : @"−", method.selectorName ?: @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = method.typeEncoding ?: @"";
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = [self buttonForMethod:method];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end

@interface RYGFastRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, strong) RYGRuntimeImageIndex *index;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *visibleClasses;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *symbols;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *visibleSymbols;
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation RYGFastRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Runtime Browser";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.visibleClasses = @[]; self.symbols = @[]; self.visibleSymbols = @[];

    self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageButton.showsMenuAsPrimaryAction = YES;
    [self.view addSubview:self.imageButton];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Objective-C", @"Mach-O"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeControl];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.dataSource = self; self.tableView.delegate = self;
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

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class or BOOL selector";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.emptyLabel = [UILabel new]; self.emptyLabel.textAlignment = NSTextAlignmentCenter; self.emptyLabel.numberOfLines = 0; self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(refreshTapped)];

    [self refreshImages];
    [self rebuildImageMenu];
    RYGLiquidGlassApplyToViewController(self);
    [self loadSelectedImage];
}

- (void)refreshImages {
    self.images = [RYGRuntimeBrowserEngine runtimeImagePaths] ?: @[];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kRYGFastRuntimeSelectedImageKey];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if (!self.selectedImagePath.length || ![self.images containsObject:self.selectedImagePath]) {
        self.selectedImagePath = nil;
        for (NSString *path in self.images) if (stored.length && [RYGFastImageID(path) isEqualToString:stored]) { self.selectedImagePath = path; break; }
        if (!self.selectedImagePath.length) for (NSString *path in self.images) if ([path.stringByStandardizingPath isEqualToString:main]) { self.selectedImagePath = path; break; }
        if (!self.selectedImagePath.length) self.selectedImagePath = self.images.firstObject;
    }
}

- (void)rebuildImageMenu {
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSString *path in self.images) {
        UIAction *action = [UIAction actionWithTitle:[RYGRuntimeBrowserEngine shortNameForImagePath:path] image:nil identifier:nil handler:^(__unused UIAction *item) {
            weakSelf.selectedImagePath = path;
            [NSUserDefaults.standardUserDefaults setObject:RYGFastImageID(path) forKey:kRYGFastRuntimeSelectedImageKey];
            [weakSelf rebuildImageMenu];
            [weakSelf loadSelectedImage];
        }];
        action.state = [path isEqualToString:self.selectedImagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.imageButton.menu = [UIMenu menuWithTitle:@"Loaded executable and frameworks" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
    RYGLiquidGlassConfigureButton(self.imageButton, NO);
    UIButtonConfiguration *configuration = self.imageButton.configuration;
    if (configuration) { configuration.title = [NSString stringWithFormat:@"Image: %@", self.selectedImagePath.length ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath] : @"None"]; configuration.baseForegroundColor = UIColor.labelColor; self.imageButton.configuration = configuration; }
}

- (void)modeChanged:(UISegmentedControl *)sender { (void)sender; self.searchController.searchBar.text = @""; self.searchController.searchBar.placeholder = self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC ? @"Class or BOOL selector" : @"Mach-O symbol"; [self loadSelectedImage]; }
- (void)refreshTapped { [RYGRuntimeIndex invalidate]; [self refreshImages]; [self rebuildImageMenu]; [self loadSelectedImage]; }

- (void)loadSelectedImage {
    NSString *path = self.selectedImagePath.copy;
    NSUInteger generation = ++self.generation;
    [self.spinner startAnimating]; self.tableView.backgroundView = self.spinner;
    if (!path.length) { [self.spinner stopAnimating]; self.emptyLabel.text = @"No loaded image."; self.tableView.backgroundView = self.emptyLabel; return; }
    __weak typeof(self) weakSelf = self;
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        [RYGRuntimeIndex requestIndexForImagePath:path completion:^(RYGRuntimeImageIndex *index) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation || ![self.selectedImagePath isEqualToString:path]) return;
            self.index = index; [self.spinner stopAnimating]; [self applyFilter];
        }];
    } else {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSArray *symbols = [RYGRuntimeBrowserEngine machOSymbolsForImagePath:path] ?: @[];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self.generation || ![self.selectedImagePath isEqualToString:path]) return;
                self.symbols = symbols; [self.spinner stopAnimating]; [self applyFilter];
            });
        });
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    NSArray *tokens = RYGFastTokens(self.searchController.searchBar.text ?: @"");
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeMachO) {
        self.visibleSymbols = !tokens.count ? self.symbols : [self.symbols filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMachOSymbol *symbol, NSDictionary *bindings) { (void)bindings; return RYGFastMatches([NSString stringWithFormat:@"%@ %@", symbol.name ?: @"", symbol.kind ?: @""], tokens); }]];
        self.emptyLabel.text = @"No Mach-O symbol matches.";
        self.tableView.backgroundView = self.visibleSymbols.count ? nil : self.emptyLabel;
        [self.tableView reloadData]; return;
    }
    NSArray *classes = self.index.classes ?: @[];
    if (!tokens.count) self.visibleClasses = classes;
    else self.visibleClasses = [classes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeClassRow *row, NSDictionary *bindings) {
        (void)bindings;
        if (RYGFastMatches(row.className ?: @"", tokens)) return YES;
        for (RYGRuntimeBoolMethod *method in [self.index methodsForClassName:row.className]) {
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@", row.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
            if (RYGFastMatches(text, tokens)) return YES;
        }
        return NO;
    }]];
    self.emptyLabel.text = @"No ABI-validated BOOL method matched this loaded image.";
    self.tableView.backgroundView = self.visibleClasses.count ? nil : self.emptyLabel;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC ? self.visibleClasses.count : self.visibleSymbols.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeMachO) return [NSString stringWithFormat:@"%lu Mach-O symbols", (unsigned long)self.visibleSymbols.count];
    return [NSString stringWithFormat:@"%lu classes · %lu classes scanned · %lu methods scanned · %.2fs", (unsigned long)self.visibleClasses.count, (unsigned long)self.index.classesScanned, (unsigned long)self.index.methodsScanned, self.index.buildDuration];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGFastRuntimeRoot"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastRuntimeRoot"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        RYGRuntimeClassRow *row = self.visibleClasses[(NSUInteger)indexPath.row];
        cell.textLabel.text = row.className;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu instance · %lu class BOOL methods", (unsigned long)row.instanceMethodCount, (unsigned long)row.classMethodCount];
    } else {
        RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
        cell.textLabel.text = symbol.name;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 0x%llx", symbol.kind ?: @"symbol", (unsigned long long)symbol.address];
    }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        RYGRuntimeClassRow *row = self.visibleClasses[(NSUInteger)indexPath.row];
        RYGFastRuntimeClassViewController *detail = [[RYGFastRuntimeClassViewController alloc] initWithIndex:self.index classRow:row initialQuery:self.searchController.searchBar.text];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name message:[NSString stringWithFormat:@"%@\n0x%llx\n\nNo C override is exposed without a resolved calling convention.", symbol.kind ?: @"symbol", (unsigned long long)symbol.address] preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = symbol.name ?: @""; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) { sheet.popoverPresentationController.sourceView = cell; sheet.popoverPresentationController.sourceRect = cell.bounds; }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
