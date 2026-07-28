#import "SCIInternalGatePrefs.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>
#import <substrate.h>

#define IGILOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] InternalGlobal " fmt, ##__VA_ARGS__)

typedef struct {
    uint64_t rawValue;
} SCIMCBoolParam;

typedef struct {
    const void *data;
    uintptr_t count;
} SCIXPluginProviderResult;

typedef SCIXPluginProviderResult (*SCIXPluginProvider)(void);
typedef SCIXPluginProvider (*SCIXPluginResolver)(uint32_t hash);

static const uint64_t kSCIEmployeeOrTestUserParam = 0x008100A700000134ULL;
static const uint64_t kSCIDogfoodingAssistantParam = 0x00810A8A000139D6ULL;
static const uint32_t kSCIInternalOnlyPluginHash = 0x64327C01U;
static const uint32_t kSCIDogfoodAssistantSocketPluginHash = 0x7FBC8058U;

static BOOL SCIInternalGlobalEnabled(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static NSObject *SCIInternalGlobalInstallLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static SCIXPluginResolver SCIResolveXPluginResolver(void) {
    static SCIXPluginResolver resolver;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        resolver = (SCIXPluginResolver)dlsym(RTLD_DEFAULT, "XPluginsGetDataFuncOrAbort");
        if (!resolver) {
            resolver = (SCIXPluginResolver)dlsym(RTLD_DEFAULT, "_XPluginsGetDataFuncOrAbort");
        }
    });
    return resolver;
}

// Query the native provider using its real two-register return ABI. This is only
// an availability probe; it never replaces a provider and never invents a
// sentinel pointer. A provider is usable only when both data and count are real.
static BOOL SCIHasNativeXPluginPayload(uint32_t hash) {
    SCIXPluginResolver resolver = SCIResolveXPluginResolver();
    if (!resolver) return NO;

    SCIXPluginProvider provider = resolver(hash);
    if (!provider) return NO;

    SCIXPluginProviderResult result = provider();
    return result.data != NULL && result.count != 0;
}

static BOOL SCIHasNativeDogfoodAssistantSocket(void) {
    static BOOL available;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        available = SCIHasNativeXPluginPayload(kSCIDogfoodAssistantSocketPluginHash);
        IGILOG("native Dogfood Assistant socket payload=%d hash=0x%08x",
               available, kSCIDogfoodAssistantSocketPluginHash);
    });
    return available;
}

static BOOL SCIShouldForceBoolParam(SCIMCBoolParam param) {
    if (!SCIInternalGlobalEnabled()) return NO;
    if (param.rawValue == kSCIEmployeeOrTestUserParam) return YES;

    // The visibility flag is only safe when the corresponding native socket
    // plugin actually ships a payload. Instagram(16) maps 0x7FBC8058 to the
    // empty provider, so the Assistant row remains hidden in that build.
    if (param.rawValue == kSCIDogfoodingAssistantParam) {
        return SCIHasNativeDogfoodAssistantSocket();
    }
    return NO;
}

static BOOL (*orig_MCGetBool)(id, SEL, SCIMCBoolParam) = NULL;
static BOOL (*orig_MCGetBoolDefault)(id, SEL, SCIMCBoolParam, BOOL) = NULL;
static BOOL (*orig_MCGetBoolOptions)(id, SEL, SCIMCBoolParam, id) = NULL;
static BOOL (*orig_MCGetBoolOptionsDefault)(id, SEL, SCIMCBoolParam, id, BOOL) = NULL;
static BOOL (*orig_MCGetBoolWithoutLogging)(id, SEL, SCIMCBoolParam) = NULL;
static BOOL (*orig_MCGetBoolWithoutLoggingDefault)(id, SEL, SCIMCBoolParam, BOOL) = NULL;

static BOOL SCI_MCGetBool(id self, SEL _cmd, SCIMCBoolParam param) {
    if (SCIShouldForceBoolParam(param)) return YES;
    return orig_MCGetBool ? orig_MCGetBool(self, _cmd, param) : NO;
}

static BOOL SCI_MCGetBoolDefault(id self, SEL _cmd, SCIMCBoolParam param, BOOL defaultValue) {
    if (SCIShouldForceBoolParam(param)) return YES;
    return orig_MCGetBoolDefault
        ? orig_MCGetBoolDefault(self, _cmd, param, defaultValue)
        : defaultValue;
}

static BOOL SCI_MCGetBoolOptions(id self, SEL _cmd, SCIMCBoolParam param, id options) {
    if (SCIShouldForceBoolParam(param)) return YES;
    return orig_MCGetBoolOptions
        ? orig_MCGetBoolOptions(self, _cmd, param, options)
        : NO;
}

