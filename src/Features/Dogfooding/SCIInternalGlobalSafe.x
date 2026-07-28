// SCIInternalGlobalSafe.x
// New-IG internal/employee bridge validated against:
// Instagram fa19f499c560b188d2802e3a1a36642209ee6e42d7639c1ebe010f14b2c4cd9b
// FBSharedFramework a79c110c59e7c16e5608227e12807583c1afcf80cb2a2e38302f147dbf99c12b
//
// Important: XPlugins hashes 0x64327C01 (internal_only) and 0x7FBC8058
// (Dogfooding Assistant socket) both resolve to the empty provider at
// Instagram+0x02BD80E4. A provider returns a 16-byte pair in x0/x1
// (data pointer, element count). Never replace it with a BOOL/sentinel pointer.

#import "../../Utils.h"
#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define IGSLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] InternalGlobalSafe " fmt, ##__VA_ARGS__)

void SCIInstallEmployeeInternalHooksIfNeeded(void);
static void SCIInstallInternalGlobalSafeHooksIfNeeded(void);

typedef struct {
    const void *data;
    uintptr_t count;
} SCIXPluginsDataPair;

typedef SCIXPluginsDataPair (*SCIXPluginsDataProvider)(void);
typedef void *(*SCIXPluginsGetDataFuncOrAbortFn)(uint32_t hash);

typedef struct {
    uint64_t raw;
} SCIMCBoolParam;

static const uint64_t kSCIEmployeeOrTestUserMC = 0x008100A700000134ULL;
static const uint64_t kSCIDogfoodingAssistantMC = 0x00810A8A000139D6ULL;
static const uint32_t kSCIInternalOnlyPluginHash = 0x64327C01U;
static const uint32_t kSCIDogfoodSocketPluginHash = 0x7FBC8058U;

static BOOL SCIEmployeeInternalMasterOn(void) {
    return [SCIUtils getBoolPref:@"sci_employee_internal"] ||
           [SCIUtils getBoolPref:@"sci_force_ig_internal_employee"] ||
           [SCIUtils getBoolPref:@"sci_force_ig_is_employee"];
}

static BOOL SCIInternalMenuOn(void) {
    return SCIEmployeeInternalMasterOn() ||
           [SCIUtils getBoolPref:@"sci_force_internal_settings_menu"] ||
           [SCIUtils getBoolPref:@"sci_force_internal_settings_availability"];
}

static SCIXPluginsGetDataFuncOrAbortFn SCIResolveXPluginsGetter(void) {
    static SCIXPluginsGetDataFuncOrAbortFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "XPluginsGetDataFuncOrAbort");
        if (!symbol) symbol = MSFindSymbol(NULL, "_XPluginsGetDataFuncOrAbort");
        fn = (SCIXPluginsGetDataFuncOrAbortFn)symbol;
    });
    return fn;
}

static BOOL SCIXPluginsPayloadAvailable(uint32_t hash) {
    SCIXPluginsGetDataFuncOrAbortFn getter = SCIResolveXPluginsGetter();
    if (!getter) return NO;

    SCIXPluginsDataProvider provider = (SCIXPluginsDataProvider)getter(hash);
    if (!provider) return NO;

    // The two hashes are present in the audited table, so calling their provider
    // is safe. The empty implementation returns { NULL, 0 } in x0/x1.
    SCIXPluginsDataPair pair = provider();
    return pair.data != NULL && pair.count != 0;
}

static BOOL SCIInternalOnlyPayloadAvailable(void) {
    static int cached = -1;
    if (cached < 0) cached = SCIXPluginsPayloadAvailable(kSCIInternalOnlyPluginHash) ? 1 : 0;
    return cached == 1;
}

static BOOL SCIDogfoodAssistantPayloadAvailable(void) {
    static int cached = -1;
    if (cached < 0) cached = SCIXPluginsPayloadAvailable(kSCIDogfoodSocketPluginHash) ? 1 : 0;
    return cached == 1;
}

