#import "RYGDeveloperTopicViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "RYGEasyGatingRuntime.h"
#import "../Features/ExpFlags/RYGMobileConfig.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import "../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <string.h>

static NSString *const kRYGInternalMenuPref = @"ryg_dev_internal_menu_enabled";
static NSString *const kRYGDogfoodModePref = @"ryg_dev_dogfood_mode_enabled";
static NSString *const kRYGDogfoodMCKeys = @"ryg_dev_dogfood_mobileconfig_keys";
static const void *kRYGNativeControlKey = &kRYGNativeControlKey;

static IMP gRYGBugMenuOriginal;
static IMP gRYGDogfoodSettingsOriginal;
static IMP gRYGDogfoodLauncherOriginal;
static id gRYGDogfoodConfig;
static id gRYGDogfoodUserSession;
static id gRYGDogfoodLauncherClient;
static id gRYGDogfoodLauncherSession;
static NSString *gRYGDogfoodLauncherName;
static NSDictionary *gRYGDogfoodLauncherParameters;

static const char *RYGUnqualifiedType(const char *type) { while (type && strchr("rnNoORV", *type)) type++; return type; }
static BOOL RYGTypeIsBool(const char *type) { type = RYGUnqualifiedType(type); return type && strchr("BcC", *type) != NULL; }
static BOOL RYGTypeIsObject(const char *type) { type = RYGUnqualifiedType(type); return type && (*type == '@' || *type == '#' || *type == ':'); }
static BOOL RYGTypeIsInteger(const char *type) { type = RYGUnqualifiedType(type); return type && strchr("cCsSiIlLqQB", *type) != NULL; }

static BOOL RYGMethodArgumentMatches(Method method, unsigned int index, char expected) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char encoded[96] = {0}; method_getArgumentType(method, index, encoded, sizeof(encoded));
    if (expected == '@') return RYGTypeIsObject(encoded);
    if (expected == 'B') return RYGTypeIsBool(encoded);
    if (expected == 'Q') return RYGTypeIsInteger(encoded);
    return NO;
}
static BOOL RYGMethodReturns(Method method, char expected) {
    if (!method) return NO;
    char encoded[96] = {0}; method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGUnqualifiedType(encoded); if (!type || !*type) return NO;
    if (expected == '@') return *type == '@'; if (expected == 'v') return *type == 'v'; if (expected == 'B') return RYGTypeIsBool(type); return NO;
}
static RYGRuntimeArgumentKind RYGArgumentKind(Method method) {
    if (!method || !RYGMethodReturns(method, 'B')) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method); if (count == 2) return RYGRuntimeArgumentNone; if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[96] = {0}; method_getArgumentType(method, 2, encoded, sizeof(encoded));
    if (RYGTypeIsObject(encoded)) return RYGRuntimeArgumentObject; if (RYGTypeIsInteger(encoded)) return RYGRuntimeArgumentInteger; return (RYGRuntimeArgumentKind)-1;
}

static RYGRuntimeBoolMethod *RYGMakeRuntimeMethod(Class cls, Method method, BOOL classMethod) {
    if (!cls || !method) return nil; RYGRuntimeArgumentKind kind = RYGArgumentKind(method);
    if (kind < RYGRuntimeArgumentNone || kind > RYGRuntimeArgumentInteger) return nil;
    SEL selector = method_getName(method); if (!selector) return nil;
    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.className = NSStringFromClass(cls) ?: @""; row.selectorName = NSStringFromSelector(selector) ?: @""; row.classMethod = classMethod; row.argumentKind = kind;
    const char *image = class_getImageName(cls); row.imagePath = image ? [NSString stringWithUTF8String:image] : @"";
    const char *types = method_getTypeEncoding(method); row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @""; return row;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGMethodsForOwner(NSString *className, BOOL classMethods, NSArray<NSString *> *selectors) {
    Class cls = objc_lookUpClass(className.UTF8String); if (!cls) return @[]; Class owner = classMethods ? object_getClass(cls) : cls; if (!owner) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    if (selectors.count) {
        for (NSString *selectorName in selectors) { RYGRuntimeBoolMethod *row = RYGMakeRuntimeMethod(cls, class_getInstanceMethod(owner, NSSelectorFromString(selectorName)), classMethods); if (row) [rows addObject:row]; }
    } else {
        unsigned int count = 0; Method *methods = class_copyMethodList(owner, &count);
        for (unsigned int i = 0; methods && i < count; i++) { RYGRuntimeBoolMethod *row = RYGMakeRuntimeMethod(cls, methods[i], classMethods); if (row) [rows addObject:row]; }
        if (methods) free(methods);
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) { return [a.selectorName localizedCaseInsensitiveCompare:b.selectorName]; }]; return rows.copy;
}

