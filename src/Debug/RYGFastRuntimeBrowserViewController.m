#import "RYGFastRuntimeBrowserViewController.h"
#import "RYGRuntimeIndex.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "RYGLoadedImageCatalog.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

typedef NS_ENUM(NSInteger, RYGFastRuntimeMode) {
    RYGFastRuntimeModeObjC = 0,
    RYGFastRuntimeModeMachO,
};

static NSString *const kRYGFastRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";

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
    for (NSString *group in tokens) {
        BOOL matched = NO;
        for (NSString *token in [group componentsSeparatedByString:@"|"]) {
            if (!token.length) continue;
            NSString *compactToken = [[token componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
            if ([lower rangeOfString:token].location != NSNotFound ||
                (compactToken.length && [compact rangeOfString:compactToken].location != NSNotFound)) {
                matched = YES;
                break;
            }
        }
        if (!matched) return NO;
    }
    return YES;
}

#pragma mark - Lazy class detail

@interface RYGFastRuntimeClassViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *initialQuery;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *methods;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *visibleMethods;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation RYGFastRuntimeClassViewController

- (instancetype)initWithImagePath:(NSString *)imagePath className:(NSString *)className initialQuery:(NSString *)query {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _imagePath = [imagePath copy] ?: @"";
        _className = [className copy] ?: @"Class";
        _initialQuery = [query copy] ?: @"";
        _methods = @[];
        _visibleMethods = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.className;
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"BOOL selector or ABI";
    self.searchController.searchBar.text = self.initialQuery;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    self.emptyLabel = [UILabel new];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(nativeChanged:) name:RYGRuntimeNativeValueDidChangeNotification object:nil];
    RYGLiquidGlassApplyToViewController(self);

    __weak typeof(self) weakSelf = self;
    [RYGRuntimeIndex requestMethodsForClassName:self.className imagePath:self.imagePath completion:^(NSArray<RYGRuntimeBoolMethod *> *methods) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.methods = methods ?: @[];
        [self.spinner stopAnimating];
        [self applyFilter];
    }];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)nativeChanged:(NSNotification *)note {
    NSString *key = note.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (key.length && [key containsString:self.className]) [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyFilter];
}

- (void)applyFilter {
    NSArray *tokens = RYGFastTokens(self.searchController.searchBar.text ?: @"");
    self.visibleMethods = !tokens.count ? self.methods : [self.methods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeBoolMethod *method, NSDictionary *bindings) {
        (void)bindings;
        return RYGFastMatches([NSString stringWithFormat:@"%@ %@ %@", method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""], tokens);
    }]];
    self.emptyLabel.text = self.methods.count ? @"No BOOL method matches this filter." : @"No ABI-safe BOOL methods are defined by this image for the class.";
    self.tableView.backgroundView = self.visibleMethods.count ? nil : self.emptyLabel;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.visibleMethods.count;
}

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
    UIAction *useNative = [UIAction actionWithTitle:@"Native" image:nil identifier:nil handler:^(__unused UIAction *action) {
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
    button.menu = [UIMenu menuWithTitle:method.selectorName ?: @"" image:nil identifier:nil options:0 children:@[
        observe,
        [UIMenu menuWithTitle:@"Output" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[useNative, on, off]]
    ]];
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

#pragma mark - Root browser

@interface RYGFastRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) NSArray<RYGLoadedImageRecord *> *imageRecords;
@property (nonatomic, strong) RYGLoadedImageRecord *selectedImage;
@property (nonatomic, strong) RYGRuntimeImageIndex *index;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *visibleClasses;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *searchHits;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *symbols;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *visibleSymbols;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, copy) NSString *browserTitle;
@property (nonatomic, copy) NSString *initialQuery;
@property (nonatomic, assign) BOOL allowsBulkVisibilityOverride;
@property (nonatomic, assign) BOOL classListLoading;
@property (nonatomic, assign) BOOL searchRunning;
@end

@implementation RYGFastRuntimeBrowserViewController