static BOOL SCIShouldForceMCParam(SCIMCBoolParam param) {
    if (!SCIEmployeeInternalMasterOn()) return NO;
    if (param.raw == kSCIEmployeeOrTestUserMC) return YES;

    // Do not expose Dogfooding Assistant when its native socket/provider payload
    // is absent. This prevents a visible row from reaching an unavailable thunk.
    if (param.raw == kSCIDogfoodingAssistantMC) {
        return SCIDogfoodAssistantPayloadAvailable();
    }
    return NO;
}

static BOOL (*orig_MCGetBool)(id, SEL, SCIMCBoolParam) = NULL;
static BOOL (*orig_MCGetBoolDefault)(id, SEL, SCIMCBoolParam, BOOL) = NULL;
static BOOL (*orig_MCGetBoolOptions)(id, SEL, SCIMCBoolParam, id) = NULL;
static BOOL (*orig_MCGetBoolOptionsDefault)(id, SEL, SCIMCBoolParam, id, BOOL) = NULL;
static BOOL (*orig_MCGetBoolNoLog)(id, SEL, SCIMCBoolParam) = NULL;
static BOOL (*orig_MCGetBoolNoLogDefault)(id, SEL, SCIMCBoolParam, BOOL) = NULL;

static BOOL SCI_MCGetBool(id self, SEL _cmd, SCIMCBoolParam param) {
    if (SCIShouldForceMCParam(param)) return YES;
    return orig_MCGetBool ? orig_MCGetBool(self, _cmd, param) : NO;
}

static BOOL SCI_MCGetBoolDefault(id self, SEL _cmd, SCIMCBoolParam param, BOOL fallback) {
    if (SCIShouldForceMCParam(param)) return YES;
    return orig_MCGetBoolDefault ? orig_MCGetBoolDefault(self, _cmd, param, fallback) : fallback;
}

static BOOL SCI_MCGetBoolOptions(id self, SEL _cmd, SCIMCBoolParam param, id options) {
    if (SCIShouldForceMCParam(param)) return YES;
    return orig_MCGetBoolOptions ? orig_MCGetBoolOptions(self, _cmd, param, options) : NO;
}

static BOOL SCI_MCGetBoolOptionsDefault(id self, SEL _cmd, SCIMCBoolParam param, id options, BOOL fallback) {
    if (SCIShouldForceMCParam(param)) return YES;
    return orig_MCGetBoolOptionsDefault
        ? orig_MCGetBoolOptionsDefault(self, _cmd, param, options, fallback)
        : fallback;
}

static BOOL SCI_MCGetBoolNoLog(id self, SEL _cmd, SCIMCBoolParam param) {
    if (SCIShouldForceMCParam(param)) return YES;
    return orig_MCGetBoolNoLog ? orig_MCGetBoolNoLog(self, _cmd, param) : NO;
}

static BOOL SCI_MCGetBoolNoLogDefault(id self, SEL _cmd, SCIMCBoolParam param, BOOL fallback) {
    if (SCIShouldForceMCParam(param)) return YES;
    return orig_MCGetBoolNoLogDefault
        ? orig_MCGetBoolNoLogDefault(self, _cmd, param, fallback)
        : fallback;
}

static BOOL SCIIsBoolMethodWithArgumentCount(Method method, unsigned int count) {
    if (!method || method_getNumberOfArguments(method) != count) return NO;
    char *returnType = method_copyReturnType(method);
    BOOL valid = returnType && (returnType[0] == 'B' || returnType[0] == 'c');
    if (returnType) free(returnType);
    return valid;
}

