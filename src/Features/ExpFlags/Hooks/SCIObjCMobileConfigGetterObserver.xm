#import "../SCIExpFlags.h"
#import "../SCIMobileConfigMapping.h"
#import "../../../Utils.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kSCIObjCFocusEnabledKey = @"sci_exp_mc_objc_focus_enabled";
static NSString *const kSCIObjCFocusTargetKey = @"sci_exp_mc_objc_focus_target";
static NSString *const kSCIObjCVerboseKey = @"igt_runtime_mc_symbol_observer_verbose";
static NSString *const kSCIObjCAllowUnaryGetBoolKey = @"sci_exp_mc_objc_allow_getbool_unary";

typedef BOOL (*SCIObjCGetBoolIMP)(id, SEL, unsigned long long);
typedef BOOL (*SCIObjCGetBoolDefaultIMP)(id, SEL, unsigned long long, BOOL);
typedef BOOL (*SCIObjCGetBoolOptionsIMP)(id, SEL, unsigned long long, id);
typedef BOOL (*SCIObjCGetBoolOptionsDefaultIMP)(id, SEL, unsigned long long, id, BOOL);

static __thread int gSCIObjCReentryDepth = 0;

static NSMutableDictionary<NSString *, NSValue *> *SCIObjCOriginalIMPs(void) {
    static NSMutableDictionary<NSString *, NSValue *> *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

static NSMutableSet<NSString *> *SCIObjCInstalledKeys(void) {
    static NSMutableSet<NSString *> *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSMutableSet set]; });
    return s;
}

static NSMutableDictionary<NSString *, NSNumber *> *SCIObjCRecordCounts(void) {
    static NSMutableDictionary<NSString *, NSNumber *> *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

static NSString *SCIObjCKey(NSString *className, NSString *selectorName) {
    return [NSString stringWithFormat:@"%@|%@", className ?: @"", selectorName ?: @""];
}

static NSString *SCIObjCFocusTarget(void) {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kSCIObjCFocusTargetKey] ?: @"";
}

static BOOL SCIObjCIsActiveKey(NSString *key) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return [ud boolForKey:kSCIObjCFocusEnabledKey] && [SCIObjCFocusTarget() isEqualToString:key];
}

static IMP SCIObjCOriginalForKey(NSString *key) {
    NSValue *value = SCIObjCOriginalIMPs()[key ?: @""];
    return value ? (IMP)value.pointerValue : NULL;
}

static NSString *SCIObjCResolvedName(unsigned long long pid) {
    return [SCIMobileConfigMapping resolvedNameForParamID:pid];
}

static NSString *SCIObjCOverrideKey(unsigned long long pid) {
    NSString *resolved = SCIObjCResolvedName(pid);
    if (resolved.length) return resolved;
    return [NSString stringWithFormat:@"mc:0x%016llx", pid];
}

static SCIExpFlagOverride SCIObjCOverrideForParam(unsigned long long pid) {
    NSString *key = SCIObjCOverrideKey(pid);
    return [SCIExpFlags overrideForName:key];
}

static BOOL SCIObjCApplyOverride(SCIExpFlagOverride ov, BOOL original) {
    if (ov == SCIExpFlagOverrideTrue) return YES;
    if (ov == SCIExpFlagOverrideFalse) return NO;
    return original;
}

static BOOL SCIObjCShouldRecord(NSString *key, unsigned long long pid, BOOL changed, SCIExpFlagOverride ov) {
    if (changed || ov != SCIExpFlagOverrideOff) return YES;

    NSString *countKey = [NSString stringWithFormat:@"%@:%016llx", key ?: @"", pid];
    NSMutableDictionary *d = SCIObjCRecordCounts();

    @synchronized (d) {
        NSUInteger count = [d[countKey] unsignedIntegerValue] + 1;
        d[countKey] = @(count);
        return count <= 3 || (count % 512) == 0;
    }
}

