#import "RYGRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString *const kRYGRuntimeSelectedImageKey = @"ryg_runtime_browser_selected_image";

typedef NS_ENUM(NSInteger, RYGRuntimeRootMode) {
    RYGRuntimeRootModeObjectiveC = 0,
    RYGRuntimeRootModeMachO,
};

typedef NS_ENUM(NSInteger, RYGRuntimeMemberSection) {
    RYGRuntimeMemberSectionInstanceMethods = 0,
    RYGRuntimeMemberSectionClassMethods,
    RYGRuntimeMemberSectionProperties,
    RYGRuntimeMemberSectionClassProperties,
};

@interface RYGRuntimeMethodEntry : NSObject
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, copy) NSString *implementationImage;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, strong, nullable) RYGRuntimeBoolMethod *boolMethod;
@end
@implementation RYGRuntimeMethodEntry @end

@interface RYGRuntimePropertyEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *attributes;
@property (nonatomic, assign) BOOL classProperty;
@end
@implementation RYGRuntimePropertyEntry @end

static NSString *RYGRuntimeImagePersistenceID(NSString *path) {
    NSString *standard = path.stringByStandardizingPath;
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static NSString *RYGRuntimeCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGRuntimeImageMatches(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    NSString *a = RYGRuntimeCanonicalPath(left);
    NSString *b = RYGRuntimeCanonicalPath(right);
    if ([a isEqualToString:b]) return YES;
    return a.lastPathComponent.length && [a.lastPathComponent isEqualToString:b.lastPathComponent];
}

static NSString *RYGRuntimeNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    BOOL previousSpace = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        BOOL alphaNumeric = (character >= 'a' && character <= 'z') ||
                            (character >= '0' && character <= '9');
        if (alphaNumeric) {
            [result appendFormat:@"%C", character];
            previousSpace = NO;
        } else if (!previousSpace) {
            [result appendString:@" "];
            previousSpace = YES;
        }
    }
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSArray<NSString *> *RYGRuntimeSearchTokens(NSString *query) {
    NSString *normalized = RYGRuntimeNormalize(query);
    if (!normalized.length) return @[];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *token in [normalized componentsSeparatedByString:@" "]) {
        if (token.length) [tokens addObject:token];
    }
    return tokens.copy;
}

