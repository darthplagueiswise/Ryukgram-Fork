#import "SCITier2EmployeeGate.h"
#import "../../Utils.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <stdint.h>
#import <string.h>

typedef void *(*SCIMSFindSymbolFn)(void *image, const char *name);
typedef void (*SCIMSHookMessageExFn)(Class cls, SEL sel, IMP repl, IMP *orig);

typedef BOOL (*SCIBoolGetter1)(id, SEL, uintptr_t);
typedef BOOL (*SCIBoolGetter2)(id, SEL, uintptr_t, id);

typedef struct {
    Class cls;
    SEL sel;
    IMP original;
    BOOL hasOptions;
} SCITier2Hook;

static volatile BOOL gEnabled = NO;
static volatile BOOL gInstalled = NO;
static volatile BOOL gInstalling = NO;
static uintptr_t gEmployeeDescriptor = 0;
static uintptr_t gEmployeeValue = 0;
static uintptr_t gEmployeeOrTestDescriptor = 0;
static uintptr_t gEmployeeOrTestValue = 0;
static SCITier2Hook gHooks[64];
static size_t gHookCount = 0;

static void SCIClearLegacyEmployeeForces(void) {
    NSArray<NSString *> *keys = @[
        @"sci_employee_internal",
        @"sci_force_mc_session_employee_gate",
        @"sci_force_ig_internal_employee",
        @"sci_force_ig_is_employee",
        @"sci_force_easy_gating_all",
        @"sci_force_easy_gating_internal",
        @"sci_force_easy_gating_auth",
        @"sci_force_easy_gating_mcq",
        @"sci_force_easy_gating_platform",
        @"sci_force_mc_internal_use_all",
        @"sci_force_all_mc_gates",
        @"sci_force_sessioned_mc_all",
        @"sci_force_msgc_sessioned_boolean",
        @"sci_force_mci_experiment_boolean",
        @"sci_force_mci_extension_boolean"
    ];
    for (NSString *key in keys) [SCIUtils setPref:@NO forKey:key];
}

static uintptr_t SCIUnsign(uintptr_t value) {
#if __LP64__
    return value & UINT64_C(0x0000ffffffffffff);
#else
    return value;
#endif
}

static void *SCIResolvePrivateSymbol(const char *name) {
    if (!name) return NULL;
    void *symbol = dlsym(RTLD_DEFAULT, name[0] == '_' ? name + 1 : name);
    if (symbol) return symbol;
    SCIMSFindSymbolFn finder = (SCIMSFindSymbolFn)dlsym(RTLD_DEFAULT, "MSFindSymbol");
    return finder ? finder(NULL, name) : NULL;
}

static BOOL SCIReadDescriptor(const char *symbolName, uintptr_t *descriptor, uintptr_t *value) {
    void *address = SCIResolvePrivateSymbol(symbolName);
    if (!address) return NO;
    uintptr_t desc = SCIUnsign((uintptr_t)address);
    uintptr_t first = 0;
    @try { first = SCIUnsign(*(const uintptr_t *)desc); }
    @catch (__unused id exception) { return NO; }
    if (!desc || !first) return NO;
    *descriptor = desc;
    *value = first;
    return YES;
}

static BOOL SCIIsEmployeeArgument(uintptr_t arg) {
    arg = SCIUnsign(arg);
    return arg && (arg == gEmployeeDescriptor || arg == gEmployeeValue);
}

static BOOL SCIIsAliasArgument(uintptr_t arg) {
    arg = SCIUnsign(arg);
    return arg && (arg == gEmployeeOrTestDescriptor || arg == gEmployeeOrTestValue);
}

static IMP SCIOriginalFor(id receiver, SEL sel, BOOL hasOptions) {
    Class cls = object_getClass(receiver);
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        for (size_t i = 0; i < gHookCount; i++) {
            if (gHooks[i].cls == current && gHooks[i].sel == sel && gHooks[i].hasOptions == hasOptions)
                return gHooks[i].original;
        }
    }
    return NULL;
}

static BOOL SCITier2GetBool(id self, SEL _cmd, uintptr_t config) {
    SCIBoolGetter1 original = (SCIBoolGetter1)SCIOriginalFor(self, _cmd, NO);
    if (!original) return NO;
    if (!gEnabled) return original(self, _cmd, config);
    if (SCIIsEmployeeArgument(config)) return YES;
    if (SCIIsAliasArgument(config)) return original(self, _cmd, gEmployeeValue);
    return original(self, _cmd, config);
}