static NSString *RYGSurfaceTitle(RYGDeveloperRuntimeSurface surface) {
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism: return @"Prism / Redesign";
        case RYGDeveloperRuntimeSurfaceLiquidGlass: return @"Liquid Glass";
        case RYGDeveloperRuntimeSurfaceStories: return @"Stories / Story Tray";
        case RYGDeveloperRuntimeSurfaceConsumerSubs: return @"SubsConsumer / IGPlus / Aura";
        case RYGDeveloperRuntimeSurfaceInternalOnly: case RYGDeveloperRuntimeSurfaceBugReport: return @"IG-only / Internal-only";
        case RYGDeveloperRuntimeSurfaceDirectDogfood: return @"Dogfooding";
        case RYGDeveloperRuntimeSurfaceSettingsRows: return @"Internal Settings";
    }
    return @"Developer";
}

static NSArray<RYGRuntimeBoolMethod *> *RYGRowsForSurface(RYGDeveloperRuntimeSurface surface) {
    NSMutableArray *rows = [NSMutableArray array];
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism:
            [rows addObjectsFromArray:RYGMethodsForOwner(@"IGFeedItemAdsFeedbackInterfaceCellParams", NO, @[@"isPrismEnabled"])];
            [rows addObjectsFromArray:RYGMethodsForOwner(@"IGTableViewCell", NO, @[@"isListRedesignOn"])]; break;
        case RYGDeveloperRuntimeSurfaceLiquidGlass:
            // Owners with a native setter/override are represented as native
            // controls below. Only the launcher-set Throwback Feed gates use
            // the generic ABI-checked observer/override path.
            [rows addObjectsFromArray:RYGMethodsForOwner(@"_TtC15IGThrowbackFeed21IGThrowbackFeedHelper", YES, nil)]; break;
        case RYGDeveloperRuntimeSurfaceStories:
            [rows addObjectsFromArray:RYGMethodsForOwner(@"_TtC27IGPersistentStoryTrayGating38IGPersistentStoryTrayGatingStaticFuncs", YES, nil)];
            [rows addObjectsFromArray:RYGMethodsForOwner(@"_TtC38IGStoryViewerRedesignExperimentHelpers38IGStoryViewerRedesignExperimentHelpers", YES, nil)]; break;
        case RYGDeveloperRuntimeSurfaceConsumerSubs:
            [rows addObjectsFromArray:RYGMethodsForOwner(@"_TtC21IGConsumerSubsService21IGConsumerSubsService", NO, nil)];
            [rows addObjectsFromArray:RYGMethodsForOwner(@"_TtC22IGProfileGatingService22IGProfileGatingService", YES, @[@"isAuraQuietPostingEnabledWithConsumerSubsService:"])]; break;
        default: break;
    }
    return rows.copy;
}

#pragma mark - Exact native internal/dogfood hooks

