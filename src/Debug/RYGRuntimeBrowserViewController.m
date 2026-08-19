#import "RYGRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>


typedef NS_ENUM(NSInteger, RYGRuntimeBrowserMode) {
    RYGRuntimeBrowserModeObjectiveC = 0,
    RYGRuntimeBrowserModeMachOSymbols,
};

static NSString *const kRYGRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";
static NSString *const kRYGRuntimeModeKey = @"ryg_runtime_browser_mode";

@interface RYGRuntimeClassRow : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign) Class runtimeClass;
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
@end
@implementation RYGRuntimePropertyRow @end

static NSString *RYGRuntimeImagePersistenceID(NSString *path) {
    NSString *standard = path.stringByStandardizingPath;
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static NSString *RYGRuntimeSearchNormalizedString(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    NSCharacterSet *alnum = NSCharacterSet.alphanumericCharacterSet;
    BOOL previousWasSpace = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        if ([alnum characterIsMember:character]) {
            [out appendFormat:@"%C", character];
            previousWasSpace = NO;
        } else if (!previousWasSpace) {
            [out appendString:@" "];
            previousWasSpace = YES;
        }
    }
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static BOOL RYGRuntimeSearchMatches(NSString *haystack, NSString *query) {
    NSString *needle = RYGRuntimeSearchNormalizedString(query);
    if (!needle.length) return YES;
    NSString *normalizedHaystack = RYGRuntimeSearchNormalizedString(haystack);
    NSString *compactHaystack = [normalizedHaystack stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSArray<NSString *> *tokens = [needle componentsSeparatedByString:@" "];
    for (NSString *token in tokens) {
        if (!token.length) continue;
        if ([normalizedHaystack rangeOfString:token].location == NSNotFound &&
            [compactHaystack rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

static NSArray<RYGRuntimeClassRow *> *RYGRuntimeClassesForImagePath(NSString *imagePath) {
    NSString *wanted = imagePath.stringByStandardizingPath;
    if (!wanted.length) return @[];

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return @[];

    NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray array];
    for (unsigned int index = 0; index < classCount; index++) {
        Class cls = classes[index];
        const char *rawImage = class_getImageName(cls);
        if (!rawImage) continue;
        NSString *classImage = [[NSString stringWithUTF8String:rawImage] stringByStandardizingPath];
        if (![classImage isEqualToString:wanted]) continue;
        NSString *className = NSStringFromClass(cls);
        if (!className.length) continue;

        // Never retain a runtime Class object in a Foundation collection. The
        // model stores it as an assign pointer; the array retains only the model.
        RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
        row.className = className;
        row.runtimeClass = cls;
        [rows addObject:row];
    }
    free(classes);

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    return rows.copy;
}

static const char *RYGRuntimeSkipTypeQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGRuntimeMethodReturnsStrictBOOL(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGRuntimeSkipTypeQualifiers(encoded);
    return type && *type == 'B';
}

static RYGRuntimeArgumentKind RYGRuntimeSafeArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;

    char encoded[64] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGRuntimeSkipTypeQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;

    // Only actual integer/scalar register arguments use the generic integer
    // adapter. Pointers and C strings are deliberately excluded even though
    // they also occupy a general-purpose register on arm64.
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGRuntimeSelectorIsUnsafeUIState(Class cls, NSString *selectorName) {
    if (!cls || !selectorName.length) return YES;
    BOOL viewLike = [cls isSubclassOfClass:UIView.class]
        || [cls isSubclassOfClass:UIViewController.class]
        || [cls isSubclassOfClass:CALayer.class];
    if (!viewLike) return NO;
    static NSSet<NSString *> *stateNames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stateNames = [NSSet setWithArray:@[
            @"isHidden", @"isSelected", @"isEnabled", @"isHighlighted",
            @"isOpaque", @"clipsToBounds", @"isUserInteractionEnabled",
            @"userInteractionEnabled", @"isFocused", @"canBecomeFocused",
            @"prefersStatusBarHidden", @"prefersHomeIndicatorAutoHidden",
            @"shouldAutorotate"
        ]];
    });
    return [stateNames containsObject:selectorName];
}

static RYGRuntimeMethodRow *RYGRuntimeMethodRowFromMethod(Class cls, Method method, BOOL classMethod, NSString *imagePath) {
    SEL selector = method_getName(method);
    NSString *selectorName = selector ? NSStringFromSelector(selector) : nil;
    if (!selectorName.length) return nil;

    RYGRuntimeMethodRow *row = [RYGRuntimeMethodRow new];
    row.selectorName = selectorName;
    row.classMethod = classMethod;
    row.typeEncoding = [NSString stringWithUTF8String:method_getTypeEncoding(method) ?: ""];
    row.argumentKind = RYGRuntimeSafeArgumentKind(method);

    BOOL structural = [RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]
        || RYGRuntimeSelectorIsUnsafeUIState(cls, selectorName);
    row.hookableBOOL = !structural && RYGRuntimeMethodReturnsStrictBOOL(method)
        && row.argumentKind >= RYGRuntimeArgumentNone
        && row.argumentKind <= RYGRuntimeArgumentInteger;

    if (row.hookableBOOL) {
        RYGRuntimeBoolMethod *boolMethod = [RYGRuntimeBoolMethod new];
        boolMethod.imagePath = imagePath ?: @"";
        boolMethod.className = NSStringFromClass(cls) ?: @"";
        boolMethod.selectorName = selectorName;
        boolMethod.typeEncoding = row.typeEncoding ?: @"";
        boolMethod.classMethod = classMethod;
        boolMethod.argumentKind = row.argumentKind;
        row.boolMethod = boolMethod;
    }
    return row;
}

static NSArray<RYGRuntimeMethodRow *> *RYGRuntimeMethodsForClass(Class cls, BOOL classMethods, NSString *imagePath) {
    if (!cls) return @[];
    Class owner = classMethods ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
    NSMutableArray<RYGRuntimeMethodRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        RYGRuntimeMethodRow *row = RYGRuntimeMethodRowFromMethod(cls, methods[index], classMethods, imagePath);
        if (row) [rows addObject:row];
    }
    if (methods) free(methods);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMethodRow *left, RYGRuntimeMethodRow *right) {
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return rows.copy;
}

static NSArray<RYGRuntimePropertyRow *> *RYGRuntimePropertiesForClass(Class cls) {
    if (!cls) return @[];
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    NSMutableArray<RYGRuntimePropertyRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        const char *rawName = property_getName(properties[index]);
        if (!rawName) continue;
        RYGRuntimePropertyRow *row = [RYGRuntimePropertyRow new];
        row.name = [NSString stringWithUTF8String:rawName] ?: @"";
        const char *rawAttributes = property_getAttributes(properties[index]);
        row.attributes = rawAttributes ? [NSString stringWithUTF8String:rawAttributes] : @"";
        [rows addObject:row];
    }
    if (properties) free(properties);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimePropertyRow *left, RYGRuntimePropertyRow *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return rows.copy;
}

static NSString *RYGRuntimeArgumentDescription(RYGRuntimeArgumentKind kind) {
    switch (kind) {
        case RYGRuntimeArgumentNone: return @"BOOL adapter · no arguments";
        case RYGRuntimeArgumentObject: return @"BOOL adapter · object argument";
        case RYGRuntimeArgumentInteger: return @"BOOL adapter · integer argument";
    }
    return @"ABI inspected · no automatic adapter";
}

#pragma mark - Class detail

@interface RYGRuntimeClassDetailViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, strong) RYGRuntimeClassRow *classRow;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *instanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *classMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *properties;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *visibleInstanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodRow *> *visibleClassMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyRow *> *visibleProperties;
@end

