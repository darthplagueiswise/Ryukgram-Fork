// SCIMCLiveApply.m — RyukGram-Fork
#import "SCIMCLiveApply.h"
#import "../Dogfooding/SCIDogfoodObjectRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <string.h>

// --- C++ overrides-table ABI (resolved from the loaded shared runtime image) ---
// getOrCreateOverridesTable returns shared_ptr<FBMobileConfigOverridesTable> BY
// VALUE (16 bytes: stored ptr + control block) via the x8 sret register. A 16-byte
// struct-return typedef makes the compiler emit exactly that ABI.
typedef struct { void *ptr; void *ctrl; } SCISharedPtr16;
typedef SCISharedPtr16 (*SCIGetTableFn)(void *manager, bool create);
typedef void (*SCIUpdateBoolFn)(void *table, uint64_t paramID, bool value, bool persist);
typedef void (*SCIRemoveFn)(void *table, uint64_t paramID, bool persist);

static const char *kGetTableSym =
    "_ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb";
static const char *kUpdateBoolSym =
    "_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb";
static const char *kRemoveSym =
    "_ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb";

static SCIGetTableFn   sGetTable   = NULL;
static SCIUpdateBoolFn sUpdateBool = NULL;
static SCIRemoveFn     sRemove     = NULL;

static void SCIResolveSymbols(void) {
    // Frameworks can be loaded after the Dev menu first asks for status. Retry
    // only missing symbols instead of permanently caching an early NULL.
    @synchronized([SCIMCLiveApply class]) {
        if (!sGetTable) {
            sGetTable = (SCIGetTableFn)dlsym(RTLD_DEFAULT, kGetTableSym);
        }
        if (!sUpdateBool) {
            sUpdateBool = (SCIUpdateBoolFn)dlsym(RTLD_DEFAULT, kUpdateBoolSym);
        }
        if (!sRemove) {
            sRemove = (SCIRemoveFn)dlsym(RTLD_DEFAULT, kRemoveSym);
        }
    }
}

static void *SCIResolveRuntimeSymbol(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length) return NULL;
    void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
    if (!symbol) {
        NSString *under = [@"_" stringByAppendingString:name];
        symbol = dlsym(RTLD_DEFAULT, under.UTF8String);
    }
    return symbol;
}

// --- live manager resolution (chain confirmed by the id-name-map diagnostic) ---
// FBMobileConfigFBTGlobalSessionManager.sharedInstance
//   -> currentSessionContextManagerHolder
//   -> holder._mcFbtManager               (FBMobileConfigFBTContextManager)
//   -> fbt._mobileconfig                   (IGMobileConfigContextManager)
//   -> ctx._configManager                  (weak_ptr<IFBMobileConfigManager>, raw)
static id SCIIvarObject(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    return iv ? object_getIvar(obj, iv) : nil;
}

static void *SCIResolveNewerLiveManager(void) {
    @try {
        Class gsm = objc_getClass("FBMobileConfigFBTGlobalSessionManager");
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (!gsm || ![gsm respondsToSelector:sharedSel]) return NULL;
        id shared = ((id (*)(id, SEL))objc_msgSend)(gsm, sharedSel);
        SEL holderSel = NSSelectorFromString(@"currentSessionContextManagerHolder");
        if (![shared respondsToSelector:holderSel]) return NULL;
        id holder = ((id (*)(id, SEL))objc_msgSend)(shared, holderSel);
        if (!holder) return NULL;

        id fbt = SCIIvarObject(holder, "_mcFbtManager");
        if (!fbt) {
            SEL s = NSSelectorFromString(@"mcFbtManager");
            if ([holder respondsToSelector:s]) fbt = ((id (*)(id, SEL))objc_msgSend)(holder, s);
        }
        if (!fbt) return NULL;

        id ctx = SCIIvarObject(fbt, "_mobileconfig");
        if (!ctx) return NULL;

        Ivar iv = class_getInstanceVariable(object_getClass(ctx), "_configManager");
        if (!iv) return NULL;
        ptrdiff_t off = ivar_getOffset(iv);
        // _configManager is a C++ weak_ptr (raw bytes, not an ObjC object): the
        // first pointer-sized word is the managed FBMobileConfigManager*.
        void *raw = *(void **)((char *)(__bridge void *)ctx + off);
        return raw;
    } @catch (__unused id e) {
        return NULL;
    }
}