static BOOL SCITier2GetBoolWithOptions(id self, SEL _cmd, uintptr_t config, id options) {
    SCIBoolGetter2 original = (SCIBoolGetter2)SCIOriginalFor(self, _cmd, YES);
    if (!original) return NO;
    if (!gEnabled) return original(self, _cmd, config, options);
    if (SCIIsEmployeeArgument(config)) return YES;
    if (SCIIsAliasArgument(config)) return original(self, _cmd, gEmployeeValue, options);
    return original(self, _cmd, config, options);
}

static BOOL SCITypeIsBool(const char *type) {
    return type && (type[0] == 'B' || type[0] == 'c' || type[0] == 'C');
}

static BOOL SCITypeIsPointerSized(const char *type) {
    if (!type || !type[0]) return NO;
    switch (type[0]) {
        case '@': case '^': case '*': case ':': case '#':
        case 'Q': case 'q': case 'L': case 'l':
            return YES;
        default:
            return NO;
    }
}

static BOOL SCIMethodABIValid(Method method, BOOL withOptions) {
    if (!method) return NO;
    if (method_getNumberOfArguments(method) != (withOptions ? 4 : 3)) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (!SCITypeIsBool(type)) return NO;
    memset(type, 0, sizeof(type));
    method_getArgumentType(method, 2, type, sizeof(type));
    return SCITypeIsPointerSized(type);
}

static Class SCIDeclaringClass(Class cls, SEL sel) {
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        BOOL found = NO;
        for (unsigned int i = 0; methods && i < count; i++) {
            if (method_getName(methods[i]) == sel) { found = YES; break; }
        }
        if (methods) free(methods);
        if (found) return current;
    }
    return Nil;
}

static BOOL SCIAlreadyHooked(Class cls, SEL sel) {
    for (size_t i = 0; i < gHookCount; i++)
        if (gHooks[i].cls == cls && gHooks[i].sel == sel) return YES;
    return NO;
}

static BOOL SCIInstallOne(SCIMSHookMessageExFn hooker, Class cls, SEL sel, BOOL withOptions) {
    cls = SCIDeclaringClass(cls, sel);
    if (!cls || SCIAlreadyHooked(cls, sel) || gHookCount >= 64) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    if (!SCIMethodABIValid(method, withOptions)) return NO;
    IMP original = NULL;
    hooker(cls, sel, withOptions ? (IMP)SCITier2GetBoolWithOptions : (IMP)SCITier2GetBool, &original);
    if (!original) return NO;
    gHooks[gHookCount++] = (SCITier2Hook){ cls, sel, original, withOptions };
    return YES;
}

static void SCIInstallTier2(void) {
    if (gInstalled || gInstalling || !gEnabled) return;
    gInstalling = YES;

    BOOL employeeOK = SCIReadDescriptor("_ig_is_employee", &gEmployeeDescriptor, &gEmployeeValue);
    BOOL aliasOK = SCIReadDescriptor("_ig_is_employee_or_test_user", &gEmployeeOrTestDescriptor, &gEmployeeOrTestValue);
    SCIMSHookMessageExFn hooker = (SCIMSHookMessageExFn)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!employeeOK || !hooker) { gInstalling = NO; return; }
    if (!aliasOK) { gEmployeeOrTestDescriptor = 0; gEmployeeOrTestValue = 0; }

    SEL getBool = sel_registerName("getBool:");
    SEL getBoolOptions = sel_registerName("getBool:withOptions:");
    int capacity = objc_getClassList(NULL, 0);
    if (capacity > 0) {
        Class *classes = calloc((size_t)capacity, sizeof(Class));
        int count = classes ? objc_getClassList(classes, capacity) : 0;
        for (int i = 0; i < count && gHookCount < 64; i++) {
            SCIInstallOne(hooker, classes[i], getBool, NO);
            SCIInstallOne(hooker, classes[i], getBoolOptions, YES);
        }
        free(classes);
    }

    gInstalled = gHookCount > 0;
    gInstalling = NO;
    NSLog(@"[SCITier2] employee canonical hooks=%zu alias=%d", gHookCount, aliasOK);
}

void SCITier2EmployeeGateSetEnabled(BOOL enabled) {
    if (enabled) SCIClearLegacyEmployeeForces();
    gEnabled = enabled;
    if (enabled) dispatch_async(dispatch_get_main_queue(), ^{ SCIInstallTier2(); });
}

BOOL SCITier2EmployeeGateEnabled(void) { return gEnabled; }
BOOL SCITier2EmployeeGateInstalled(void) { return gInstalled; }

__attribute__((constructor))
static void SCITier2Bootstrap(void) {
    @autoreleasepool {
        gEnabled = [SCIUtils getBoolPref:@"sci_tier2_employee_internal"];
        if (gEnabled) SCIClearLegacyEmployeeForces();
        if (gEnabled) dispatch_async(dispatch_get_main_queue(), ^{ SCIInstallTier2(); });
    }
}
