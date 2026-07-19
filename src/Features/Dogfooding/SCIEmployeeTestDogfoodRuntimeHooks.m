#import "SCIInternalGatePrefs.h"
#import "../Gating/SCICSymbolStub.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>

#define ETDLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] EmployeeTestDogfood " fmt, ##__VA_ARGS__)

// This module no longer scans every loaded Objective-C class. The previous
// post-launch alias scan installed arbitrary isTestUser/isDogfooder-style hooks
// roughly five seconds after activation and is the only staged work matching the
// observed delayed crash window. Identity MobileConfig is now forced at the
// shared typed readers instead, so every real consumer sees the same value.

static BOOL ETDMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

#pragma mark - Remove legacy owner-managed C-stub state

static NSString *const kETDOwnerKey =
    @"sci_employee_test_dogfood_descriptor_owner";
static NSString *const kETDPreviousKey =
    @"sci_employee_test_dogfood_descriptor_previous";

static NSArray<NSString *> *ETDLegacyDescriptors(void) {
    return @[@"ig_is_employee", @"ig_is_employee_or_test_user"];
}

static void ETDRestoreLegacyDescriptorState(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if (![defaults boolForKey:kETDOwnerKey]) return;

        NSDictionary *previous = [defaults dictionaryForKey:kETDPreviousKey];
        for (NSString *symbol in ETDLegacyDescriptors()) {
            id saved = previous[symbol];
            NSNumber *restore = [saved isKindOfClass:NSNumber.class]
                ? (NSNumber *)saved
                : nil;
            [SCICSymbolStub setParamDescriptorForce:restore forSymbol:symbol];
        }
        [defaults removeObjectForKey:kETDPreviousKey];
        [defaults removeObjectForKey:kETDOwnerKey];
        ETDLOG("removed legacy descriptor-force ownership");
    });
}

#pragma mark - Missing exact MobileConfig reader variants

typedef uint64_t ETDBoolParam;

typedef struct {
    const char *symbol;
    uint8_t offsets[8];
    uint8_t offsetCount;
} ETDDescriptorSpec;

// Symbol extents and BOOL fields revalidated in FBSharedFramework:
//   ig_is_employee                 size 0x10 -> +0x00, +0x08
//   ig_is_employee_or_test_user    size 0x08 -> +0x00
//   ig_dogfooding_assistant        size 0x10 -> BOOL at +0x08
//   ig_dogfooding_first_client     size 0x40 -> BOOL fields below
//   xav_switcher...check_fdid       size 0x08 -> +0x00
static const ETDDescriptorSpec kETDDescriptorSpecs[] = {
    { "ig_is_employee", { 0x00, 0x08 }, 2 },
    { "ig_is_employee_or_test_user", { 0x00 }, 1 },
    { "ig_dogfooding_assistant", { 0x08 }, 1 },
    { "ig_dogfooding_first_client",
      { 0x00, 0x08, 0x10, 0x28, 0x30, 0x38 }, 6 },
    { "xav_switcher_ig_ios_test_user_check_fdid", { 0x00 }, 1 },
};

static ETDBoolParam sETDForcedParams[16];
static size_t sETDForcedParamCount;

static void *ETDResolveDataSymbol(const char *name) {
    if (!name || !name[0]) return NULL;
    void *address = dlsym(RTLD_DEFAULT, name);
    if (address) return address;

    char underscored[256] = {0};
    size_t length = strlen(name);
    if (length + 2 > sizeof(underscored)) return NULL;
    underscored[0] = '_';
    memcpy(underscored + 1, name, length + 1);
    return dlsym(RTLD_DEFAULT, underscored);
}

static void ETDResolveForcedParams(void) {
    sETDForcedParamCount = 0;
    for (size_t i = 0;
         i < sizeof(kETDDescriptorSpecs) / sizeof(kETDDescriptorSpecs[0]);
         i++) {
        const ETDDescriptorSpec *spec = &kETDDescriptorSpecs[i];
        const uint8_t *descriptor = ETDResolveDataSymbol(spec->symbol);
        if (!descriptor) continue;

        for (uint8_t j = 0; j < spec->offsetCount; j++) {
            ETDBoolParam parameter = 0;
            memcpy(&parameter, descriptor + spec->offsets[j], sizeof(parameter));
            if (!parameter) continue;

            BOOL duplicate = NO;
            for (size_t k = 0; k < sETDForcedParamCount; k++) {
                if (sETDForcedParams[k] == parameter) {
                    duplicate = YES;
                    break;
                }
            }
            if (!duplicate &&
                sETDForcedParamCount <
                    sizeof(sETDForcedParams) / sizeof(sETDForcedParams[0])) {
                sETDForcedParams[sETDForcedParamCount++] = parameter;
            }
        }
    }
}

static BOOL ETDForceParameter(ETDBoolParam parameter) {
    if (!ETDMasterOn()) return NO;
    for (size_t i = 0; i < sETDForcedParamCount; i++) {
        if (sETDForcedParams[i] == parameter) return YES;
    }
    return NO;
}

static NSMutableDictionary<NSString *, NSValue *> *sETDOptionsDefaultOriginals;
static NSMutableDictionary<NSString *, NSValue *> *sETDWithoutLoggingOriginals;
static NSMutableDictionary<NSString *, NSValue *> *sETDWithoutLoggingDefaultOriginals;

static NSString *ETDMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%p#%s", cls,
            selector ? sel_getName(selector) : "<nil>"];
}

static IMP ETDOriginalForObject(id object, SEL selector,
                                NSMutableDictionary<NSString *, NSValue *> *store) {
    if (!object || !selector || !store) return NULL;
    @synchronized (store) {
        for (Class cls = object_getClass(object); cls;
             cls = class_getSuperclass(cls)) {
            NSValue *value = store[ETDMethodKey(cls, selector)];
            if (value) return value.pointerValue;
        }
    }
    return NULL;
}

