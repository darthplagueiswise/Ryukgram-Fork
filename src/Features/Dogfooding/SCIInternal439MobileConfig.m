// SCIInternal439MobileConfig.m
// Targeted, sideload-safe MobileConfig overrides for Instagram(16).
//
// Revalidated binaries:
//   Instagram         fa19f499c560b188d2802e3a1a36642209ee6e42d7639c1ebe010f14b2c4cd9b
//   FBSharedFramework a79c110c59e7c16e5608227e12807583c1afcf80cb2a2e38302f147dbf99c12b
//
// This module deliberately does NOT touch XPlugins providers 0x64327C01 or
// 0x253F21CF. They return (data, count), not BOOL, and both are compiled as
// null providers in this build. A sentinel pointer would be dereferenced by
// native callers and is therefore invalid.

#import "SCIInternalGatePrefs.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>

#define SCI439LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IG439MC " fmt, ##__VA_ARGS__)

typedef struct {
    uint64_t rawValue;
} SCI439MCBoolParam;

static const uint64_t kSCI439EmployeeOrTestUser = 0x008100A700000134ULL;
static const uint64_t kSCI439DogfoodingAssistant = 0x00810A8A000139D6ULL;

static BOOL SCI439InternalModeEnabled(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled] ||
           [SCIInternalGatePrefs boolForKey:@"sci_force_internal_settings_menu"] ||
           [SCIInternalGatePrefs boolForKey:@"sci_force_internal_settings_availability"];
}

static BOOL SCI439ShouldForceBool(SCI439MCBoolParam param) {
    if (!SCI439InternalModeEnabled()) return NO;
    return param.rawValue == kSCI439EmployeeOrTestUser ||
           param.rawValue == kSCI439DogfoodingAssistant;
}

static BOOL SCI439IsBoolType(const char *type) {
    return type && (type[0] == 'B' || type[0] == 'c');
}

static BOOL SCI439IsObjectType(const char *type) {
    return type && type[0] == '@';
}

static BOOL SCI439IsBoolParamType(const char *type) {
    if (!type) return NO;
    if (strcmp(type, "Q") == 0 || strcmp(type, "q") == 0) return YES;
    return type[0] == '{' && strstr(type, "=Q") != NULL;
}

static BOOL SCI439MethodMatches(Method method,
                                unsigned int argumentCount,
                                BOOL optionsArgument,
                                BOOL defaultArgument) {
    if (!method || method_getNumberOfArguments(method) != argumentCount) return NO;

    char returnType[64] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (!SCI439IsBoolType(returnType)) return NO;

    char paramType[128] = {0};
    method_getArgumentType(method, 2, paramType, sizeof(paramType));
    if (!SCI439IsBoolParamType(paramType)) return NO;

    unsigned int next = 3;
    if (optionsArgument) {
        char optionsType[64] = {0};
        method_getArgumentType(method, next++, optionsType, sizeof(optionsType));
        if (!SCI439IsObjectType(optionsType)) return NO;
    }
    if (defaultArgument) {
        char defaultType[64] = {0};
        method_getArgumentType(method, next, defaultType, sizeof(defaultType));
        if (!SCI439IsBoolType(defaultType)) return NO;
    }
    return YES;
}

typedef BOOL (*SCI439MCOneIMP)(id, SEL, SCI439MCBoolParam);
typedef BOOL (*SCI439MCDefaultIMP)(id, SEL, SCI439MCBoolParam, BOOL);
typedef BOOL (*SCI439MCOptionsIMP)(id, SEL, SCI439MCBoolParam, id);
typedef BOOL (*SCI439MCOptionsDefaultIMP)(id, SEL, SCI439MCBoolParam, id, BOOL);

static SCI439MCOneIMP orig_SCI439GetBool = NULL;
static SCI439MCDefaultIMP orig_SCI439GetBoolDefault = NULL;
static SCI439MCOptionsIMP orig_SCI439GetBoolOptions = NULL;
static SCI439MCOptionsDefaultIMP orig_SCI439GetBoolOptionsDefault = NULL;
static SCI439MCOneIMP orig_SCI439GetBoolWithoutLogging = NULL;
static SCI439MCDefaultIMP orig_SCI439GetBoolWithoutLoggingDefault = NULL;
static SCI439MCDefaultIMP orig_SCI439GetBoolXStackDefault = NULL;

static BOOL SCI439GetBool(id self, SEL _cmd, SCI439MCBoolParam param) {
    if (SCI439ShouldForceBool(param)) return YES;
    return orig_SCI439GetBool ? orig_SCI439GetBool(self, _cmd, param) : NO;
}

static BOOL SCI439GetBoolDefault(id self, SEL _cmd,
                                 SCI439MCBoolParam param, BOOL defaultValue) {
    if (SCI439ShouldForceBool(param)) return YES;
    return orig_SCI439GetBoolDefault
        ? orig_SCI439GetBoolDefault(self, _cmd, param, defaultValue)
        : defaultValue;
}