static void SCIInstallMobileConfigEmployeeHooks(void) {
    static BOOL installed = NO;
    if (installed || !SCIEmployeeInternalMasterOn()) return;

    Class cls = objc_getClass("FBMobileConfigContextManager");
    if (!cls) return;

#define SCI_HOOK_MC(selectorName, argc, replacement, original) do { \
    SEL selector = NSSelectorFromString(selectorName); \
    Method method = class_getInstanceMethod(cls, selector); \
    if (!(original) && SCIIsBoolMethodWithArgumentCount(method, argc)) { \
        MSHookMessageEx(cls, selector, (IMP)(replacement), (IMP *)&(original)); \
    } else if (method && !(original)) { \
        IGSLOG("skip %{public}s ABI=%{public}s", selectorName, method_getTypeEncoding(method)); \
    } \
} while (0)

    SCI_HOOK_MC("getBool:", 3, SCI_MCGetBool, orig_MCGetBool);
    SCI_HOOK_MC("getBool:withDefault:", 4, SCI_MCGetBoolDefault, orig_MCGetBoolDefault);
    SCI_HOOK_MC("getBool:withOptions:", 4, SCI_MCGetBoolOptions, orig_MCGetBoolOptions);
    SCI_HOOK_MC("getBool:withOptions:withDefault:", 5, SCI_MCGetBoolOptionsDefault, orig_MCGetBoolOptionsDefault);
    SCI_HOOK_MC("getBoolWithoutLogging:", 3, SCI_MCGetBoolNoLog, orig_MCGetBoolNoLog);
    SCI_HOOK_MC("getBoolWithoutLogging:withDefault:", 4, SCI_MCGetBoolNoLogDefault, orig_MCGetBoolNoLogDefault);

#undef SCI_HOOK_MC

    installed = orig_MCGetBool || orig_MCGetBoolDefault || orig_MCGetBoolOptions ||
                orig_MCGetBoolOptionsDefault || orig_MCGetBoolNoLog ||
                orig_MCGetBoolNoLogDefault;
    IGSLOG("MC employee hooks installed=%d internalPayload=%d assistantPayload=%d",
           installed, SCIInternalOnlyPayloadAvailable(),
           SCIDogfoodAssistantPayloadAvailable());
}

static BOOL SCIWriteBoolIvar(id object, const char *name, BOOL value) {
    if (!object || !name) return NO;
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar) return NO;
    BOOL normalized = value ? YES : NO;
    uint8_t *bytes = (uint8_t *)(__bridge void *)object;
    memcpy(bytes + ivar_getOffset(ivar), &normalized, sizeof(normalized));
    return YES;
}

static UITableView *SCIBugMenuTableView(id controller) {
    if (!controller) return nil;
    Ivar ivar = class_getInstanceVariable([controller class], "tableView");
    if (!ivar) ivar = class_getInstanceVariable([controller class], "_tableView");
    if (!ivar) return nil;
    id value = object_getIvar(controller, ivar);
    return [value isKindOfClass:UITableView.class] ? value : nil;
}

static NSString *SCITextInView(UIView *view) {
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) {
        return ((UILabel *)view).text;
    }
    for (UIView *child in view.subviews) {
        NSString *text = SCITextInView(child);
        if (text.length) return text;
    }
    return nil;
}

static NSString *SCIBugMenuCellTitle(UITableViewCell *cell) {
    NSString *title = cell.textLabel.text;
    if (!title.length) title = SCITextInView(cell.contentView);
    if (!title.length) title = cell.accessibilityLabel;
    return [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL SCIIsDogfoodAssistantTitle(NSString *title) {
    return title.length &&
        [title caseInsensitiveCompare:@"Dogfooding Assistant"] == NSOrderedSame;
}

static void SCIApplyDogfoodAssistantSafety(id controller, BOOL reload) {
    if (!controller || SCIDogfoodAssistantPayloadAvailable()) return;
    BOOL changed = SCIWriteBoolIvar(controller, "showDogfoodingAssistant", NO);
    if (reload && changed) {
        UITableView *table = SCIBugMenuTableView(controller);
        [table reloadData];
        [table setNeedsLayout];
    }
}

static void (*orig_SafeBugMenuViewDidLoad)(id, SEL) = NULL;
static void (*orig_SafeBugMenuViewDidAppear)(id, SEL, BOOL) = NULL;
static void (*orig_SafeBugMenuDidSelect)(id, SEL, UITableView *, NSIndexPath *) = NULL;

static void SCI_SafeBugMenuViewDidLoad(id self, SEL _cmd) {
    if (orig_SafeBugMenuViewDidLoad) orig_SafeBugMenuViewDidLoad(self, _cmd);
    SCIApplyDogfoodAssistantSafety(self, YES);
}

static void SCI_SafeBugMenuViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_SafeBugMenuViewDidAppear) {
        orig_SafeBugMenuViewDidAppear(self, _cmd, animated);
    }
    SCIApplyDogfoodAssistantSafety(self, YES);
}