- (instancetype)init { return [self initWithTitle:@"Runtime Browser" initialQuery:@""]; }

- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery {
    return [self initWithTitle:title initialQuery:initialQuery allowsBulkVisibilityOverride:NO];
}

- (instancetype)initWithTitle:(NSString *)title
                  initialQuery:(NSString *)initialQuery
    allowsBulkVisibilityOverride:(BOOL)allowsBulkVisibilityOverride {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        NSString *copiedTitle = [title copy];
        _browserTitle = copiedTitle.length ? copiedTitle : @"Runtime Browser";
        _initialQuery = [initialQuery copy] ?: @"";
        _allowsBulkVisibilityOverride = allowsBulkVisibilityOverride;
        _visibleClasses = @[];
        _searchHits = @[];
        _symbols = @[];
        _visibleSymbols = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.browserTitle;
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];

    self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageButton.showsMenuAsPrimaryAction = YES;
    [self.view addSubview:self.imageButton];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Objective-C", @"C Symbols"]];
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
    UILayoutGuide *contentGuide = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.imageButton.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8],
        [self.imageButton.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor],
        [self.imageButton.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor],
        [self.modeControl.topAnchor constraintEqualToAnchor:self.imageButton.bottomAnchor constant:8],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class or BOOL selector";
    self.searchController.searchBar.text = self.initialQuery;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.statusLabel = [UILabel new];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(refreshTapped)];
    if (self.allowsBulkVisibilityOverride) {
        UIBarButtonItem *reveal = [[UIBarButtonItem alloc] initWithTitle:@"Reveal All" style:UIBarButtonItemStylePlain target:self action:@selector(revealAllVisibilityRows)];
        self.navigationItem.rightBarButtonItems = @[refresh, reveal];
    } else {
        self.navigationItem.rightBarButtonItem = refresh;
    }

    // Deliberately does not call runtimeImagePaths. That legacy helper nested
    // dyld scans during sorting and could block this push before the first paint.
    [self refreshImages];
    [self rebuildImageMenu];
    [self updateStatus];
    RYGLiquidGlassApplyToViewController(self);

    // The controller is already fully presented before any Objective-C metadata
    // operation is requested.
    dispatch_async(dispatch_get_main_queue(), ^{ [self loadSelectedImage]; });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [RYGRuntimeIndex cancelActiveSearch];
}

- (void)refreshImages {
    self.imageRecords = [RYGLoadedImageCatalog bundledImages] ?: @[];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kRYGFastRuntimeSelectedImageKey];
    RYGLoadedImageRecord *selected = self.selectedImage;
    if (selected && ![self.imageRecords containsObject:selected]) selected = nil;
    if (!selected && stored.length) selected = [RYGLoadedImageCatalog recordForStableIdentifier:stored];
    if (!selected) selected = [RYGLoadedImageCatalog mainExecutableRecord] ?: self.imageRecords.firstObject;
    self.selectedImage = selected;
}

