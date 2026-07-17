#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define MCGLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] MCIdentityDescriptors " fmt, ##__VA_ARGS__)

// Revalidated with LIEF + radare2 + Capstone against:
// Instagram         a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa
// FBSharedFramework 22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc
//
// These names DO exist. They are exported MobileConfig descriptor objects in
// FBSharedFramework __TEXT,__const and imported by Instagram through chained
// fixups. They are not callable BOOL functions and their bytes must not be
// patched. Instagram reads their uint64 parameter fields through the typed
// getBool:/getBool:withOptions:/getBool:withDefault: consumers hooked below.

typedef uint64_t SCIMCBoolParam;

typedef struct {
    const char *symbol;
    uint8_t offsets[8];
    uint8_t offsetCount;
} SCIMCDescriptorSpec;

static const SCIMCDescriptorSpec kSCIMCDescriptorSpecs[] = {
    // _ig_is_employee occupies 0x10 bytes; both fields are mc_bool_param_t.
    { "ig_is_employee", { 0x00, 0x08 }, 2 },

    // _ig_is_employee_or_test_user occupies one uint64 field.
    { "ig_is_employee_or_test_user", { 0x00 }, 1 },

    // _ig_dogfooding_assistant has a non-BOOL field at +0 and its BOOL field
    // at +8. The native caller at Instagram 0x103eca9a4 loads [descriptor,#8].
    { "ig_dogfooding_assistant", { 0x08 }, 1 },

    // _ig_dogfooding_first_client is a 0x40-byte generated group. Offsets with
    // the 0x81 bool tag are included; the 0x82 fields at +0x18/+0x20 are not.
    { "ig_dogfooding_first_client",
      { 0x00, 0x08, 0x10, 0x28, 0x30, 0x38 }, 6 },

    // This XAV descriptor is consumed by -getBool: at Instagram 0x1090ce714.
    { "xav_switcher_ig_ios_test_user_check_fdid", { 0x00 }, 1 },
};

static NSMutableDictionary<NSNumber *, NSString *> *sSCIMCForcedParamNames;
static NSMutableDictionary<NSString *, NSValue *> *sSCIMCGetBoolOriginals;
static NSMutableDictionary<NSString *, NSValue *> *sSCIMCGetBoolOptionsOriginals;
static NSMutableDictionary<NSString *, NSValue *> *sSCIMCGetBoolDefaultOriginals;

static BOOL SCIMCMasterOn(void) {
    return [SCIInternalGatePrefs employeeInternalMasterEnabled];
}

static NSString *SCIMCMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%p#%s", cls, sel_getName(selector) ?: "<nil>"];
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

static void SCIMCRefreshDescriptorIDs(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        if (!sSCIMCForcedParamNames) {
            sSCIMCForcedParamNames = [NSMutableDictionary dictionary];
        }

        for (NSUInteger i = 0;
             i < sizeof(kSCIMCDescriptorSpecs) / sizeof(kSCIMCDescriptorSpecs[0]);
             i++) {
            const SCIMCDescriptorSpec *spec = &kSCIMCDescriptorSpecs[i];
            const uint8_t *descriptor = SCIMCResolveDataSymbol(spec->symbol);
            if (!descriptor) continue;

            for (uint8_t j = 0; j < spec->offsetCount; j++) {
                uint8_t offset = spec->offsets[j];
                SCIMCBoolParam parameter = 0;
                memcpy(&parameter, descriptor + offset, sizeof(parameter));
                if (!parameter) continue;

                NSString *name = [NSString stringWithFormat:@"%s+0x%02x",
                                  spec->symbol, offset];
                sSCIMCForcedParamNames[@(parameter)] = name;
            }
        }
    }
}

static NSString *SCIMCForcedName(SCIMCBoolParam parameter) {
    if (!SCIMCMasterOn()) return nil;
    SCIMCRefreshDescriptorIDs();
    @synchronized (SCIDogfoodObjectRuntime.class) {
        return sSCIMCForcedParamNames[@(parameter)];
    }
}

static IMP SCIMCOriginalForObject(id object, SEL selector,
                                  NSMutableDictionary<NSString *, NSValue *> *store) {
    if (!object || !selector || !store) return NULL;
    @synchronized (store) {
        for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
            NSValue *value = store[SCIMCMethodKey(cls, selector)];
            if (value) return value.pointerValue;
        }
    }
    return NULL;
}

static BOOL newSCIMCGetBool(id self, SEL _cmd, SCIMCBoolParam parameter) {
    NSString *forced = SCIMCForcedName(parameter);
    if (forced) {
        MCGLOG("force getBool %{public}@ receiver=%{public}@",
               forced, NSStringFromClass(object_getClass(self)));
        return YES;
    }

    IMP original = SCIMCOriginalForObject(self, _cmd, sSCIMCGetBoolOriginals);
    return original
        ? ((BOOL (*)(id, SEL, SCIMCBoolParam))original)(self, _cmd, parameter)
        : NO;
}