static void SCI_SafeBugMenuDidSelect(id self, SEL _cmd,
                                     UITableView *tableView,
                                     NSIndexPath *indexPath) {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *title = SCIBugMenuCellTitle(cell);
    if (SCIIsDogfoodAssistantTitle(title) &&
        !SCIDogfoodAssistantPayloadAvailable()) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [SCIDogfoodObjectRuntime noteAction:@"Dogfooding Assistant"
            status:@"blocked: XPlugins socket provider is empty"
            detail:@"hash=0x7FBC8058; unavailable initializer was not called"];
        return;
    }
    if (orig_SafeBugMenuDidSelect) {
        orig_SafeBugMenuDidSelect(self, _cmd, tableView, indexPath);
    }
}

static void SCIInstallBugMenuPayloadSafety(void) {
    static BOOL installed = NO;
    if (installed || !SCIInternalMenuOn()) return;

    // Make the existing availability/status hook authoritative first, then wrap
    // it with payload safety so this replacement remains the outermost hook.
    SCIInstallEmployeeInternalHooksIfNeeded();

    Class cls = objc_getClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
    if (!cls) cls = objc_getClass("IGBugReportMenuViewController");
    if (!cls) return;

    Method loadMethod = class_getInstanceMethod(cls, @selector(viewDidLoad));
    if (!orig_SafeBugMenuViewDidLoad && loadMethod) {
        MSHookMessageEx(cls, @selector(viewDidLoad),
                        (IMP)SCI_SafeBugMenuViewDidLoad,
                        (IMP *)&orig_SafeBugMenuViewDidLoad);
    }

    Method appearMethod = class_getInstanceMethod(cls, @selector(viewDidAppear:));
    if (!orig_SafeBugMenuViewDidAppear && appearMethod) {
        MSHookMessageEx(cls, @selector(viewDidAppear:),
                        (IMP)SCI_SafeBugMenuViewDidAppear,
                        (IMP *)&orig_SafeBugMenuViewDidAppear);
    }

    SEL select = @selector(tableView:didSelectRowAtIndexPath:);
    Method selectMethod = class_getInstanceMethod(cls, select);
    if (!orig_SafeBugMenuDidSelect && selectMethod) {
        MSHookMessageEx(cls, select, (IMP)SCI_SafeBugMenuDidSelect,
                        (IMP *)&orig_SafeBugMenuDidSelect);
    }

    installed = orig_SafeBugMenuViewDidLoad || orig_SafeBugMenuViewDidAppear ||
                orig_SafeBugMenuDidSelect;
}

static BOOL (*orig_TryOpenNativeDogfoodSettings)(id, SEL) = NULL;

static BOOL SCI_TryOpenNativeDogfoodSettings(id self, SEL _cmd) {
    if (!SCIDogfoodAssistantPayloadAvailable()) {
        [self noteAction:@"Open Native Dogfood Settings"
                  status:@"blocked: XPlugins socket provider is empty"
                  detail:@"hash=0x7FBC8058; no sentinel bridge and no unavailable initializer"];
        return NO;
    }

    UIViewController *top = [self topViewController];
    id session = [self activeUserSession];
    id config = [self bestDogfoodSettingsConfig];
    if (!top || !session || !config) {
        [self noteAction:@"Open Native Dogfood Settings"
                  status:@"missing native top/session/config"
                  detail:[self dogfoodNativeState]];
        return NO;
    }

    Class launcher = NSClassFromString(@"IGDogfoodingSettings.IGDogfoodingSettings");
    if (!launcher) launcher = NSClassFromString(@"_TtC20IGDogfoodingSettings20IGDogfoodingSettings");
    SEL selector = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    Method method = launcher ? class_getClassMethod(launcher, selector) : NULL;
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !encoding || strcmp(encoding, "v40@0:8@16@24@32") != 0) {
        [self noteAction:@"Open Native Dogfood Settings"
                  status:@"factory unavailable or ABI changed"
                  detail:encoding ? [NSString stringWithUTF8String:encoding] : @"missing"];
        return NO;
    }

    @try {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(
            launcher, selector, config, top, session);
        [self noteAction:@"Open Native Dogfood Settings"
                  status:@"sent through validated factory"
                  detail:[self dogfoodNativeState]];
        return YES;
    } @catch (id exception) {
        [self noteAction:@"Open Native Dogfood Settings"
                  status:@"factory exception"
                  detail:exception];
        return NO;
    }
}

