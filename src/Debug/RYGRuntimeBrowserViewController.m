#import "RYGRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>

static const void *kRYGRuntimeMethodToggleKey = &kRYGRuntimeMethodToggleKey;
static NSString *const kRYGRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";
static NSString *const kRYGRuntimeModeKey = @"ryg_runtime_browser_mode";

typedef NS_ENUM(NSInteger, RYGRuntimeBrowserMode) {
    RYGRuntimeBrowserModeObjectiveC = 0,
    RYGRuntimeBrowserModeMachOSymbols,
};

@interface RYGRuntimeClassRow : NSObject
@property (nonatomic, copy) NSString *className;
@end
@implementation RYGRuntimeClassRow @end

@interface RYGRuntimeMethodRow : NSObject
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, assign) BOOL hookableBOOL;
@property (nonatomic, assign) RYGRuntimeArgumentKind argumentKind;
@property (nonatomic, strong) RYGRuntimeBoolMethod *boolMethod;
@end
@implementation RYGRuntimeMethodRow @end

@interface RYGRuntimePropertyRow : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *attributes;
@property (nonatomic, assign) BOOL classProperty;
@end
@implementation RYGRuntimePropertyRow @end

static NSString *RYGRuntimeNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    BOOL previousSpace = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        BOOL alpha = character >= 'a' && character <= 'z';
        BOOL digit = character >= '0' && character <= '9';
        if (alpha || digit) {
            [result appendFormat:@"%C", character];
            previousSpace = NO;
        } else if (!previousSpace) {
            [result appendString:@" "];
            previousSpace = YES;
        }
    }
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static BOOL RYGRuntimeMatches(NSString *text, NSString *query) {
    NSString *normalizedQuery = RYGRuntimeNormalize(query);
    if (!normalizedQuery.length) return YES;
    NSString *normalizedText = RYGRuntimeNormalize(text);
    NSString *compact = [normalizedText stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in [normalizedQuery componentsSeparatedByString:@" "]) {
        if (!token.length) continue;
        if ([normalizedText rangeOfString:token].location == NSNotFound &&
            [compact rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

static NSString *RYGRuntimeImageIdentity(NSString *path) {
    NSString *standard = path.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    NSString *bundle = NSBundle.mainBundle.bundlePath.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    NSString *prefix = [bundle stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static NSArray<RYGRuntimeClassRow *> *RYGRuntimeClassesForImagePath(NSString *imagePath) {
    if (!imagePath.length) return @[];

    // The selected path comes straight from dyld. Ask the Objective-C runtime
    // for that exact image rather than scanning every class and comparing path
    // strings (/var vs /private/var was enough to make the old browser empty).
    unsigned int count = 0;
    const char **names = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &count);
    if (!names) {
        NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
        if (![resolved isEqualToString:imagePath])
            names = objc_copyClassNamesForImage(resolved.fileSystemRepresentation, &count);
    }
    if (!names) return @[];

    NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        const char *raw = names[index];
        if (!raw || !*raw) continue;
        NSString *name = [NSString stringWithUTF8String:raw];
        if (!name.length) continue;
        RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
        row.className = name;
        [rows addObject:row];
    }
    free(names);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    return rows.copy;
}

static const char *RYGRuntimeSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGRuntimeReturnsStrictBOOL(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGRuntimeSkipQualifiers(encoded);
    return type && *type == 'B';
}

static RYGRuntimeArgumentKind RYGRuntimeArgumentKindForMethod(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;

    char encoded[64] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGRuntimeSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static RYGRuntimeMethodRow *RYGRuntimeBuildMethodRow(Class cls,
                                                      Method method,
                                                      BOOL classMethod,
                                                      NSString *imagePath) {
    SEL selector = method_getName(method);
    if (!selector) return nil;
    NSString *selectorName = NSStringFromSelector(selector);
    if (!selectorName.length) return nil;

    RYGRuntimeMethodRow *row = [RYGRuntimeMethodRow new];
    row.selectorName = selectorName;
    row.classMethod = classMethod;
    const char *types = method_getTypeEncoding(method);
    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    row.argumentKind = RYGRuntimeArgumentKindForMethod(method);

    // Hookability is based only on the live ABI. No name, prefix, employee,
    // feature, UI-state or BOOL-gate semantic classification is used here.
    row.hookableBOOL = RYGRuntimeReturnsStrictBOOL(method)
        && row.argumentKind >= RYGRuntimeArgumentNone
        && row.argumentKind <= RYGRuntimeArgumentInteger;

    if (row.hookableBOOL) {
        RYGRuntimeBoolMethod *runtimeMethod = [RYGRuntimeBoolMethod new];
        runtimeMethod.imagePath = imagePath ?: @"";
        runtimeMethod.className = NSStringFromClass(cls) ?: @"";
        runtimeMethod.selectorName = selectorName;
        runtimeMethod.typeEncoding = row.typeEncoding ?: @"";
        runtimeMethod.classMethod = classMethod;
        runtimeMethod.argumentKind = row.argumentKind;
        row.boolMethod = runtimeMethod;
    }
    return row;
}

static NSArray<RYGRuntimeMethodRow *> *RYGRuntimeMethodsForClass(Class cls,
                                                                  BOOL classMethods,
                                                                  NSString *imagePath) {
    if (!cls) return @[];
    Class owner = classMethods ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
    NSMutableArray<RYGRuntimeMethodRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        RYGRuntimeMethodRow *row = RYGRuntimeBuildMethodRow(cls, methods[index], classMethods, imagePath);
        if (row) [rows addObject:row];
    }
    if (methods) free(methods);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMethodRow *left, RYGRuntimeMethodRow *right) {
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return rows.copy;
}

static NSArray<RYGRuntimePropertyRow *> *RYGRuntimePropertiesForClass(Class cls, BOOL classProperties) {
    if (!cls) return @[];
    Class owner = classProperties ? object_getClass(cls) : cls;
    unsigned int count = 0;
    objc_property_t *properties = owner ? class_copyPropertyList(owner, &count) : NULL;
    NSMutableArray<RYGRuntimePropertyRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        const char *rawName = property_getName(properties[index]);
        if (!rawName) continue;
        RYGRuntimePropertyRow *row = [RYGRuntimePropertyRow new];
        row.name = [NSString stringWithUTF8String:rawName] ?: @"";
        const char *rawAttributes = property_getAttributes(properties[index]);
        row.attributes = rawAttributes ? [NSString stringWithUTF8String:rawAttributes] : @"";
        row.classProperty = classProperties;
        [rows addObject:row];
    }
    if (properties) free(properties);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimePropertyRow *left, RYGRuntimePropertyRow *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return rows.copy;
}

static NSString *RYGRuntimeAdapterName(RYGRuntimeArgumentKind kind) {
    switch (kind) {
        case RYGRuntimeArgumentNone: return @"BOOL · no arguments";
        case RYGRuntimeArgumentObject: return @"BOOL · object argument";
        case RYGRuntimeArgumentInteger: return @"BOOL · integer argument";
    }
    return @"No safe BOOL adapter";
}

@interface RYGRuntimeClassDetailViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *instanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *classMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *properties;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *classProperties;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *visibleInstanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *visibleClassMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *visibleProperties;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *visibleClassProperties;
@end

@implementation RYGRuntimeClassDetailViewController

- (instancetype)initWithClassName:(NSString *)className imagePath:(NSString *)imagePath {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _className = className.copy;
        _imagePath = imagePath.copy;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.className;
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58.0;

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
    [self reloadMembers];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)reloadMembers {
    Class cls = objc_lookUpClass(self.className.UTF8String);
    self.instanceMethods = RYGRuntimeMethodsForClass(cls, NO, self.imagePath);
    self.classMethods = RYGRuntimeMethodsForClass(cls, YES, self.imagePath);
    self.properties = RYGRuntimePropertiesForClass(cls, NO);
    self.classProperties = RYGRuntimePropertiesForClass(cls, YES);
    [self applyFilter];
}

- (void)runtimeValueChanged:(NSNotification *)notification { (void)notification; [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text ?: @"";
    NSMutableArray *instanceMethods = [NSMutableArray array];
    NSMutableArray *classMethods = [NSMutableArray array];
    NSMutableArray *properties = [NSMutableArray array];
    NSMutableArray *classProperties = [NSMutableArray array];

    for (RYGRuntimeMethodRow *row in self.instanceMethods) {
        if (RYGRuntimeMatches([NSString stringWithFormat:@"%@ %@", row.selectorName, row.typeEncoding], query)) [instanceMethods addObject:row];
    }
    for (RYGRuntimeMethodRow *row in self.classMethods) {
        if (RYGRuntimeMatches([NSString stringWithFormat:@"%@ %@", row.selectorName, row.typeEncoding], query)) [classMethods addObject:row];
    }
    for (RYGRuntimePropertyRow *row in self.properties) {
        if (RYGRuntimeMatches([NSString stringWithFormat:@"%@ %@", row.name, row.attributes], query)) [properties addObject:row];
    }
    for (RYGRuntimePropertyRow *row in self.classProperties) {
        if (RYGRuntimeMatches([NSString stringWithFormat:@"%@ %@", row.name, row.attributes], query)) [classProperties addObject:row];
    }
    self.visibleInstanceMethods = instanceMethods.copy;
    self.visibleClassMethods = classMethods.copy;
    self.visibleProperties = properties.copy;
    self.visibleClassProperties = classProperties.copy;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return self.visibleInstanceMethods.count;
        case 1: return self.visibleClassMethods.count;
        case 2: return self.visibleProperties.count;
        default: return self.visibleClassProperties.count;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return @"Instance Methods";
        case 1: return @"Class Methods";
        case 2: return @"Properties";
        default: return @"Class Properties";
    }
}

- (UITableViewCell *)methodCellForRow:(RYGRuntimeMethodRow *)row tableView:(UITableView *)tableView {
    static NSString *identifier = @"RYGRuntimeMethodCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", row.classMethod ? @"+" : @"-", row.selectorName];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;

    if (!row.hookableBOOL) {
        cell.detailTextLabel.text = row.typeEncoding;
        cell.imageView.image = [UIImage systemImageNamed:@"function"];
        cell.imageView.tintColor = UIColor.tertiaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSNumber *forced = row.boolMethod.overrideValue;
    NSNumber *live = row.boolMethod.liveValue;
    NSString *valueText = forced
        ? [NSString stringWithFormat:@"forced %@", forced.boolValue ? @"true" : @"false"]
        : (live ? [NSString stringWithFormat:@"native %@", live.boolValue ? @"true" : @"false"] : @"native not observed");
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@\n%@",
                                 RYGRuntimeAdapterName(row.argumentKind), valueText, row.typeEncoding ?: @""];
    cell.imageView.image = [UIImage systemImageNamed:@"waveform.path.ecg"];
    cell.imageView.tintColor = [RYGUtils RYGColor_Primary];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UISwitch *toggle = [UISwitch new];
    toggle.on = forced ? forced.boolValue : (live ? live.boolValue : NO);
    objc_setAssociatedObject(toggle, kRYGRuntimeMethodToggleKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [toggle addTarget:self action:@selector(methodToggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (UITableViewCell *)propertyCellForRow:(RYGRuntimePropertyRow *)row tableView:(UITableView *)tableView {
    static NSString *identifier = @"RYGRuntimePropertyCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.textLabel.text = row.name;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = row.attributes;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.imageView.image = [UIImage systemImageNamed:@"p.circle"];
    cell.imageView.tintColor = UIColor.tertiaryLabelColor;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self methodCellForRow:self.visibleInstanceMethods[indexPath.row] tableView:tableView];
    if (indexPath.section == 1) return [self methodCellForRow:self.visibleClassMethods[indexPath.row] tableView:tableView];
    if (indexPath.section == 2) return [self propertyCellForRow:self.visibleProperties[indexPath.row] tableView:tableView];
    return [self propertyCellForRow:self.visibleClassProperties[indexPath.row] tableView:tableView];
}

- (void)methodToggleChanged:(UISwitch *)toggle {
    RYGRuntimeMethodRow *row = objc_getAssociatedObject(toggle, kRYGRuntimeMethodToggleKey);
    if (!row.hookableBOOL || !row.boolMethod) return;
    [RYGRuntimeBrowserEngine setOverride:@(toggle.isOn) forMethod:row.boolMethod];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGRuntimeMethodRow *row = nil;
    if (indexPath.section == 0) row = self.visibleInstanceMethods[indexPath.row];
    else if (indexPath.section == 1) row = self.visibleClassMethods[indexPath.row];
    if (!row.hookableBOOL || !row.boolMethod) return;
    [self presentActionsForMethod:row];
}

- (void)presentActionsForMethod:(RYGRuntimeMethodRow *)row {
    NSNumber *forced = row.boolMethod.overrideValue;
    NSNumber *live = row.boolMethod.liveValue;
    NSString *message = [NSString stringWithFormat:@"%@\nOriginal: %@\nOutput: %@",
        row.typeEncoding ?: @"",
        live ? (live.boolValue ? @"true" : @"false") : @"not observed yet",
        forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.selectorName
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Observe Original Value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        RYGRuntimeBeginLiveObservation(@[row.boolMethod]);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force True" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:row.boolMethod]; [weakSelf.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Force False" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:row.boolMethod]; [weakSelf.tableView reloadData];
    }]];
    if (forced) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native Value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:row.boolMethod]; [weakSelf.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

@interface RYGRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *classRows;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *visibleClassRows;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *symbolRows;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *visibleSymbolRows;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation RYGRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Runtime";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.classRows = @[];
    self.visibleClassRows = @[];
    self.symbolRows = @[];
    self.visibleSymbolRows = @[];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"Objective-C", @"Mach-O"]];
    NSInteger storedMode = [NSUserDefaults.standardUserDefaults integerForKey:kRYGRuntimeModeKey];
    self.modeControl.selectedSegmentIndex = storedMode == RYGRuntimeBrowserModeMachOSymbols
        ? RYGRuntimeBrowserModeMachOSymbols : RYGRuntimeBrowserModeObjectiveC;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.modeControl.frame = CGRectMake(16.0, 6.0, self.view.bounds.size.width - 32.0, 34.0);

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 46.0)];
    self.modeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.modeControl];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.tableHeaderView = header;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    [self refreshImages];
    [self rebuildNavigationItems];
    [self updateSearchPlaceholder];
    [self scanSelectedImage];
    RYGLiquidGlassApplyToViewController(self);
}