static BOOL RYGRuntimeTextMatchesTokens(NSString *value, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *normalized = RYGRuntimeNormalize(value);
    NSString *compact = [normalized stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in tokens) {
        if ([normalized rangeOfString:token].location == NSNotFound &&
            [compact rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

static NSArray<NSString *> *RYGRuntimeClassNamesForImage(NSString *imagePath) {
    if (!imagePath.length) return @[];
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    unsigned int count = 0;
    const char **rawNames = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &count);
    if ((!rawNames || count == 0) && imagePath.stringByResolvingSymlinksInPath.length) {
        if (rawNames) free(rawNames);
        NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
        rawNames = objc_copyClassNamesForImage(resolved.fileSystemRepresentation, &count);
    }
    if (rawNames) {
        for (unsigned int index = 0; index < count; index++) {
            if (!rawNames[index] || !*rawNames[index]) continue;
            NSString *name = [NSString stringWithUTF8String:rawNames[index]];
            if (name.length) [names addObject:name];
        }
        free(rawNames);
    }

    if (!names.count) {
        int total = objc_getClassList(NULL, 0);
        if (total > 0 && total < 500000) {
            Class __unsafe_unretained *classes = calloc((size_t)total, sizeof(Class));
            int filled = classes ? objc_getClassList(classes, total) : 0;
            for (int index = 0; index < filled; index++) {
                Class cls = classes[index];
                const char *rawImage = cls ? class_getImageName(cls) : NULL;
                if (!rawImage) continue;
                NSString *actualImage = [NSString stringWithUTF8String:rawImage];
                if (!RYGRuntimeImageMatches(actualImage, imagePath)) continue;
                const char *rawClassName = class_getName(cls);
                if (!rawClassName || !*rawClassName) continue;
                NSString *name = [NSString stringWithUTF8String:rawClassName];
                if (name.length) [names addObject:name];
            }
            free(classes);
        }
    }
    return [names.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static const char *RYGRuntimeSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
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

static BOOL RYGRuntimeMethodIsHookableBool(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGRuntimeSkipQualifiers(encoded);
    RYGRuntimeArgumentKind argument = RYGRuntimeArgumentKindForMethod(method);
    return type && strchr("BcC", *type) != NULL &&
           argument >= RYGRuntimeArgumentNone && argument <= RYGRuntimeArgumentInteger;
}

static RYGRuntimeBoolMethod *RYGRuntimeBoolMethodForMethod(NSString *className,
                                                           NSString *imagePath,
                                                           Method method,
                                                           BOOL classMethod) {
    if (!RYGRuntimeMethodIsHookableBool(method)) return nil;
    SEL selector = method_getName(method);
    if (!selector) return nil;
    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.imagePath = imagePath ?: @"";
    row.className = className ?: @"";
    row.selectorName = NSStringFromSelector(selector) ?: @"";
    row.classMethod = classMethod;
    row.argumentKind = RYGRuntimeArgumentKindForMethod(method);
    const char *types = method_getTypeEncoding(method);
    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    return row;
}

static NSString *RYGRuntimeImplementationImage(Method method) {
    IMP implementation = method ? method_getImplementation(method) : NULL;
    Dl_info info = {0};
    if (!implementation || !dladdr((const void *)implementation, &info) || !info.dli_fname) return @"";
    return [NSString stringWithUTF8String:info.dli_fname].lastPathComponent ?: @"";
}

static BOOL RYGRuntimeClassMatchesTokens(NSString *className, NSArray<NSString *> *tokens) {
    if (!tokens.count || RYGRuntimeTextMatchesTokens(className, tokens)) return YES;
    Class cls = objc_lookUpClass(className.UTF8String);
    if (!cls) return NO;
    for (NSUInteger pass = 0; pass < 2; pass++) {
        Class owner = pass ? object_getClass(cls) : cls;
        unsigned int methodCount = 0;
        Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
        for (unsigned int index = 0; methods && index < methodCount; index++) {
            Method method = methods[index];
            SEL selector = method_getName(method);
            const char *types = method_getTypeEncoding(method);
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@",
                              className,
                              selector ? NSStringFromSelector(selector) : @"",
                              types ? [NSString stringWithUTF8String:types] : @""];
            if (RYGRuntimeTextMatchesTokens(text, tokens)) {
                free(methods);
                return YES;
            }
        }
        if (methods) free(methods);

        unsigned int propertyCount = 0;
        objc_property_t *properties = owner ? class_copyPropertyList(owner, &propertyCount) : NULL;
        for (unsigned int index = 0; properties && index < propertyCount; index++) {
            const char *rawName = property_getName(properties[index]);
            const char *rawAttributes = property_getAttributes(properties[index]);
            NSString *text = [NSString stringWithFormat:@"%@ %@ %@",
                              className,
                              rawName ? [NSString stringWithUTF8String:rawName] : @"",
                              rawAttributes ? [NSString stringWithUTF8String:rawAttributes] : @""];
            if (RYGRuntimeTextMatchesTokens(text, tokens)) {
                free(properties);
                return YES;
            }
        }
        if (properties) free(properties);
    }
    return NO;
}

static void RYGStyleRuntimeCell(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    if (!cell.backgroundView) cell.backgroundView = RYGLiquidGlassView(NO, YES, nil);
}

#pragma mark - Class detail

@interface RYGRuntimeClassDetailViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodEntry *> *instanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodEntry *> *classMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyEntry *> *properties;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyEntry *> *classProperties;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodEntry *> *visibleInstanceMethods;
@property (nonatomic, copy) NSArray<RYGRuntimeMethodEntry *> *visibleClassMethods;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyEntry *> *visibleProperties;
@property (nonatomic, copy) NSArray<RYGRuntimePropertyEntry *> *visibleClassProperties;
@property (nonatomic, copy) NSArray<NSNumber *> *visibleSections;
@property (nonatomic, assign) NSUInteger generation;
@end

@implementation RYGRuntimeClassDetailViewController

- (instancetype)initWithClassName:(NSString *)className imagePath:(NSString *)imagePath {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _className = [className copy] ?: @"";
        _imagePath = [imagePath copy] ?: @"";
        _instanceMethods = @[];
        _classMethods = @[];
        _properties = @[];
        _classProperties = @[];
        _visibleSections = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.className;
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(@"Runtime Class");
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Method, property or ABI";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    __weak typeof(self) weakSelf = self;
    UIAction *refresh = [UIAction actionWithTitle:@"Refresh live class"
                                            image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                       identifier:nil
                                          handler:^(__unused UIAction *action) { [weakSelf reloadMembers]; }];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                 menu:[UIMenu menuWithTitle:@"Runtime Class" children:@[refresh]]];
    RYGLiquidGlassApplyToViewController(self);
    [self reloadMembers];
}

- (void)reloadMembers {
    NSString *className = self.className.copy;
    NSString *imagePath = self.imagePath.copy;
    NSUInteger generation = ++self.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<RYGRuntimeMethodEntry *> *instanceMethods = [NSMutableArray array];
        NSMutableArray<RYGRuntimeMethodEntry *> *classMethods = [NSMutableArray array];
        NSMutableArray<RYGRuntimePropertyEntry *> *properties = [NSMutableArray array];
        NSMutableArray<RYGRuntimePropertyEntry *> *classProperties = [NSMutableArray array];
        Class cls = objc_lookUpClass(className.UTF8String);
        if (cls) {
            for (NSUInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                NSMutableArray<RYGRuntimeMethodEntry *> *methodRows = classMethod ? classMethods : instanceMethods;
                NSMutableArray<RYGRuntimePropertyEntry *> *propertyRows = classMethod ? classProperties : properties;

                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                for (unsigned int index = 0; methods && index < methodCount; index++) {
                    Method method = methods[index];
                    SEL selector = method_getName(method);
                    if (!selector) continue;
                    RYGRuntimeMethodEntry *entry = [RYGRuntimeMethodEntry new];
                    entry.selectorName = NSStringFromSelector(selector) ?: @"";
                    const char *types = method_getTypeEncoding(method);
                    entry.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                    entry.implementationImage = RYGRuntimeImplementationImage(method);
                    entry.classMethod = classMethod;
                    entry.boolMethod = RYGRuntimeBoolMethodForMethod(className, imagePath, method, classMethod);
                    [methodRows addObject:entry];
                }
                if (methods) free(methods);

                unsigned int propertyCount = 0;
                objc_property_t *runtimeProperties = owner ? class_copyPropertyList(owner, &propertyCount) : NULL;
                for (unsigned int index = 0; runtimeProperties && index < propertyCount; index++) {
                    const char *rawName = property_getName(runtimeProperties[index]);
                    if (!rawName || !*rawName) continue;
                    RYGRuntimePropertyEntry *entry = [RYGRuntimePropertyEntry new];
                    entry.name = [NSString stringWithUTF8String:rawName] ?: @"";
                    const char *rawAttributes = property_getAttributes(runtimeProperties[index]);
                    entry.attributes = rawAttributes ? [NSString stringWithUTF8String:rawAttributes] : @"";
                    entry.classProperty = classMethod;
                    [propertyRows addObject:entry];
                }
                if (runtimeProperties) free(runtimeProperties);
            }
        }

        [instanceMethods sortUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
            RYGRuntimeMethodEntry *left = leftObject, *right = rightObject;
            return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
        }];
        [classMethods sortUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
            RYGRuntimeMethodEntry *left = leftObject, *right = rightObject;
            return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
        }];
        [properties sortUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
            RYGRuntimePropertyEntry *left = leftObject, *right = rightObject;
            return [left.name localizedCaseInsensitiveCompare:right.name];
        }];
        [classProperties sortUsingComparator:^NSComparisonResult(id leftObject, id rightObject) {
            RYGRuntimePropertyEntry *left = leftObject, *right = rightObject;
            return [left.name localizedCaseInsensitiveCompare:right.name];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.generation) return;
            self.instanceMethods = instanceMethods.copy;
            self.classMethods = classMethods.copy;
            self.properties = properties.copy;
            self.classProperties = classProperties.copy;
            [self applyFilter];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self applyFilter];
}