static NSString *(*orig_OpenDogfoodingSettingsVC)(id, SEL) = NULL;
static void (*orig_OpenInstagramDebugMenu)(id, SEL, id) = NULL;

static NSString *SCI_OpenDogfoodingSettingsVC(id self, SEL _cmd) {
    BOOL opened = [SCIDogfoodObjectRuntime tryOpenNativeDogfoodSettings];
    return opened
        ? @"opened native Dogfooding Settings through validated factory"
        : @"blocked: native Dogfooding Assistant provider/config unavailable";
}

static void SCI_OpenInstagramDebugMenu(id self, SEL _cmd, id completion) {
    // Retry late-loaded FBShared/Bug Reporter classes immediately before the
    // native entry point. Every installer is idempotent and ABI-validated.
    SCIInstallInternalGlobalSafeHooksIfNeeded();
    if (orig_OpenInstagramDebugMenu) {
        orig_OpenInstagramDebugMenu(self, _cmd, completion);
    }
}

static void SCIInstallSafeDogfoodOpeners(void) {
    static BOOL installed = NO;
    if (installed) return;

    Class runtime = objc_getClass("SCIDogfoodObjectRuntime");
    Class runtimeMeta = runtime ? object_getClass(runtime) : Nil;
    SEL tryOpen = @selector(tryOpenNativeDogfoodSettings);
    Method tryOpenMethod = runtimeMeta ? class_getInstanceMethod(runtimeMeta, tryOpen) : NULL;
    if (!orig_TryOpenNativeDogfoodSettings &&
        SCIIsBoolMethodWithArgumentCount(tryOpenMethod, 2)) {
        MSHookMessageEx(runtimeMeta, tryOpen,
                        (IMP)SCI_TryOpenNativeDogfoodSettings,
                        (IMP *)&orig_TryOpenNativeDogfoodSettings);
    }

    Class menus = objc_getClass("SCIInternalMenusLauncher");
    Class menusMeta = menus ? object_getClass(menus) : Nil;
    SEL openSettings = NSSelectorFromString(@"openDogfoodingSettingsVC");
    Method openMethod = menusMeta ? class_getInstanceMethod(menusMeta, openSettings) : NULL;
    if (!orig_OpenDogfoodingSettingsVC && openMethod &&
        method_getNumberOfArguments(openMethod) == 2) {
        MSHookMessageEx(menusMeta, openSettings,
                        (IMP)SCI_OpenDogfoodingSettingsVC,
                        (IMP *)&orig_OpenDogfoodingSettingsVC);
    }

    SEL openDebug = NSSelectorFromString(@"openInstagramDebugMenuWithCompletion:");
    Method debugMethod = menusMeta ? class_getInstanceMethod(menusMeta, openDebug) : NULL;
    if (!orig_OpenInstagramDebugMenu && debugMethod &&
        method_getNumberOfArguments(debugMethod) == 3) {
        MSHookMessageEx(menusMeta, openDebug,
                        (IMP)SCI_OpenInstagramDebugMenu,
                        (IMP *)&orig_OpenInstagramDebugMenu);
    }

    installed = orig_TryOpenNativeDogfoodSettings ||
                orig_OpenDogfoodingSettingsVC || orig_OpenInstagramDebugMenu;
}

static void SCIInstallInternalGlobalSafeHooksIfNeeded(void) {
    if (!SCIInternalMenuOn() && !SCIEmployeeInternalMasterOn()) return;
    SCIInstallEmployeeInternalHooksIfNeeded();
    SCIInstallMobileConfigEmployeeHooks();
    SCIInstallBugMenuPayloadSafety();
    SCIInstallSafeDogfoodOpeners();
}

%ctor {
    @autoreleasepool {
        // One deferred pass runs after tweak constructors, ensuring the existing
        // Bug Reporter hook is installed before the payload-safety wrapper.
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIInstallInternalGlobalSafeHooksIfNeeded();
        });
    }
}
