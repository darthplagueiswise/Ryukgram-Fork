#import "RYGRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeClassBrowser.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"

static NSString *const kRYGRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";

typedef NS_ENUM(NSInteger, RYGRuntimeTopMode) {
    RYGRuntimeTopModeClasses = 0,
    RYGRuntimeTopModeMachO,
};

static NSString *RYGRuntimeImagePersistenceID(NSString *path) {
    NSString *standard = path.stringByStandardizingPath;
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static BOOL RYGRuntimeContainsTokens(NSString *haystack, NSString *query) {
    if (!query.length) return YES;
    NSString *hay = haystack.lowercaseString ?: @"";
    for (NSString *token in [query.lowercaseString componentsSeparatedByCharactersInSet:
                              NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (token.length && [hay rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

#pragma mark - Class detail

@interface RYGRuntimeClassDetailViewController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithClassRow:(RYGRuntimeClassRow *)row;
@property (nonatomic, strong) RYGRuntimeClassRow *classRow;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *instanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *classMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *properties;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *visibleInstanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *visibleClassMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *visibleProperties;
@end

@implementation RYGRuntimeClassDetailViewController

- (instancetype)initWithClassRow:(RYGRuntimeClassRow *)row {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _classRow = row;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.classRow.className ?: @"Class";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Method, property or ABI";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(runtimeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    [self reloadRuntime];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)runtimeValueChanged:(NSNotification *)notification {
    NSString *key = notification.userInfo[RYGRuntimeNativeValueKeyUserInfoKey];
    if (key.length && [key containsString:self.classRow.className ?: @""]) [self.tableView reloadData];
}

- (void)reloadRuntime {
    self.instanceMethods = [RYGRuntimeClassBrowser methodsForClass:self.classRow classMethods:NO] ?: @[];
    self.classMethods = [RYGRuntimeClassBrowser methodsForClass:self.classRow classMethods:YES] ?: @[];
    self.properties = [RYGRuntimeClassBrowser propertiesForClass:self.classRow] ?: @[];
    [self applyFilter];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyFilter];
}

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text ?: @"";
    if (!query.length) {
        self.visibleInstanceMethods = self.instanceMethods ?: @[];
        self.visibleClassMethods = self.classMethods ?: @[];
        self.visibleProperties = self.properties ?: @[];
    } else {
        NSPredicate *methodPredicate = [NSPredicate predicateWithBlock:^BOOL(RYGRuntimeMethodRow *row, NSDictionary *bindings) {
            (void)bindings;
            return [RYGRuntimeClassBrowser methodRow:row matchesSearch:query];
        }];
        self.visibleInstanceMethods = [self.instanceMethods filteredArrayUsingPredicate:methodPredicate];
        self.visibleClassMethods = [self.classMethods filteredArrayUsingPredicate:methodPredicate];
        self.visibleProperties = [self.properties filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(RYGRuntimePropertyRow *row, NSDictionary *bindings) {
                (void)bindings;
                return RYGRuntimeContainsTokens([NSString stringWithFormat:@"%@ %@", row.name ?: @"", row.attributes ?: @""], query);
            }]];
    }
    [self.tableView reloadData];
}

- (NSArray *)rowsForSection:(NSInteger)section {
    if (section == 0) return self.visibleInstanceMethods ?: @[];
    if (section == 1) return self.visibleClassMethods ?: @[];
    return self.visibleProperties ?: @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return [self rowsForSection:section].count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Instance Methods";
    if (section == 1) return @"Class Methods";
    return @"Properties";
}

- (UIButton *)selectorButtonForMethod:(RYGRuntimeBoolMethod *)method {
    NSNumber *forced = method.overrideValue;
    NSNumber *native = method.liveValue;
    NSString *title = forced
        ? (forced.boolValue ? @"On" : @"Off")
        : (native ? (native.boolValue ? @"Native On" : @"Native Off") : @"Native");

    __weak typeof(self) weakSelf = self;
    UIAction *nativeAction = [UIAction actionWithTitle:@"Native" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    nativeAction.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    UIAction *forceOn = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    forceOn.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *forceOff = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
        [weakSelf.tableView reloadData];
    }];
    forceOff.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.menu = [UIMenu menuWithTitle:@"Output"
                                  image:nil
                             identifier:nil
                                options:UIMenuOptionsSingleSelection
                               children:@[nativeAction, forceOn, forceOff]];
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = title;
        configuration.baseForegroundColor = UIColor.labelColor;
        if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets];
        button.configuration = configuration;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
    }
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGRuntimeClassDetail"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGRuntimeClassDetail"];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;

    if (indexPath.section < 2) {
        RYGRuntimeMethodRow *row = [self rowsForSection:indexPath.section][(NSUInteger)indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", row.classMethod ? @"+" : @"−", row.selectorName ?: @""];
        if (row.hookableBool) {
            RYGRuntimeBoolMethod *method = [RYGRuntimeClassBrowser boolDescriptorForMethod:row];
            NSNumber *native = method.liveValue;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                         row.typeEncoding ?: @"",
                                         native ? (native.boolValue ? @"observed true" : @"observed false") : @"not observed"];
            cell.accessoryView = [self selectorButtonForMethod:method];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            cell.detailTextLabel.text = row.typeEncoding.length ? row.typeEncoding : @"No type encoding";
        }
    } else {
        RYGRuntimePropertyRow *property = [self rowsForSection:indexPath.section][(NSUInteger)indexPath.row];
        cell.textLabel.text = property.name ?: @"Property";
        cell.detailTextLabel.text = property.attributes ?: @"";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section >= 2) return;
    RYGRuntimeMethodRow *row = [self rowsForSection:indexPath.section][(NSUInteger)indexPath.row];
    if (!row.hookableBool) return;
    RYGRuntimeBoolMethod *method = [RYGRuntimeClassBrowser boolDescriptorForMethod:row];
    if (!method) return;
    RYGRuntimeBeginLiveObservation(@[method]);
    [RYGUtils showToastForDuration:1.0 title:@"Observing native value" subtitle:row.selectorName];
}