typedef id (*RYGBugMenuInitFn)(id, SEL, id, id, id, id, id, id, long long, long long, BOOL, BOOL, BOOL, BOOL, long long);
static BOOL RYGBugMenuSignatureMatches(Method method) {
    if (!method || method_getNumberOfArguments(method) != 15 || !RYGMethodReturns(method, '@')) return NO;
    for (unsigned int i = 2; i <= 7; i++) if (!RYGMethodArgumentMatches(method, i, '@')) return NO;
    if (!RYGMethodArgumentMatches(method, 8, 'Q') || !RYGMethodArgumentMatches(method, 9, 'Q')) return NO;
    for (unsigned int i = 10; i <= 13; i++) if (!RYGMethodArgumentMatches(method, i, 'B')) return NO;
    return RYGMethodArgumentMatches(method, 14, 'Q');
}
static id RYGBugMenuInit(id self, SEL cmd, id deviceSession, id userSession, id reliabilityLogging, id navChain, id endpoint, id entryPoint, long long style, long long availability, BOOL showInternal, BOOL showLoggedOutInternal, BOOL showShake, BOOL showDogfood, long long maisaVariant) {
    BOOL internalMode = [NSUserDefaults.standardUserDefaults boolForKey:kRYGInternalMenuPref] || [NSUserDefaults.standardUserDefaults boolForKey:kRYGDogfoodModePref];
    BOOL dogfoodMode = [NSUserDefaults.standardUserDefaults boolForKey:kRYGDogfoodModePref]; RYGBugMenuInitFn original = (RYGBugMenuInitFn)gRYGBugMenuOriginal; if (!original) return nil;
    return original(self, cmd, deviceSession, userSession, reliabilityLogging, navChain, endpoint, entryPoint, style, availability, internalMode ? YES : showInternal, internalMode ? YES : showLoggedOutInternal, showShake, dogfoodMode ? YES : showDogfood, maisaVariant);
}
static void RYGInstallBugMenuHook(void) {
    if (gRYGBugMenuOriginal) return; Class cls = objc_lookUpClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
    SEL selector = NSSelectorFromString(@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL; if (RYGBugMenuSignatureMatches(method)) MSHookMessageEx(cls, selector, (IMP)RYGBugMenuInit, &gRYGBugMenuOriginal);
}

typedef id (*RYGDogfoodSettingsInitFn)(id, SEL, id, id);
static id RYGDogfoodSettingsInit(id self, SEL cmd, id config, id userSession) {
    if (config) gRYGDogfoodConfig = config; if (userSession) gRYGDogfoodUserSession = userSession;
    RYGDogfoodSettingsInitFn original = (RYGDogfoodSettingsInitFn)gRYGDogfoodSettingsOriginal; return original ? original(self, cmd, config, userSession) : nil;
}
static void RYGInstallDogfoodConfigCapture(void) {
    if (gRYGDogfoodSettingsOriginal) return; Class cls = objc_lookUpClass("_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"); SEL selector = NSSelectorFromString(@"initWithConfig:userSession:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (method && method_getNumberOfArguments(method) == 4 && RYGMethodReturns(method, '@') && RYGMethodArgumentMatches(method, 2, '@') && RYGMethodArgumentMatches(method, 3, '@')) MSHookMessageEx(cls, selector, (IMP)RYGDogfoodSettingsInit, &gRYGDogfoodSettingsOriginal);
}

typedef BOOL (*RYGDogfoodLauncherFn)(id, SEL, id, id, id);
static BOOL RYGDogfoodLauncherOverride(id self, SEL cmd, id userSession, id launcherName, id parameters) {
    if (self) gRYGDogfoodLauncherClient = self; if (userSession) gRYGDogfoodLauncherSession = userSession;
    if ([launcherName isKindOfClass:NSString.class]) gRYGDogfoodLauncherName = [launcherName copy];
    if ([parameters isKindOfClass:NSDictionary.class]) gRYGDogfoodLauncherParameters = [parameters copy];
    RYGDogfoodLauncherFn original = (RYGDogfoodLauncherFn)gRYGDogfoodLauncherOriginal; return original ? original(self, cmd, userSession, launcherName, parameters) : NO;
}
static void RYGInstallDogfoodLauncherCapture(void) {
    if (gRYGDogfoodLauncherOriginal) return; Class cls = objc_lookUpClass("_TtC35IGDogfoodingAssistantLauncherClient35IGDogfoodingAssistantLauncherClient"); SEL selector = NSSelectorFromString(@"overrideLauncherWithUserSession:launcherName:parametersToValues:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (method && method_getNumberOfArguments(method) == 5 && RYGMethodReturns(method, 'B') && RYGMethodArgumentMatches(method, 2, '@') && RYGMethodArgumentMatches(method, 3, '@') && RYGMethodArgumentMatches(method, 4, '@')) MSHookMessageEx(cls, selector, (IMP)RYGDogfoodLauncherOverride, &gRYGDogfoodLauncherOriginal);
}
static BOOL RYGReapplyCapturedDogfoodLauncher(void) {
    RYGInstallDogfoodLauncherCapture(); if (!gRYGDogfoodLauncherClient || !gRYGDogfoodLauncherSession || !gRYGDogfoodLauncherName.length || !gRYGDogfoodLauncherParameters) return NO;
    return ((BOOL (*)(id, SEL, id, id, id))objc_msgSend)(gRYGDogfoodLauncherClient, NSSelectorFromString(@"overrideLauncherWithUserSession:launcherName:parametersToValues:"), gRYGDogfoodLauncherSession, gRYGDogfoodLauncherName, gRYGDogfoodLauncherParameters);
}

static UIViewController *RYGTopViewController(void) {
    UIWindow *key = nil; for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) { if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue; for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) { key = window; break; } if (key) break; }
    UIViewController *top = key.rootViewController; BOOL changed = YES;
    while (changed && top) { changed = NO; if (top.presentedViewController && !top.presentedViewController.isBeingDismissed) { top = top.presentedViewController; changed = YES; continue; } if ([top isKindOfClass:UINavigationController.class] && ((UINavigationController *)top).visibleViewController) { top = ((UINavigationController *)top).visibleViewController; changed = YES; continue; } if ([top isKindOfClass:UITabBarController.class] && ((UITabBarController *)top).selectedViewController) { top = ((UITabBarController *)top).selectedViewController; changed = YES; } }
    return top;
}
static BOOL RYGOpenDogfoodSettings(void) {
    RYGInstallDogfoodConfigCapture(); if (!gRYGDogfoodConfig || !gRYGDogfoodUserSession) return NO;
    Class cls = objc_lookUpClass("_TtC20IGDogfoodingSettings20IGDogfoodingSettings"); SEL selector = NSSelectorFromString(@"openWithConfig:onViewController:userSession:"); Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 5 || !RYGMethodReturns(method, 'v') || !RYGMethodArgumentMatches(method, 2, '@') || !RYGMethodArgumentMatches(method, 3, '@') || !RYGMethodArgumentMatches(method, 4, '@')) return NO;
    UIViewController *top = RYGTopViewController(); if (!top) return NO; ((void (*)(id, SEL, id, id, id))objc_msgSend)((id)cls, selector, gRYGDogfoodConfig, top, gRYGDogfoodUserSession); return YES;
}
static RYGRuntimeBoolMethod *RYGStoryTrayGateMethod(void) {
    return RYGMethodsForOwner(@"_TtC27IGPersistentStoryTrayGating38IGPersistentStoryTrayGatingStaticFuncs", YES, @[@"isTrayAttachedToHeaderEnabled:"]).firstObject;
}
static BOOL RYGOpenStoryTrayDebug(void) {
    RYGRuntimeBoolMethod *gate = RYGStoryTrayGateMethod();
    if (!gate) return NO;
    [RYGRuntimeBrowserEngine observeMethod:gate];
    NSNumber *current = gate.liveValue;
    if (!current) return NO;
    Class cls = objc_lookUpClass("_TtC25IGOverlayStoriesTrayDebug39IGOverlayStoriesTrayDebugViewController"); SEL selector = NSSelectorFromString(@"presentFrom:currentlyEnabled:onApplyAndRestart:"); Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 5 || !RYGMethodReturns(method, 'v') || !RYGMethodArgumentMatches(method, 2, '@') || !RYGMethodArgumentMatches(method, 3, 'B') || !RYGMethodArgumentMatches(method, 4, '@')) return NO;
    UIViewController *top = RYGTopViewController(); if (!top) return NO;
    void (^completion)(void) = ^{};
    ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)((id)cls, selector, top, current.boolValue, completion);
    return YES;
}