@implementation RYGRuntimeClassDetailViewController

- (instancetype)initWithClassRow:(RYGRuntimeClassRow *)classRow imagePath:(NSString *)imagePath {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _classRow = classRow;
        _imagePath = imagePath.copy;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.classRow.className;
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = RYGLocalized(@"Method, property or ABI");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    Class cls = self.classRow.runtimeClass;
    self.instanceMethods = RYGRuntimeMethodsForClass(cls, NO, self.imagePath);
    self.classMethods = RYGRuntimeMethodsForClass(cls, YES, self.imagePath);
    self.properties = RYGRuntimePropertiesForClass(cls);
    [self applyFilter];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeNativeValueChanged:)
                                                 name:RYGRuntimeNativeValueDidChangeNotification
                                               object:nil];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)runtimeNativeValueChanged:(NSNotification *)notification {
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applyFilter];
}

- (void)applyFilter {
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) {
        self.visibleInstanceMethods = self.instanceMethods;
        self.visibleClassMethods = self.classMethods;
        self.visibleProperties = self.properties;
    } else {
        self.visibleInstanceMethods = [self.instanceMethods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeMethodRow *row, NSDictionary *bindings) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@", row.selectorName ?: @"", row.typeEncoding ?: @""];
            return RYGRuntimeSearchMatches(haystack, query);
        }]];
        self.visibleClassMethods = [self.classMethods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeMethodRow *row, NSDictionary *bindings) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@", row.selectorName ?: @"", row.typeEncoding ?: @""];
            return RYGRuntimeSearchMatches(haystack, query);
        }]];
        self.visibleProperties = [self.properties filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimePropertyRow *row, NSDictionary *bindings) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@", row.name ?: @"", row.attributes ?: @""];
            return RYGRuntimeSearchMatches(haystack, query);
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return self.visibleInstanceMethods.count;
    if (section == 1) return self.visibleClassMethods.count;
    return self.visibleProperties.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return [NSString stringWithFormat:RYGLocalized(@"Instance Methods (%lu)"), (unsigned long)self.visibleInstanceMethods.count];
    if (section == 1) return [NSString stringWithFormat:RYGLocalized(@"Class Methods (%lu)"), (unsigned long)self.visibleClassMethods.count];
    return [NSString stringWithFormat:RYGLocalized(@"Properties (%lu)"), (unsigned long)self.visibleProperties.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (indexPath.section < 2) {
        RYGRuntimeMethodRow *row = indexPath.section == 0
            ? self.visibleInstanceMethods[indexPath.row]
            : self.visibleClassMethods[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", row.classMethod ? @"+" : @"-", row.selectorName];
        NSString *status = row.hookableBOOL ? RYGRuntimeArgumentDescription(row.argumentKind) : @"ABI inspected · no automatic adapter";
        if (row.hookableBOOL) {
            NSNumber *forced = row.boolMethod.overrideValue;
            NSNumber *live = row.boolMethod.liveValue;
            if (forced) status = [status stringByAppendingFormat:@" · forced %@", forced.boolValue ? @"true" : @"false"];
            else if (live) status = [status stringByAppendingFormat:@" · live %@", live.boolValue ? @"true" : @"false"];
            else status = [status stringByAppendingString:@" · live value not observed"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.imageView.image = [UIImage systemImageNamed:@"waveform.path.ecg"];
            cell.imageView.tintColor = [RYGUtils RYGColor_Primary];
        } else {
            cell.imageView.image = [UIImage systemImageNamed:@"function"];
            cell.imageView.tintColor = UIColor.tertiaryLabelColor;
        }
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", row.typeEncoding ?: @"", status];
    } else {
        RYGRuntimePropertyRow *row = self.visibleProperties[indexPath.row];
        cell.textLabel.text = row.name;
        cell.detailTextLabel.text = row.attributes;
        cell.imageView.image = [UIImage systemImageNamed:@"p.circle"];
        cell.imageView.tintColor = UIColor.tertiaryLabelColor;
    }
    return cell;
}

- (void)presentMethodActions:(RYGRuntimeMethodRow *)row fromCell:(UITableViewCell *)cell {
    RYGRuntimeBoolMethod *method = row.boolMethod;
    NSNumber *native = method.liveValue;
    NSNumber *forced = method.overrideValue;
    NSString *nativeText = native ? (native.boolValue ? @"true" : @"false") : @"not observed yet";
    NSString *outputText = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native";
    NSString *message = row.hookableBOOL
        ? [NSString stringWithFormat:@"%@\n%@\nOriginal: %@\nOutput: %@", self.classRow.className, row.typeEncoding, nativeText, outputText]
        : [NSString stringWithFormat:@"%@\n%@\nABI inspected. No safe automatic adapter is registered for this signature.", self.classRow.className, row.typeEncoding];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row.selectorName
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    if (row.hookableBOOL) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Observe original live value"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            RYGRuntimeBeginLiveObservation(@[method]);
            [RYGUtils showToastForDuration:1.5 title:@"Live observer installed" subtitle:@"Waiting for Instagram to call this method"];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
            [weakSelf.tableView reloadData];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
            [weakSelf.tableView reloadData];
        }]];
        if (forced) {
            [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
                [weakSelf.tableView reloadData];
            }]];
        }
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy method details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@",
                                                 row.classMethod ? @"+" : @"-",
                                                 weakSelf.classRow.className ?: @"",
                                                 row.selectorName ?: @"",
                                                 row.typeEncoding ?: @""];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = cell ?: self.tableView;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(CGRectGetMidX(self.tableView.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section < 2) {
        RYGRuntimeMethodRow *row = indexPath.section == 0
            ? self.visibleInstanceMethods[indexPath.row]
            : self.visibleClassMethods[indexPath.row];
        [self presentMethodActions:row fromCell:cell];
        return;
    }
    RYGRuntimePropertyRow *row = self.visibleProperties[indexPath.row];
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@", row.name ?: @"", row.attributes ?: @""];
    [RYGUtils showToastForDuration:1.2 title:@"Copied" subtitle:row.name];
}