@end

#pragma mark - Root browser

@interface RYGRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *classRows;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *visibleClassRows;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *symbolRows;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *visibleSymbolRows;
@property (nonatomic, assign) NSUInteger scanGeneration;
@end

@implementation RYGRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Runtime Browser";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.classRows = @[];
    self.visibleClassRows = @[];
    self.symbolRows = @[];
    self.visibleSymbolRows = @[];

    self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageButton.showsMenuAsPrimaryAction = YES;
    self.imageButton.changesSelectionAsPrimaryAction = YES;
    [self.view addSubview:self.imageButton];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Classes", @"Mach-O"]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = RYGRuntimeTopModeClasses;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50.0;
    [self.view addSubview:self.tableView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.imageButton.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8.0],
        [self.imageButton.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [self.imageButton.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [self.modeControl.topAnchor constraintEqualToAnchor:self.imageButton.bottomAnchor constant:8.0],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [self.tableView.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:4.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.emptyLabel = [UILabel new];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont systemFontOfSize:14.0];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(refreshTapped)];

    [self refreshRuntimeImages];
    [self rebuildImageMenu];
    RYGLiquidGlassApplyToViewController(self);
    [self scanSelectedImage];
}

- (void)refreshRuntimeImages {
    self.images = [RYGRuntimeBrowserEngine runtimeImagePaths] ?: @[];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kRYGRuntimeSelectedImageKey];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if (!self.selectedImagePath.length || ![self.images containsObject:self.selectedImagePath]) {
        self.selectedImagePath = nil;
        for (NSString *path in self.images) {
            if (stored.length && [RYGRuntimeImagePersistenceID(path) isEqualToString:stored]) {
                self.selectedImagePath = path;
                break;
            }
        }
        if (!self.selectedImagePath.length) {
            for (NSString *path in self.images) {
                if ([path.stringByStandardizingPath isEqualToString:main]) {
                    self.selectedImagePath = path;
                    break;
                }
            }
        }
        if (!self.selectedImagePath.length) self.selectedImagePath = self.images.firstObject;
    }
}

- (void)rebuildImageMenu {
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSString *path in self.images) {
        UIAction *action = [UIAction actionWithTitle:[RYGRuntimeBrowserEngine shortNameForImagePath:path]
                                              image:nil
                                         identifier:nil
                                            handler:^(__unused UIAction *item) {
            weakSelf.selectedImagePath = path;
            [NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImagePersistenceID(path)
                                                    forKey:kRYGRuntimeSelectedImageKey];
            [weakSelf rebuildImageMenu];
            [weakSelf scanSelectedImage];
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
        if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets];
        self.imageButton.configuration = configuration;
    }
}