- (NSArray<RYGRuntimeMethodEntry *> *)filterMethods:(NSArray<RYGRuntimeMethodEntry *> *)source tokens:(NSArray<NSString *> *)tokens {
    if (!tokens.count) return source ?: @[];
    NSMutableArray *rows = [NSMutableArray array];
    for (RYGRuntimeMethodEntry *entry in source) {
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@ %@", self.className, entry.selectorName, entry.typeEncoding, entry.implementationImage];
        if (RYGRuntimeTextMatchesTokens(text, tokens)) [rows addObject:entry];
    }
    return rows.copy;
}

- (NSArray<RYGRuntimePropertyEntry *> *)filterProperties:(NSArray<RYGRuntimePropertyEntry *> *)source tokens:(NSArray<NSString *> *)tokens {
    if (!tokens.count) return source ?: @[];
    NSMutableArray *rows = [NSMutableArray array];
    for (RYGRuntimePropertyEntry *entry in source) {
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@", self.className, entry.name, entry.attributes];
        if (RYGRuntimeTextMatchesTokens(text, tokens)) [rows addObject:entry];
    }
    return rows.copy;
}

- (void)applyFilter {
    NSArray<NSString *> *tokens = RYGRuntimeSearchTokens(self.searchController.searchBar.text ?: @"");
    self.visibleInstanceMethods = [self filterMethods:self.instanceMethods tokens:tokens];
    self.visibleClassMethods = [self filterMethods:self.classMethods tokens:tokens];
    self.visibleProperties = [self filterProperties:self.properties tokens:tokens];
    self.visibleClassProperties = [self filterProperties:self.classProperties tokens:tokens];
    NSMutableArray<NSNumber *> *sections = [NSMutableArray array];
    if (self.visibleInstanceMethods.count) [sections addObject:@(RYGRuntimeMemberSectionInstanceMethods)];
    if (self.visibleClassMethods.count) [sections addObject:@(RYGRuntimeMemberSectionClassMethods)];
    if (self.visibleProperties.count) [sections addObject:@(RYGRuntimeMemberSectionProperties)];
    if (self.visibleClassProperties.count) [sections addObject:@(RYGRuntimeMemberSectionClassProperties)];
    self.visibleSections = sections.copy;
    [self.tableView reloadData];
}