static BOOL SCIObjectGetter(id object, NSString *name, id *valueOut) {
    if (!object || !name.length) return NO;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[64] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char *type = returnType;
    while (strchr("rnNoORV", *type)) type++;
    if (*type != '@') return NO;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (valueOut) *valueOut = value;
        return value != nil;
    } @catch (__unused id exception) {
        return NO;
    }
}

static BOOL SCIIsMobileConfigContext(id object) {
    if (!object) return NO;
    Class contextClass = objc_getClass("IGMobileConfigContextManager");
    if (contextClass && [object isKindOfClass:contextClass]) return YES;
    Protocol *contextProtocol = objc_getProtocol("FBMobileConfigContext");
    return contextProtocol && [object conformsToProtocol:contextProtocol];
}

static id SCIContextFromObject(id root, NSUInteger depth,
                               NSMutableSet<NSValue *> *visited) {
    if (!root || depth > 3) return nil;
    if (SCIIsMobileConfigContext(root)) return root;
    NSValue *address = [NSValue valueWithPointer:(__bridge const void *)root];
    if ([visited containsObject:address]) return nil;
    [visited addObject:address];

    // Instagram 376 exports FBLink_IGUserSession_FBMobileConfigAPI and adds the
    // `mobileConfig` surface to the live session. Keep historical spellings for
    // adjacent builds and validate every returned object before use.
    for (NSString *selectorName in @[
        @"mobileConfig", @"mobileConfigContext", @"mobileConfigAPI",
        @"mobileconfig", @"contextManager"
    ]) {
        id child = nil;
        if (!SCIObjectGetter(root, selectorName, &child) || !child) continue;
        id context = SCIContextFromObject(child, depth + 1, visited);
        if (context) return context;
    }

    // Some versions store the context instead of exposing the category getter.
    // Traverse only explicitly named MobileConfig object ivars; never walk the
    // enormous generic IGUserSession graph.
    for (Class cls = object_getClass(root); cls; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int index = 0; ivars && index < count; index++) {
            const char *rawName = ivar_getName(ivars[index]);
            const char *encoding = ivar_getTypeEncoding(ivars[index]);
            if (!rawName || !encoding || encoding[0] != '@') continue;
            NSString *name = [[NSString stringWithUTF8String:rawName] lowercaseString];
            if (![name containsString:@"mobileconfig"] &&
                ![name containsString:@"configmanager"]) continue;
            id child = nil;
            @try { child = object_getIvar(root, ivars[index]); }
            @catch (__unused id exception) {}
            id context = SCIContextFromObject(child, depth + 1, visited);
            if (context) { free(ivars); return context; }
        }
        if (ivars) free(ivars);
    }
    return nil;
}

static id SCIResolve376LiveContext(void) {
    static __weak id cachedContext = nil;
    id context = cachedContext;
    if (SCIIsMobileConfigContext(context)) return context;
    id session = [SCIDogfoodObjectRuntime activeUserSession];
    context = SCIContextFromObject(session, 0, [NSMutableSet set]);
    if (context) cachedContext = context;
    return context;
}

static void *SCIManagerFrom376Context(id context) {
    if (!context) return NULL;
    Ivar ivar = class_getInstanceVariable(object_getClass(context), "_configManager");
    if (!ivar) return NULL;
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding || !strstr(encoding, "weak_ptr") ||
        !strstr(encoding, "MobileConfigManager")) return NULL;
    ptrdiff_t offset = ivar_getOffset(ivar);
    // libc++ weak_ptr layout in this binary is {managed pointer, control block}.
    // Borrow the first word; the live context owns the manager's lifetime.
    return *(void **)((uint8_t *)(__bridge void *)context + offset);
}