static id RYGSharedHelper(NSString *className) {
    Class cls = objc_lookUpClass(className.UTF8String); SEL selector = NSSelectorFromString(@"shared"); Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    return method && method_getNumberOfArguments(method) == 2 && RYGMethodReturns(method, '@') ? ((id (*)(id, SEL))objc_msgSend)((id)cls, selector) : nil;
}
static NSNumber *RYGNativeHelperEnabled(NSString *className) {
    id helper = RYGSharedHelper(className); SEL selector = NSSelectorFromString(@"isEnabled"); Method method = helper ? class_getInstanceMethod([helper class], selector) : NULL;
    return method && method_getNumberOfArguments(method) == 2 && RYGMethodReturns(method, 'B') ? @(((BOOL (*)(id, SEL))objc_msgSend)(helper, selector)) : nil;
}
static BOOL RYGSetNativeHelperBool(NSString *className, NSString *selectorName, BOOL enabled) {
    id helper = RYGSharedHelper(className); SEL selector = NSSelectorFromString(selectorName); Method method = helper ? class_getInstanceMethod([helper class], selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3 || !RYGMethodReturns(method, 'v') || !RYGMethodArgumentMatches(method, 2, 'B')) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(helper, selector, enabled); return YES;
}
static BOOL RYGOverrideNativeHelper(NSString *className, BOOL enabled) { return RYGSetNativeHelperBool(className, @"overrideIsEnabled:", enabled); }
static BOOL RYGSetNativeHelperEnabled(NSString *className, BOOL enabled) { return RYGSetNativeHelperBool(className, @"setIsEnabled:", enabled); }