- (void)rebuildImageMenu {
    NSMutableArray *actions = [NSMutableArray arrayWithCapacity:self.imageRecords.count];
    __weak typeof(self) weakSelf = self;
    for (RYGLoadedImageRecord *record in self.imageRecords) {
        UIAction *action = [UIAction actionWithTitle:record.displayName ?: @"Image" image:nil identifier:nil handler:^(__unused UIAction *item) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.selectedImage = record;
            [NSUserDefaults.standardUserDefaults setObject:record.stableIdentifier forKey:kRYGFastRuntimeSelectedImageKey];
            [self rebuildImageMenu];
            [self loadSelectedImage];
        }];
        action.state = record == self.selectedImage ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.imageButton.menu = [UIMenu menuWithTitle:@"Loaded executable and frameworks" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
    RYGLiquidGlassConfigureButton(self.imageButton, NO);
    UIButtonConfiguration *configuration = self.imageButton.configuration;
    if (configuration) {
        configuration.title = [NSString stringWithFormat:@"Image: %@", self.selectedImage.displayName ?: @"None"];
        configuration.baseForegroundColor = UIColor.labelColor;
        self.imageButton.configuration = configuration;
    }
}

- (void)modeChanged:(UISegmentedControl *)sender {
    (void)sender;
    [RYGRuntimeIndex cancelActiveSearch];
    self.searchController.searchBar.text = @"";
    self.searchController.searchBar.placeholder = self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC ? @"Class or BOOL selector" : @"C symbol";
    [self loadSelectedImage];
}

- (void)refreshTapped {
    [RYGRuntimeIndex cancelActiveSearch];
    [RYGLoadedImageCatalog invalidate];
    [RYGRuntimeIndex invalidate];
    [RYGRuntimeBrowserEngine invalidateRuntimeCaches];
    [self refreshImages];
    [self rebuildImageMenu];
    [self loadSelectedImage];
}

- (void)loadSelectedImage {
    NSString *path = self.selectedImage.path.copy;
    NSUInteger generation = ++self.generation;
    [RYGRuntimeIndex cancelActiveSearch];
    self.searchHits = @[];
    self.searchRunning = NO;
    if (!path.length) {
        self.index = nil;
        self.symbols = @[];
        self.visibleSymbols = @[];
        [self updateStatus];
        [self.tableView reloadData];
        return;
    }

    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        self.classListLoading = YES;
        self.index = [RYGRuntimeIndex cachedIndexForImagePath:path];
        [self applyFilter];
        __weak typeof(self) weakSelf = self;
        [RYGRuntimeIndex requestIndexForImagePath:path completion:^(RYGRuntimeImageIndex *index) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation || ![self.selectedImage.path isEqualToString:path]) return;
            self.index = index;
            if (index.classes.count || index.classesScanned > 0) self.classListLoading = NO;
            [self applyFilter];
        }];
        return;
    }

    self.classListLoading = NO;
    self.symbols = @[];
    self.visibleSymbols = @[];
    [self updateStatus];
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *symbols = [RYGRuntimeBrowserEngine machOSymbolsForImagePath:path] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation || ![self.selectedImage.path isEqualToString:path]) return;
            self.symbols = symbols;
            [self applyFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyFilter];
}

- (void)applyFilter {
    NSArray *tokens = RYGFastTokens(self.searchController.searchBar.text ?: @"");
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeMachO) {
        self.visibleSymbols = !tokens.count ? self.symbols : [self.symbols filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMachOSymbol *symbol, NSDictionary *bindings) {
            (void)bindings;
            return RYGFastMatches([NSString stringWithFormat:@"%@ %@", symbol.name ?: @"", symbol.kind ?: @""], tokens);
        }]];
        [self updateStatus];
        [self.tableView reloadData];
        return;
    }

    NSArray<RYGRuntimeClassRow *> *classes = self.index.classes ?: @[];
    if (!tokens.count) {
        [RYGRuntimeIndex cancelActiveSearch];
        self.searchRunning = NO;
        self.searchHits = @[];
        self.visibleClasses = classes;
        [self updateStatus];
        [self.tableView reloadData];
        return;
    }

    NSString *query = self.searchController.searchBar.text ?: @"";
    NSMutableOrderedSet<NSString *> *wantedNames = [NSMutableOrderedSet orderedSet];
    for (RYGRuntimeClassRow *row in classes) if (RYGFastMatches(row.className ?: @"", tokens)) [wantedNames addObject:row.className];
    for (RYGRuntimeBoolMethod *method in self.searchHits) if (method.className.length) [wantedNames addObject:method.className];
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableDictionary<NSString *, RYGRuntimeClassRow *> *byName = [NSMutableDictionary dictionaryWithCapacity:classes.count];
    for (RYGRuntimeClassRow *row in classes) if (row.className.length) byName[row.className] = row;
    for (NSString *name in wantedNames) {
        RYGRuntimeClassRow *row = byName[name];
        if (!row) {
            row = [RYGRuntimeClassRow new];
            row.imagePath = self.selectedImage.path ?: @"";
            row.className = name;
        }
        [visible addObject:row];
    }
    self.visibleClasses = visible;
    [self updateStatus];
    [self.tableView reloadData];

    NSUInteger generation = self.generation;
    NSString *path = self.selectedImage.path.copy;
    self.searchRunning = YES;
    __weak typeof(self) weakSelf = self;
    [RYGRuntimeIndex requestSearchForImagePath:path query:query completion:^(NSArray<RYGRuntimeBoolMethod *> *matches, NSUInteger classesScanned, NSUInteger methodsScanned, BOOL finished) {
        (void)classesScanned; (void)methodsScanned;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.generation || ![self.selectedImage.path isEqualToString:path] || ![self.searchController.searchBar.text isEqualToString:query]) return;
        self.searchHits = matches ?: @[];
        self.searchRunning = !finished;
        NSArray *currentTokens = RYGFastTokens(query);
        NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
        for (RYGRuntimeClassRow *row in self.index.classes ?: @[]) if (RYGFastMatches(row.className ?: @"", currentTokens)) [names addObject:row.className];
        for (RYGRuntimeBoolMethod *method in self.searchHits) if (method.className.length) [names addObject:method.className];
        NSMutableDictionary<NSString *, RYGRuntimeClassRow *> *currentByName = [NSMutableDictionary dictionary];
        for (RYGRuntimeClassRow *row in self.index.classes ?: @[]) if (row.className.length) currentByName[row.className] = row;
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:names.count];
        for (NSString *name in names) {
            RYGRuntimeClassRow *row = currentByName[name];
            if (!row) {
                row = [RYGRuntimeClassRow new];
                row.imagePath = path;
                row.className = name;
            }
            [rows addObject:row];
        }
        self.visibleClasses = rows;
        [self updateStatus];
        [self.tableView reloadData];
    }];
}

