#import "SCIInternalGatePrefs.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdatomic.h>
#import <stdint.h>
#import <string.h>

#define MCGLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] MCIdentityDescriptors " fmt, ##__VA_ARGS__)

// Exported MobileConfig descriptors are DATA objects.  Their uint64 parameter
// fields are compared at the typed Objective-C readers; descriptor bytes and
// individual ARM64 call sites are never patched.

typedef uint64_t SCIMCBoolParam;

typedef struct {
    const char *symbol;
    uint8_t offsets[8];
    uint8_t offsetCount;
} SCIMCDescriptorSpec;

typedef struct {
    Class cls;
    IMP original;
} SCIMCOriginalEntry;

static const SCIMCDescriptorSpec kSCIMCDescriptorSpecs[] = {
    { "ig_is_employee", { 0x00, 0x08 }, 2 },
    { "ig_is_employee_or_test_user", { 0x00 }, 1 },
    { "ig_dogfooding_assistant", { 0x08 }, 1 },
    { "ig_dogfooding_first_client",
      { 0x00, 0x08, 0x10, 0x28, 0x30, 0x38 }, 6 },
    { "xav_switcher_ig_ios_test_user_check_fdid", { 0x00 }, 1 },
};

#define SCI_MC_MAX_PARAMS 16
#define SCI_MC_MAX_ORIGINALS 16

static SCIMCBoolParam sSCIMCForcedParams[SCI_MC_MAX_PARAMS];
static atomic_size_t sSCIMCForcedParamCount;

static SCIMCOriginalEntry sSCIMCGetBoolOriginals[SCI_MC_MAX_ORIGINALS];
static SCIMCOriginalEntry sSCIMCGetBoolOptionsOriginals[SCI_MC_MAX_ORIGINALS];
static SCIMCOriginalEntry sSCIMCGetBoolDefaultOriginals[SCI_MC_MAX_ORIGINALS];
static atomic_uint sSCIMCGetBoolCount;
static atomic_uint sSCIMCGetBoolOptionsCount;
static atomic_uint sSCIMCGetBoolDefaultCount;

