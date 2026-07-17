#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>

#define SMCLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] SessionlessCapture " fmt, ##__VA_ARGS__)

// Strong references are intentional. The old runtime map stores weak objects and
// the FBT global holder may still be nil when the debug UI is opened. These are
// objects constructed and owned by Instagram; nothing is synthesized here.
static id sSessionlessContext;
static id sSessionlessHolder;
static id sSessionlessFBTManager;
static NSString *sSessionlessCaptureSource;

static NSString *SMCNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *out = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') {
            [out appendFormat:@"%c", *p++];
            continue;
        }
        [out appendString:@"@"]; p++;
        if (*p == '"') {
            for (p++; *p && *p != '"'; p++) {}
            if (*p) p++;
        } else if (*p == '?') {
            [out appendString:@"?"]; p++;
            if (*p == '<') {
                NSInteger depth = 0;
                do {
                    if (*p == '<') depth++;
                    else if (*p == '>') depth--;
                    p++;
                } while (*p && depth > 0);
            }
        }
    }
    return out;
}

static BOOL SMCMethodMatches(Method method, const char *expected) {
    return method && expected &&
        [SMCNormalizedEncoding(method_getTypeEncoding(method))
            isEqualToString:SMCNormalizedEncoding(expected)];
}

static BOOL SMCContextHasValidManager(id context) {
    if (!context) return NO;
    SEL selector = NSSelectorFromString(@"hasValidManager");
    Method method = class_getInstanceMethod([context class], selector);
    if (!SMCMethodMatches(method, "B16@0:8") &&
        !SMCMethodMatches(method, "c16@0:8")) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(context, selector);
    } @catch (__unused id exception) {
        return NO;
    }
}

static id SMCObjectGetter(id object, NSString *name) {
    if (!object || !name.length) return nil;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    if (!SMCMethodMatches(method, "@16@0:8")) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused id exception) {
        return nil;
    }
}

static void SMCCaptureContext(id context, NSString *source) {
    if (!SMCContextHasValidManager(context)) return;
    @synchronized (SCIDogfoodObjectRuntime.class) {
        sSessionlessContext = context;
        sSessionlessCaptureSource = source.copy ?: @"native capture";
    }
    [SCIDogfoodObjectRuntime noteObject:context
                                   role:@"IGMobileConfigSessionlessContextManager"
                                 source:source ?: @"native capture"];
    SMCLOG("captured valid context %{public}@ via %{public}@",
           NSStringFromClass([context class]), source);
}

static void SMCCaptureFBTManager(id manager, NSString *source) {
    if (!manager) return;
    @synchronized (SCIDogfoodObjectRuntime.class) {
        sSessionlessFBTManager = manager;
    }
    id context = SMCObjectGetter(manager, @"mobileconfig");
    if (context) SMCCaptureContext(context, source);
}

static void SMCCaptureHolder(id holder, NSString *source) {
    if (!holder) return;
    @synchronized (SCIDogfoodObjectRuntime.class) {
        sSessionlessHolder = holder;
    }
    id manager = SMCObjectGetter(holder, @"mcFbtManager");
    if (manager) SMCCaptureFBTManager(manager, source);
}

id SCIValidatedSessionlessMobileConfigContext(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        return SMCContextHasValidManager(sSessionlessContext)
            ? sSessionlessContext
            : nil;
    }
}

NSString *SCIValidatedSessionlessMobileConfigCaptureState(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        return [NSString stringWithFormat:
            @"holder=%@ %@\nfbtManager=%@ %@\ncontext=%@ %@\nmanagerValid=%@\nsource=%@",
            sSessionlessHolder ? NSStringFromClass([sSessionlessHolder class]) : @"nil",
            sSessionlessHolder ? [NSString stringWithFormat:@"%p", sSessionlessHolder] : @"",
            sSessionlessFBTManager ? NSStringFromClass([sSessionlessFBTManager class]) : @"nil",
            sSessionlessFBTManager ? [NSString stringWithFormat:@"%p", sSessionlessFBTManager] : @"",
            sSessionlessContext ? NSStringFromClass([sSessionlessContext class]) : @"nil",
            sSessionlessContext ? [NSString stringWithFormat:@"%p", sSessionlessContext] : @"",
            SMCContextHasValidManager(sSessionlessContext) ? @"YES" : @"NO",
            sSessionlessCaptureSource ?: @"none"];
    }
}

