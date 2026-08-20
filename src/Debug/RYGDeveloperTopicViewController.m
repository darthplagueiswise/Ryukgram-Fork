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
#import <mach-o/dyld.h>
#include <string.h>

static NSString *const kRYGInternalMenuPref = @"ryg_dev_internal_menu_enabled";
static NSString *const kRYGDogfoodModePref = @"ryg_dev_dogfood_mode_enabled";
static NSString *const kRYGDogfoodOwnedMCStatePref = @"ryg_dev_dogfood_owned_mc_state_v2";
static NSString *const kRYGPrismSetterModePref = @"ryg_dev_prism_setter_mode_v2";
static NSString *const kRYGRedesignSetterModePref = @"ryg_dev_redesign_setter_mode_v2";
static const void *kRYGNativeControlKey = &kRYGNativeControlKey;
static const void *kRYGMCParamKey = &kRYGMCParamKey;

static IMP gRYGBugMenuOriginal;
static IMP gRYGBugMenuLegacyOriginal;
static IMP gRYGDogfoodSettingsInitOriginal;
static IMP gRYGDogfoodSettingsOpenOriginal;
static IMP gRYGDogfoodLauncherOriginal;
static IMP gRYGPrismSetterOriginal;
static IMP gRYGRedesignSetterOriginal;

static id gRYGDogfoodConfig;
static id gRYGDogfoodUserSession;
static id gRYGDogfoodLauncherClient;
static id gRYGDogfoodLauncherSession;
static NSString *gRYGDogfoodLauncherName;
static NSDictionary *gRYGDogfoodLauncherParameters;
static NSInteger gRYGPrismSetterMode = -1;
static NSInteger gRYGRedesignSetterMode = -1;
static BOOL gRYGDeveloperBootstrapScheduled;
static BOOL gRYGDeveloperImageCallbackRegistered;

#pragma mark - ABI validation

