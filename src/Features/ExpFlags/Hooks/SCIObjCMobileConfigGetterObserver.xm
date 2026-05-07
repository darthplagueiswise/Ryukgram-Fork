#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>
#import <dlfcn.h>
#import "../SCIExpFlags.h"
#import "../SCIDexKitNameResolver.h"

static NSString *const kHooksKey = @"sci_exp_mc_objc_getter_observer_enabled";
static NSString *const kStartupKey = @"sci_exp_mc_objc_startup_hooks_enabled";
static NSString *const kStoreKey = @"sci_exp_overrides_by_name";
static NSString *const kApplyOverridesKey = @"sci_exp_mc_objc_apply_overrides_enabled";

static NSMutableDictionary<NSString *, NSValue *> *gOrig;
static NSDictionary<NSString *, NSNumber *> *gOverrides;
static NSMutableDictionary<NSString *, NSNumber *> *gHits;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL gInstalled = NO;
static __thread BOOL gInside = NO;

static NSString *SCIKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

static NSString *SCIClassName(id obj) {
    Class cls = obj ? [obj class] : Nil;
    return cls ? NSStringFromClass(cls) : @"?";
}

static NSString *SCIBrokerIDForObject(id obj) {
    NSString *cls = SCIClassName(obj);
    if ([cls containsString:@"Sessionless"]) return @"igsl";
    if ([cls hasPrefix:@"FBMobileConfig"]) return @"fb";
    return @"ig";
}

static NSString *SCIHexOverrideKey(uint64_t value) {
    return [NSString stringWithFormat:@"mc:0x%016llx", (unsigned long long)value];
}

static IMP SCIOrigFor(id obj, SEL sel) {
    Class cls = obj ? [obj class] : Nil;
    pthread_mutex_lock(&gLock);
    while (cls) {
        NSValue *value = gOrig[SCIKey(cls, sel)];
        if (value) {
            IMP imp = (IMP)(uintptr_t)value.pointerValue;
            pthread_mutex_unlock(&gLock);
            return imp;
        }
        cls = class_getSuperclass(cls);
    }
    pthread_mutex_unlock(&gLock);
    return NULL;
}

static void SCIRefreshOverrides(void) {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kStoreKey];
    pthread_mutex_lock(&gLock);
    gOverrides = dict ? [dict copy] : @{};
    pthread_mutex_unlock(&gLock);
}

static SCIExpFlagOverride SCIOverrideForKey(NSString *key) {
    if (!key.length) return SCIExpFlagOverrideOff;
    pthread_mutex_lock(&gLock);
    NSNumber *value = gOverrides[key];
    pthread_mutex_unlock(&gLock);
    return value ? (SCIExpFlagOverride)value.integerValue : SCIExpFlagOverrideOff;
}

static BOOL SCIApplyOverridesEnabled(void) {
    id enabled = [[NSUserDefaults standardUserDefaults] objectForKey:kApplyOverridesKey];
    return enabled && [enabled boolValue];
}

static BOOL SCIApplyOverrideValue(SCIExpFlagOverride override, BOOL original) {
    if (override == SCIExpFlagOverrideTrue) return YES;
    if (override == SCIExpFlagOverrideFalse) return NO;
    return original;
}

static NSString *SCIOverrideText(SCIExpFlagOverride override) {
    if (override == SCIExpFlagOverrideTrue) return @"ForceON";
    if (override == SCIExpFlagOverrideFalse) return @"ForceOFF";
    return @"Off";
}

static SCIExpFlagOverride SCIOverrideForSpecifier(uint64_t specifier, NSString *brokerID) {
    NSString *bid = brokerID.length ? brokerID : @"ig";
    uint64_t normalized = [SCIDexKitNameResolver normalizedSpecifierValue:specifier];

    SCIDexKitResolvedName *resolved = [SCIDexKitNameResolver resolveBrokerID:bid value:specifier];
    if (resolved.name.length) {
        SCIExpFlagOverride byName = SCIOverrideForKey(resolved.name);
        if (byName != SCIExpFlagOverrideOff) return byName;
    }

    NSArray<NSString *> *keys = @[
        [NSString stringWithFormat:@"mcbr:%@:%016llx", bid, (unsigned long long)specifier],
        [NSString stringWithFormat:@"mcbr:%@:%016llx", bid, (unsigned long long)normalized],
        SCIHexOverrideKey(specifier),
        SCIHexOverrideKey(normalized)
    ];
    for (NSString *key in keys) {
        SCIExpFlagOverride override = SCIOverrideForKey(key);
        if (override != SCIExpFlagOverrideOff) return override;
    }
    return SCIExpFlagOverrideOff;
}