- (NSArray *)rowsForSectionKind:(RYGRuntimeMemberSection)kind {
    switch (kind) {
        case RYGRuntimeMemberSectionInstanceMethods: return self.visibleInstanceMethods ?: @[];
        case RYGRuntimeMemberSectionClassMethods: return self.visibleClassMethods ?: @[];
        case RYGRuntimeMemberSectionProperties: return self.visibleProperties ?: @[];
        case RYGRuntimeMemberSectionClassProperties: return self.visibleClassProperties ?: @[];
    }
    return @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return self.visibleSections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section < 0 || section >= (NSInteger)self.visibleSections.count) return 0;
    RYGRuntimeMemberSection kind = (RYGRuntimeMemberSection)self.visibleSections[(NSUInteger)section].integerValue;
    return [self rowsForSectionKind:kind].count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section < 0 || section >= (NSInteger)self.visibleSections.count) return nil;
    switch ((RYGRuntimeMemberSection)self.visibleSections[(NSUInteger)section].integerValue) {
        case RYGRuntimeMemberSectionInstanceMethods: return @"Instance Methods";
        case RYGRuntimeMemberSectionClassMethods: return @"Class Methods";
        case RYGRuntimeMemberSectionProperties: return @"Properties";
        case RYGRuntimeMemberSectionClassProperties: return @"Class Properties";
    }
    return nil;
}