static const char *RYGUnqualifiedType(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGTypeIsBool(const char *type) {
    type = RYGUnqualifiedType(type);
    return type && *type == 'B';
}

static BOOL RYGTypeIsObject(const char *type) {
    type = RYGUnqualifiedType(type);
    return type && *type == '@';
}

static BOOL RYGTypeIsInteger(const char *type) {
    type = RYGUnqualifiedType(type);
    return type && (*type == 'q' || *type == 'Q');
}

static BOOL RYGTypeIsInt64(const char *type) {
    type = RYGUnqualifiedType(type);
    return type && (*type == 'q' || *type == 'Q');
}

static BOOL RYGMethodReturns(Method method, char expected) {
    if (!method) return NO;
    char encoded[96] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGUnqualifiedType(encoded);
    if (!type || !*type) return NO;
    if (expected == '@') return *type == '@';
    if (expected == 'v') return *type == 'v';
    if (expected == 'B') return RYGTypeIsBool(type);
    return NO;
}

static BOOL RYGMethodArgumentMatches(Method method, unsigned int index, char expected) {
    if (!method || index >= method_getNumberOfArguments(method)) return NO;
    char encoded[96] = {0};
    method_getArgumentType(method, index, encoded, sizeof(encoded));
    if (expected == '@') return RYGTypeIsObject(encoded);
    if (expected == 'B') return RYGTypeIsBool(encoded);
    if (expected == 'Q') return RYGTypeIsInt64(encoded);
    return NO;
}

static RYGRuntimeArgumentKind RYGArgumentKind(Method method) {
    if (!method || !RYGMethodReturns(method, 'B')) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[96] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    if (RYGTypeIsObject(encoded)) return RYGRuntimeArgumentObject;
    if (RYGTypeIsInteger(encoded)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static RYGRuntimeBoolMethod *RYGRuntimeMethodForOwner(NSString *className,
                                                       NSString *selectorName,
                                                       BOOL classMethod) {
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    if (!cls || !selectorName.length) return nil;
    Class owner = classMethod ? object_getClass(cls) : cls;
    Method method = owner ? class_getInstanceMethod(owner, NSSelectorFromString(selectorName)) : NULL;
    RYGRuntimeArgumentKind kind = RYGArgumentKind(method);
    if (kind < RYGRuntimeArgumentNone || kind > RYGRuntimeArgumentInteger) return nil;

    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.className = className;
    row.selectorName = selectorName;
    row.classMethod = classMethod;
    row.argumentKind = kind;
    const char *types = method_getTypeEncoding(method);
    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    const char *image = class_getImageName(cls);
    row.imagePath = image ? [NSString stringWithUTF8String:image] : @"";
    return row;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGAllBoolMethodsForOwner(NSString *className, BOOL classMethods) {
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    Class owner = cls ? (classMethods ? object_getClass(cls) : cls) : Nil;
    if (!owner) return @[];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(owner, &count);
    NSMutableArray *rows = [NSMutableArray array];
    for (unsigned int index = 0; methods && index < count; index++) {
        SEL selector = method_getName(methods[index]);
        if (!selector) continue;
        RYGRuntimeBoolMethod *row = RYGRuntimeMethodForOwner(className, NSStringFromSelector(selector), classMethods);
        if (row) [rows addObject:row];
    }
    if (methods) free(methods);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return rows.copy;
}

static void RYGAppendExact(NSMutableArray<RYGRuntimeBoolMethod *> *rows,
                           NSString *className,
                           NSString *selectorName,
                           BOOL classMethod) {
    RYGRuntimeBoolMethod *row = RYGRuntimeMethodForOwner(className, selectorName, classMethod);
    if (row) [rows addObject:row];
}

#pragma mark - Exact binary-validated surfaces

static NSString *RYGSurfaceTitle(RYGDeveloperRuntimeSurface surface) {
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism: return @"Prism / Redesign";
        case RYGDeveloperRuntimeSurfaceLiquidGlass: return @"Liquid Glass";
        case RYGDeveloperRuntimeSurfaceStories: return @"Stories / Story Tray";
        case RYGDeveloperRuntimeSurfaceConsumerSubs: return @"SubsConsumer / IGPlus / Aura";
        case RYGDeveloperRuntimeSurfaceInternalOnly:
        case RYGDeveloperRuntimeSurfaceBugReport: return @"IG-only / Internal-only";
        case RYGDeveloperRuntimeSurfaceDirectDogfood: return @"Dogfooding";
        case RYGDeveloperRuntimeSurfaceSettingsRows: return @"Internal Settings";
    }
    return @"Developer";
}

static NSArray<RYGRuntimeBoolMethod *> *RYGRowsForSurface(RYGDeveloperRuntimeSurface surface) {
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism:
            RYGAppendExact(rows, @"IGFeedItemAdsFeedbackInterfaceCellParams", @"isPrismEnabled", NO);
            RYGAppendExact(rows, @"IGTableViewCell", @"isListRedesignOn", NO);
            break;
        case RYGDeveloperRuntimeSurfaceLiquidGlass:
            [rows addObjectsFromArray:RYGAllBoolMethodsForOwner(@"_TtC15IGThrowbackFeed21IGThrowbackFeedHelper", YES)];
            break;
        case RYGDeveloperRuntimeSurfaceStories:
            RYGAppendExact(rows, @"_TtC27IGPersistentStoryTrayGating38IGPersistentStoryTrayGatingStaticFuncs", @"isTrayAttachedToHeaderEnabled:", YES);
            RYGAppendExact(rows, @"_TtC38IGStoryViewerRedesignExperimentHelpers38IGStoryViewerRedesignExperimentHelpers", @"isStoryViewerCardAnimationEnabledWithLauncherSet:", YES);
            break;
        case RYGDeveloperRuntimeSurfaceConsumerSubs:
            [rows addObjectsFromArray:RYGAllBoolMethodsForOwner(@"_TtC21IGConsumerSubsService21IGConsumerSubsService", NO)];
            RYGAppendExact(rows, @"_TtC22IGProfileGatingService22IGProfileGatingService", @"isAuraQuietPostingEnabledWithConsumerSubsService:", YES);
            break;
        default:
            break;
    }
    return rows.copy;
}

#pragma mark - Internal menu visibility, exact initializer ABIs

typedef id (*RYGBugMenuInitFn)(id, SEL, id, id, id, id, id, id, long long, long long, BOOL, BOOL, BOOL, BOOL, long long);
typedef id (*RYGBugMenuLegacyInitFn)(id, SEL, id, id, id, id, id, id, long long, long long, BOOL, BOOL, BOOL);

static BOOL RYGBugMenuFullSignatureMatches(Method method) {
    if (!method || method_getNumberOfArguments(method) != 15 || !RYGMethodReturns(method, '@')) return NO;
    for (unsigned int index = 2; index <= 7; index++) if (!RYGMethodArgumentMatches(method, index, '@')) return NO;
    if (!RYGMethodArgumentMatches(method, 8, 'Q') || !RYGMethodArgumentMatches(method, 9, 'Q')) return NO;
    for (unsigned int index = 10; index <= 13; index++) if (!RYGMethodArgumentMatches(method, index, 'B')) return NO;
    return RYGMethodArgumentMatches(method, 14, 'Q');
}

static BOOL RYGBugMenuLegacySignatureMatches(Method method) {
    if (!method || method_getNumberOfArguments(method) != 13 || !RYGMethodReturns(method, '@')) return NO;
    for (unsigned int index = 2; index <= 7; index++) if (!RYGMethodArgumentMatches(method, index, '@')) return NO;
    if (!RYGMethodArgumentMatches(method, 8, 'Q') || !RYGMethodArgumentMatches(method, 9, 'Q')) return NO;
    for (unsigned int index = 10; index <= 12; index++) if (!RYGMethodArgumentMatches(method, index, 'B')) return NO;
    return YES;
}

static id RYGBugMenuInit(id self, SEL cmd, id deviceSession, id userSession, id reliabilityLogging,
                         id navChain, id endpoint, id entryPoint, long long style, long long availability,
                         BOOL showInternal, BOOL showLoggedOutInternal, BOOL showShake, BOOL showDogfood,
                         long long maisaVariant) {
    if (userSession) gRYGDogfoodUserSession = userSession;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL dogfoodMode = [defaults boolForKey:kRYGDogfoodModePref];
    BOOL internalMode = dogfoodMode || [defaults boolForKey:kRYGInternalMenuPref];
    RYGBugMenuInitFn original = (RYGBugMenuInitFn)gRYGBugMenuOriginal;
    return original ? original(self, cmd, deviceSession, userSession, reliabilityLogging, navChain, endpoint, entryPoint,
                               style, availability,
                               internalMode ? YES : showInternal,
                               internalMode ? YES : showLoggedOutInternal,
                               showShake,
                               dogfoodMode ? YES : showDogfood,
                               maisaVariant) : nil;
}

static id RYGBugMenuLegacyInit(id self, SEL cmd, id deviceSession, id userSession, id reliabilityLogging,
                               id navChain, id endpoint, id entryPoint, long long style, long long availability,
                               BOOL showInternal, BOOL showLoggedOutInternal, BOOL showShake) {
    if (userSession) gRYGDogfoodUserSession = userSession;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL internalMode = [defaults boolForKey:kRYGDogfoodModePref] || [defaults boolForKey:kRYGInternalMenuPref];
    RYGBugMenuLegacyInitFn original = (RYGBugMenuLegacyInitFn)gRYGBugMenuLegacyOriginal;
    return original ? original(self, cmd, deviceSession, userSession, reliabilityLogging, navChain, endpoint, entryPoint,
                               style, availability,
                               internalMode ? YES : showInternal,
                               internalMode ? YES : showLoggedOutInternal,
                               showShake) : nil;
}

static void RYGInstallBugMenuHooks(void) {
    Class cls = objc_lookUpClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
    if (!cls) return;

    if (!gRYGBugMenuOriginal) {
        SEL selector = NSSelectorFromString(@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:");
        Method method = class_getInstanceMethod(cls, selector);
        if (RYGBugMenuFullSignatureMatches(method)) gRYGBugMenuOriginal = method_setImplementation(method, (IMP)RYGBugMenuInit);
    }

    if (!gRYGBugMenuLegacyOriginal) {
        SEL selector = NSSelectorFromString(@"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:");
        Method method = class_getInstanceMethod(cls, selector);
        if (RYGBugMenuLegacySignatureMatches(method)) gRYGBugMenuLegacyOriginal = method_setImplementation(method, (IMP)RYGBugMenuLegacyInit);
    }
}

#pragma mark - Dogfooding native context capture

typedef id (*RYGDogfoodSettingsInitFn)(id, SEL, id, id);
typedef void (*RYGDogfoodSettingsOpenFn)(id, SEL, id, id, id);
typedef BOOL (*RYGDogfoodLauncherFn)(id, SEL, id, id, id);

static id RYGDogfoodSettingsInit(id self, SEL cmd, id config, id userSession) {
    if (config) gRYGDogfoodConfig = config;
    if (userSession) gRYGDogfoodUserSession = userSession;
    RYGDogfoodSettingsInitFn original = (RYGDogfoodSettingsInitFn)gRYGDogfoodSettingsInitOriginal;
    return original ? original(self, cmd, config, userSession) : nil;
}

static void RYGDogfoodSettingsOpen(id self, SEL cmd, id config, id viewController, id userSession) {
    if (config) gRYGDogfoodConfig = config;
    if (userSession) gRYGDogfoodUserSession = userSession;
    RYGDogfoodSettingsOpenFn original = (RYGDogfoodSettingsOpenFn)gRYGDogfoodSettingsOpenOriginal;
    if (original) original(self, cmd, config, viewController, userSession);
}

static void RYGInstallDogfoodConfigCapture(void) {
    Class controller = objc_lookUpClass("_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController");
    if (!gRYGDogfoodSettingsInitOriginal && controller) {
        SEL selector = NSSelectorFromString(@"initWithConfig:userSession:");
        Method method = class_getInstanceMethod(controller, selector);
        if (method && method_getNumberOfArguments(method) == 4 && RYGMethodReturns(method, '@') &&
            RYGMethodArgumentMatches(method, 2, '@') && RYGMethodArgumentMatches(method, 3, '@')) {
            gRYGDogfoodSettingsInitOriginal = method_setImplementation(method, (IMP)RYGDogfoodSettingsInit);
        }
    }

    Class opener = objc_lookUpClass("_TtC20IGDogfoodingSettings20IGDogfoodingSettings");
    Class meta = opener ? object_getClass(opener) : Nil;
    if (!gRYGDogfoodSettingsOpenOriginal && meta) {
        SEL selector = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
        Method method = class_getInstanceMethod(meta, selector);
        if (method && method_getNumberOfArguments(method) == 5 && RYGMethodReturns(method, 'v') &&
            RYGMethodArgumentMatches(method, 2, '@') && RYGMethodArgumentMatches(method, 3, '@') &&
            RYGMethodArgumentMatches(method, 4, '@')) {
            gRYGDogfoodSettingsOpenOriginal = method_setImplementation(method, (IMP)RYGDogfoodSettingsOpen);
        }
    }
}

static BOOL RYGDogfoodLauncherOverride(id self, SEL cmd, id userSession, id launcherName, id parameters) {
    if (self) gRYGDogfoodLauncherClient = self;
    if (userSession) gRYGDogfoodLauncherSession = userSession;
    if ([launcherName isKindOfClass:NSString.class]) gRYGDogfoodLauncherName = [launcherName copy];
    if ([parameters isKindOfClass:NSDictionary.class]) gRYGDogfoodLauncherParameters = [parameters copy];
    RYGDogfoodLauncherFn original = (RYGDogfoodLauncherFn)gRYGDogfoodLauncherOriginal;
    return original ? original(self, cmd, userSession, launcherName, parameters) : NO;
}

static void RYGInstallDogfoodLauncherCapture(void) {
    if (gRYGDogfoodLauncherOriginal) return;
    Class cls = objc_lookUpClass("_TtC35IGDogfoodingAssistantLauncherClient35IGDogfoodingAssistantLauncherClient");
    SEL selector = NSSelectorFromString(@"overrideLauncherWithUserSession:launcherName:parametersToValues:");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (method && method_getNumberOfArguments(method) == 5 && RYGMethodReturns(method, 'B') &&
        RYGMethodArgumentMatches(method, 2, '@') && RYGMethodArgumentMatches(method, 3, '@') &&
        RYGMethodArgumentMatches(method, 4, '@')) {
        gRYGDogfoodLauncherOriginal = method_setImplementation(method, (IMP)RYGDogfoodLauncherOverride);
    }
}

static BOOL RYGReapplyCapturedDogfoodLauncher(void) {
    RYGInstallDogfoodLauncherCapture();
    if (!gRYGDogfoodLauncherClient || !gRYGDogfoodLauncherSession || !gRYGDogfoodLauncherName.length || !gRYGDogfoodLauncherParameters) return NO;
    SEL selector = NSSelectorFromString(@"overrideLauncherWithUserSession:launcherName:parametersToValues:");
    return ((BOOL (*)(id, SEL, id, id, id))objc_msgSend)(gRYGDogfoodLauncherClient, selector,
                                                         gRYGDogfoodLauncherSession,
                                                         gRYGDogfoodLauncherName,
                                                         gRYGDogfoodLauncherParameters);
}

#pragma mark - Exact Prism setter interception

typedef void (*RYGBoolSetterFn)(id, SEL, BOOL);

static void RYGPrismSetter(id self, SEL cmd, BOOL enabled) {
    RYGBoolSetterFn original = (RYGBoolSetterFn)gRYGPrismSetterOriginal;
    if (original) original(self, cmd, gRYGPrismSetterMode < 0 ? enabled : (gRYGPrismSetterMode != 0));
}

static void RYGRedesignSetter(id self, SEL cmd, BOOL enabled) {
    RYGBoolSetterFn original = (RYGBoolSetterFn)gRYGRedesignSetterOriginal;
    if (original) original(self, cmd, gRYGRedesignSetterMode < 0 ? enabled : (gRYGRedesignSetterMode != 0));
}

static BOOL RYGInstallBoolSetterHook(NSString *className, NSString *selectorName, IMP replacement, IMP *original) {
    if (*original) return YES;
    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = NSSelectorFromString(selectorName);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3 || !RYGMethodReturns(method, 'v') || !RYGMethodArgumentMatches(method, 2, 'B')) return NO;
    *original = method_setImplementation(method, replacement);
    return *original != NULL;
}

#pragma mark - Native presenters/helpers

static UIViewController *RYGTopViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) { keyWindow = window; break; }
        if (keyWindow) break;
    }
    UIViewController *top = keyWindow.rootViewController;
    BOOL changed = YES;
    while (changed && top) {
        changed = NO;
        if (top.presentedViewController && !top.presentedViewController.isBeingDismissed) { top = top.presentedViewController; changed = YES; continue; }
        if ([top isKindOfClass:UINavigationController.class] && ((UINavigationController *)top).visibleViewController) { top = ((UINavigationController *)top).visibleViewController; changed = YES; continue; }
        if ([top isKindOfClass:UITabBarController.class] && ((UITabBarController *)top).selectedViewController) { top = ((UITabBarController *)top).selectedViewController; changed = YES; }
    }
    return top;
}