#pragma mark - Global dogfood MobileConfig
static BOOL RYGDogfoodStrongName(NSString *value) {
    NSString *s = value.lowercaseString ?: @""; return [s containsString:@"dogfood"] || [s containsString:@"dogfooding"] || [s containsString:@"is_employee"] || [s containsString:@"isemployee"] || [s containsString:@"is_internal"] || [s containsString:@"isinternal"] || [s containsString:@"internal_only"] || [s containsString:@"internal-only"] || [s containsString:@"is_dogfood_user"];
}
static BOOL RYGDogfoodEnableLeaf(NSString *value) { NSString *s = value.lowercaseString ?: @""; return [s isEqualToString:@"enabled"] || [s isEqualToString:@"is_enabled"] || [s hasPrefix:@"enable_"] || [s hasPrefix:@"should_enable"] || [s hasPrefix:@"show_internal"]; }
static NSString *RYGMCStableKey(RYGMCParam *param) { return [NSString stringWithFormat:@"%u:%u", param.configNumber, param.paramIndex]; }
static NSUInteger RYGApplyDogfoodMobileConfig(BOOL enabled) {
    RYGMobileConfig *mc = RYGMobileConfig.shared; [mc reloadFromRuntime]; NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (enabled) {
        NSMutableArray *changed = [NSMutableArray array];
        for (RYGMCConfig *config in mc.allConfigs) { BOOL strongConfig = RYGDogfoodStrongName(config.name); for (RYGMCParam *param in config.params) { if (!param.isRuntimeBacked || param.type != RYGMCTypeBool) continue; if (!RYGDogfoodStrongName(param.name) && !(strongConfig && RYGDogfoodEnableLeaf(param.name))) continue; if ([mc setOverride:@YES for:param]) [changed addObject:RYGMCStableKey(param)]; } }
        [defaults setObject:changed.copy forKey:kRYGDogfoodMCKeys]; return changed.count;
    }
    NSSet *wanted = [NSSet setWithArray:[defaults stringArrayForKey:kRYGDogfoodMCKeys] ?: @[]]; NSUInteger cleared = 0;
    for (RYGMCConfig *config in mc.allConfigs) for (RYGMCParam *param in config.params) if ([wanted containsObject:RYGMCStableKey(param)] && [mc overrideStateFor:param] == RYGMCOverrideSet) { [mc clearOverrideFor:param]; cleared++; }
    [defaults removeObjectForKey:kRYGDogfoodMCKeys]; return cleared;
}

#pragma mark - Controller
@interface RYGDeveloperTopicViewController () <UISearchResultsUpdating>
@property (nonatomic, assign) RYGDeveloperRuntimeSurface surface;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *allRows;
@property (nonatomic, copy) NSArray<NSString *> *classSections;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *rowsByClass;
@property (nonatomic, copy) NSArray<NSDictionary *> *nativeControls;
@end