static void SCIObjCRecordAsync(NSString *className,
                               NSString *selectorName,
                               unsigned long long pid,
                               BOOL defaultValue,
                               BOOL hasDefault,
                               BOOL original,
                               BOOL finalValue,
                               SCIExpFlagOverride ov) {
    NSString *classCopy = [className copy] ?: @"";
    NSString *selectorCopy = [selectorName copy] ?: @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *key = SCIObjCKey(classCopy, selectorCopy);
        if (!SCIObjCShouldRecord(key, pid, original != finalValue, ov)) return;
        NSString *resolved = SCIObjCResolvedName(pid);
        NSString *ovText = ov == SCIExpFlagOverrideTrue ? @"ForceON" : (ov == SCIExpFlagOverrideFalse ? @"ForceOFF" : @"Off");
        NSString *def = [NSString stringWithFormat:@"ObjC MobileConfig getter · safe=1 · target=%@ · name=%@ · default=%@ · original=%d · final=%d · override=%@ · shadowTrue=1 · wouldChangeIfTrue=%d",
                         key,
                         resolved ?: @"",
                         hasDefault ? (defaultValue ? @"YES" : @"NO") : @"n/a",
                         original,
                         finalValue,
                         ovText,
                         original ? 0 : 1];
        [SCIExpFlags recordMCParamID:pid
                                type:SCIExpMCTypeBool
                        defaultValue:def
                       originalValue:original ? @"YES" : @"NO"
                        contextClass:classCopy
                        selectorName:selectorCopy];
    });
}

static BOOL SCIObjCRecordAndReturn(NSString *className,
                                   NSString *selectorName,
                                   unsigned long long pid,
                                   BOOL defaultValue,
                                   BOOL hasDefault,
                                   BOOL original) {
    SCIExpFlagOverride ov = SCIObjCOverrideForParam(pid);
    BOOL finalValue = SCIObjCApplyOverride(ov, original);

    if (gSCIObjCReentryDepth <= 1) {
        SCIObjCRecordAsync(className, selectorName, pid, defaultValue, hasDefault, original, finalValue, ov);
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSCIObjCVerboseKey]) {
        NSLog(@"[RyukGram][MCObjCFocus] %@ %@ pid=0x%016llx original=%d final=%d",
              className, selectorName, pid, original, finalValue);
    }
    return finalValue;
}

static BOOL hook_getBool(id self, SEL _cmd, unsigned long long pid) {
    NSString *cls = NSStringFromClass(object_getClass(self));
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *key = SCIObjCKey(cls, sel);
    SCIObjCGetBoolIMP orig = (SCIObjCGetBoolIMP)SCIObjCOriginalForKey(key);
    if (gSCIObjCReentryDepth > 0) return orig ? orig(self, _cmd, pid) : NO;
    gSCIObjCReentryDepth++;
    BOOL original = orig ? orig(self, _cmd, pid) : NO;
    BOOL ret = SCIObjCIsActiveKey(key) ? SCIObjCRecordAndReturn(cls, sel, pid, NO, NO, original) : original;
    gSCIObjCReentryDepth--;
    return ret;
}

static BOOL hook_getBool_withDefault(id self, SEL _cmd, unsigned long long pid, BOOL def) {
    NSString *cls = NSStringFromClass(object_getClass(self));
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *key = SCIObjCKey(cls, sel);
    SCIObjCGetBoolDefaultIMP orig = (SCIObjCGetBoolDefaultIMP)SCIObjCOriginalForKey(key);
    if (gSCIObjCReentryDepth > 0) return orig ? orig(self, _cmd, pid, def) : def;
    gSCIObjCReentryDepth++;
    BOOL original = orig ? orig(self, _cmd, pid, def) : def;
    BOOL ret = SCIObjCIsActiveKey(key) ? SCIObjCRecordAndReturn(cls, sel, pid, def, YES, original) : original;
    gSCIObjCReentryDepth--;
    return ret;
}

static BOOL hook_getBool_withOptions(id self, SEL _cmd, unsigned long long pid, id options) {
    NSString *cls = NSStringFromClass(object_getClass(self));
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *key = SCIObjCKey(cls, sel);
    SCIObjCGetBoolOptionsIMP orig = (SCIObjCGetBoolOptionsIMP)SCIObjCOriginalForKey(key);
    if (gSCIObjCReentryDepth > 0) return orig ? orig(self, _cmd, pid, options) : NO;
    gSCIObjCReentryDepth++;
    BOOL original = orig ? orig(self, _cmd, pid, options) : NO;
    BOOL ret = SCIObjCIsActiveKey(key) ? SCIObjCRecordAndReturn(cls, sel, pid, NO, NO, original) : original;
    gSCIObjCReentryDepth--;
    return ret;
}