static BOOL RYGOpenDogfoodSettings(void) {
    RYGInstallDogfoodConfigCapture();
    if (!gRYGDogfoodConfig || !gRYGDogfoodUserSession) return NO;
    Class cls = objc_lookUpClass("_TtC20IGDogfoodingSettings20IGDogfoodingSettings");
    SEL selector = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    UIViewController *top = RYGTopViewController();
    if (!top || !method || method_getNumberOfArguments(method) != 5 || !RYGMethodReturns(method, 'v') ||
        !RYGMethodArgumentMatches(method, 2, '@') || !RYGMethodArgumentMatches(method, 3, '@') || !RYGMethodArgumentMatches(method, 4, '@')) return NO;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)((id)cls, selector, gRYGDogfoodConfig, top, gRYGDogfoodUserSession);
    return YES;
}

static RYGRuntimeBoolMethod *RYGStoryTrayGateMethod(void) {
    return RYGRuntimeMethodForOwner(@"_TtC27IGPersistentStoryTrayGating38IGPersistentStoryTrayGatingStaticFuncs",
                                    @"isTrayAttachedToHeaderEnabled:", YES);
}

static BOOL RYGOpenStoryTrayDebug(void) {
    RYGRuntimeBoolMethod *gate = RYGStoryTrayGateMethod();
    if (!gate) return NO;
    NSNumber *forced = gate.overrideValue;
    NSNumber *observed = gate.liveValue;
    BOOL current = forced ? forced.boolValue : (observed ? observed.boolValue : NO);
    Class cls = objc_lookUpClass("_TtC25IGOverlayStoriesTrayDebug39IGOverlayStoriesTrayDebugViewController");
    SEL selector = NSSelectorFromString(@"presentFrom:currentlyEnabled:onApplyAndRestart:");
    Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 5 || !RYGMethodReturns(method, 'v') ||
        !RYGMethodArgumentMatches(method, 2, '@') || !RYGMethodArgumentMatches(method, 3, 'B')) return NO;
    char callbackType[96] = {0};
    method_getArgumentType(method, 4, callbackType, sizeof(callbackType));
    const char *unqualified = RYGUnqualifiedType(callbackType);
    if (!unqualified || strncmp(unqualified, "@?", 2) != 0) return NO;
    UIViewController *top = RYGTopViewController();
    if (!top) return NO;
    void (^completion)(BOOL) = ^(BOOL enabled) {
        [RYGRuntimeBrowserEngine setOverride:@(enabled) forMethod:gate];
    };
    ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)((id)cls, selector, top, current, completion);
    return YES;
}