static BOOL SCIShouldRecord(uint64_t specifier, SEL sel) {
    NSString *key = [NSString stringWithFormat:@"%@:%016llx", NSStringFromSelector(sel), (unsigned long long)specifier];
    pthread_mutex_lock(&gLock);
    if (!gHits) gHits = [NSMutableDictionary dictionary];
    NSUInteger count = gHits[key].unsignedIntegerValue + 1;
    gHits[key] = @(count);
    pthread_mutex_unlock(&gLock);
    return count <= 2 || (count % 2048) == 0;
}

static void SCIResolveCaller(void *address, NSString **imageOut, NSString **symbolOut) {
    if (imageOut) *imageOut = nil;
    if (symbolOut) *symbolOut = nil;
    if (!address) return;
    Dl_info info = {0};
    if (!dladdr(address, &info)) return;
    if (imageOut && info.dli_fname) *imageOut = [@(info.dli_fname) lastPathComponent];
    if (symbolOut && info.dli_sname) *symbolOut = @(info.dli_sname);
}

static void SCIRecordBoolRead(id obj, SEL sel, uint64_t specifier, BOOL defaultValue, BOOL originalValue, BOOL finalValue, SCIExpFlagOverride override, NSString *source, void *caller) {
    NSString *className = SCIClassName(obj);
    NSString *selectorName = NSStringFromSelector(sel);
    NSString *brokerID = SCIBrokerIDForObject(obj);
    NSString *callerImage = nil;
    NSString *callerSymbol = nil;
    SCIResolveCaller(caller, &callerImage, &callerSymbol);

    [SCIDexKitNameResolver noteMobileConfigBoolReadWithClassName:className
                                                        selector:selectorName
                                                       specifier:specifier
                                                    defaultValue:defaultValue
                                                   originalValue:originalValue
                                                      finalValue:finalValue
                                                          source:(source.length ? source : @"objc-getBool")
                                                     callerImage:callerImage
                                                    callerSymbol:callerSymbol
                                                   callerAddress:(uint64_t)(uintptr_t)caller];

    if (!SCIShouldRecord(specifier, sel)) return;

    SCIDexKitResolvedName *resolved = [SCIDexKitNameResolver resolveBrokerID:brokerID value:specifier];
    NSString *title = resolved.name.length ? resolved.name : (resolved.title ?: @"");
    NSString *detail = [NSString stringWithFormat:@"source=%@ · context=%@ · selector=%@ · broker=%@ · caller=%@/%@ · title=%@ · detail=%@ · default=%d · original=%d · final=%d · override=%@",
                        source.length ? source : @"objc-getBool",
                        className,
                        selectorName,
                        brokerID,
                        callerImage ?: @"",
                        callerSymbol ?: @"",
                        title,
                        resolved.detail ?: @"",
                        defaultValue ? 1 : 0,
                        originalValue ? 1 : 0,
                        finalValue ? 1 : 0,
                        SCIOverrideText(override)];

    [SCIExpFlags recordMCParamID:specifier
                            type:SCIExpMCTypeBool
                    defaultValue:detail
                   originalValue:originalValue ? @"YES" : @"NO"
                    contextClass:className
                    selectorName:selectorName];
}

static BOOL SCIHookGetBool(id obj, SEL sel, uint64_t specifier) {
    void *caller = __builtin_return_address(0);
    BOOL (*orig)(id, SEL, uint64_t) = (BOOL (*)(id, SEL, uint64_t))SCIOrigFor(obj, sel);
    if (gInside) return orig ? orig(obj, sel, specifier) : NO;
    gInside = YES;
    BOOL original = orig ? orig(obj, sel, specifier) : NO;
    BOOL apply = SCIApplyOverridesEnabled();
    SCIExpFlagOverride override = apply ? SCIOverrideForSpecifier(specifier, SCIBrokerIDForObject(obj)) : SCIExpFlagOverrideOff;
    BOOL finalValue = apply ? SCIApplyOverrideValue(override, original) : original;
    SCIRecordBoolRead(obj, sel, specifier, original, original, finalValue, override, @"objc-getBool", caller);
    gInside = NO;
    return finalValue;
}