@end

#pragma mark - Image browser

@interface RYGRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *classRows;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *symbolRows;
@property (nonatomic, copy) NSArray *visibleRows;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, assign, getter=isScanning) BOOL scanning;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation RYGRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = RYGLocalized(@"Runtime browser");
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.classRows = @[];
    self.symbolRows = @[];
    self.visibleRows = @[];

    NSInteger storedMode = [NSUserDefaults.standardUserDefaults integerForKey:kRYGRuntimeModeKey];

    UIView *controlBar = [UIView new];
    controlBar.translatesAutoresizingMaskIntoConstraints = NO;
    controlBar.backgroundColor = UIColor.clearColor;
    [self.view addSubview:controlBar];

    self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageButton.accessibilityIdentifier = @"RYGRuntimeBrowserLiveScan";
    self.imageButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    self.imageButton.showsMenuAsPrimaryAction = YES;
    [self.imageButton setTitle:RYGLocalized(@"Image") forState:UIControlStateNormal];
    RYGLiquidGlassConfigureButton(self.imageButton, NO);
    [controlBar addSubview:self.imageButton];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[RYGLocalized(@"Objective-C"), RYGLocalized(@"Mach-O")]];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.modeControl.selectedSegmentIndex = storedMode == RYGRuntimeBrowserModeMachOSymbols
        ? RYGRuntimeBrowserModeMachOSymbols : RYGRuntimeBrowserModeObjectiveC;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [controlBar addSubview:self.modeControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [controlBar.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8.0],
        [controlBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [controlBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [self.imageButton.topAnchor constraintEqualToAnchor:controlBar.topAnchor],
        [self.imageButton.leadingAnchor constraintEqualToAnchor:controlBar.leadingAnchor],
        [self.imageButton.trailingAnchor constraintEqualToAnchor:controlBar.trailingAnchor],
        [self.imageButton.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        [self.modeControl.topAnchor constraintEqualToAnchor:self.imageButton.bottomAnchor constant:8.0],
        [self.modeControl.leadingAnchor constraintEqualToAnchor:controlBar.leadingAnchor],
        [self.modeControl.trailingAnchor constraintEqualToAnchor:controlBar.trailingAnchor],
        [self.modeControl.bottomAnchor constraintEqualToAnchor:controlBar.bottomAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:controlBar.bottomAnchor constant:4.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    [self updateSearchPlaceholder];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(scanSelectedImage)];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.emptyLabel = [UILabel new];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    [self refreshRuntimeImages];
    [self scanSelectedImage];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)updateSearchPlaceholder {
    self.searchController.searchBar.placeholder = self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeObjectiveC
        ? RYGLocalized(@"Class name")
        : RYGLocalized(@"Symbol name or section");
}

- (void)refreshRuntimeImages {
    self.images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *storedIdentity = [NSUserDefaults.standardUserDefaults stringForKey:kRYGRuntimeSelectedImageKey];
    if (!self.selectedImagePath.length || ![self.images containsObject:self.selectedImagePath]) {
        self.selectedImagePath = nil;
        for (NSString *path in self.images) {
            BOOL exactIdentity = storedIdentity.length && [RYGRuntimeImagePersistenceID(path) isEqualToString:storedIdentity];
            BOOL legacyName = storedIdentity.length && ![storedIdentity containsString:@"/"]
                && [[RYGRuntimeBrowserEngine shortNameForImagePath:path] isEqualToString:storedIdentity];
            if (exactIdentity || legacyName) {
                self.selectedImagePath = path;
                [NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImagePersistenceID(path) forKey:kRYGRuntimeSelectedImageKey];
                break;
            }
        }
        if (!self.selectedImagePath) self.selectedImagePath = self.images.firstObject;
    }
    [self rebuildImageMenu];
}

- (void)rebuildImageMenu {
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    NSString *mainPath = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    for (NSString *path in self.images) {
        NSString *name = [RYGRuntimeBrowserEngine shortNameForImagePath:path];
        UIAction *action = [UIAction actionWithTitle:name
                                              image:[UIImage systemImageNamed:[path isEqualToString:mainPath] ? @"app" : @"shippingbox"]
                                         identifier:nil
                                            handler:^(__kindof UIAction *item) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.selectedImagePath = path;
            [NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImagePersistenceID(path) forKey:kRYGRuntimeSelectedImageKey];
            [self rebuildImageMenu];
            [self scanSelectedImage];
        }];
        action.state = [path isEqualToString:self.selectedImagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    NSString *name = self.selectedImagePath.length
        ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath]
        : RYGLocalized(@"No loaded image");
    NSString *title = [NSString stringWithFormat:RYGLocalized(@"Image: %@"), name];
    [self.imageButton setTitle:title forState:UIControlStateNormal];
    UIButtonConfiguration *configuration = self.imageButton.configuration;
    if (configuration) {
        configuration.title = title;
        if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets];
        self.imageButton.configuration = configuration;
    }
    self.imageButton.menu = [UIMenu menuWithTitle:RYGLocalized(@"Loaded executable and frameworks") children:actions];
    [self.imageButton invalidateIntrinsicContentSize];
}

- (void)modeChanged:(UISegmentedControl *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.selectedSegmentIndex forKey:kRYGRuntimeModeKey];
    [self updateSearchPlaceholder];
    [self scanSelectedImage];
}

- (void)setScanning:(BOOL)scanning {
    _scanning = scanning;
    self.navigationItem.rightBarButtonItem.enabled = !scanning;
    if (scanning) {
        [self.spinner startAnimating];
        self.tableView.backgroundView = self.spinner;
    } else {
        [self.spinner stopAnimating];
        self.tableView.backgroundView = self.visibleRows.count ? nil : self.emptyLabel;
    }
}

- (void)scanSelectedImage {
    [self refreshRuntimeImages];
    NSString *path = self.selectedImagePath.copy;
    if (!path.length) {
        self.classRows = @[];
        self.symbolRows = @[];
        [self applySearchFilter];
        return;
    }

    RYGRuntimeBrowserMode mode = (RYGRuntimeBrowserMode)self.modeControl.selectedSegmentIndex;
    NSUInteger generation = ++self.scanGeneration;
    self.scanning = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *rows = mode == RYGRuntimeBrowserModeObjectiveC
            ? RYGRuntimeClassesForImagePath(path)
            : [RYGRuntimeBrowserEngine machOSymbolsForImagePath:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.scanGeneration) return;
            if (mode == RYGRuntimeBrowserModeObjectiveC) self.classRows = rows;
            else self.symbolRows = rows;
            self.scanning = NO;
            [self applySearchFilter];
        });
    });
}