static BOOL SCI_MCGetBoolOptionsDefault(id self, SEL _cmd, SCIMCBoolParam param,
                                         id options, BOOL defaultValue) {
    if (SCIShouldForceBoolParam(param)) return YES;
    return orig_MCGetBoolOptionsDefault
        ? orig_MCGetBoolOptionsDefault(self, _cmd, param, options, defaultValue)
        : defaultValue;
}

static BOOL SCI_MCGetBoolWithoutLogging(id self, SEL _cmd, SCIMCBoolParam param) {
    if (SCIShouldForceBoolParam(param)) return YES;
    return orig_MCGetBoolWithoutLogging
        ? orig_MCGetBoolWithoutLogging(self, _cmd, param)
        : NO;
}

static BOOL SCI_MCGetBoolWithoutLoggingDefault(id self, SEL _cmd,
                                                SCIMCBoolParam param,
                                                BOOL defaultValue) {
    if (SCIShouldForceBoolParam(param)) return YES;
    return orig_MCGetBoolWithoutLoggingDefault
        ? orig_MCGetBoolWithoutLoggingDefault(self, _cmd, param, defaultValue)
        : defaultValue;
}

static BOOL SCIHookInstanceMethod(Class cls, NSString *selectorName,
                                  const char *expectedEncoding,
                                  IMP replacement, IMP *original) {
    if (!cls || !selectorName.length || !expectedEncoding || !replacement || !original) return NO;
    if (*original) return YES;

    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !encoding || strcmp(encoding, expectedEncoding) != 0) {
        if (method) {
            IGILOG("skip %{public}@.%{public}@ ABI=%{public}s expected=%{public}s",
                   NSStringFromClass(cls), selectorName, encoding ?: "(null)", expectedEncoding);
        }
        return NO;
    }

    MSHookMessageEx(cls, selector, replacement, original);
    return *original != NULL;
}

static BOOL SCIInstallMobileConfigHooks(void) {
    Class cls = objc_getClass("FBMobileConfigContextManager");
    if (!cls) return NO;

    BOOL getBool = SCIHookInstanceMethod(
        cls, @"getBool:", "B24@0:8{mc_bool_param_t=Q}16",
        (IMP)SCI_MCGetBool, (IMP *)&orig_MCGetBool);
    BOOL getBoolDefault = SCIHookInstanceMethod(
        cls, @"getBool:withDefault:", "B28@0:8{mc_bool_param_t=Q}16B24",
        (IMP)SCI_MCGetBoolDefault, (IMP *)&orig_MCGetBoolDefault);
    BOOL getBoolOptions = SCIHookInstanceMethod(
        cls, @"getBool:withOptions:", "B32@0:8{mc_bool_param_t=Q}16@24",
        (IMP)SCI_MCGetBoolOptions, (IMP *)&orig_MCGetBoolOptions);
    BOOL getBoolOptionsDefault = SCIHookInstanceMethod(
        cls, @"getBool:withOptions:withDefault:",
        "B36@0:8{mc_bool_param_t=Q}16@24B32",
        (IMP)SCI_MCGetBoolOptionsDefault, (IMP *)&orig_MCGetBoolOptionsDefault);
    BOOL withoutLogging = SCIHookInstanceMethod(
        cls, @"getBoolWithoutLogging:", "B24@0:8{mc_bool_param_t=Q}16",
        (IMP)SCI_MCGetBoolWithoutLogging, (IMP *)&orig_MCGetBoolWithoutLogging);
    BOOL withoutLoggingDefault = SCIHookInstanceMethod(
        cls, @"getBoolWithoutLogging:withDefault:",
        "B28@0:8{mc_bool_param_t=Q}16B24",
        (IMP)SCI_MCGetBoolWithoutLoggingDefault,
        (IMP *)&orig_MCGetBoolWithoutLoggingDefault);

    return getBool && getBoolDefault && getBoolOptions && getBoolOptionsDefault &&
           withoutLogging && withoutLoggingDefault;
}

static NSString *(*orig_OpenDogfoodingSettingsVC)(id, SEL) = NULL;

static NSString *SCI_OpenDogfoodingSettingsVC(id self __unused, SEL _cmd __unused) {
    // IGS DogfoodingSettingsConfig -init is an unavailable Swift thunk in this
    // build and terminates with brk #1. Objective-C exception handling cannot
    // catch that trap. Keep the safe Notes entrypoint and native Debug Menu, but
    // never call the incomplete settings factory without its XPlugins payload.
    return @"Native Dogfooding Settings is unavailable in this Instagram build: IGS DogfoodingSettingsConfig.init traps with brk #1 and the 0x7FBC8058 socket provider is empty. Use Internal Settings or Notes Dogfooding instead.";
}