static BOOL SCIHookGetBoolDefault(id obj, SEL sel, uint64_t specifier, BOOL defaultValue) {
    void *caller = __builtin_return_address(0);
    BOOL (*orig)(id, SEL, uint64_t, BOOL) = (BOOL (*)(id, SEL, uint64_t, BOOL))SCIOrigFor(obj, sel);
    if (gInside) return orig ? orig(obj, sel, specifier, defaultValue) : defaultValue;
    gInside = YES;
    BOOL original = orig ? orig(obj, sel, specifier, defaultValue) : defaultValue;
    BOOL apply = SCIApplyOverridesEnabled();
    SCIExpFlagOverride override = apply ? SCIOverrideForSpecifier(specifier, SCIBrokerIDForObject(obj)) : SCIExpFlagOverrideOff;
    BOOL finalValue = apply ? SCIApplyOverrideValue(override, original) : original;
    SCIRecordBoolRead(obj, sel, specifier, defaultValue, original, finalValue, override, @"objc-getBool", caller);
    gInside = NO;
    return finalValue;
}

static BOOL SCIHookGetBoolOptions(id obj, SEL sel, uint64_t specifier, void *options) {
    void *caller = __builtin_return_address(0);
    BOOL (*orig)(id, SEL, uint64_t, void *) = (BOOL (*)(id, SEL, uint64_t, void *))SCIOrigFor(obj, sel);
    if (gInside) return orig ? orig(obj, sel, specifier, options) : NO;
    gInside = YES;
    BOOL original = orig ? orig(obj, sel, specifier, options) : NO;
    BOOL apply = SCIApplyOverridesEnabled();
    SCIExpFlagOverride override = apply ? SCIOverrideForSpecifier(specifier, SCIBrokerIDForObject(obj)) : SCIExpFlagOverrideOff;
    BOOL finalValue = apply ? SCIApplyOverrideValue(override, original) : original;
    SCIRecordBoolRead(obj, sel, specifier, original, original, finalValue, override, @"objc-getBool", caller);
    gInside = NO;
    return finalValue;
}

static BOOL SCIHookGetBoolOptionsDefault(id obj, SEL sel, uint64_t specifier, void *options, BOOL defaultValue) {
    void *caller = __builtin_return_address(0);
    BOOL (*orig)(id, SEL, uint64_t, void *, BOOL) = (BOOL (*)(id, SEL, uint64_t, void *, BOOL))SCIOrigFor(obj, sel);
    if (gInside) return orig ? orig(obj, sel, specifier, options, defaultValue) : defaultValue;
    gInside = YES;
    BOOL original = orig ? orig(obj, sel, specifier, options, defaultValue) : defaultValue;
    BOOL apply = SCIApplyOverridesEnabled();
    SCIExpFlagOverride override = apply ? SCIOverrideForSpecifier(specifier, SCIBrokerIDForObject(obj)) : SCIExpFlagOverrideOff;
    BOOL finalValue = apply ? SCIApplyOverrideValue(override, original) : original;
    SCIRecordBoolRead(obj, sel, specifier, defaultValue, original, finalValue, override, @"objc-getBool", caller);
    gInside = NO;
    return finalValue;
}

static BOOL SCIMethodSizeOK(Class cls, SEL sel, NSUInteger argc, NSUInteger retSizeWanted, NSUInteger arg2SizeWanted) {
    if (!cls || !sel) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != argc) return NO;
    char ret[128] = {0};
    char arg[128] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    method_getArgumentType(method, 2, arg, sizeof(arg));
    NSUInteger retSize = 0;
    NSUInteger argSize = 0;
    NSGetSizeAndAlignment(ret, &retSize, NULL);
    NSGetSizeAndAlignment(arg, &argSize, NULL);
    return retSize == retSizeWanted && argSize == arg2SizeWanted;
}

static BOOL SCIMethodLooksBoolU64(Class cls, SEL sel, NSUInteger argc) {
    return SCIMethodSizeOK(cls, sel, argc, sizeof(BOOL), sizeof(uint64_t));
}

static BOOL SCIMethodLooksU64ToU64(Class cls, SEL sel) {
    return SCIMethodSizeOK(cls, sel, 3, sizeof(uint64_t), sizeof(uint64_t));
}