- (void)applySearchFilter {
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL objectiveC = self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeObjectiveC;
    NSArray *source = objectiveC ? self.classRows : self.symbolRows;
    if (!query.length) {
        self.visibleRows = source;
    } else if (objectiveC) {
        self.visibleRows = [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGRuntimeClassRow *row, NSDictionary *bindings) {
            return RYGRuntimeSearchMatches(row.className, query);
        }]];
    } else {
        self.visibleRows = [source filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMachOSymbol *row, NSDictionary *bindings) {
            return RYGRuntimeSearchMatches([NSString stringWithFormat:@"%@ %@", row.name ?: @"", row.kind ?: @""], query);
        }]];
    }

    self.emptyLabel.text = objectiveC
        ? RYGLocalized(@"No Objective-C class matched this loaded image. Classes are shown as the runtime owns them; methods are inspected only after opening a class.")
        : RYGLocalized(@"No Mach-O symbol matched this loaded image.");
    self.tableView.backgroundView = self.visibleRows.count || self.isScanning ? (self.isScanning ? self.spinner : nil) : self.emptyLabel;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self applySearchFilter];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visibleRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.5 weight:UIFontWeightSemibold];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;

    if (self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeObjectiveC) {
        RYGRuntimeClassRow *row = self.visibleRows[indexPath.row];
        cell.textLabel.text = row.className;
        cell.detailTextLabel.text = RYGLocalized(@"Open declared instance methods, class methods and properties");
        cell.imageView.image = [UIImage systemImageNamed:@"cube.transparent"];
        cell.imageView.tintColor = UIColor.secondaryLabelColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        RYGMachOSymbol *row = self.visibleRows[indexPath.row];
        cell.textLabel.text = row.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 0x%llx%@", row.kind ?: @"Symbol", row.address,
                                     row.external ? @" · external" : @""];
        cell.imageView.image = [UIImage systemImageNamed:[row.kind isEqualToString:@"Function"] ? @"function" : @"number"];
        cell.imageView.tintColor = UIColor.secondaryLabelColor;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.visibleRows.count) return;

    if (self.modeControl.selectedSegmentIndex == RYGRuntimeBrowserModeObjectiveC) {
        RYGRuntimeClassRow *row = self.visibleRows[indexPath.row];
        RYGRuntimeClassDetailViewController *detail = [[RYGRuntimeClassDetailViewController alloc] initWithClassRow:row
                                                                                                         imagePath:self.selectedImagePath];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }

    RYGMachOSymbol *symbol = self.visibleRows[indexPath.row];
    UIPasteboard.generalPasteboard.string = symbol.name;
    [RYGUtils showToastForDuration:1.2 title:@"Copied" subtitle:symbol.name];
}

@end