static BOOL SCIInstallUnsafeDogfoodingLauncherGuard(void) {
    Class cls = objc_getClass("SCIInternalMenusLauncher");
    if (!cls) return NO;
    Class meta = object_getClass(cls);
    return SCIHookInstanceMethod(
        meta, @"openDogfoodingSettingsVC", "@16@0:8",
        (IMP)SCI_OpenDogfoodingSettingsVC,
        (IMP *)&orig_OpenDogfoodingSettingsVC
    );
}

typedef id (*SCIBugReportMenuInitializer)(
    id, SEL, id, id, id, id, id,
    NSInteger, NSInteger, NSInteger,
    BOOL, BOOL, BOOL, BOOL,
    NSInteger
);

static SCIBugReportMenuInitializer orig_BugReportMenuInitializer = NULL;

static id SCI_BugReportMenuInitializer(
    id self, SEL _cmd,
    id deviceSession,
    id userSession,
    id reliabilityLogging,
    id navChain,
    id endpoint,
    NSInteger entryPoint,
    NSInteger style,
    NSInteger availabilityStatus,
    BOOL showInternalSettings,
    BOOL showLoggedOutInternalSettings,
    BOOL showShakeToReportPreferenceToggle,
    BOOL showDogfoodingAssistant,
    NSInteger maisaUXVariantRawValue
) {
    if (SCIInternalGlobalEnabled()) {
        availabilityStatus = 0;
        showInternalSettings = YES;

        // Do not expose a row whose socket plugin is absent. If a later build
        // ships a genuine 0x7FBC8058 payload, the native row is enabled again.
        showDogfoodingAssistant = SCIHasNativeDogfoodAssistantSocket();
    }

    return orig_BugReportMenuInitializer
        ? orig_BugReportMenuInitializer(
            self, _cmd,
            deviceSession, userSession, reliabilityLogging, navChain, endpoint,
            entryPoint, style, availabilityStatus,
            showInternalSettings, showLoggedOutInternalSettings,
            showShakeToReportPreferenceToggle, showDogfoodingAssistant,
            maisaUXVariantRawValue)
        : nil;
}

static BOOL SCIInstallBugReportMenuHook(void) {
    Class cls = objc_getClass(
        "_TtC17IGBugReporterMenu29IGBugReportMenuViewController"
    );
    if (!cls) return NO;

    NSString *selectorName = @"initWithDeviceSession:userSession:reliabilityLogging:navChain:endpoint:entryPoint:style:internalSettingsAvailabilityStatus:showInternalSettings:showLoggedOutInternalSettings:showShakeToReportPreferenceToggle:showDogfoodingAssistant:maisaUXVariantRawValue:";
    const char *encoding = "@104@0:8@16@24@32@40@48q56q64q72B80B84B88B92q96";
    return SCIHookInstanceMethod(
        cls, selectorName, encoding,
        (IMP)SCI_BugReportMenuInitializer,
        (IMP *)&orig_BugReportMenuInitializer
    );
}

BOOL SCIInstallInternalGlobalHooksIfNeeded(void) {
    @synchronized (SCIInternalGlobalInstallLock()) {
        BOOL launcherGuardReady = SCIInstallUnsafeDogfoodingLauncherGuard();
        if (!SCIInternalGlobalEnabled()) return launcherGuardReady;

        BOOL mcReady = SCIInstallMobileConfigHooks();
        BOOL menuReady = SCIInstallBugReportMenuHook();

        static dispatch_once_t logOnce;
        dispatch_once(&logOnce, ^{
            BOOL internalPayload = SCIHasNativeXPluginPayload(kSCIInternalOnlyPluginHash);
            BOOL assistantPayload = SCIHasNativeDogfoodAssistantSocket();
            IGILOG("native payloads internal_only=%d(0x%08x) assistant_socket=%d(0x%08x)",
                   internalPayload, kSCIInternalOnlyPluginHash,
                   assistantPayload, kSCIDogfoodAssistantSocketPluginHash);
        });

        IGILOG("install pass mc=%d menu=%d launcherGuard=%d",
               mcReady, menuReady, launcherGuardReady);
        return mcReady && menuReady && launcherGuardReady;
    }
}

__attribute__((constructor))
static void SCIInternalGlobalHooksCtor(void) {
    @autoreleasepool {
        // Only targeted class/selector lookups. Late Instagram frameworks are
        // retried by the existing coalesced Dogfood dyld callback.
        SCIInstallInternalGlobalHooksIfNeeded();
    }
}