- (UIButton *)outputButtonForMethod:(RYGRuntimeBoolMethod *)method {
    NSNumber *forced = method.overrideValue;
    NSNumber *native = method.liveValue;
    NSString *closedTitle = forced ? (forced.boolValue ? @"On" : @"Off") :
        (native ? (native.boolValue ? @"Native On" : @"Native Off") : @"Native");
    __weak typeof(self) weakSelf = self;
    UIAction *nativeAction = [UIAction actionWithTitle:@"Native" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:nil forMethod:method]; [weakSelf.tableView reloadData];
    }];
    nativeAction.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    UIAction *forceOn = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method]; [weakSelf.tableView reloadData];
    }];
    forceOn.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *forceOff = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method]; [weakSelf.tableView reloadData];
    }];
    forceOff.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.menu = [UIMenu menuWithTitle:@"BOOL output" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[nativeAction, forceOn, forceOff]];
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *configuration = button.configuration;
    if (configuration) {
        configuration.title = closedTitle;
        if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets];
        button.configuration = configuration;
    } else [button setTitle:closedTitle forState:UIControlStateNormal];
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGRuntimeMember";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    RYGStyleRuntimeCell(cell);
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    RYGRuntimeMemberSection kind = (RYGRuntimeMemberSection)self.visibleSections[(NSUInteger)indexPath.section].integerValue;
    NSArray *rows = [self rowsForSectionKind:kind];
    if ((NSUInteger)indexPath.row >= rows.count) return cell;
    if (kind == RYGRuntimeMemberSectionInstanceMethods || kind == RYGRuntimeMemberSectionClassMethods) {
        RYGRuntimeMethodEntry *entry = rows[(NSUInteger)indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", entry.classMethod ? @"+" : @"−", entry.selectorName ?: @""];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
        cell.textLabel.numberOfLines = 2;
        NSMutableArray<NSString *> *details = [NSMutableArray array];
        if (entry.typeEncoding.length) [details addObject:entry.typeEncoding];
        if (entry.implementationImage.length) [details addObject:entry.implementationImage];
        if (entry.boolMethod) [details addObject:@"BOOL override supported"];
        cell.detailTextLabel.text = [details componentsJoinedByString:@" · "];
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.numberOfLines = 2;
        if (entry.boolMethod) cell.accessoryView = [self outputButtonForMethod:entry.boolMethod];
    } else {
        RYGRuntimePropertyEntry *entry = rows[(NSUInteger)indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"@property %@", entry.name ?: @""];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
        cell.textLabel.numberOfLines = 2;
        cell.detailTextLabel.text = entry.attributes ?: @"";
        cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.numberOfLines = 2;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *source = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGRuntimeMemberSection kind = (RYGRuntimeMemberSection)self.visibleSections[(NSUInteger)indexPath.section].integerValue;
    NSArray *rows = [self rowsForSectionKind:kind];
    if ((NSUInteger)indexPath.row >= rows.count) return;
    if (kind == RYGRuntimeMemberSectionProperties || kind == RYGRuntimeMemberSectionClassProperties) {
        RYGRuntimePropertyEntry *entry = rows[(NSUInteger)indexPath.row];
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@", entry.name ?: @"", entry.attributes ?: @""];
        [RYGUtils showToastForDuration:0.9 title:@"Property copied" subtitle:entry.name];
        return;
    }

    RYGRuntimeMethodEntry *entry = rows[(NSUInteger)indexPath.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:entry.selectorName
                                                                    message:[NSString stringWithFormat:@"%@\n%@", entry.typeEncoding ?: @"", entry.implementationImage ?: @""]
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    if (entry.boolMethod) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Observe native value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { RYGRuntimeBeginLiveObservation(@[entry.boolMethod]); }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force On" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [RYGRuntimeBrowserEngine setOverride:@YES forMethod:entry.boolMethod]; [self.tableView reloadData]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force Off" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [RYGRuntimeBrowserEngine setOverride:@NO forMethod:entry.boolMethod]; [self.tableView reloadData]; }]];
        if (entry.boolMethod.overrideValue) [sheet addAction:[UIAlertAction actionWithTitle:@"Use Native" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [RYGRuntimeBrowserEngine setOverride:nil forMethod:entry.boolMethod]; [self.tableView reloadData]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy method details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@[%@ %@] %@", entry.classMethod ? @"+" : @"−", self.className, entry.selectorName ?: @"", entry.typeEncoding ?: @""];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = source ?: self.view;
        sheet.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Runtime root

@interface RYGRuntimeBrowserViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *imageButton;
@property (nonatomic, strong) UIButton *modeButton;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSString *> *images;
@property (nonatomic, copy) NSString *selectedImagePath;
@property (nonatomic, assign) RYGRuntimeRootMode mode;
@property (nonatomic, copy) NSArray<NSString *> *allClassNames;
@property (nonatomic, copy) NSArray<NSString *> *visibleClassNames;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *allSymbols;
@property (nonatomic, copy) NSArray<RYGMachOSymbol *> *visibleSymbols;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, assign) NSUInteger searchGeneration;
@property (nonatomic, assign, getter=isScanning) BOOL scanning;
@end

@implementation RYGRuntimeBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Runtime Browser";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(@"Runtime Browser");
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.mode = RYGRuntimeRootModeObjectiveC;
    self.allClassNames = @[];
    self.visibleClassNames = @[];
    self.allSymbols = @[];
    self.visibleSymbols = @[];

    self.imageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.imageButton.showsMenuAsPrimaryAction = YES;
    self.imageButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modeButton.showsMenuAsPrimaryAction = YES;

    UIStackView *selectors = [[UIStackView alloc] initWithArrangedSubviews:@[self.imageButton, self.modeButton]];
    selectors.translatesAutoresizingMaskIntoConstraints = NO;
    selectors.axis = UILayoutConstraintAxisHorizontal;
    selectors.alignment = UIStackViewAlignmentCenter;
    selectors.spacing = 8.0;
    [self.imageButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.modeButton setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [self.view addSubview:selectors];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    [self.view addSubview:self.tableView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [selectors.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8.0],
        [selectors.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16.0],
        [selectors.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor constant:-16.0],
        [self.tableView.topAnchor constraintEqualToAnchor:selectors.bottomAnchor constant:6.0],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class, method or property";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.emptyLabel = [UILabel new];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];

    __weak typeof(self) weakSelf = self;
    UIAction *refresh = [UIAction actionWithTitle:@"Refresh live runtime" image:[UIImage systemImageNamed:@"arrow.clockwise"] identifier:nil handler:^(__unused UIAction *action) { [weakSelf refreshAndScan]; }];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] menu:[UIMenu menuWithTitle:@"Runtime" children:@[refresh]]];

    [self refreshRuntimeImages];
    [self rebuildImageMenu];
    [self rebuildModeMenu];
    RYGLiquidGlassApplyToViewController(self);
    [self scanCurrentMode];
}