static id RYGSharedHelper(NSString *className) {
    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = NSSelectorFromString(@"shared");
    Method method = cls ? class_getClassMethod(cls, selector) : NULL;
    return method && method_getNumberOfArguments(method) == 2 && RYGMethodReturns(method, '@')
        ? ((id (*)(id, SEL))objc_msgSend)((id)cls, selector) : nil;
}

static NSNumber *RYGNativeHelperEnabled(NSString *className) {
    id helper = RYGSharedHelper(className);
    SEL selector = NSSelectorFromString(@"isEnabled");
    Method method = helper ? class_getInstanceMethod([helper class], selector) : NULL;
    return method && method_getNumberOfArguments(method) == 2 && RYGMethodReturns(method, 'B')
        ? @(((BOOL (*)(id, SEL))objc_msgSend)(helper, selector)) : nil;
}

static BOOL RYGSetNativeHelperBool(NSString *className, NSString *selectorName, BOOL enabled) {
    id helper = RYGSharedHelper(className);
    SEL selector = NSSelectorFromString(selectorName);
    Method method = helper ? class_getInstanceMethod([helper class], selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 3 || !RYGMethodReturns(method, 'v') || !RYGMethodArgumentMatches(method, 2, 'B')) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(helper, selector, enabled);
    return YES;
}

#pragma mark - Resolved MobileConfig dogfood integration

typedef struct {
    unsigned int configNumber;
    unsigned int paramIndex;
    const char *label;
} RYGDogfoodMCTarget;

static const RYGDogfoodMCTarget kRYGDogfoodCoreMCTargets[] = {
    {56474, 0, "ig_is_employee.is_employee"},
    {56474, 1, "ig_is_employee.is_employee_or_employee_test_account"},
    {90775, 1, "ig_dogfooding_assistant.show_in_bug_report_menu"},
    {58792, 0, "ig_dogfooding_first_client.is_enabled"},
};

static RYGMCParam *RYGFindMCParamByIdentity(RYGMobileConfig *mobileConfig, unsigned int configNumber, unsigned int paramIndex) {
    if (!mobileConfig) return nil;
    for (RYGMCConfig *config in mobileConfig.allConfigs) {
        if (config.number != configNumber) continue;
        for (RYGMCParam *param in config.params) {
            if (param.paramIndex == paramIndex && param.isRuntimeBacked) return param;
        }
        break;
    }
    return nil;
}

static NSString *RYGDogfoodMCIdentity(unsigned int configNumber, unsigned int paramIndex) {
    return [NSString stringWithFormat:@"%u:%u", configNumber, paramIndex];
}

static NSDictionary *RYGDogfoodOwnedMCState(void) {
    id value = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGDogfoodOwnedMCStatePref];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSUInteger RYGApplyDogfoodCoreMobileConfig(BOOL enabled, NSUInteger *availableCount) {
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    NSMutableDictionary *owned = [RYGDogfoodOwnedMCState() mutableCopy];
    NSUInteger available = 0, changed = 0;

    for (NSUInteger index = 0; index < sizeof(kRYGDogfoodCoreMCTargets) / sizeof(kRYGDogfoodCoreMCTargets[0]); index++) {
        const RYGDogfoodMCTarget target = kRYGDogfoodCoreMCTargets[index];
        NSString *identity = RYGDogfoodMCIdentity(target.configNumber, target.paramIndex);
        RYGMCParam *param = RYGFindMCParamByIdentity(mobileConfig, target.configNumber, target.paramIndex);
        if (!param || param.type != RYGMCTypeBool) continue;
        available++;

        if (enabled) {
            NSDictionary *ownership = [owned[identity] isKindOfClass:NSDictionary.class] ? owned[identity] : nil;
            NSNumber *existing = [mobileConfig overrideValueFor:param];
            if (!ownership && existing && existing.boolValue) continue;

            if (!ownership) {
                NSMutableDictionary *record = [NSMutableDictionary dictionary];
                BOOL hadOverride = [mobileConfig overrideStateFor:param] == RYGMCOverrideSet;
                record[@"hadOverride"] = @(hadOverride);
                if (hadOverride && existing) record[@"previousValue"] = @([existing boolValue]);
                record[@"label"] = [NSString stringWithUTF8String:target.label] ?: identity;
                ownership = record.copy;
            }

            if ([mobileConfig setOverride:@YES for:param]) {
                owned[identity] = ownership;
                changed++;
            }
        } else {
            NSDictionary *ownership = [owned[identity] isKindOfClass:NSDictionary.class] ? owned[identity] : nil;
            if (!ownership) continue;
            BOOL hadOverride = [ownership[@"hadOverride"] boolValue];
            NSNumber *previous = [ownership[@"previousValue"] isKindOfClass:NSNumber.class] ? ownership[@"previousValue"] : nil;
            if (hadOverride && previous) {
                if ([mobileConfig setOverride:previous for:param]) {
                    [owned removeObjectForKey:identity];
                    changed++;
                }
            } else {
                [mobileConfig clearOverrideFor:param];
                [owned removeObjectForKey:identity];
                changed++;
            }
        }
    }

    if (owned.count) [NSUserDefaults.standardUserDefaults setObject:owned.copy forKey:kRYGDogfoodOwnedMCStatePref];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:kRYGDogfoodOwnedMCStatePref];
    if (availableCount) *availableCount = available;
    return changed;
}

