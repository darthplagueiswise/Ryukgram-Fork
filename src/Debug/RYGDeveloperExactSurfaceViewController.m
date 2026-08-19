#import "RYGDeveloperExactSurfaceViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

static const void *kRYGExactSurfaceMethodKey = &kRYGExactSurfaceMethodKey;

@interface RYGDeveloperExactRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) RYGRuntimeBoolMethod *method;
@end
@implementation RYGDeveloperExactRow @end

@interface RYGDeveloperExactGroup : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSArray<RYGDeveloperExactRow *> *rows;
@end
@implementation RYGDeveloperExactGroup @end

static NSString *RYGExactSurfaceTitle(RYGDeveloperExactSurface surface) {
    switch (surface) {
        case RYGDeveloperExactSurfaceStories: return @"Stories · Tray & Grid";
        case RYGDeveloperExactSurfaceBugReport: return @"Bug Report";
        case RYGDeveloperExactSurfaceSettingsVisibility: return @"Hidden Settings Rows";
        case RYGDeveloperExactSurfaceDirectDogfood: return @"Direct Dogfooding";
    }
    return @"Developer";
}

static BOOL RYGExactContains(NSString *value, NSString *needle) {
    return value.length && needle.length &&
        [value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static const char *RYGExactSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGExactArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;

    char encoded[64] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGExactSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGExactSupportedBOOL(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *result = RYGExactSkipQualifiers(encoded);
    RYGRuntimeArgumentKind argument = RYGExactArgumentKind(method);
    return result && *result == 'B'
        && argument >= RYGRuntimeArgumentNone
        && argument <= RYGRuntimeArgumentInteger;
}

static NSArray<NSString *> *RYGExactPrimaryImages(void) {
    NSArray<NSString *> *images = RYGRuntimeBrowserEngine.runtimeImagePaths;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    NSString *main = NSBundle.mainBundle.executablePath;
    for (NSString *path in images) {
        if ([path isEqualToString:main] ||
            [path.stringByResolvingSymlinksInPath isEqualToString:main.stringByResolvingSymlinksInPath]) {
            [selected addObject:path];
            break;
        }
    }
    for (NSString *path in images) {
        if (RYGExactContains(path.lastPathComponent, @"FBShared")) [selected addObject:path];
    }
    return selected.array;
}

static const char **RYGExactCopyClassNames(NSString *imagePath, unsigned int *count) {
    if (count) *count = 0;
    const char **names = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, count);
    if (names) return names;
    NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
    if (![resolved isEqualToString:imagePath])
        return objc_copyClassNamesForImage(resolved.fileSystemRepresentation, count);
    return NULL;
}

static BOOL RYGExactBugReportSelector(NSString *selector) {
    static NSSet<NSString *> *exact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exact = [NSSet setWithArray:@[
            @"showDogfoodingAssistant",
            @"showInternalSettings",
            @"showLoggedOutInternalSettings",
            @"showShakeToReportPreferenceToggle",
            @"isSandboxCreatorAgentEnabled",
        ]];
    });
    return [exact containsObject:selector];
}

static BOOL RYGExactMatchesSurface(RYGDeveloperExactSurface surface,
                                   NSString *className,
                                   NSString *selector) {
    switch (surface) {
        case RYGDeveloperExactSurfaceStories:
            return RYGExactContains(className, @"StoriesTray")
                || RYGExactContains(className, @"StoryTray")
                || RYGExactContains(className, @"StoryGrid")
                || RYGExactContains(selector, @"StoriesTray")
                || RYGExactContains(selector, @"StoryTray")
                || RYGExactContains(selector, @"StoryGrid");

        case RYGDeveloperExactSurfaceBugReport:
            if (RYGExactBugReportSelector(selector)) return YES;
            if (!RYGExactContains(className, @"BugReport")) return NO;
            return RYGExactContains(selector, @"show")
                || RYGExactContains(selector, @"internal")
                || RYGExactContains(selector, @"loggedOut")
                || RYGExactContains(selector, @"dogfood")
                || RYGExactContains(selector, @"sandbox")
                || RYGExactContains(selector, @"shake");

        case RYGDeveloperExactSurfaceSettingsVisibility:
            if (!RYGExactContains(className, @"Settings")) return NO;
            return [selector hasPrefix:@"shouldShow"]
                || [selector hasPrefix:@"canShow"]
                || [selector hasPrefix:@"showInSettings"]
                || [selector hasPrefix:@"isVisible"]
                || [selector hasPrefix:@"isHidden"]
                || [selector hasPrefix:@"isDisabled"]
                || [selector hasPrefix:@"isEnabled"]
                || [selector hasPrefix:@"isEligible"]
                || [selector hasPrefix:@"canSee"];

        case RYGDeveloperExactSurfaceDirectDogfood:
            return RYGExactContains(className, @"DogfoodingSettings")
                || RYGExactContains(className, @"DogfoodingAssistant")
                || RYGExactContains(selector, @"dogfood");
    }
    return NO;
}