- (void)refreshRuntimeImages {
    self.images = [RYGRuntimeBrowserEngine runtimeImagePaths] ?: @[];
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kRYGRuntimeSelectedImageKey];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if (!self.selectedImagePath.length || ![self.images containsObject:self.selectedImagePath]) {
        self.selectedImagePath = nil;
        for (NSString *path in self.images) if (stored.length && [RYGRuntimeImagePersistenceID(path) isEqualToString:stored]) { self.selectedImagePath = path; break; }
        if (!self.selectedImagePath.length) for (NSString *path in self.images) if (RYGRuntimeImageMatches(path, main)) { self.selectedImagePath = path; break; }
        if (!self.selectedImagePath.length) self.selectedImagePath = self.images.firstObject;
    }
}

- (void)rebuildImageMenu {
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSString *path in self.images) {
        UIAction *action = [UIAction actionWithTitle:[RYGRuntimeBrowserEngine shortNameForImagePath:path] image:nil identifier:nil handler:^(__unused UIAction *item) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.selectedImagePath = path;
            [NSUserDefaults.standardUserDefaults setObject:RYGRuntimeImagePersistenceID(path) forKey:kRYGRuntimeSelectedImageKey];
            [self rebuildImageMenu];
            [self scanCurrentMode];
        }];
        action.state = [path isEqualToString:self.selectedImagePath] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.imageButton.menu = [UIMenu menuWithTitle:@"Loaded image" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
    RYGLiquidGlassConfigureButton(self.imageButton, NO);
    UIButtonConfiguration *configuration = self.imageButton.configuration;
    NSString *title = self.selectedImagePath.length ? [RYGRuntimeBrowserEngine shortNameForImagePath:self.selectedImagePath] : @"No image";
    if (configuration) { configuration.title = title; if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets]; self.imageButton.configuration = configuration; }
    else [self.imageButton setTitle:title forState:UIControlStateNormal];
}