static BOOL SCI439GetBoolOptions(id self, SEL _cmd,
                                 SCI439MCBoolParam param, id options) {
    if (SCI439ShouldForceBool(param)) return YES;
    return orig_SCI439GetBoolOptions
        ? orig_SCI439GetBoolOptions(self, _cmd, param, options)
        : NO;
}

static BOOL SCI439GetBoolOptionsDefault(id self, SEL _cmd,
                                        SCI439MCBoolParam param, id options,
                                        BOOL defaultValue) {
    if (SCI439ShouldForceBool(param)) return YES;
    return orig_SCI439GetBoolOptionsDefault
        ? orig_SCI439GetBoolOptionsDefault(self, _cmd, param, options, defaultValue)
        : defaultValue;
}

static BOOL SCI439GetBoolWithoutLogging(id self, SEL _cmd,
                                        SCI439MCBoolParam param) {
    if (SCI439ShouldForceBool(param)) return YES;
    return orig_SCI439GetBoolWithoutLogging
        ? orig_SCI439GetBoolWithoutLogging(self, _cmd, param)
        : NO;
}

static BOOL SCI439GetBoolWithoutLoggingDefault(id self, SEL _cmd,
                                               SCI439MCBoolParam param,
                                               BOOL defaultValue) {
    if (SCI439ShouldForceBool(param)) return YES;
    return orig_SCI439GetBoolWithoutLoggingDefault
        ? orig_SCI439GetBoolWithoutLoggingDefault(self, _cmd, param, defaultValue)
        : defaultValue;
}

static BOOL SCI439GetBoolXStackDefault(id self, SEL _cmd,
                                       SCI439MCBoolParam param,
                                       BOOL defaultValue) {
    if (SCI439ShouldForceBool(param)) return YES;
    return orig_SCI439GetBoolXStackDefault
        ? orig_SCI439GetBoolXStackDefault(self, _cmd, param, defaultValue)
        : defaultValue;
}

static BOOL SCI439InstallOne(Class cls, const char *selectorName,
                             IMP replacement, IMP *original,
                             unsigned int argumentCount,
                             BOOL optionsArgument,
                             BOOL defaultArgument) {
    SEL selector = sel_registerName(selectorName);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;

    if (!SCI439MethodMatches(method, argumentCount,
                             optionsArgument, defaultArgument)) {
        SCI439LOG("skip %{public}s ABI=%{public}s",
                  selectorName, method_getTypeEncoding(method) ?: "<nil>");
        return NO;
    }

    MSHookMessageEx(cls, selector, replacement, original);
    SCI439LOG("hooked %{public}s ABI=%{public}s",
              selectorName, method_getTypeEncoding(method));
    return original && *original != NULL;
}

void SCIInstallInternal439MobileConfigHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!SCI439InternalModeEnabled()) return;

        Class cls = objc_getClass("FBMobileConfigContextManager");
        if (!cls) {
            SCI439LOG("FBMobileConfigContextManager unavailable");
            return;
        }

        NSUInteger installed = 0;
        installed += SCI439InstallOne(cls, "getBool:",
            (IMP)SCI439GetBool, (IMP *)&orig_SCI439GetBool, 3, NO, NO);
        installed += SCI439InstallOne(cls, "getBool:withDefault:",
            (IMP)SCI439GetBoolDefault, (IMP *)&orig_SCI439GetBoolDefault,
            4, NO, YES);
        installed += SCI439InstallOne(cls, "getBool:withOptions:",
            (IMP)SCI439GetBoolOptions, (IMP *)&orig_SCI439GetBoolOptions,
            4, YES, NO);
        installed += SCI439InstallOne(cls, "getBool:withOptions:withDefault:",
            (IMP)SCI439GetBoolOptionsDefault,
            (IMP *)&orig_SCI439GetBoolOptionsDefault, 5, YES, YES);
        installed += SCI439InstallOne(cls, "getBoolWithoutLogging:",
            (IMP)SCI439GetBoolWithoutLogging,
            (IMP *)&orig_SCI439GetBoolWithoutLogging, 3, NO, NO);
        installed += SCI439InstallOne(cls, "getBoolWithoutLogging:withDefault:",
            (IMP)SCI439GetBoolWithoutLoggingDefault,
            (IMP *)&orig_SCI439GetBoolWithoutLoggingDefault, 4, NO, YES);
        installed += SCI439InstallOne(cls,
            "getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:",
            (IMP)SCI439GetBoolXStackDefault,
            (IMP *)&orig_SCI439GetBoolXStackDefault, 4, NO, YES);

        SCI439LOG("installed %lu targeted MobileConfig hooks",
                  (unsigned long)installed);
    });
}

__attribute__((constructor))
static void SCIInternal439MobileConfigInit(void) {
    @autoreleasepool {
        SCIInstallInternal439MobileConfigHooksIfNeeded();
    }
}