static NSString *RYGExactPrettySelector(NSString *selector) {
    if (!selector.length) return @"Option";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < selector.length; index++) {
        unichar character = [selector characterAtIndex:index];
        if (character == ':' || character == '_') {
            if (result.length && ![[result substringFromIndex:result.length - 1] isEqualToString:@" "]) [result appendString:@" "];
            continue;
        }
        if (index > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:character]) [result appendString:@" "];
        [result appendFormat:@"%C", character];
    }
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSArray<RYGDeveloperExactGroup *> *RYGExactScanSurface(RYGDeveloperExactSurface surface) {
    NSMutableDictionary<NSString *, NSMutableArray<RYGDeveloperExactRow *> *> *byClass = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];

    for (NSString *imagePath in RYGExactPrimaryImages()) {
        unsigned int classCount = 0;
        const char **classNames = RYGExactCopyClassNames(imagePath, &classCount);
        if (!classNames) continue;

        for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
            const char *rawClassName = classNames[classIndex];
            if (!rawClassName || !*rawClassName) continue;
            Class cls = objc_lookUpClass(rawClassName);
            if (!cls) continue;
            NSString *className = [NSString stringWithUTF8String:rawClassName];

            for (NSUInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    if (!RYGExactSupportedBOOL(method)) continue;
                    SEL selectorValue = method_getName(method);
                    if (!selectorValue) continue;
                    NSString *selector = NSStringFromSelector(selectorValue);
                    if (!RYGExactMatchesSurface(surface, className, selector)) continue;

                    RYGRuntimeBoolMethod *runtimeMethod = [RYGRuntimeBoolMethod new];
                    runtimeMethod.imagePath = imagePath;
                    runtimeMethod.className = className ?: @"";
                    runtimeMethod.selectorName = selector ?: @"";
                    runtimeMethod.classMethod = classMethod;
                    runtimeMethod.argumentKind = RYGExactArgumentKind(method);
                    const char *types = method_getTypeEncoding(method);
                    runtimeMethod.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                    if (!runtimeMethod.overrideKey.length || [dedupe containsObject:runtimeMethod.overrideKey]) continue;
                    [dedupe addObject:runtimeMethod.overrideKey];

                    RYGDeveloperExactRow *row = [RYGDeveloperExactRow new];
                    row.title = RYGExactPrettySelector(selector);
                    row.method = runtimeMethod;
                    NSMutableArray *bucket = byClass[className];
                    if (!bucket) { bucket = [NSMutableArray array]; byClass[className] = bucket; }
                    [bucket addObject:row];
                }
                if (methods) free(methods);
            }
        }
        free(classNames);
    }

    NSArray<NSString *> *classNames = [byClass.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<RYGDeveloperExactGroup *> *groups = [NSMutableArray arrayWithCapacity:classNames.count];
    for (NSString *className in classNames) {
        NSArray *rows = [byClass[className] sortedArrayUsingComparator:^NSComparisonResult(RYGDeveloperExactRow *left, RYGDeveloperExactRow *right) {
            return [left.title localizedCaseInsensitiveCompare:right.title];
        }];
        RYGDeveloperExactGroup *group = [RYGDeveloperExactGroup new];
        group.className = className;
        group.rows = rows;
        [groups addObject:group];
    }
    return groups.copy;
}