static BOOL SCIMCMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static void *SCIMCResolveDataSymbol(const char *name) {
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

static void SCIMCResolveDescriptorIDs(void) {
    if (atomic_load_explicit(&sSCIMCForcedParamCount,
                             memory_order_acquire) != 0) {
        return;
    }

    SCIMCBoolParam resolved[SCI_MC_MAX_PARAMS] = {0};
    size_t resolvedCount = 0;

    for (size_t i = 0;
         i < sizeof(kSCIMCDescriptorSpecs) / sizeof(kSCIMCDescriptorSpecs[0]);
         i++) {
        const SCIMCDescriptorSpec *spec = &kSCIMCDescriptorSpecs[i];
        const uint8_t *descriptor = SCIMCResolveDataSymbol(spec->symbol);
        if (!descriptor) continue;

        for (uint8_t j = 0; j < spec->offsetCount; j++) {
            SCIMCBoolParam parameter = 0;
            memcpy(&parameter, descriptor + spec->offsets[j], sizeof(parameter));
            if (!parameter) continue;

            BOOL duplicate = NO;
            for (size_t k = 0; k < resolvedCount; k++) {
                if (resolved[k] == parameter) {
                    duplicate = YES;
                    break;
                }
            }
            if (!duplicate && resolvedCount < SCI_MC_MAX_PARAMS) {
                resolved[resolvedCount++] = parameter;
            }
        }
    }

    if (resolvedCount) {
        memcpy(sSCIMCForcedParams, resolved,
               resolvedCount * sizeof(SCIMCBoolParam));
        atomic_store_explicit(&sSCIMCForcedParamCount, resolvedCount,
                              memory_order_release);
    }

    MCGLOG("resolved %lu typed descriptor parameter(s)",
           (unsigned long)resolvedCount);
}

static BOOL SCIMCShouldForce(SCIMCBoolParam parameter) {
    if (!SCIMCMasterOn()) return NO;

    size_t count = atomic_load_explicit(&sSCIMCForcedParamCount,
                                        memory_order_acquire);
    for (size_t i = 0; i < count; i++) {
        if (sSCIMCForcedParams[i] == parameter) return YES;
    }
    return NO;
}

static IMP SCIMCOriginalForReceiver(id receiver,
                                    SCIMCOriginalEntry *entries,
                                    atomic_uint *entryCount) {
    if (!receiver || !entries || !entryCount) return NULL;

    unsigned int count = atomic_load_explicit(entryCount, memory_order_acquire);
    for (Class cls = object_getClass(receiver); cls;
         cls = class_getSuperclass(cls)) {
        for (unsigned int i = 0; i < count; i++) {
            if (entries[i].cls == cls) return entries[i].original;
        }
    }
    return NULL;
}

static BOOL newSCIMCGetBool(id self, SEL _cmd, SCIMCBoolParam parameter) {
    IMP original = SCIMCOriginalForReceiver(
        self, sSCIMCGetBoolOriginals, &sSCIMCGetBoolCount);
    BOOL nativeValue = original
        ? ((BOOL (*)(id, SEL, SCIMCBoolParam))original)(self, _cmd, parameter)
        : NO;
    return SCIMCShouldForce(parameter) ? YES : nativeValue;
}

static BOOL newSCIMCGetBoolWithOptions(id self, SEL _cmd,
                                       SCIMCBoolParam parameter, id options) {
    IMP original = SCIMCOriginalForReceiver(
        self, sSCIMCGetBoolOptionsOriginals, &sSCIMCGetBoolOptionsCount);
    BOOL nativeValue = original
        ? ((BOOL (*)(id, SEL, SCIMCBoolParam, id))original)(
            self, _cmd, parameter, options)
        : NO;
    return SCIMCShouldForce(parameter) ? YES : nativeValue;
}

static BOOL newSCIMCGetBoolWithDefault(id self, SEL _cmd,
                                       SCIMCBoolParam parameter,
                                       BOOL defaultValue) {
    IMP original = SCIMCOriginalForReceiver(
        self, sSCIMCGetBoolDefaultOriginals, &sSCIMCGetBoolDefaultCount);
    BOOL nativeValue = original
        ? ((BOOL (*)(id, SEL, SCIMCBoolParam, BOOL))original)(
            self, _cmd, parameter, defaultValue)
        : defaultValue;
    return SCIMCShouldForce(parameter) ? YES : nativeValue;
}

static BOOL SCIMCEncodingIsGetBool(const char *encoding) {
    if (!encoding) return NO;
    return strcmp(encoding, "B24@0:8{mc_bool_param_t=Q}16") == 0 ||
           strcmp(encoding, "B24@0:8{mc_sessionless_bool_param_t=Q}16") == 0 ||
           strcmp(encoding, "B24@0:8{mc_sessionbased_bool_param_t=Q}16") == 0;
}

static BOOL SCIMCEncodingIsGetBoolWithOptions(const char *encoding) {
    if (!encoding) return NO;
    return strcmp(encoding, "B32@0:8{mc_bool_param_t=Q}16@24") == 0 ||
           strcmp(encoding, "B32@0:8{mc_sessionless_bool_param_t=Q}16@24") == 0 ||
           strcmp(encoding, "B32@0:8{mc_sessionbased_bool_param_t=Q}16@24") == 0;
}

static BOOL SCIMCEncodingIsGetBoolWithDefault(const char *encoding) {
    if (!encoding) return NO;
    return strcmp(encoding, "B28@0:8{mc_bool_param_t=Q}16B24") == 0 ||
           strcmp(encoding, "B28@0:8{mc_sessionless_bool_param_t=Q}16B24") == 0 ||
           strcmp(encoding, "B28@0:8{mc_sessionbased_bool_param_t=Q}16B24") == 0;
}

static Method SCIMCDeclaredMethod(Class cls, SEL selector) {
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

static void SCIMCHookExact(Class cls, SEL selector,
                           BOOL (*encodingValidator)(const char *),
                           IMP replacement,
                           SCIMCOriginalEntry *entries,
                           atomic_uint *entryCount) {
    if (!cls || !selector || !encodingValidator || !replacement ||
        !entries || !entryCount) {
        return;
    }

    Method method = SCIMCDeclaredMethod(cls, selector);
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !encodingValidator(encoding)) return;

    unsigned int count = atomic_load_explicit(entryCount, memory_order_acquire);
    for (unsigned int i = 0; i < count; i++) {
        if (entries[i].cls == cls) return;
    }
    if (count >= SCI_MC_MAX_ORIGINALS) return;

    IMP original = NULL;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (!original) return;

    entries[count].cls = cls;
    entries[count].original = original;
    atomic_store_explicit(entryCount, count + 1, memory_order_release);

    MCGLOG("exact reader %s.%s ABI=%s",
           class_getName(cls), sel_getName(selector), encoding);
}

static void SCIMCInstallKnownReaders(void) {
    static const char *kClassNames[] = {
        "FBMobileConfigStartupConfigs",
        "FBMobileConfigEmptyImpl",
        "FBMobileConfigContextObjcImpl",
        "IGMobileConfigContextManager",
        "FBMobileConfigContextManager",
        "IGMobileConfigUserSessionContextManager",
    };

    SEL getBool = sel_registerName("getBool:");
    SEL getBoolOptions = sel_registerName("getBool:withOptions:");
    SEL getBoolDefault = sel_registerName("getBool:withDefault:");

    for (size_t i = 0; i < sizeof(kClassNames) / sizeof(kClassNames[0]); i++) {
        Class cls = objc_getClass(kClassNames[i]);
        if (!cls) continue;

        SCIMCHookExact(cls, getBool, SCIMCEncodingIsGetBool,
                       (IMP)newSCIMCGetBool,
                       sSCIMCGetBoolOriginals, &sSCIMCGetBoolCount);
        SCIMCHookExact(cls, getBoolOptions,
                       SCIMCEncodingIsGetBoolWithOptions,
                       (IMP)newSCIMCGetBoolWithOptions,
                       sSCIMCGetBoolOptionsOriginals,
                       &sSCIMCGetBoolOptionsCount);
        SCIMCHookExact(cls, getBoolDefault,
                       SCIMCEncodingIsGetBoolWithDefault,
                       (IMP)newSCIMCGetBoolWithDefault,
                       sSCIMCGetBoolDefaultOriginals,
                       &sSCIMCGetBoolDefaultCount);
    }
}

void SCIInstallEmployeeMobileConfigDescriptorHooks(void) {
    // Must be called on the main thread after the application is active.  This
    // pass is bounded to known classes and never enumerates the Objective-C
    // runtime or installs IMPs from a background queue.
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIInstallEmployeeMobileConfigDescriptorHooks();
        });
        return;
    }

    @synchronized (SCIInternalGatePrefs.class) {
        SCIMCResolveDescriptorIDs();
        SCIMCInstallKnownReaders();
    }

    MCGLOG("bounded pass bool=%u options=%u default=%u params=%lu",
           atomic_load_explicit(&sSCIMCGetBoolCount, memory_order_acquire),
           atomic_load_explicit(&sSCIMCGetBoolOptionsCount, memory_order_acquire),
           atomic_load_explicit(&sSCIMCGetBoolDefaultCount, memory_order_acquire),
           (unsigned long)atomic_load_explicit(&sSCIMCForcedParamCount,
                                               memory_order_acquire));
}