- (void)updateStatus {
    if (!self.selectedImage) {
        self.statusLabel.text = @"No loaded app image.";
        self.tableView.backgroundView = self.statusLabel;
        return;
    }
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeMachO) {
        if (!self.symbols.count) self.statusLabel.text = @"C symbols load only when this tab is selected.";
        else if (!self.visibleSymbols.count) self.statusLabel.text = @"No C symbol matches.";
        else { self.tableView.backgroundView = nil; return; }
        self.tableView.backgroundView = self.statusLabel;
        return;
    }
    if (self.visibleClasses.count) {
        self.tableView.backgroundView = nil;
        return;
    }
    if (self.classListLoading) self.statusLabel.text = @"Loading class names in background…";
    else if (self.searchRunning) self.statusLabel.text = @"Searching BOOL selectors in background…";
    else self.statusLabel.text = @"No matching class or ABI-safe BOOL selector.";
    self.tableView.backgroundView = self.statusLabel;
}

- (void)revealAllVisibilityRows {
    if (!self.allowsBulkVisibilityOverride) return;
    if (!self.searchHits.count) {
        [RYGUtils showToastForDuration:1.4 title:@"Search first" subtitle:@"Reveal All applies only to already discovered ABI-safe visibility gates; it never triggers a synchronous whole-app scan."];
        return;
    }
    NSUInteger changed = 0;
    for (RYGRuntimeBoolMethod *method in self.searchHits) {
        NSString *normalized = [[[method.selectorName lowercaseString]
            componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
            componentsJoinedByString:@""];
        NSNumber *desired = nil;
        if ([normalized hasPrefix:@"ishidden"] || [normalized hasPrefix:@"shouldhide"] || [normalized hasPrefix:@"hide"]) desired = @NO;
        else if ([normalized hasPrefix:@"shouldshow"] || [normalized hasPrefix:@"canshow"] ||
                 [normalized hasPrefix:@"isvisible"] || [normalized hasPrefix:@"isavailable"] ||
                 [normalized hasPrefix:@"shoulddisplay"]) desired = @YES;
        if (!desired) continue;
        [RYGRuntimeBrowserEngine setOverride:desired forMethod:method];
        changed++;
    }
    [RYGUtils showToastForDuration:1.3 title:@"Settings visibility applied" subtitle:[NSString stringWithFormat:@"%lu discovered ABI-safe gate(s)", (unsigned long)changed]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC ? self.visibleClasses.count : self.visibleSymbols.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeMachO) {
        NSUInteger ready = 0;
        for (RYGMachOSymbol *symbol in self.visibleSymbols) if (symbol.isRebindableImport) ready++;
        return [NSString stringWithFormat:@"%lu symbols · %lu rebindable imports", (unsigned long)self.visibleSymbols.count, (unsigned long)ready];
    }
    NSString *suffix = self.searchRunning ? @" · searching…" : @"";
    return [NSString stringWithFormat:@"%lu classes%@", (unsigned long)self.visibleClasses.count, suffix];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGFastRuntimeRoot"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastRuntimeRoot"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        RYGRuntimeClassRow *row = self.visibleClasses[(NSUInteger)indexPath.row];
        cell.textLabel.text = row.className;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = (row.instanceMethodCount || row.classMethodCount)
            ? [NSString stringWithFormat:@"%lu instance · %lu class BOOL methods", (unsigned long)row.instanceMethodCount, (unsigned long)row.classMethodCount]
            : @"Methods load when opened";
    } else {
        RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
        cell.textLabel.text = symbol.name;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
        NSString *state = symbol.overrideValue ? (symbol.overrideValue.boolValue ? @"Forced On" : @"Forced Off") : @"Native";
        cell.detailTextLabel.text = symbol.isRebindableImport
            ? [NSString stringWithFormat:@"rebindable import · %@", state]
            : [NSString stringWithFormat:@"%@ · 0x%llx", symbol.kind ?: @"symbol", (unsigned long long)symbol.address];
    }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}