@implementation RYGDeveloperTopicViewController
+ (void)activatePersistedNativeFeatures {
    RYGInstallDogfoodConfigCapture(); RYGInstallDogfoodLauncherCapture();
    if ([NSUserDefaults.standardUserDefaults boolForKey:kRYGInternalMenuPref] || [NSUserDefaults.standardUserDefaults boolForKey:kRYGDogfoodModePref]) RYGInstallBugMenuHook();
    if ([NSUserDefaults.standardUserDefaults boolForKey:kRYGDogfoodModePref]) [RYGEasyGatingRuntime.shared installIfNeeded];
}
- (instancetype)initWithSurface:(RYGDeveloperRuntimeSurface)surface { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _surface = surface; _allRows = @[]; _classSections = @[]; _rowsByClass = @{}; _nativeControls = @[]; } return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = RYGSurfaceTitle(self.surface); self.view.backgroundColor = [RYGPopupChrome backgroundColor]; self.tableView.backgroundColor = [RYGPopupChrome backgroundColor]; self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag; self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 54.0;
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil]; self.searchController.searchResultsUpdater = self; self.searchController.obscuresBackgroundDuringPresentation = NO; self.searchController.searchBar.placeholder = @"Class or method"; self.navigationItem.searchController = self.searchController; self.navigationItem.hidesSearchBarWhenScrolling = YES;
    RYGLiquidGlassApplyToViewController(self); [[self class] activatePersistedNativeFeatures]; [self rebuildNativeControls]; [self refreshRows];
    if (self.surface == RYGDeveloperRuntimeSurfaceStories) { RYGRuntimeBoolMethod *gate = RYGStoryTrayGateMethod(); if (gate) [RYGRuntimeBrowserEngine observeMethod:gate]; }
}
- (void)refreshRows { self.allRows = RYGRowsForSurface(self.surface); [self rebuildFilteredModel]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self rebuildFilteredModel]; }
- (void)rebuildFilteredModel {
    NSString *query = self.searchController.searchBar.text.lowercaseString ?: @""; NSArray *tokens = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (RYGRuntimeBoolMethod *method in self.allRows) { NSString *text = [[NSString stringWithFormat:@"%@ %@ %@", method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""] lowercaseString]; BOOL matches = YES; for (NSString *token in tokens) if (token.length && [text rangeOfString:token].location == NSNotFound) { matches = NO; break; } if (!matches) continue; NSString *key = method.className.length ? method.className : @"Runtime"; if (!groups[key]) groups[key] = [NSMutableArray array]; [groups[key] addObject:method]; }
    self.classSections = [groups.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]; NSMutableDictionary *frozen = [NSMutableDictionary dictionary]; for (NSString *key in self.classSections) frozen[key] = [groups[key] copy]; self.rowsByClass = frozen.copy; [self.tableView reloadData];
}
- (void)rebuildNativeControls {
    NSMutableArray *rows = [NSMutableArray array];
    if (self.surface == RYGDeveloperRuntimeSurfaceStories) [rows addObject:@{@"kind":@"storyDebug", @"title":@"Open native Story Tray Debug", @"subtitle":@"Uses the live isTrayAttachedToHeaderEnabled: value; never invents the current state"}];
    else if (self.surface == RYGDeveloperRuntimeSurfaceLiquidGlass) {
        [rows addObject:@{@"kind":@"swizzleGlass", @"title":@"Liquid Glass Swizzle", @"subtitle":@"Native setIsEnabled:"}];
        [rows addObject:@{@"kind":@"throwback", @"title":@"Throwback Chrome", @"subtitle":@"Native overrideIsEnabled:"}];
        [rows addObject:@{@"kind":@"navGlass", @"title":@"Liquid Glass Navigation", @"subtitle":@"Native overrideIsEnabled:"}];
    }
    else if (self.surface == RYGDeveloperRuntimeSurfaceInternalOnly || self.surface == RYGDeveloperRuntimeSurfaceBugReport || self.surface == RYGDeveloperRuntimeSurfaceSettingsRows) [rows addObject:@{@"kind":@"internal", @"title":@"Expose Internal Settings", @"subtitle":@"Exact IGBugReportMenu initializer flags"}];
    else if (self.surface == RYGDeveloperRuntimeSurfaceDirectDogfood) {
        [rows addObject:@{@"kind":@"dogfood", @"title":@"Global Dogfooding Mode", @"subtitle":@"Internal menu + native launcher + resolved MobileConfig + EasyGating"}];
        [rows addObject:@{@"kind":@"dogfoodOpen", @"title":@"Open Dogfooding Settings", @"subtitle":@"Uses the native IGDogfoodingSettingsConfig captured from Instagram"}];
        [rows addObject:@{@"kind":@"dogfoodLauncher", @"title":@"Reapply native Dogfooding launcher", @"subtitle":@"Reuses the exact userSession / launcher / parameters captured from Instagram"}];
        [rows addObject:@{@"kind":@"easyGating", @"title":@"Install EasyGating final-ID observer", @"subtitle":@"No pre-map selector IDs and no broad employee getter hooks"}];
        [rows addObject:@{@"kind":@"dogfoodMC", @"title":@"Reapply dogfood MobileConfig", @"subtitle":@"Uses imported/resolved id_name_mapping names"}];
    }
    self.nativeControls = rows.copy;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return (self.nativeControls.count ? 1 : 0) + self.classSections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; if (self.nativeControls.count && section == 0) return self.nativeControls.count; NSInteger i = section - (self.nativeControls.count ? 1 : 0); return (i >= 0 && i < (NSInteger)self.classSections.count) ? [self.rowsByClass[self.classSections[(NSUInteger)i]] count] : 0; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; if (self.nativeControls.count && section == 0) return @"Native controls"; NSInteger i = section - (self.nativeControls.count ? 1 : 0); return (i >= 0 && i < (NSInteger)self.classSections.count) ? self.classSections[(NSUInteger)i] : nil; }