static UIViewController *RYGExactTopController(UIViewController *controller) {
    if (!controller) return nil;
    if (controller.presentedViewController) return RYGExactTopController(controller.presentedViewController);
    if ([controller isKindOfClass:UINavigationController.class])
        return RYGExactTopController(((UINavigationController *)controller).visibleViewController);
    if ([controller isKindOfClass:UITabBarController.class])
        return RYGExactTopController(((UITabBarController *)controller).selectedViewController);
    return controller;
}

static NSArray<UIWindow *> *RYGExactApplicationWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    } else if (UIApplication.sharedApplication.keyWindow) {
        [windows addObject:UIApplication.sharedApplication.keyWindow];
    }
    return windows.copy;
}

static id RYGExactCurrentUserSession(void) {
    SEL selector = NSSelectorFromString(@"userSession");
    for (UIWindow *window in RYGExactApplicationWindows()) {
        if ([window respondsToSelector:selector]) {
            id session = ((id (*)(id, SEL))objc_msgSend)(window, selector);
            if (session) return session;
        }
    }
    return nil;
}

static UIViewController *RYGExactCurrentPresenter(void) {
    UIWindow *key = nil;
    for (UIWindow *window in RYGExactApplicationWindows()) {
        if (window.isKeyWindow) { key = window; break; }
        if (!key && !window.hidden && window.alpha > 0.0) key = window;
    }
    return RYGExactTopController(key.rootViewController);
}

static BOOL RYGExactValidateTwoObjectVoidMethod(Method method) {
    if (!method || method_getNumberOfArguments(method) != 4) return NO;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (*RYGExactSkipQualifiers(returnType) != 'v') return NO;
    for (unsigned int index = 2; index < 4; index++) {
        char argument[32] = {0};
        method_getArgumentType(method, index, argument, sizeof(argument));
        if (*RYGExactSkipQualifiers(argument) != '@') return NO;
    }
    return YES;
}

static BOOL RYGExactCanOpenDirectNotesDogfood(void) {
    NSArray<NSString *> *classNames = @[
        @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs",
        @"IGDirectNotesDogfoodingSettingsStaticFuncs",
    ];
    SEL selector = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        Method method = cls ? class_getClassMethod(cls, selector) : NULL;
        if (RYGExactValidateTwoObjectVoidMethod(method)) return YES;
    }
    return NO;
}

static BOOL RYGExactOpenDirectNotesDogfood(void) {
    UIViewController *presenter = RYGExactCurrentPresenter();
    id userSession = RYGExactCurrentUserSession();
    if (!presenter || !userSession) return NO;

    NSArray<NSString *> *classNames = @[
        @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs",
        @"IGDirectNotesDogfoodingSettingsStaticFuncs",
    ];
    SEL selector = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        Method method = cls ? class_getClassMethod(cls, selector) : NULL;
        if (!RYGExactValidateTwoObjectVoidMethod(method)) continue;
        ((void (*)(id, SEL, id, id))objc_msgSend)(cls, selector, presenter, userSession);
        return YES;
    }
    return NO;
}

@interface RYGDeveloperExactSurfaceViewController ()
@property (nonatomic, assign) RYGDeveloperExactSurface surface;
@property (nonatomic, copy) NSArray<RYGDeveloperExactGroup *> *groups;
@property (nonatomic, assign) NSUInteger scanGeneration;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation RYGDeveloperExactSurfaceViewController