static BOOL newSCIMCGetBoolWithOptions(id self, SEL _cmd,
                                       SCIMCBoolParam parameter, id options) {
    NSString *forced = SCIMCForcedName(parameter);
    if (forced) {
        MCGLOG("force getBool:withOptions: %{public}@ receiver=%{public}@",
               forced, NSStringFromClass(object_getClass(self)));
        return YES;
    }

    IMP original = SCIMCOriginalForObject(self, _cmd,
                                          sSCIMCGetBoolOptionsOriginals);
    return original
        ? ((BOOL (*)(id, SEL, SCIMCBoolParam, id))original)(
            self, _cmd, parameter, options)
        : NO;
}

static BOOL newSCIMCGetBoolWithDefault(id self, SEL _cmd,
                                       SCIMCBoolParam parameter, BOOL defaultValue) {
    NSString *forced = SCIMCForcedName(parameter);
    if (forced) {
        MCGLOG("force getBool:withDefault: %{public}@ receiver=%{public}@",
               forced, NSStringFromClass(object_getClass(self)));
        return YES;
    }

    IMP original = SCIMCOriginalForObject(self, _cmd,
                                          sSCIMCGetBoolDefaultOriginals);
    return original
        ? ((BOOL (*)(id, SEL, SCIMCBoolParam, BOOL))original)(
            self, _cmd, parameter, defaultValue)
        : defaultValue;
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
    return encoding &&
        strcmp(encoding, "B28@0:8{mc_bool_param_t=Q}16B24") == 0;
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

static void SCIMCHookDeclaredMethod(Class cls, SEL selector, Method method,
                                    IMP replacement,
                                    NSMutableDictionary<NSString *, NSValue *> *store) {
    if (!cls || !selector || !method || !replacement || !store) return;
    NSString *key = SCIMCMethodKey(cls, selector);
    @synchronized (store) {
        if (store[key]) return;
    }

    IMP original = NULL;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (!original) return;

    @synchronized (store) {
        store[key] = [NSValue valueWithPointer:original];
    }
    MCGLOG("hooked %{public}@.%{public}s ABI=%{public}s",
           NSStringFromClass(cls), sel_getName(selector),
           method_getTypeEncoding(method));
}

static void SCIMCInstallDescriptorReaderHooks(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        if (!sSCIMCGetBoolOriginals) {
            sSCIMCGetBoolOriginals = [NSMutableDictionary dictionary];
            sSCIMCGetBoolOptionsOriginals = [NSMutableDictionary dictionary];
            sSCIMCGetBoolDefaultOriginals = [NSMutableDictionary dictionary];
        }

        SCIMCRefreshDescriptorIDs();

        int classCount = objc_getClassList(NULL, 0);
        if (classCount <= 0) return;
        Class *classes = (__unsafe_unretained Class *)calloc(
            (size_t)classCount, sizeof(Class));
        if (!classes) return;
        classCount = objc_getClassList(classes, classCount);

        SEL getBool = NSSelectorFromString(@"getBool:");
        SEL getBoolOptions = NSSelectorFromString(@"getBool:withOptions:");
        SEL getBoolDefault = NSSelectorFromString(@"getBool:withDefault:");

        for (int i = 0; i < classCount; i++) {
            Class cls = classes[i];
            NSString *className = NSStringFromClass(cls) ?: @"";
            if ([className rangeOfString:@"MobileConfig"
                                 options:NSCaseInsensitiveSearch].location == NSNotFound) {
                continue;
            }

            Method method = SCIMCDeclaredMethod(cls, getBool);
            if (method && SCIMCEncodingIsGetBool(method_getTypeEncoding(method))) {
                SCIMCHookDeclaredMethod(cls, getBool, method,
                    (IMP)newSCIMCGetBool, sSCIMCGetBoolOriginals);
            }

            method = SCIMCDeclaredMethod(cls, getBoolOptions);
            if (method &&
                SCIMCEncodingIsGetBoolWithOptions(method_getTypeEncoding(method))) {
                SCIMCHookDeclaredMethod(cls, getBoolOptions, method,
                    (IMP)newSCIMCGetBoolWithOptions,
                    sSCIMCGetBoolOptionsOriginals);
            }

            method = SCIMCDeclaredMethod(cls, getBoolDefault);
            if (method &&
                SCIMCEncodingIsGetBoolWithDefault(method_getTypeEncoding(method))) {
                SCIMCHookDeclaredMethod(cls, getBoolDefault, method,
                    (IMP)newSCIMCGetBoolWithDefault,
                    sSCIMCGetBoolDefaultOriginals);
            }
        }
        free(classes);

        MCGLOG("resolved %lu descriptor parameter IDs",
               (unsigned long)sSCIMCForcedParamNames.count);
    }
}

static void SCIMCImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    SCIMCInstallDescriptorReaderHooks();
}

__attribute__((constructor))
static void SCIEmployeeMobileConfigDescriptorHooksCtor(void) {
    @autoreleasepool {
        // Install regardless of the current preference. Replacements consult the
        // consolidated Employee / Internal master live on every read.
        SCIMCInstallDescriptorReaderHooks();
        _dyld_register_func_for_add_image(SCIMCImageLoaded);
    }
}