- (RYGRuntimeBoolMethod *)methodAtIndexPath:(NSIndexPath *)indexPath { NSInteger i = indexPath.section - (self.nativeControls.count ? 1 : 0); if (i < 0 || i >= (NSInteger)self.classSections.count) return nil; NSArray *rows = self.rowsByClass[self.classSections[(NSUInteger)i]]; return indexPath.row < (NSInteger)rows.count ? rows[(NSUInteger)indexPath.row] : nil; }

- (UIButton *)selectorButtonForMethod:(RYGRuntimeBoolMethod *)method {
    NSNumber *forced = method.overrideValue, *native = method.liveValue; NSString *title = forced ? (forced.boolValue ? @"On" : @"Off") : (native ? (native.boolValue ? @"Native On" : @"Native Off") : @"Native");
    __weak typeof(self) weakSelf = self;
    UIAction *nativeAction = [UIAction actionWithTitle:@"Native" image:nil identifier:nil handler:^(__unused UIAction *a) { [RYGRuntimeBrowserEngine setOverride:nil forMethod:method]; [weakSelf.tableView reloadData]; }]; nativeAction.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    UIAction *on = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *a) { [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method]; [weakSelf.tableView reloadData]; }]; on.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *off = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *a) { [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method]; [weakSelf.tableView reloadData]; }]; off.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.menu = [UIMenu menuWithTitle:@"Output" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:@[nativeAction, on, off]];
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    // Configure Glass only after the button is a menu source so the helper uses
    // UIKit's native menu metrics/default insets for the closed→expanded morph.
    RYGLiquidGlassConfigureButton(button, NO);
    UIButtonConfiguration *cfg = button.configuration; if (cfg) { cfg.title = title; if (@available(iOS 26.0, *)) [cfg setDefaultContentInsets]; button.configuration = cfg; } else [button setTitle:title forState:UIControlStateNormal];
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.nativeControls.count && indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGNativeControl"]; if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGNativeControl"];
        NSDictionary *row = self.nativeControls[(NSUInteger)indexPath.row]; cell.textLabel.text = row[@"title"]; cell.detailTextLabel.text = row[@"subtitle"]; cell.detailTextLabel.numberOfLines = 2; cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone; cell.selectionStyle = UITableViewCellSelectionStyleDefault; NSString *kind = row[@"kind"];
        if ([kind isEqualToString:@"internal"] || [kind isEqualToString:@"dogfood"] || [kind isEqualToString:@"swizzleGlass"] || [kind isEqualToString:@"throwback"] || [kind isEqualToString:@"navGlass"]) {
            UISwitch *toggle = [UISwitch new];
            if ([kind isEqualToString:@"internal"]) toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:kRYGInternalMenuPref];
            else if ([kind isEqualToString:@"dogfood"]) toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:kRYGDogfoodModePref];
            else if ([kind isEqualToString:@"swizzleGlass"]) toggle.on = [RYGNativeHelperEnabled(@"_TtC20IGLiquidGlassSwizzle26IGLiquidGlassSwizzleToggle") boolValue];
            else if ([kind isEqualToString:@"throwback"]) toggle.on = [RYGNativeHelperEnabled(@"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper") boolValue];
            else toggle.on = [RYGNativeHelperEnabled(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper") boolValue];
            objc_setAssociatedObject(toggle, kRYGNativeControlKey, kind, OBJC_ASSOCIATION_COPY_NONATOMIC); [toggle addTarget:self action:@selector(nativeSwitchChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGKnownMethod"]; if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGKnownMethod"];
    RYGRuntimeBoolMethod *method = [self methodAtIndexPath:indexPath]; cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", method.classMethod ? @"+" : @"−", method.selectorName ?: @""]; cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium]; cell.textLabel.numberOfLines = 2; NSNumber *native = method.liveValue; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", method.typeEncoding ?: @"", native ? (native.boolValue ? @"observed true" : @"observed false") : @"not observed"]; cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular]; cell.detailTextLabel.textColor = UIColor.secondaryLabelColor; cell.accessoryView = [self selectorButtonForMethod:method]; cell.selectionStyle = UITableViewCellSelectionStyleDefault; return cell;
}