- (void)rebuildModeMenu {
    __weak typeof(self) weakSelf = self;
    UIAction *objc = [UIAction actionWithTitle:@"Objective-C Classes" image:[UIImage systemImageNamed:@"square.stack.3d.up"] identifier:nil handler:^(__unused UIAction *action) {
        weakSelf.mode = RYGRuntimeRootModeObjectiveC;
        weakSelf.searchController.searchBar.placeholder = @"Class, method or property";
        [weakSelf rebuildModeMenu]; [weakSelf scanCurrentMode];
    }];
    objc.state = self.mode == RYGRuntimeRootModeObjectiveC ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *macho = [UIAction actionWithTitle:@"Mach-O Symbols" image:[UIImage systemImageNamed:@"function"] identifier:nil handler:^(__unused UIAction *action) {
        weakSelf.mode = RYGRuntimeRootModeMachO;
        weakSelf.searchController.searchBar.placeholder = @"Mach-O symbol";
        [weakSelf rebuildModeMenu]; [weakSelf scanCurrentMode];
    }];
    macho.state = self.mode == RYGRuntimeRootModeMachO ? UIMenuElementStateOn : UIMenuElementStateOff;
    self.modeButton.menu = [UIMenu menuWithTitle:@"Runtime source" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[objc, macho]];
    RYGLiquidGlassConfigureButton(self.modeButton, NO);
    UIButtonConfiguration *configuration = self.modeButton.configuration;
    NSString *title = self.mode == RYGRuntimeRootModeObjectiveC ? @"Classes" : @"Mach-O";
    if (configuration) { configuration.title = title; if (@available(iOS 26.0, *)) [configuration setDefaultContentInsets]; self.modeButton.configuration = configuration; }
    else [self.modeButton setTitle:title forState:UIControlStateNormal];
}

- (void)setScanning:(BOOL)scanning {
    _scanning = scanning;
    if (scanning) { [self.spinner startAnimating]; self.tableView.backgroundView = self.spinner; }
    else {
        [self.spinner stopAnimating];
        BOOL hasRows = self.mode == RYGRuntimeRootModeObjectiveC ? self.visibleClassNames.count > 0 : self.visibleSymbols.count > 0;
        self.tableView.backgroundView = hasRows ? nil : self.emptyLabel;
    }
}

- (void)refreshAndScan { [self refreshRuntimeImages]; [self rebuildImageMenu]; [self scanCurrentMode]; }

- (void)scanCurrentMode {
    NSString *imagePath = self.selectedImagePath.copy;
    NSUInteger generation = ++self.scanGeneration;
    if (!imagePath.length) {
        self.allClassNames = @[]; self.visibleClassNames = @[]; self.allSymbols = @[]; self.visibleSymbols = @[];
        self.emptyLabel.text = @"No loaded app image"; self.scanning = NO; [self.tableView reloadData]; return;
    }
    self.scanning = YES;
    __weak typeof(self) weakSelf = self;
    if (self.mode == RYGRuntimeRootModeObjectiveC) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray<NSString *> *classes = RYGRuntimeClassNamesForImage(imagePath);
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self.scanGeneration || self.mode != RYGRuntimeRootModeObjectiveC || ![self.selectedImagePath isEqualToString:imagePath]) return;
                self.allClassNames = classes ?: @[];
                self.scanning = NO;
                [self applyRootSearch];
            });
        });
    } else {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray<RYGMachOSymbol *> *symbols = [RYGRuntimeBrowserEngine machOSymbolsForImagePath:imagePath];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self.scanGeneration || self.mode != RYGRuntimeRootModeMachO || ![self.selectedImagePath isEqualToString:imagePath]) return;
                self.allSymbols = symbols ?: @[];
                self.scanning = NO;
                [self applyRootSearch];
            });
        });
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyRootSearch]; }