static BOOL hook_getBool_withOptions_withDefault(id self, SEL _cmd, unsigned long long pid, id options, BOOL def) {
    NSString *cls = NSStringFromClass(object_getClass(self));
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *key = SCIObjCKey(cls, sel);
    SCIObjCGetBoolOptionsDefaultIMP orig = (SCIObjCGetBoolOptionsDefaultIMP)SCIObjCOriginalForKey(key);
    if (gSCIObjCReentryDepth > 0) return orig ? orig(self, _cmd, pid, options, def) : def;
    gSCIObjCReentryDepth++;
    BOOL original = orig ? orig(self, _cmd, pid, options, def) : def;
    BOOL ret = SCIObjCIsActiveKey(key) ? SCIObjCRecordAndReturn(cls, sel, pid, def, YES, original) : original;
    gSCIObjCReentryDepth--;
    return ret;
}

static IMP SCIObjCNewIMPForSelector(NSString *selectorName) {
    if ([selectorName isEqualToString:@"getBool:"]) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kSCIObjCAllowUnaryGetBoolKey]) return NULL;
        return (IMP)hook_getBool;
    }
    if ([selectorName isEqualToString:@"getBool:withDefault:"]) return (IMP)hook_getBool_withDefault;
    if ([selectorName isEqualToString:@"getBool:withOptions:"]) return (IMP)hook_getBool_withOptions;
    if ([selectorName isEqualToString:@"getBool:withOptions:withDefault:"]) return (IMP)hook_getBool_withOptions_withDefault;
    return NULL;
}

static BOOL SCIClassDefinesInstanceSelector(Class cls, SEL sel) {
    if (!cls || !sel) return NO;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; methods && i < count; i++) {
        if (method_getName(methods[i]) == sel) { found = YES; break; }
    }
    if (methods) free(methods);
    return found;
}

static BOOL SCIMethodHasExpectedBoolSignature(Class cls, SEL sel, NSString *selectorName) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    char ret[16] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (!(ret[0] == 'B' || ret[0] == 'c')) return NO;

    unsigned int argc = method_getNumberOfArguments(m);
    if ([selectorName isEqualToString:@"getBool:"]) return argc == 3;
    if ([selectorName isEqualToString:@"getBool:withDefault:"]) return argc == 4;
    if ([selectorName isEqualToString:@"getBool:withOptions:"]) return argc == 4;
    if ([selectorName isEqualToString:@"getBool:withOptions:withDefault:"]) return argc == 5;
    return NO;
}

static void SCIInstallOneFocusedObjCGetter(NSString *className, NSString *selectorName) {
    if (!className.length || !selectorName.length) return;
    NSString *key = SCIObjCKey(className, selectorName);
    if ([SCIObjCInstalledKeys() containsObject:key]) return;

    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selectorName);
    if (!SCIClassDefinesInstanceSelector(cls, sel)) {
        NSLog(@"[RyukGram][MCObjCFocus] skip inherited/missing %@", key);
        return;
    }
    if (!SCIMethodHasExpectedBoolSignature(cls, sel, selectorName)) {
        NSLog(@"[RyukGram][MCObjCFocus] skip bad signature %@", key);
        return;
    }
    IMP newImp = SCIObjCNewIMPForSelector(selectorName);
    if (!newImp) {
        NSLog(@"[RyukGram][MCObjCFocus] skip disabled selector %@", key);
        return;
    }

    IMP original = NULL;
    MSHookMessageEx(cls, sel, newImp, &original);
    if (original) {
        SCIObjCOriginalIMPs()[key] = [NSValue valueWithPointer:(const void *)original];
        [SCIObjCInstalledKeys() addObject:key];
        NSLog(@"[RyukGram][MCObjCFocus] installed %@", key);
    }
}

extern "C" void SCIInstallFocusedObjCGetterObserver(void) {
    NSString *target = SCIObjCFocusTarget();
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSCIObjCFocusEnabledKey] || !target.length || [target isEqualToString:@"off"]) return;
    NSArray<NSString *> *parts = [target componentsSeparatedByString:@"|"];
    if (parts.count != 2) return;
    SCIInstallOneFocusedObjCGetter(parts[0], parts[1]);
}

%ctor {
    NSDictionary *defaults = @{
        @"sci_exp_flags_enabled": @YES,
        @"sci_exp_mc_c_hooks_enabled": @NO,
        @"sci_exp_mc_hooks_enabled": @NO,
        kSCIObjCFocusEnabledKey: @NO,
        kSCIObjCFocusTargetKey: @"off",
        kSCIObjCVerboseKey: @NO,
        kSCIObjCAllowUnaryGetBoolKey: @NO
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    SCIInstallFocusedObjCGetterObserver();
}