- (void)nativeSwitchChanged:(UISwitch *)toggle {
    NSString *kind = objc_getAssociatedObject(toggle, kRYGNativeControlKey);
    if ([kind isEqualToString:@"internal"]) { [NSUserDefaults.standardUserDefaults setBool:toggle.isOn forKey:kRYGInternalMenuPref]; if (toggle.isOn) RYGInstallBugMenuHook(); }
    else if ([kind isEqualToString:@"dogfood"]) { [NSUserDefaults.standardUserDefaults setBool:toggle.isOn forKey:kRYGDogfoodModePref]; if (toggle.isOn) { RYGInstallBugMenuHook(); RYGInstallDogfoodConfigCapture(); RYGInstallDogfoodLauncherCapture(); [RYGEasyGatingRuntime.shared installIfNeeded]; (void)RYGReapplyCapturedDogfoodLauncher(); NSUInteger count = RYGApplyDogfoodMobileConfig(YES); [RYGUtils showToastForDuration:2.0 title:@"Dogfooding enabled" subtitle:[NSString stringWithFormat:@"%lu resolved MobileConfig BOOLs", (unsigned long)count]]; } else { NSUInteger count = RYGApplyDogfoodMobileConfig(NO); [RYGUtils showToastForDuration:1.5 title:@"Dogfooding disabled" subtitle:[NSString stringWithFormat:@"%lu RyukGram overrides cleared", (unsigned long)count]]; } }
    else if ([kind isEqualToString:@"swizzleGlass"]) { if (!RYGSetNativeHelperEnabled(@"_TtC20IGLiquidGlassSwizzle26IGLiquidGlassSwizzleToggle", toggle.isOn)) toggle.on = !toggle.isOn; }
    else if ([kind isEqualToString:@"throwback"]) { if (!RYGOverrideNativeHelper(@"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper", toggle.isOn)) toggle.on = !toggle.isOn; }
    else if ([kind isEqualToString:@"navGlass"]) { if (!RYGOverrideNativeHelper(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper", toggle.isOn)) toggle.on = !toggle.isOn; }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.nativeControls.count && indexPath.section == 0) {
        NSString *kind = self.nativeControls[(NSUInteger)indexPath.row][@"kind"];
        if ([kind isEqualToString:@"storyDebug"]) {
            if (!RYGOpenStoryTrayDebug()) [RYGUtils showErrorHUDWithDescription:@"Story Tray observer is armed, but Instagram has not produced a native isTrayAttachedToHeaderEnabled: value yet. Return to the feed/Stories once and retry; RyukGram will not invent the current state."];
        }
        else if ([kind isEqualToString:@"dogfoodOpen"]) { if (!RYGOpenDogfoodSettings()) [RYGUtils showErrorHUDWithDescription:@"Open the native Dogfooding Assistant once so Instagram creates a real IGDogfoodingSettingsConfig; RyukGram will capture and reuse it"]; }
        else if ([kind isEqualToString:@"dogfoodLauncher"]) { if (!RYGReapplyCapturedDogfoodLauncher()) [RYGUtils showErrorHUDWithDescription:@"No native Dogfooding launcher invocation has been captured yet"]; }
        else if ([kind isEqualToString:@"easyGating"]) { [RYGEasyGatingRuntime.shared installIfNeeded]; [RYGUtils showToastForDuration:1.2 title:@"EasyGating observer installed" subtitle:[NSString stringWithFormat:@"%lu final IDs observed", (unsigned long)RYGEasyGatingRuntime.shared.observations.count]]; }
        else if ([kind isEqualToString:@"dogfoodMC"]) { NSUInteger count = RYGApplyDogfoodMobileConfig(YES); [RYGUtils showToastForDuration:1.5 title:@"MobileConfig reapplied" subtitle:[NSString stringWithFormat:@"%lu resolved BOOLs", (unsigned long)count]]; }
        return;
    }
    RYGRuntimeBoolMethod *method = [self methodAtIndexPath:indexPath]; if (!method) return; RYGRuntimeBeginLiveObservation(@[method]); [RYGUtils showToastForDuration:1.0 title:@"Observing native value" subtitle:method.selectorName];
}
@end