- (void)presentCABIForSymbol:(RYGMachOSymbol *)symbol value:(NSNumber *)value source:(UIView *)source {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"C BOOL ABI" message:@"Select only the integer/pointer-register argument count confirmed by disassembly. Float/vector/struct ABIs are intentionally unsupported." preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"BOOL f(void)", @"BOOL f(x0)", @"BOOL f(x0,x1)", @"BOOL f(x0,x1,x2)", @"BOOL f(x0,x1,x2,x3)"];
    for (NSInteger index = 0; index < (NSInteger)titles.count; index++) {
        [sheet addAction:[UIAlertAction actionWithTitle:titles[(NSUInteger)index] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            RYGCFunctionABI abi = (RYGCFunctionABI)(RYGCFunctionABIBool0 + index);
            if (![RYGRuntimeBrowserEngine setCOverride:value forSymbol:symbol abi:abi]) [RYGUtils showErrorHUDWithDescription:@"C import rebinding failed"];
            [self.tableView reloadData];
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
    if (self.modeControl.selectedSegmentIndex == RYGFastRuntimeModeObjC) {
        RYGRuntimeClassRow *row = self.visibleClasses[(NSUInteger)indexPath.row];
        RYGFastRuntimeClassViewController *detail = [[RYGFastRuntimeClassViewController alloc]
            initWithImagePath:self.selectedImage.path
                    className:row.className
                 initialQuery:self.searchController.searchBar.text ?: @""];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
    NSString *message = symbol.isRebindableImport
        ? @"This import can be rebound in this image without modifying __TEXT."
        : @"This symbol has no lazy/non-lazy import slot in this image and will not be patched.";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name message:message preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = symbol.name ?: @""; }]];
    if (symbol.isRebindableImport) {
        if (symbol.overrideValue) {
            [sheet addAction:[UIAlertAction actionWithTitle:@"Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                if (![RYGRuntimeBrowserEngine setCOverride:nil forSymbol:symbol abi:RYGCFunctionABIUnknown]) [RYGUtils showErrorHUDWithDescription:@"Could not restore original import binding"];
                [self.tableView reloadData];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force On…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self presentCABIForSymbol:symbol value:@YES source:cell]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force Off…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self presentCABIForSymbol:symbol value:@NO source:cell]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