#pragma mark - Exact native capture points

static id (*origSessionlessInit)(id, SEL, const void *) = NULL;
static id newSessionlessInit(id self, SEL _cmd, const void *managerSharedPtr) {
    id result = origSessionlessInit
        ? origSessionlessInit(self, _cmd, managerSharedPtr)
        : nil;
    SMCCaptureContext(result, @"IGMobileConfigSessionlessContextManager.initWithManager:");
    return result;
}

static id (*origFBTContextInit)(id, SEL, id, id) = NULL;
static id newFBTContextInit(id self, SEL _cmd, id mapping, id mobileconfig) {
    id result = origFBTContextInit
        ? origFBTContextInit(self, _cmd, mapping, mobileconfig)
        : nil;
    if (result) {
        @synchronized (SCIDogfoodObjectRuntime.class) {
            sSessionlessFBTManager = result;
        }
    }
    SMCCaptureContext(mobileconfig,
        @"FBMobileConfigFBTContextManager.initWithFbtToMCIdMapping:mobileconfig:");
    return result;
}

static void (*origSetupHolder)(id, SEL, id) = NULL;
static void newSetupHolder(id self, SEL _cmd, id holder) {
    if (origSetupHolder) origSetupHolder(self, _cmd, holder);
    SMCCaptureHolder(holder,
        @"FBMobileConfigFBTGlobalSessionManager.setupFBTSessionlessContextManagerHolder:");
}

static void (*origSetFBTManager)(id, SEL, id) = NULL;
static void newSetFBTManager(id self, SEL _cmd, id manager) {
    if (origSetFBTManager) origSetFBTManager(self, _cmd, manager);
    @synchronized (SCIDogfoodObjectRuntime.class) {
        sSessionlessHolder = self;
    }
    SMCCaptureFBTManager(manager,
        @"FBMobileConfigFBTContextManagerHolder.setMcFbtManager:");
}

static id (*origGetHolder)(id, SEL) = NULL;
static id newGetHolder(id self, SEL _cmd) {
    id value = origGetHolder ? origGetHolder(self, _cmd) : nil;
    if (value) SMCCaptureHolder(value,
        @"FBMobileConfigFBTGlobalSessionManager.sessionlessContextManagerHolder");
    @synchronized (SCIDogfoodObjectRuntime.class) {
        return value ?: sSessionlessHolder;
    }
}

static id (*origGetFBTManager)(id, SEL) = NULL;
static id newGetFBTManager(id self, SEL _cmd) {
    id value = origGetFBTManager ? origGetFBTManager(self, _cmd) : nil;
    if (value) SMCCaptureFBTManager(value,
        @"FBMobileConfigFBTContextManagerHolder.mcFbtManager");
    @synchronized (SCIDogfoodObjectRuntime.class) {
        return value ?: sSessionlessFBTManager;
    }
}

static id (*origGetMobileconfig)(id, SEL) = NULL;
static id newGetMobileconfig(id self, SEL _cmd) {
    id value = origGetMobileconfig ? origGetMobileconfig(self, _cmd) : nil;
    if (value) SMCCaptureContext(value,
        @"FBMobileConfigFBTContextManager.mobileconfig");
    @synchronized (SCIDogfoodObjectRuntime.class) {
        return value ?: (SMCContextHasValidManager(sSessionlessContext)
            ? sSessionlessContext : nil);
    }
}

static id (*origBaseSessionlessFactory)(id, SEL) = NULL;
static id newBaseSessionlessFactory(id self, SEL _cmd) {
    id original = origBaseSessionlessFactory
        ? origBaseSessionlessFactory(self, _cmd)
        : nil;
    id captured = SCIValidatedSessionlessMobileConfigContext();
    if (captured) return captured;
    if (SMCContextHasValidManager(original)) {
        SMCCaptureContext(original,
            @"FBMobileConfigContextManager.sessionlessContextManager");
    }
    return original;
}

