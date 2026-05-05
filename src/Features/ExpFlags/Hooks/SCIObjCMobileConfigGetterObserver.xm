#import "../SCIExpFlags.h"
#import "../SCIMobileConfigMapping.h"
#import "../../../Utils.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kSCIObjCFocusEnabledKey = @"sci_exp_mc_objc_focus_enabled";
static NSString *const kSCIObjCFocusTargetKey = @"sci_exp_mc_objc_focus_target";
static NSString *const kSCIObjCVerboseKey = @"igt_runtime_mc_symbol_observer_verbose";

typedef BOOL (*SCIObjCGetBoolIMP)(id, SEL, unsigned long long);
typedef BOOL (*SCIObjCGetBoolDefaultIMP)(id, SEL, unsigned long long, BOOL);
typedef BOOL (*SCIObjCGetBoolOptionsIMP)(id, SEL, unsigned long long, id);
typedef BOOL (*SCIObjCGetBoolOptionsDefaultIMP)(id, SEL, unsigned long long, id, BOOL);
typedef BOOL (*SCIObjCGetBoolStringDefaultIMP)(id, SEL, id, BOOL);

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
        return count <= 8 || (count % 256) == 0;
    }
}

static BOOL SCIObjCRecordAndReturn(NSString *className,
                                   NSString *selectorName,
                                   unsigned long long pid,
                                   BOOL defaultValue,
                                   BOOL hasDefault,
                                   BOOL original) {
    NSString *key = SCIObjCKey(className, selectorName);
    SCIExpFlagOverride ov = SCIObjCOverrideForParam(pid);
    BOOL finalValue = SCIObjCApplyOverride(ov, original);
    BOOL changed = (original != finalValue);

    if (SCIObjCShouldRecord(key, pid, changed || !original, ov)) {
        NSString *resolved = SCIObjCResolvedName(pid);
        NSString *ovText = ov == SCIExpFlagOverrideTrue ? @"ForceON" : (ov == SCIExpFlagOverrideFalse ? @"ForceOFF" : @"Off");
        NSString *def = [NSString stringWithFormat:@"ObjC MobileConfig getter · focused=1 · target=%@ · name=%@ · default=%@ · original=%d · final=%d · override=%@ · shadowTrue=1 · wouldChangeIfTrue=%d",
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
                        contextClass:className
                        selectorName:selectorName];
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
    BOOL original = orig ? orig(self, _cmd, pid) : NO;
    if (!SCIObjCIsActiveKey(key)) return original;
    return SCIObjCRecordAndReturn(cls, sel, pid, NO, NO, original);
}

static BOOL hook_getBool_withDefault(id self, SEL _cmd, unsigned long long pid, BOOL def) {
    NSString *cls = NSStringFromClass(object_getClass(self));
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *key = SCIObjCKey(cls, sel);
    SCIObjCGetBoolDefaultIMP orig = (SCIObjCGetBoolDefaultIMP)SCIObjCOriginalForKey(key);
    BOOL original = orig ? orig(self, _cmd, pid, def) : def;
    if (!SCIObjCIsActiveKey(key)) return original;
    return SCIObjCRecordAndReturn(cls, sel, pid, def, YES, original);
}

static BOOL hook_getBool_withOptions(id self, SEL _cmd, unsigned long long pid, id options) {
    NSString *cls = NSStringFromClass(object_getClass(self));
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *key = SCIObjCKey(cls, sel);
    SCIObjCGetBoolOptionsIMP orig = (SCIObjCGetBoolOptionsIMP)SCIObjCOriginalForKey(key);
    BOOL original = orig ? orig(self, _cmd, pid, options) : NO;
    if (!SCIObjCIsActiveKey(key)) return original;
    return SCIObjCRecordAndReturn(cls, sel, pid, NO, NO, original);
}

static BOOL hook_getBool_withOptions_withDefault(id self, SEL _cmd, unsigned long long pid, id options, BOOL def) {
    NSString *cls = NSStringFromClass(object_getClass(self));
    NSString *sel = NSStringFromSelector(_cmd);
    NSString *key = SCIObjCKey(cls, sel);
    SCIObjCGetBoolOptionsDefaultIMP orig = (SCIObjCGetBoolOptionsDefaultIMP)SCIObjCOriginalForKey(key);
    BOOL original = orig ? orig(self, _cmd, pid, options, def) : def;
    if (!SCIObjCIsActiveKey(key)) return original;
    return SCIObjCRecordAndReturn(cls, sel, pid, def, YES, original);
}

static IMP SCIObjCNewIMPForSelector(NSString *selectorName) {
    if ([selectorName isEqualToString:@"getBool:"]) return (IMP)hook_getBool;
    if ([selectorName isEqualToString:@"getBool:withDefault:"]) return (IMP)hook_getBool_withDefault;
    if ([selectorName isEqualToString:@"getBool:withOptions:"]) return (IMP)hook_getBool_withOptions;
    if ([selectorName isEqualToString:@"getBool:withOptions:withDefault:"]) return (IMP)hook_getBool_withOptions_withDefault;
    return NULL;
}

static void SCIInstallOneFocusedObjCGetter(NSString *className, NSString *selectorName) {
    if (!className.length || !selectorName.length) return;
    NSString *key = SCIObjCKey(className, selectorName);
    if ([SCIObjCInstalledKeys() containsObject:key]) return;

    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selectorName);
    if (!class_getInstanceMethod(cls, sel)) return;
    IMP newImp = SCIObjCNewIMPForSelector(selectorName);
    if (!newImp) return;

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
        @"sci_exp_mc_c_hooks_enabled": @YES,
        @"sci_exp_mc_hooks_enabled": @NO,
        kSCIObjCFocusEnabledKey: @NO,
        kSCIObjCFocusTargetKey: @"off",
        kSCIObjCVerboseKey: @NO
    };
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    SCIInstallFocusedObjCGetterObserver();
}