static NSArray<RYGMCParam *> *RYGExactPrismMCCandidates(void) {
    static const unsigned int targets[][2] = {
        {111146, 1},
        {111146, 3},
        {76504, 1},
        {76504, 19},
        {76504, 21},
        {44021, 9},
        {44021, 18},
    };
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    NSMutableArray<RYGMCParam *> *rows = [NSMutableArray array];
    for (NSUInteger index = 0; index < sizeof(targets) / sizeof(targets[0]); index++) {
        RYGMCParam *param = RYGFindMCParamByIdentity(mobileConfig, targets[index][0], targets[index][1]);
        if (param && param.type == RYGMCTypeBool) [rows addObject:param];
    }
    return rows.copy;
}

static BOOL RYGDogfoodCandidateName(NSString *name) {
    NSString *value = name.lowercaseString ?: @"";
    return [value containsString:@"dogfood"] || [value containsString:@"employee"] || [value containsString:@"internal"];
}

static NSArray<RYGMCParam *> *RYGResolvedDogfoodMCCandidates(void) {
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    NSMutableArray<RYGMCParam *> *out = [NSMutableArray array];
    for (RYGMCConfig *config in mobileConfig.allConfigs) {
        BOOL configMatch = RYGDogfoodCandidateName(config.name);
        for (RYGMCParam *param in config.params) {
            if (!param.isRuntimeBacked || param.type != RYGMCTypeBool || !param.name.length) continue;
            if (configMatch || RYGDogfoodCandidateName(param.name)) [out addObject:param];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(RYGMCParam *left, RYGMCParam *right) {
        if (left.configNumber != right.configNumber) return left.configNumber < right.configNumber ? NSOrderedAscending : NSOrderedDescending;
        return left.paramIndex == right.paramIndex ? NSOrderedSame : (left.paramIndex < right.paramIndex ? NSOrderedAscending : NSOrderedDescending);
    }];
    return out.copy;
}

#pragma mark - Controller

static void RYGDeveloperNativeImageDidLoad(const struct mach_header *header, intptr_t slide);
static void RYGEnsureDeveloperImageCallback(void);
static void RYGScheduleDeveloperNativeActivation(void);

@interface RYGDeveloperTopicViewController () <UISearchResultsUpdating>
@property (nonatomic, assign) RYGDeveloperRuntimeSurface surface;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSArray<RYGRuntimeBoolMethod *> *allRows;
@property (nonatomic, copy) NSArray<NSString *> *classSections;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *rowsByClass;
@property (nonatomic, copy) NSArray<NSDictionary *> *nativeControls;
@property (nonatomic, copy) NSArray<RYGMCParam *> *mobileConfigCandidates;
@end

@implementation RYGDeveloperTopicViewController

+ (void)activatePersistedNativeFeatures {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSNumber *prismMode = [defaults objectForKey:kRYGPrismSetterModePref];
    NSNumber *redesignMode = [defaults objectForKey:kRYGRedesignSetterModePref];
    gRYGPrismSetterMode = [prismMode isKindOfClass:NSNumber.class] ? prismMode.integerValue : -1;
    gRYGRedesignSetterMode = [redesignMode isKindOfClass:NSNumber.class] ? redesignMode.integerValue : -1;
    if (gRYGPrismSetterMode >= 0) (void)RYGInstallBoolSetterHook(@"IGBloksFollowButtonView", @"setPrismEnabled:", (IMP)RYGPrismSetter, &gRYGPrismSetterOriginal);
    if (gRYGRedesignSetterMode >= 0) (void)RYGInstallBoolSetterHook(@"IGTableViewCell", @"setListRedesignOn:", (IMP)RYGRedesignSetter, &gRYGRedesignSetterOriginal);
    [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
    BOOL dogfoodMode = [defaults boolForKey:kRYGDogfoodModePref];
    BOOL internalMode = dogfoodMode || [defaults boolForKey:kRYGInternalMenuPref];
    if (internalMode) RYGInstallBugMenuHooks();
    if (dogfoodMode) {
        RYGInstallDogfoodConfigCapture();
        RYGInstallDogfoodLauncherCapture();
        [RYGEasyGatingRuntime.shared installIfNeeded];
        (void)RYGApplyDogfoodCoreMobileConfig(YES, NULL);
    }
}

- (instancetype)initWithSurface:(RYGDeveloperRuntimeSurface)surface {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _surface = surface;
        _allRows = @[];
        _classSections = @[];
        _rowsByClass = @{};
        _nativeControls = @[];
        _mobileConfigCandidates = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = RYGSurfaceTitle(self.surface);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 54.0;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Class, method or resolved MobileConfig";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    RYGLiquidGlassApplyToViewController(self);
    [[self class] activatePersistedNativeFeatures];
    [self rebuildModels];

    if (self.surface == RYGDeveloperRuntimeSurfaceStories) {
        RYGRuntimeBoolMethod *gate = RYGStoryTrayGateMethod();
        if (gate) [RYGRuntimeBrowserEngine observeMethod:gate];
    }
}

- (void)rebuildModels {
    self.allRows = RYGRowsForSurface(self.surface);
    [self rebuildNativeControls];
    if (self.surface == RYGDeveloperRuntimeSurfaceDirectDogfood) self.mobileConfigCandidates = RYGResolvedDogfoodMCCandidates();
    else if (self.surface == RYGDeveloperRuntimeSurfacePrism) self.mobileConfigCandidates = RYGExactPrismMCCandidates();
    else self.mobileConfigCandidates = @[];
    [self rebuildFilteredModel];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self rebuildFilteredModel];
}

- (BOOL)text:(NSString *)text matchesTokens:(NSArray<NSString *> *)tokens {
    NSString *lower = text.lowercaseString ?: @"";
    for (NSString *token in tokens) if (token.length && [lower rangeOfString:token].location == NSNotFound) return NO;
    return YES;
}

- (void)rebuildFilteredModel {
    NSString *query = self.searchController.searchBar.text.lowercaseString ?: @"";
    NSArray<NSString *> *tokens = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableDictionary<NSString *, NSMutableArray<RYGRuntimeBoolMethod *> *> *groups = [NSMutableDictionary dictionary];
    for (RYGRuntimeBoolMethod *method in self.allRows) {
        NSString *text = [NSString stringWithFormat:@"%@ %@ %@", method.className ?: @"", method.selectorName ?: @"", method.typeEncoding ?: @""];
        if (![self text:text matchesTokens:tokens]) continue;
        NSString *key = method.className.length ? method.className : @"Runtime";
        if (!groups[key]) groups[key] = [NSMutableArray array];
        [groups[key] addObject:method];
    }
    self.classSections = [groups.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableDictionary *frozen = [NSMutableDictionary dictionary];
    for (NSString *key in self.classSections) frozen[key] = [groups[key] copy];
    self.rowsByClass = frozen.copy;
    [self.tableView reloadData];
}

- (void)rebuildNativeControls {
    NSMutableArray *rows = [NSMutableArray array];
    switch (self.surface) {
        case RYGDeveloperRuntimeSurfacePrism:
            [rows addObject:@{@"kind":@"prismSetter", @"title":@"Follow Button Prism setter", @"subtitle":@"Exact -setPrismEnabled: · Native / Force On / Force Off"}];
            [rows addObject:@{@"kind":@"redesignSetter", @"title":@"List Redesign setter", @"subtitle":@"Exact -setListRedesignOn: · Native / Force On / Force Off"}];
            break;
        case RYGDeveloperRuntimeSurfaceLiquidGlass:
            [rows addObject:@{@"kind":@"swizzleGlass", @"title":@"Liquid Glass Swizzle", @"subtitle":@"Native -setIsEnabled:"}];
            [rows addObject:@{@"kind":@"throwback", @"title":@"Throwback Chrome", @"subtitle":@"Native -overrideIsEnabled:"}];
            [rows addObject:@{@"kind":@"navGlass", @"title":@"Liquid Glass Navigation", @"subtitle":@"Native -overrideIsEnabled:"}];
            break;
        case RYGDeveloperRuntimeSurfaceStories:
            [rows addObject:@{@"kind":@"storyDebug", @"title":@"Open native Story Tray Debug", @"subtitle":@"Uses the actual observed isTrayAttachedToHeaderEnabled: value"}];
            break;
        case RYGDeveloperRuntimeSurfaceInternalOnly:
        case RYGDeveloperRuntimeSurfaceBugReport:
        case RYGDeveloperRuntimeSurfaceSettingsRows:
            [rows addObject:@{@"kind":@"internal", @"title":@"Expose Internal Settings", @"subtitle":@"Hooks both validated IGBugReportMenu initializers; only visibility BOOL arguments change"}];
            break;
        case RYGDeveloperRuntimeSurfaceDirectDogfood:
            [rows addObject:@{@"kind":@"dogfood", @"title":@"Global Dogfooding Mode", @"subtitle":@"Internal menu + native launcher capture + EasyGating final IDs + exact dogfooding-assistant MobileConfig"}];
            [rows addObject:@{@"kind":@"dogfoodOpen", @"title":@"Open Dogfooding Settings", @"subtitle":@"Reuses a real IGDogfoodingSettingsConfig captured from Instagram"}];
            [rows addObject:@{@"kind":@"dogfoodLauncher", @"title":@"Reapply native Dogfooding launcher", @"subtitle":@"Reuses the exact captured userSession / launcher / parameters"}];
            [rows addObject:@{@"kind":@"easyGating", @"title":@"EasyGating final-ID observer", @"subtitle":@"Observes the final mapped IDs; no pre-map selector guessing"}];
            break;
        default:
            break;
    }
    self.nativeControls = rows.copy;
}

- (NSInteger)nativeSectionCount { return self.nativeControls.count ? 1 : 0; }
- (NSInteger)mobileConfigSectionIndex { return [self nativeSectionCount] + self.classSections.count; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [self nativeSectionCount] + self.classSections.count + (self.mobileConfigCandidates.count ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (self.nativeControls.count && section == 0) return self.nativeControls.count;
    NSInteger classIndex = section - [self nativeSectionCount];
    if (classIndex >= 0 && classIndex < (NSInteger)self.classSections.count) return [self.rowsByClass[self.classSections[(NSUInteger)classIndex]] count];
    if (self.mobileConfigCandidates.count && section == [self mobileConfigSectionIndex]) return self.mobileConfigCandidates.count;
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (self.nativeControls.count && section == 0) return @"Native controls";
    NSInteger classIndex = section - [self nativeSectionCount];
    if (classIndex >= 0 && classIndex < (NSInteger)self.classSections.count) return self.classSections[(NSUInteger)classIndex];
    if (self.mobileConfigCandidates.count && section == [self mobileConfigSectionIndex]) {
        return self.surface == RYGDeveloperRuntimeSurfacePrism
            ? @"Validated Prism MobileConfig"
            : @"Resolved MobileConfig · dogfood / employee / internal";
    }
    return nil;
}

- (RYGRuntimeBoolMethod *)methodAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger classIndex = indexPath.section - [self nativeSectionCount];
    if (classIndex < 0 || classIndex >= (NSInteger)self.classSections.count) return nil;
    NSArray *rows = self.rowsByClass[self.classSections[(NSUInteger)classIndex]];
    return indexPath.row < (NSInteger)rows.count ? rows[(NSUInteger)indexPath.row] : nil;
}

- (UIButton *)glassSelectorWithTitle:(NSString *)title actions:(NSArray<UIAction *> *)actions {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = title ?: @"Native";
    button.configuration = configuration;
    button.menu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
    button.showsMenuAsPrimaryAction = YES;
    button.changesSelectionAsPrimaryAction = YES;
    RYGLiquidGlassConfigureButton(button, NO);
    return button;
}

- (UIButton *)selectorButtonForMethod:(RYGRuntimeBoolMethod *)method {
    NSNumber *forced = method.overrideValue;
    NSNumber *native = method.liveValue;
    NSString *title = forced ? (forced.boolValue ? @"Forced On" : @"Forced Off") : (native ? (native.boolValue ? @"Native On" : @"Native Off") : @"Native");
    __weak typeof(self) weakSelf = self;
    UIAction *nativeAction = [UIAction actionWithTitle:@"Native" image:nil identifier:nil handler:^(__unused UIAction *action) { [RYGRuntimeBrowserEngine setOverride:nil forMethod:method]; [weakSelf.tableView reloadData]; }];
    nativeAction.state = forced ? UIMenuElementStateOff : UIMenuElementStateOn;
    UIAction *onAction = [UIAction actionWithTitle:@"Force On" image:nil identifier:nil handler:^(__unused UIAction *action) { [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method]; [weakSelf.tableView reloadData]; }];
    onAction.state = forced && forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *offAction = [UIAction actionWithTitle:@"Force Off" image:nil identifier:nil handler:^(__unused UIAction *action) { [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method]; [weakSelf.tableView reloadData]; }];
    offAction.state = forced && !forced.boolValue ? UIMenuElementStateOn : UIMenuElementStateOff;
    return [self glassSelectorWithTitle:title actions:@[nativeAction, onAction, offAction]];
}

- (UIButton *)setterSelectorForKind:(NSString *)kind mode:(NSInteger)mode {
    __weak typeof(self) weakSelf = self;
    UIAction *(^action)(NSString *, NSInteger) = ^UIAction *(NSString *title, NSInteger value) {
        UIAction *item = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *a) {
            if ([kind isEqualToString:@"prismSetter"]) {
                if (!RYGInstallBoolSetterHook(@"IGBloksFollowButtonView", @"setPrismEnabled:", (IMP)RYGPrismSetter, &gRYGPrismSetterOriginal)) {
                    [RYGUtils showErrorHUDWithDescription:@"IGBloksFollowButtonView -setPrismEnabled: is not loaded with the validated v20@0:8B16 ABI"];
                    return;
                }
                gRYGPrismSetterMode = value;
                if (value < 0) [NSUserDefaults.standardUserDefaults removeObjectForKey:kRYGPrismSetterModePref];
                else [NSUserDefaults.standardUserDefaults setInteger:value forKey:kRYGPrismSetterModePref];
            } else {
                if (!RYGInstallBoolSetterHook(@"IGTableViewCell", @"setListRedesignOn:", (IMP)RYGRedesignSetter, &gRYGRedesignSetterOriginal)) {
                    [RYGUtils showErrorHUDWithDescription:@"IGTableViewCell -setListRedesignOn: is not loaded with the validated v20@0:8B16 ABI"];
                    return;
                }
                gRYGRedesignSetterMode = value;
                if (value < 0) [NSUserDefaults.standardUserDefaults removeObjectForKey:kRYGRedesignSetterModePref];
                else [NSUserDefaults.standardUserDefaults setInteger:value forKey:kRYGRedesignSetterModePref];
            }
            [weakSelf.tableView reloadData];
        }];
        item.state = mode == value ? UIMenuElementStateOn : UIMenuElementStateOff;
        return item;
    };
    NSString *title = mode < 0 ? @"Native" : (mode ? @"Forced On" : @"Forced Off");
    return [self glassSelectorWithTitle:title actions:@[action(@"Native", -1), action(@"Force On", 1), action(@"Force Off", 0)]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.nativeControls.count && indexPath.section == 0) {
        NSDictionary *control = self.nativeControls[(NSUInteger)indexPath.row];
        NSString *kind = control[@"kind"];
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGNativeControl"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGNativeControl"];
        cell.textLabel.text = control[@"title"];
        cell.detailTextLabel.text = control[@"subtitle"];
        cell.detailTextLabel.numberOfLines = 2;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

        if ([kind isEqualToString:@"internal"] || [kind isEqualToString:@"dogfood"] ||
            [kind isEqualToString:@"swizzleGlass"] || [kind isEqualToString:@"throwback"] || [kind isEqualToString:@"navGlass"]) {
            UISwitch *toggle = [UISwitch new];
            if ([kind isEqualToString:@"internal"]) toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:kRYGInternalMenuPref];
            else if ([kind isEqualToString:@"dogfood"]) toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:kRYGDogfoodModePref];
            else if ([kind isEqualToString:@"swizzleGlass"]) toggle.on = [RYGNativeHelperEnabled(@"_TtC20IGLiquidGlassSwizzle26IGLiquidGlassSwizzleToggle") boolValue];
            else if ([kind isEqualToString:@"throwback"]) toggle.on = [RYGNativeHelperEnabled(@"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper") boolValue];
            else toggle.on = [RYGNativeHelperEnabled(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper") boolValue];
            toggle.onTintColor = [RYGUtils RYGColor_Primary];
            objc_setAssociatedObject(toggle, kRYGNativeControlKey, kind, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [toggle addTarget:self action:@selector(nativeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if ([kind isEqualToString:@"prismSetter"]) {
            cell.accessoryView = [self setterSelectorForKind:kind mode:gRYGPrismSetterMode];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if ([kind isEqualToString:@"redesignSetter"]) {
            cell.accessoryView = [self setterSelectorForKind:kind mode:gRYGRedesignSetterMode];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }

    if (self.mobileConfigCandidates.count && indexPath.section == [self mobileConfigSectionIndex]) {
        RYGMCParam *param = self.mobileConfigCandidates[(NSUInteger)indexPath.row];
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGDogfoodMC"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGDogfoodMC"];
        cell.textLabel.text = param.name.length ? param.name : [NSString stringWithFormat:@"Param %u", param.paramIndex];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"config %u · param %u", param.configNumber, param.paramIndex];
        UISwitch *toggle = [UISwitch new];
        RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
        NSNumber *forced = [mobileConfig overrideValueFor:param];
        id live = [mobileConfig liveValueFor:param];
        toggle.on = forced ? forced.boolValue : ([live isKindOfClass:NSNumber.class] ? [live boolValue] : NO);
        toggle.onTintColor = [RYGUtils RYGColor_Primary];
        objc_setAssociatedObject(toggle, kRYGMCParamKey, param, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(mobileConfigSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RYGKnownMethod"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGKnownMethod"];
    RYGRuntimeBoolMethod *method = [self methodAtIndexPath:indexPath];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", method.classMethod ? @"+" : @"−", method.selectorName ?: @""];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightMedium];
    cell.textLabel.numberOfLines = 2;
    NSNumber *native = method.liveValue;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", method.typeEncoding ?: @"", native ? (native.boolValue ? @"observed true" : @"observed false") : @"not observed"];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = [self selectorButtonForMethod:method];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)mobileConfigSwitchChanged:(UISwitch *)toggle {
    RYGMCParam *param = objc_getAssociatedObject(toggle, kRYGMCParamKey);
    if (!param) return;
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    if (![mobileConfig setOverride:@(toggle.isOn) for:param]) {
        toggle.on = !toggle.isOn;
        [RYGUtils showErrorHUDWithDescription:@"The resolved MobileConfig row is not currently writable through FBMobileConfigStartupConfigs"];
    }
}

- (void)nativeSwitchChanged:(UISwitch *)toggle {
    NSString *kind = objc_getAssociatedObject(toggle, kRYGNativeControlKey);
    if ([kind isEqualToString:@"internal"]) {
        [NSUserDefaults.standardUserDefaults setBool:toggle.isOn forKey:kRYGInternalMenuPref];
        if (toggle.isOn) {
            RYGEnsureDeveloperImageCallback();
            RYGInstallBugMenuHooks();
            RYGScheduleDeveloperNativeActivation();
        }
        return;
    }
    if ([kind isEqualToString:@"dogfood"]) {
        [NSUserDefaults.standardUserDefaults setBool:toggle.isOn forKey:kRYGDogfoodModePref];
        if (toggle.isOn) {
            RYGEnsureDeveloperImageCallback();
            RYGInstallBugMenuHooks();
            RYGInstallDogfoodConfigCapture();
            RYGInstallDogfoodLauncherCapture();
            [RYGEasyGatingRuntime.shared installIfNeeded];
            NSUInteger available = 0;
            NSUInteger mobileConfigChanged = RYGApplyDogfoodCoreMobileConfig(YES, &available);
            BOOL launcherReapplied = RYGReapplyCapturedDogfoodLauncher();
            RYGScheduleDeveloperNativeActivation();
            [RYGUtils showToastForDuration:2.0 title:@"Dogfooding enabled" subtitle:[NSString stringWithFormat:@"core MC %lu/%lu active · launcher %@", (unsigned long)mobileConfigChanged, (unsigned long)available, launcherReapplied ? @"reapplied" : @"awaiting native context"]];
        } else {
            NSUInteger available = 0;
            NSUInteger restored = RYGApplyDogfoodCoreMobileConfig(NO, &available);
            [RYGUtils showToastForDuration:1.5 title:@"Dogfooding disabled" subtitle:[NSString stringWithFormat:@"%lu RyukGram-owned MC value(s) restored", (unsigned long)restored]];
        }
        [self rebuildModels];
        return;
    }
    if ([kind isEqualToString:@"swizzleGlass"]) {
        if (!RYGSetNativeHelperBool(@"_TtC20IGLiquidGlassSwizzle26IGLiquidGlassSwizzleToggle", @"setIsEnabled:", toggle.isOn)) toggle.on = !toggle.isOn;
    } else if ([kind isEqualToString:@"throwback"]) {
        if (!RYGSetNativeHelperBool(@"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper", @"overrideIsEnabled:", toggle.isOn)) toggle.on = !toggle.isOn;
    } else if ([kind isEqualToString:@"navGlass"]) {
        if (!RYGSetNativeHelperBool(@"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper", @"overrideIsEnabled:", toggle.isOn)) toggle.on = !toggle.isOn;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.nativeControls.count && indexPath.section == 0) {
        NSString *kind = self.nativeControls[(NSUInteger)indexPath.row][@"kind"];
        if ([kind isEqualToString:@"storyDebug"]) {
            if (!RYGOpenStoryTrayDebug()) [RYGUtils showErrorHUDWithDescription:@"Native Story Tray Debug controller is unavailable or its ABI no longer matches."];
        } else if ([kind isEqualToString:@"dogfoodOpen"]) {
            if (!RYGOpenDogfoodSettings()) [RYGUtils showErrorHUDWithDescription:@"No real IGDogfoodingSettingsConfig has been captured yet. Open Instagram's native Dogfooding Assistant once; the validated opener will then reuse that config."];
        } else if ([kind isEqualToString:@"dogfoodLauncher"]) {
            if (!RYGReapplyCapturedDogfoodLauncher()) [RYGUtils showErrorHUDWithDescription:@"No native Dogfooding launcher invocation has been captured yet"];
        } else if ([kind isEqualToString:@"easyGating"]) {
            [RYGEasyGatingRuntime.shared installIfNeeded];
            [RYGUtils showToastForDuration:1.2 title:@"EasyGating observer installed" subtitle:[NSString stringWithFormat:@"%lu final IDs observed", (unsigned long)RYGEasyGatingRuntime.shared.observations.count]];
        }
        return;
    }
    if (self.mobileConfigCandidates.count && indexPath.section == [self mobileConfigSectionIndex]) return;
    RYGRuntimeBoolMethod *method = [self methodAtIndexPath:indexPath];
    if (!method) return;
    RYGRuntimeBeginLiveObservation(@[method]);
    [RYGUtils showToastForDuration:1.0 title:@"Observing native value" subtitle:method.selectorName];
}

@end

#pragma mark - Persisted exact native activation

static void RYGEnsureDeveloperImageCallback(void) {
    @synchronized(RYGDeveloperTopicViewController.class) {
        if (gRYGDeveloperImageCallbackRegistered) return;
        gRYGDeveloperImageCallbackRegistered = YES;
    }
    _dyld_register_func_for_add_image(RYGDeveloperNativeImageDidLoad);
}

static void RYGScheduleDeveloperNativeActivation(void) {
    @synchronized(RYGDeveloperTopicViewController.class) {
        if (gRYGDeveloperBootstrapScheduled) return;
        gRYGDeveloperBootstrapScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized(RYGDeveloperTopicViewController.class) { gRYGDeveloperBootstrapScheduled = NO; }
        [RYGDeveloperTopicViewController activatePersistedNativeFeatures];
    });
}

static void RYGDeveloperNativeImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    RYGScheduleDeveloperNativeActivation();
}

__attribute__((constructor(210))) static void RYGDeveloperNativeBootstrap(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if (![defaults boolForKey:kRYGDogfoodModePref] && ![defaults boolForKey:kRYGInternalMenuPref]) return;
        RYGEnsureDeveloperImageCallback();
        RYGScheduleDeveloperNativeActivation();
    }
}