- (void)applyRootSearch {
    NSString *query = self.searchController.searchBar.text ?: @"";
    NSArray<NSString *> *tokens = RYGRuntimeSearchTokens(query);
    if (self.mode == RYGRuntimeRootModeMachO) {
        if (!tokens.count) self.visibleSymbols = self.allSymbols ?: @[];
        else {
            NSMutableArray<RYGMachOSymbol *> *matches = [NSMutableArray array];
            for (RYGMachOSymbol *symbol in self.allSymbols) if (RYGRuntimeTextMatchesTokens([NSString stringWithFormat:@"%@ %@", symbol.name ?: @"", symbol.kind ?: @""], tokens)) [matches addObject:symbol];
            self.visibleSymbols = matches.copy;
        }
        self.emptyLabel.text = query.length ? @"No Mach-O symbol matched" : @"No symbols in this image";
        if (!self.isScanning) self.tableView.backgroundView = self.visibleSymbols.count ? nil : self.emptyLabel;
        [self.tableView reloadData];
        return;
    }

    if (!tokens.count) {
        self.visibleClassNames = self.allClassNames ?: @[];
        self.emptyLabel.text = @"No Objective-C classes in this loaded image";
        if (!self.isScanning) self.tableView.backgroundView = self.visibleClassNames.count ? nil : self.emptyLabel;
        [self.tableView reloadData];
        return;
    }

    NSUInteger generation = ++self.searchGeneration;
    NSArray<NSString *> *classes = self.allClassNames.copy ?: @[];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.16 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSString *> *matches = [NSMutableArray array];
        for (NSString *className in classes) @autoreleasepool { if (RYGRuntimeClassMatchesTokens(className, tokens)) [matches addObject:className]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.searchGeneration || self.mode != RYGRuntimeRootModeObjectiveC) return;
            self.visibleClassNames = matches.copy;
            self.emptyLabel.text = @"No live class/member matched this search";
            if (!self.isScanning) self.tableView.backgroundView = self.visibleClassNames.count ? nil : self.emptyLabel;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.mode == RYGRuntimeRootModeObjectiveC ? self.visibleClassNames.count : self.visibleSymbols.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.mode == RYGRuntimeRootModeObjectiveC) return self.visibleClassNames.count ? [NSString stringWithFormat:@"%lu live classes", (unsigned long)self.visibleClassNames.count] : nil;
    return self.visibleSymbols.count ? [NSString stringWithFormat:@"%lu live symbols", (unsigned long)self.visibleSymbols.count] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGRuntimeRoot";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    RYGStyleRuntimeCell(cell);
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (self.mode == RYGRuntimeRootModeObjectiveC) {
        if ((NSUInteger)indexPath.row >= self.visibleClassNames.count) return cell;
        cell.textLabel.text = self.visibleClassNames[(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = @"Live Objective-C class";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        if ((NSUInteger)indexPath.row >= self.visibleSymbols.count) return cell;
        RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
        cell.textLabel.text = symbol.name;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · 0x%llx%@", symbol.kind ?: @"Symbol", (unsigned long long)symbol.address, symbol.external ? @" · external" : @""];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *source = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.mode == RYGRuntimeRootModeObjectiveC) {
        if ((NSUInteger)indexPath.row >= self.visibleClassNames.count) return;
        RYGRuntimeClassDetailViewController *detail = [[RYGRuntimeClassDetailViewController alloc] initWithClassName:self.visibleClassNames[(NSUInteger)indexPath.row] imagePath:self.selectedImagePath];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    if ((NSUInteger)indexPath.row >= self.visibleSymbols.count) return;
    RYGMachOSymbol *symbol = self.visibleSymbols[(NSUInteger)indexPath.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name message:[NSString stringWithFormat:@"%@\n0x%llx\n%@", symbol.kind ?: @"Symbol", (unsigned long long)symbol.address, symbol.external ? @"external" : @"local"] preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol details" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@ 0x%llx", symbol.kind ?: @"", symbol.name ?: @"", (unsigned long long)symbol.address]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) { sheet.popoverPresentationController.sourceView = source ?: self.view; sheet.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds; }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