static void *SCIResolveLiveManager(void) {
    void *manager = SCIResolveNewerLiveManager();
    if (manager) return manager;
    return SCIManagerFrom376Context(SCIResolve376LiveContext());
}

// Fetch the live overrides-table raw pointer. The returned shared_ptr's stored
// pointer aliases a table owned by the manager (getOrCreate), so it stays valid
// for the manager's lifetime; we use the raw pointer and don't retain the ref.
static void *SCILiveOverridesTable(SCIMCLiveResult *outErr) {
    SCIResolveSymbols();
    if (!sGetTable) { if (outErr) *outErr = SCIMCLiveNoSymbol; return NULL; }
    void *manager = SCIResolveLiveManager();
    if (!manager) { if (outErr) *outErr = SCIMCLiveNoManager; return NULL; }
    SCISharedPtr16 sp = sGetTable(manager, true);
    if (!sp.ptr) { if (outErr) *outErr = SCIMCLiveNoTable; return NULL; }
    if (outErr) *outErr = SCIMCLiveOK;
    return sp.ptr;
}

@implementation SCIMCLiveApply

+ (NSString *)wiringStatus {
    SCIResolveSymbols();
    if (!sGetTable || !sUpdateBool) return @"no symbols";
    if (SCIResolveNewerLiveManager()) return @"ready (session manager)";
    if (SCIManagerFrom376Context(SCIResolve376LiveContext())) {
        return @"ready (IGMobileConfig context)";
    }
    return @"no manager";
}

+ (uint64_t)paramIDForDescriptorSymbol:(NSString *)symbolName {
    void *descriptor = SCIResolveRuntimeSymbol(symbolName);
    if (!descriptor) return 0;
    uint64_t paramID = 0;
    memcpy(&paramID, descriptor, sizeof(paramID));
    return paramID;
}

+ (SCIMCLiveResult)setOverrideForParamID:(uint64_t)paramID value:(BOOL)value {
    SCIMCLiveResult err = SCIMCLiveOK;
    void *table = SCILiveOverridesTable(&err);
    if (!table) return err;
    if (!sUpdateBool) return SCIMCLiveNoSymbol;
    sUpdateBool(table, paramID, value ? true : false, /*persist=*/true);
    return SCIMCLiveOK;
}

+ (SCIMCLiveResult)clearOverrideForParamID:(uint64_t)paramID {
    SCIMCLiveResult err = SCIMCLiveOK;
    void *table = SCILiveOverridesTable(&err);
    if (!table) return err;
    if (!sRemove) return SCIMCLiveNoSymbol;
    sRemove(table, paramID, /*persist=*/true);
    return SCIMCLiveOK;
}

+ (NSString *)applyIsEmployeeProbe {
    uint64_t paramID = [self paramIDForDescriptorSymbol:@"ig_is_employee"];
    if (!paramID) {
        return @"ig_is_employee DATA descriptor is not exported by this runtime.";
    }
    SCIMCLiveResult r = [self setOverrideForParamID:paramID value:YES];
    switch (r) {
        case SCIMCLiveOK:        return [NSString stringWithFormat:@"applied ig_is_employee=true live (descriptor 0x%016llx; relaunch not required).", (unsigned long long)paramID];
        case SCIMCLiveNoManager: return @"no live FBMobileConfigManager (open the app past login first).";
        case SCIMCLiveNoTable:   return @"getOrCreateOverridesTable returned null.";
        case SCIMCLiveNoSymbol:  return @"required shared-runtime C++ symbol not found (build/link changed).";
    }
    return @"unknown";
}

@end