static uint64_t SCIHookAlias(id obj, SEL sel, uint64_t raw) {
    uint64_t (*orig)(id, SEL, uint64_t) = (uint64_t (*)(id, SEL, uint64_t))SCIOrigFor(obj, sel);
    if (gInside) return orig ? orig(obj, sel, raw) : raw;
    gInside = YES;
    uint64_t translated = orig ? orig(obj, sel, raw) : raw;
    gInside = NO;
    if (raw && translated && raw != translated) {
        NSString *source = [NSString stringWithFormat:@"%@ %@", SCIClassName(obj), NSStringFromSelector(sel)];
        [SCIDexKitNameResolver noteAliasFromSpecifier:raw toSpecifier:translated source:source];
    }
    return translated;
}

static void SCIInstallOne(Class cls, NSString *selectorName, IMP replacement) {
    if (!cls || !selectorName.length || !replacement) return;
    SEL sel = NSSelectorFromString(selectorName);
    if (!class_getInstanceMethod(cls, sel)) return;
    NSString *key = SCIKey(cls, sel);
    pthread_mutex_lock(&gLock);
    BOOL alreadyInstalled = gOrig[key] != nil;
    pthread_mutex_unlock(&gLock);
    if (alreadyInstalled) return;
    IMP old = NULL;
    MSHookMessageEx(cls, sel, replacement, &old);
    if (!old) return;
    pthread_mutex_lock(&gLock);
    if (!gOrig) gOrig = [NSMutableDictionary dictionary];
    gOrig[key] = [NSValue valueWithPointer:(const void *)(uintptr_t)old];
    pthread_mutex_unlock(&gLock);
}

static void SCIInstallBoolHook(Class cls, NSString *selectorName, NSUInteger argc, IMP replacement) {
    SEL sel = NSSelectorFromString(selectorName);
    if (SCIMethodLooksBoolU64(cls, sel, argc)) SCIInstallOne(cls, selectorName, replacement);
}

static void SCIInstallAliasHook(Class cls, NSString *selectorName) {
    SEL sel = NSSelectorFromString(selectorName);
    if (SCIMethodLooksU64ToU64(cls, sel)) SCIInstallOne(cls, selectorName, (IMP)SCIHookAlias);
}

static void SCIInstallClassHooks(NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SCIInstallBoolHook(cls, @"getBool:", 3, (IMP)SCIHookGetBool);
    SCIInstallBoolHook(cls, @"getBool:withDefault:", 4, (IMP)SCIHookGetBoolDefault);
    SCIInstallBoolHook(cls, @"getBool:withOptions:", 4, (IMP)SCIHookGetBoolOptions);
    SCIInstallBoolHook(cls, @"getBool:withOptions:withDefault:", 5, (IMP)SCIHookGetBoolOptionsDefault);
    SCIInstallBoolHook(cls, @"getBoolWithoutLogging:", 3, (IMP)SCIHookGetBool);
    SCIInstallBoolHook(cls, @"getBoolWithoutLogging:withDefault:", 4, (IMP)SCIHookGetBoolDefault);
    SCIInstallAliasHook(cls, @"_getTranslatedSpecifier:");
    SCIInstallAliasHook(cls, @"getStableIdFromParamSpecifier:");
}

static void SCIInstallAllObjCObserverHooks(void) {
    if (gInstalled) return;
    gInstalled = YES;
    SCIRefreshOverrides();
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
        SCIRefreshOverrides();
    }];
    for (NSString *className in @[
        @"IGMobileConfigContextManager",
        @"IGMobileConfigSessionlessContextManager",
        @"IGMobileConfigUserSessionContextManager",
        @"FBMobileConfigContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigContextObjcImpl"
    ]) {
        SCIInstallClassHooks(className);
    }
    NSLog(@"[RyukGram][MCObjCObserver] installed explicit pass-through ObjC MobileConfig observer feeding SCIDexKitNameResolver");
}

__attribute__((visibility("default"))) void SCIInstallFocusedObjCGetterObserver(void) {
    SCIInstallAllObjCObserverHooks();
}

__attribute__((visibility("default"))) void SCIInstallObjCMobileConfigGetterObserver(void) {
    SCIInstallAllObjCObserverHooks();
}

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kHooksKey: @NO,
        kStartupKey: @NO,
        kApplyOverridesKey: @NO,
        @"sci_exp_mc_c_hooks_enabled": @NO,
        @"sci_exp_mc_hooks_enabled": @NO
    }];
    // Launch-safe by design: no ObjC MobileConfig methods are hooked from %ctor.
    // MC Broker / focused lab can opt in by calling SCIInstallObjCMobileConfigGetterObserver()
    // or SCIInstallFocusedObjCGetterObserver().
}