- (RYGRuntimeBrowserMode)mode {
    return self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeMachOSymbols
        ? RYGRuntimeBrowserModeMachOSymbols : RYGRuntimeBrowserModeObjectiveC;
}

- (void)refreshImages {
    self.images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kRYGRuntimeSelectedImageKey];
    if (![self.images containsObject:self.selectedImagePath]) self.selectedImagePath = nil;
    if (!self.selectedImagePath.length && stored.length) {
        for (NSString *path in self.images) {
            if ([RYGRuntimeImageIdentity(path) isEqualToString:stored] ||
                [[RYGRuntimeBrowserEngine shortNameForImagePath:path] isEqualToString:stored]) {
                self.selectedImagePath = path;
                break;
            }
        }
    }
    if (!self.selectedImagePath.length) self.selectedImagePath = self.images.firstObject;
}

- (UIMenu *)imageMenu {
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSString *path in self.images) {
        UIAction *action = [UIAction actionWithTitle:[RYGRuntimeBrowserEngine shortNameForImagePath:path]
                                              image:nil
                                         identifier:nil
                                            handler:^(__unused UIAction *item) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.selectedImagePath = path;
            [NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImageIdentity(path) forKey:kRYGRuntimeSelectedImageKey];
            [self rebuildNavigationItems];
            [self scanSelectedImage];
        }];
        action.state = [path isEqualToString:self.selectedImagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:@"Loaded Image" children:actions];
}