static id (*origSubclassSessionlessFactory)(id, SEL) = NULL;
static id newSubclassSessionlessFactory(id self, SEL _cmd) {
    id original = origSubclassSessionlessFactory
        ? origSubclassSessionlessFactory(self, _cmd)
        : nil;
    id captured = SCIValidatedSessionlessMobileConfigContext();
    if (captured) return captured;
    if (SMCContextHasValidManager(original)) {
        SMCCaptureContext(original,
            @"FBMobileConfigSessionlessContextManager.sessionlessContextManager");
    }
    return original;
}

#pragma mark - Early installation and image-load retries

static void SMCHookInstance(Class cls, NSString *name, const char *encoding,
                            IMP replacement, IMP *original) {
    if (!cls || !name.length || !replacement || !original || *original) return;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!SMCMethodMatches(method, encoding)) return;
    MSHookMessageEx(cls, selector, replacement, original);
}

static void SMCHookClass(Class cls, NSString *name, const char *encoding,
                         IMP replacement, IMP *original) {
    if (!cls || !name.length || !replacement || !original || *original) return;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getClassMethod(cls, selector);
    if (!SMCMethodMatches(method, encoding)) return;
    MSHookMessageEx(object_getClass(cls), selector, replacement, original);
}

static void SMCInstallCaptureHooks(void) {
    @synchronized (SCIDogfoodObjectRuntime.class) {
        static const char *sharedPtrEncoding =
            "@32@0:8{shared_ptr<mobileconfig::FBMobileConfigManager>="
            "^{FBMobileConfigManager}^{__shared_weak_count}}16";

        SMCHookInstance(NSClassFromString(@"IGMobileConfigSessionlessContextManager"),
            @"initWithManager:", sharedPtrEncoding,
            (IMP)newSessionlessInit, (IMP *)&origSessionlessInit);

        SMCHookInstance(NSClassFromString(@"FBMobileConfigFBTContextManager"),
            @"initWithFbtToMCIdMapping:mobileconfig:", "@32@0:8@16@24",
            (IMP)newFBTContextInit, (IMP *)&origFBTContextInit);

        Class global = NSClassFromString(@"FBMobileConfigFBTGlobalSessionManager");
        SMCHookInstance(global, @"setupFBTSessionlessContextManagerHolder:",
            "v24@0:8@16", (IMP)newSetupHolder, (IMP *)&origSetupHolder);
        SMCHookInstance(global, @"sessionlessContextManagerHolder", "@16@0:8",
            (IMP)newGetHolder, (IMP *)&origGetHolder);

        Class holder = NSClassFromString(@"FBMobileConfigFBTContextManagerHolder");
        SMCHookInstance(holder, @"setMcFbtManager:", "v24@0:8@16",
            (IMP)newSetFBTManager, (IMP *)&origSetFBTManager);
        SMCHookInstance(holder, @"mcFbtManager", "@16@0:8",
            (IMP)newGetFBTManager, (IMP *)&origGetFBTManager);

        Class fbt = NSClassFromString(@"FBMobileConfigFBTContextManager");
        SMCHookInstance(fbt, @"mobileconfig", "@16@0:8",
            (IMP)newGetMobileconfig, (IMP *)&origGetMobileconfig);

        SMCHookClass(NSClassFromString(@"FBMobileConfigContextManager"),
            @"sessionlessContextManager", "@16@0:8",
            (IMP)newBaseSessionlessFactory,
            (IMP *)&origBaseSessionlessFactory);
        SMCHookClass(NSClassFromString(@"FBMobileConfigSessionlessContextManager"),
            @"sessionlessContextManager", "@16@0:8",
            (IMP)newSubclassSessionlessFactory,
            (IMP *)&origSubclassSessionlessFactory);
    }
}

static void SMCImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    SMCInstallCaptureHooks();
}

__attribute__((constructor))
static void SCISessionlessMobileConfigEarlyCaptureCtor(void) {
    @autoreleasepool {
        // Install before UIApplicationDidBecomeActive. The previous deferred hook
        // missed initWithManager: and setupFBTSessionlessContextManagerHolder:.
        SMCInstallCaptureHooks();
        _dyld_register_func_for_add_image(SMCImageLoaded);
    }
}