static BOOL ETDGetBoolOptionsDefault(id self, SEL _cmd,
                                     ETDBoolParam parameter,
                                     id options, BOOL defaultValue) {
    IMP original = ETDOriginalForObject(
        self, _cmd, sETDOptionsDefaultOriginals);
    BOOL nativeValue = original
        ? ((BOOL (*)(id, SEL, ETDBoolParam, id, BOOL))original)(
            self, _cmd, parameter, options, defaultValue)
        : defaultValue;
    return ETDForceParameter(parameter) ? YES : nativeValue;
}

static BOOL ETDGetBoolWithoutLogging(id self, SEL _cmd,
                                     ETDBoolParam parameter) {
    IMP original = ETDOriginalForObject(
        self, _cmd, sETDWithoutLoggingOriginals);
    BOOL nativeValue = original
        ? ((BOOL (*)(id, SEL, ETDBoolParam))original)(
            self, _cmd, parameter)
        : NO;
    return ETDForceParameter(parameter) ? YES : nativeValue;
}

static BOOL ETDGetBoolWithoutLoggingDefault(id self, SEL _cmd,
                                            ETDBoolParam parameter,
                                            BOOL defaultValue) {
    IMP original = ETDOriginalForObject(
        self, _cmd, sETDWithoutLoggingDefaultOriginals);
    BOOL nativeValue = original
        ? ((BOOL (*)(id, SEL, ETDBoolParam, BOOL))original)(
            self, _cmd, parameter, defaultValue)
        : defaultValue;
    return ETDForceParameter(parameter) ? YES : nativeValue;
}

static Method ETDDeclaredMethod(Class cls, SEL selector) {
    if (!cls || !selector) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method result = NULL;
    for (unsigned int i = 0; methods && i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            result = methods[i];
            break;
        }
    }
    if (methods) free(methods);
    return result;
}

static BOOL ETDEncodingMatchesAny(const char *encoding,
                                  NSArray<NSString *> *expected) {
    if (!encoding) return NO;
    for (NSString *value in expected) {
        if (strcmp(encoding, value.UTF8String) == 0) return YES;
    }
    return NO;
}

static void ETDHookExact(Class cls, NSString *selectorName,
                         NSArray<NSString *> *encodings,
                         IMP replacement,
                         NSMutableDictionary<NSString *, NSValue *> *store) {
    if (!cls || !selectorName.length || !replacement || !store) return;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = ETDDeclaredMethod(cls, selector);
    if (!method ||
        !ETDEncodingMatchesAny(method_getTypeEncoding(method), encodings)) {
        return;
    }

    NSString *key = ETDMethodKey(cls, selector);
    @synchronized (store) {
        if (store[key]) return;
    }

    IMP original = NULL;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (!original) return;
    @synchronized (store) {
        store[key] = [NSValue valueWithPointer:original];
    }
    ETDLOG("exact reader %{public}s.%{public}s ABI=%{public}s",
           class_getName(cls), sel_getName(selector),
           method_getTypeEncoding(method));
}

static void ETDInstallMissingReaderVariants(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ETDResolveForcedParams();
        sETDOptionsDefaultOriginals = [NSMutableDictionary dictionary];
        sETDWithoutLoggingOriginals = [NSMutableDictionary dictionary];
        sETDWithoutLoggingDefaultOriginals = [NSMutableDictionary dictionary];

        NSArray<NSString *> *optionsDefaultABIs = @[
            @"B36@0:8{mc_bool_param_t=Q}16@24B32",
            @"B36@0:8{mc_bool_param_t=Q}16^{?}24B32"
        ];
        NSArray<NSString *> *baseABIs = @[
            @"B24@0:8{mc_bool_param_t=Q}16"
        ];
        NSArray<NSString *> *defaultABIs = @[
            @"B28@0:8{mc_bool_param_t=Q}16B24"
        ];

        for (NSString *className in @[
            @"FBMobileConfigStartupConfigs",
            @"FBMobileConfigEmptyImpl",
            @"FBMobileConfigContextObjcImpl",
            @"IGMobileConfigContextManager",
            @"FBMobileConfigContextManager"
        ]) {
            Class cls = NSClassFromString(className);
            ETDHookExact(cls, @"getBool:withOptions:withDefault:",
                         optionsDefaultABIs,
                         (IMP)ETDGetBoolOptionsDefault,
                         sETDOptionsDefaultOriginals);
        }

        Class fbContext = NSClassFromString(@"FBMobileConfigContextManager");
        ETDHookExact(fbContext, @"getBoolWithoutLogging:",
                     baseABIs, (IMP)ETDGetBoolWithoutLogging,
                     sETDWithoutLoggingOriginals);
        ETDHookExact(fbContext, @"getBoolWithoutLogging:withDefault:",
                     defaultABIs, (IMP)ETDGetBoolWithoutLoggingDefault,
                     sETDWithoutLoggingDefaultOriginals);

        ETDLOG("bounded exact pass params=%lu optionsDefault=%lu noLog=%lu noLogDefault=%lu",
               (unsigned long)sETDForcedParamCount,
               (unsigned long)sETDOptionsDefaultOriginals.count,
               (unsigned long)sETDWithoutLoggingOriginals.count,
               (unsigned long)sETDWithoutLoggingDefaultOriginals.count);
    });
}

void SCIInstallEmployeeTestDogfoodRuntimeHooks(void) {
    // Called by the centralized post-activation bootstrap. No delayed class-list
    // scan, no NSUserDefaults observer and no arbitrary identity alias hooks.
    ETDRestoreLegacyDescriptorState();
    ETDInstallMissingReaderVariants();
}