- (void)rebuildNavigationItems {
    NSString *imageTitle = self.selectedImagePath.length
        ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath] : @"Image";
    UIBarButtonItem *image = [[UIBarButtonItem alloc] initWithTitle:imageTitle menu:[self imageMenu]];
    UIBarButtonItem *refresh = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(scanSelectedImage)];
    self.navigationItem.rightBarButtonItems = @[refresh, image];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegmentIndex forKey:kRYGRuntimeModeKey];
    [self updateSearchPlaceholder];
    [self scanSelectedImage];
}

- (void)updateSearchPlaceholder {
    self.searchController.searchBar.placeholder = self.mode == RYGRuntimeBrowserModeObjectiveC
        ? @"Class name" : @"Symbol name";
}

- (void)scanSelectedImage {
    [self refreshImages];
    [self rebuildNavigationItems];
    NSString *path = self.selectedImagePath.copy;
    if (!path.length) return;

    NSUInteger generation = ++self.generation;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    RYGRuntimeBrowserMode mode = self.mode;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (mode == RYGRuntimeBrowserModeObjectiveC) {
            NSArray<RYGRuntimeClassRow *> *rows = RYGRuntimeClassesForImagePath(path);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.generation || self.mode != mode) return;
                self.classRows = rows;
                [self applyFilter];
            });
        } else {
            NSArray<RYGMachOSymbol *> *rows = [RYGRuntimeBrowserEngine machOSymbolsForImagePath:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self.generation || self.mode != mode) return;
                self.symbolRows = rows;
                [self applyFilter];
            });
        }
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }

- (void)applyFilter {
    NSString *query = self.searchController.searchBar.text ?: @"";
    if (self.mode == RYGRuntimeBrowserModeObjectiveC) {
        NSMutableArray *matches = [NSMutableArray array];
        for (RYGRuntimeClassRow *row in self.classRows) if (RYGRuntimeMatches(row.className, query)) [matches addObject:row];
        self.visibleClassRows = matches.copy;
        self.visibleSymbolRows = @[];
    } else {
        NSMutableArray *matches = [NSMutableArray array];
        for (RYGMachOSymbol *row in self.symbolRows) {
            if (RYGRuntimeMatches([NSString stringWithFormat:@"%@ %@", row.name ?: @"", row.kind ?: @""], query)) [matches addObject:row];
        }
        self.visibleSymbolRows = matches.copy;
        self.visibleClassRows = @[];
    }
    [self.spinner stopAnimating];
    self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.mode == RYGRuntimeBrowserModeObjectiveC ? self.visibleClassRows.count : self.visibleSymbolRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGRuntimeRootCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (self.mode == RYGRuntimeBrowserModeObjectiveC) {
        RYGRuntimeClassRow *row = self.visibleClassRows[indexPath.row];
        cell.textLabel.text = row.className;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.5 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:@"cube.transparent"];
        cell.imageView.tintColor = UIColor.secondaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        RYGMachOSymbol *row = self.visibleSymbolRows[indexPath.row];
        cell.textLabel.text = row.name;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 0x%llx%@", row.kind ?: @"Symbol", row.address,
                                     row.external ? @" · external" : @""];
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = [UIImage systemImageNamed:@"function"];
        cell.imageView.tintColor = UIColor.secondaryLabelColor;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.mode == RYGRuntimeBrowserModeObjectiveC) {
        RYGRuntimeClassRow *row = self.visibleClassRows[indexPath.row];
        RYGRuntimeClassDetailViewController *detail = [[RYGRuntimeClassDetailViewController alloc]
            initWithClassName:row.className imagePath:self.selectedImagePath];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    RYGMachOSymbol *symbol = self.visibleSymbolRows[indexPath.row];
    UIPasteboard.generalPasteboard.string = symbol.name;
    [RYGUtils showToastForDuration:1.0 title:@"Copied" subtitle:symbol.name];
}

@end