- (instancetype)initWithSurface:(RYGDeveloperExactSurface)surface {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _surface = surface;
        _groups = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = RYGExactSurfaceTitle(self.surface);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 48.0;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshSurface)];
    __weak typeof(self) weakSelf = self;
    UIAction *native = [UIAction actionWithTitle:@"Use Native Values" image:[UIImage systemImageNamed:@"arrow.uturn.backward"] identifier:nil handler:^(__unused UIAction *action) {
        [weakSelf resetAllOverrides];
    }];
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:[UIMenu menuWithChildren:@[native]]];
    self.navigationItem.rightBarButtonItems = @[refresh, more];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(runtimeValueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
    RYGLiquidGlassApplyToViewController(self);
    [self refreshSurface];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)refreshSurface {
    NSUInteger generation = ++self.scanGeneration;
    [self.spinner startAnimating];
    self.tableView.backgroundView = self.spinner;
    RYGDeveloperExactSurface surface = self.surface;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGDeveloperExactGroup *> *groups = RYGExactScanSurface(surface);
        NSMutableArray<RYGRuntimeBoolMethod *> *methods = [NSMutableArray array];
        for (RYGDeveloperExactGroup *group in groups)
            for (RYGDeveloperExactRow *row in group.rows) [methods addObject:row.method];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.scanGeneration) return;
            self.groups = groups;
            [self.spinner stopAnimating];
            self.tableView.backgroundView = nil;
            [self.tableView reloadData];
            if (methods.count) RYGRuntimeBeginLiveObservation(methods);
        });
    });
}

- (void)runtimeValueChanged:(NSNotification *)notification { (void)notification; [self.tableView reloadData]; }

- (void)resetAllOverrides {
    for (RYGDeveloperExactGroup *group in self.groups)
        for (RYGDeveloperExactRow *row in group.rows)
            [RYGRuntimeBrowserEngine setOverride:nil forMethod:row.method];
    [self.tableView reloadData];
}

- (BOOL)hasDirectDogfoodAction {
    return self.surface == RYGDeveloperExactSurfaceDirectDogfood && RYGExactCanOpenDirectNotesDogfood();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return self.groups.count + (self.hasDirectDogfoodAction ? 1 : 0);
}

- (BOOL)isActionSection:(NSInteger)section {
    return self.hasDirectDogfoodAction && section == 0;
}

- (RYGDeveloperExactGroup *)groupForSection:(NSInteger)section {
    NSInteger index = section - (self.hasDirectDogfoodAction ? 1 : 0);
    if (index < 0 || index >= (NSInteger)self.groups.count) return nil;
    return self.groups[(NSUInteger)index];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if ([self isActionSection:section]) return 1;
    return [self groupForSection:section].rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ([self isActionSection:section]) return nil;
    return [self groupForSection:section].className;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGExactDeveloperCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if ([self isActionSection:indexPath.section]) {
        cell.textLabel.text = @"Open Direct Notes Dogfooding Settings";
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.text = nil;
        cell.imageView.image = [UIImage systemImageNamed:@"pawprint.fill"];
        cell.imageView.tintColor = [RYGUtils RYGColor_Primary];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    RYGDeveloperExactRow *row = [self groupForSection:indexPath.section].rows[indexPath.row];
    RYGRuntimeBoolMethod *method = row.method;
    cell.textLabel.text = row.title;
    cell.textLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
    NSNumber *forced = method.overrideValue;
    NSNumber *live = method.liveValue;
    cell.detailTextLabel.text = forced
        ? [NSString stringWithFormat:@"forced %@", forced.boolValue ? @"true" : @"false"]
        : (live ? [NSString stringWithFormat:@"native %@", live.boolValue ? @"true" : @"false"] : nil);
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    UISwitch *toggle = [UISwitch new];
    toggle.on = forced ? forced.boolValue : (live ? live.boolValue : NO);
    toggle.onTintColor = [RYGUtils RYGColor_Primary];
    objc_setAssociatedObject(toggle, kRYGExactSurfaceMethodKey, method, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)toggleChanged:(UISwitch *)toggle {
    RYGRuntimeBoolMethod *method = objc_getAssociatedObject(toggle, kRYGExactSurfaceMethodKey);
    if (!method) return;
    [RYGRuntimeBrowserEngine setOverride:@(toggle.isOn) forMethod:method];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (![self isActionSection:indexPath.section]) return;
    if (!RYGExactOpenDirectNotesDogfood()) {
        [RYGUtils showErrorHUDWithDescription:@"The verified Direct Notes dogfooding launcher is not available in the current runtime session."];
    }
}

@end