- (void)modeChanged:(UISegmentedControl *)sender {
    (void)sender;
    self.searchController.searchBar.text = @"";
    self.searchController.searchBar.placeholder = self.modeControl.selectedSegmentIndex == RYGRuntimeTopModeClasses ? @"Class" : @"Mach-O symbol";
    [self scanSelectedImage];
}

- (void)refreshTapped {
    [self refreshRuntimeImages];
    [self rebuildImageMenu];
    [self scanSelectedImage];
}

- (void)scanSelectedImage {
    NSString *path = self.selectedImagePath.copy;
    NSUInteger generation = ++self.scanGeneration;
    if (!path.length) return;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    RYGRuntimeTopMode mode = (RYGRuntimeTopMode)self.modeControl.selectedSegmentIndex;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (mode == RYGRuntimeTopModeClasses) {
            NSArray *rows = [RYGRuntimeClassBrowser classesForImagePath:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self.scanGeneration || ![self.selectedImagePath isEqualToString:path]) return;
                self.classRows = rows ?: @[];
                [self.spinner stopAnimating];
                [self applySearchFilter];
            });
        } else {
            NSArray *rows = [RYGRuntimeBrowserEngine machOSymbolsForImagePath:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self.scanGeneration || ![self.selectedImagePath isEqualToString:path]) return;
                self.symbolRows = rows ?: @[];
                [self.spinner stopAnimating];
                [self applySearchFilter];
            });
        }
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applySearchFilter];
}

- (void)applySearchFilter {
    NSString *query = self.searchController.searchBar.text ?: @"";
    if (self.modeControl.selectedSegmentIndex == RYGRuntimeTopModeClasses) {
        self.visibleClassRows = query.length
            ? [self.classRows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeClassRow *row, NSDictionary *bindings) {
                (void)bindings;
                return RYGRuntimeContainsTokens(row.className ?: @"", query);
            }]]
            : (self.classRows ?: @[]);
        self.emptyLabel.text = @"No Objective-C class in this loaded image matches the search.";
        self.tableView.backgroundView = self.visibleClassRows.count ? nil : self.emptyLabel;
    } else {
        self.visibleSymbolRows = query.length
            ? [self.symbolRows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMachOSymbol *row, NSDictionary *bindings) {
                (void)bindings;
                return RYGRuntimeContainsTokens([NSString stringWithFormat:@"%@ %@", row.name ?: @"", row.kind ?: @""], query);
            }]]
            : (self.symbolRows ?: @[]);
        self.emptyLabel.text = @"No Mach-O symbol matches the search.";
        self.tableView.backgroundView = self.visibleSymbolRows.count ? nil : self.emptyLabel;
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.modeControl.selectedSegmentIndex == RYGRuntimeTopModeClasses
        ? self.visibleClassRows.count : self.visibleSymbolRows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.modeControl.selectedSegmentIndex == RYGRuntimeTopModeClasses
        ? [NSString stringWithFormat:@"%lu Classes", (unsigned long)self.visibleClassRows.count]
        : [NSString stringWithFormat:@"%lu Mach-O Symbols", (unsigned long)self.visibleSymbolRows.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGRuntimeRoot"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGRuntimeRoot"];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (self.modeControl.selectedSegmentIndex == RYGRuntimeTopModeClasses) {
        RYGRuntimeClassRow *row = self.visibleClassRows[(NSUInteger)indexPath.row];
        cell.textLabel.text = row.className;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu instance · %lu class · %lu properties",
                                     (unsigned long)row.instanceMethodCount,
                                     (unsigned long)row.classMethodCount,
                                     (unsigned long)row.propertyCount];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:10.5];
    } else {
        RYGMachOSymbol *row = self.visibleSymbolRows[(NSUInteger)indexPath.row];
        cell.textLabel.text = row.name;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 0x%llx",
                                     row.kind ?: @"symbol",
                                     (unsigned long long)row.address];
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.modeControl.selectedSegmentIndex == RYGRuntimeTopModeClasses) {
        RYGRuntimeClassRow *row = self.visibleClassRows[(NSUInteger)indexPath.row];
        [self.navigationController pushViewController:[[RYGRuntimeClassDetailViewController alloc] initWithClassRow:row] animated:YES];
        return;
    }

    RYGMachOSymbol *symbol = self.visibleSymbolRows[(NSUInteger)indexPath.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name
                                                                    message:[NSString stringWithFormat:@"%@\n0x%llx\n\nPatch is disabled until this symbol's ABI is resolved.", symbol.kind ?: @"symbol", (unsigned long long)symbol.address]
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = symbol.name ?: @"";
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
