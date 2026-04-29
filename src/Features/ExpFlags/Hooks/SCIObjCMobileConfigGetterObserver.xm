#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../SCIExpFlags.h"
#import "../SCIExpMobileConfigMapping.h"
#import "../../../Utils.h"

static NSMutableDictionary<NSString *, NSValue *> *SCIObjCMCOriginalIMPs;

static NSString *SCIObjCMCKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

static NSString *SCIObjCMCHex(unsigned long long pid) {
    return [NSString stringWithFormat:@"mc:0x%016llx", pid];
}

static IMP SCIObjCMCOriginalIMP(id self, SEL sel) {
    Class cls = [self class];
    while (cls) {
        NSValue *value = SCIObjCMCOriginalIMPs[SCIObjCMCKey(cls, sel)];
        if (value) return value.pointerValue;
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

static NSString *SCIObjCMCContextName(id self) {
    Class cls = [self class];
    return cls ? NSStringFromClass(cls) : @"?";
}

static NSString *SCIObjCMCNameFromObject(id name) {
    if (!name) return nil;
    NSString *s = [name isKindOfClass:NSString.class] ? (NSString *)name : [name description];
    return s.length ? s : nil;
}

static SCIExpFlagOverride SCIObjCMCOverrideForParam(unsigned long long pid) {
    NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:pid];
    if (mapped.length) {
        SCIExpFlagOverride ov = [SCIExpFlags overrideForName:mapped];
        if (ov != SCIExpFlagOverrideOff) return ov;
    }

    return [SCIExpFlags overrideForName:SCIObjCMCHex(pid)];
}

static SCIExpFlagOverride SCIObjCMCOverrideForName(id name) {
    NSString *s = SCIObjCMCNameFromObject(name);
    if (!s.length) return SCIExpFlagOverrideOff;
    return [SCIExpFlags overrideForName:s];
}

static BOOL SCIObjCMCApplyOverride(SCIExpFlagOverride ov, BOOL original) {
    if (ov == SCIExpFlagOverrideTrue) return YES;
    if (ov == SCIExpFlagOverrideFalse) return NO;
    return original;
}

static NSString *SCIObjCMCOverrideText(SCIExpFlagOverride ov) {
    if (ov == SCIExpFlagOverrideTrue) return @"ForceON";
    if (ov == SCIExpFlagOverrideFalse) return @"ForceOFF";
    return @"Off";
}

static void SCIObjCMCRecord(id self,
                            SEL sel,
                            unsigned long long pid,
                            NSString *explicitName,
                            BOOL defaultValue,
                            BOOL originalValue,
                            BOOL finalValue,
                            SCIExpFlagOverride overrideState) {
    NSString *namePart = explicitName.length ? [NSString stringWithFormat:@" · name=%@", explicitName] : @"";
    NSString *detail = [NSString stringWithFormat:@"source=ObjC MobileConfig getter · selector=%@ · context=%@%@ · default=%d · original=%d · final=%d · override=%@ · shadowTrue=1 · wouldChangeIfTrue=%d",
                        NSStringFromSelector(sel),
                        SCIObjCMCContextName(self),
                        namePart,
                        defaultValue,
                        originalValue,
                        finalValue,
                        SCIObjCMCOverrideText(overrideState),
                        originalValue ? 0 : 1];

    [SCIExpFlags recordMCParamID:pid
                            type:SCIExpMCTypeBool
                    defaultValue:detail
                   originalValue:originalValue ? @"YES" : @"NO"
                    contextClass:SCIObjCMCContextName(self)
                    selectorName:NSStringFromSelector(sel)];
}

static BOOL SCIObjCMCGetBool(id self, SEL sel, unsigned long long pid) {
    BOOL (*orig)(id, SEL, unsigned long long) = (BOOL (*)(id, SEL, unsigned long long))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, pid) : NO;
    SCIExpFlagOverride ov = SCIObjCMCOverrideForParam(pid);
    BOOL finalValue = SCIObjCMCApplyOverride(ov, original);
    SCIObjCMCRecord(self, sel, pid, nil, original, original, finalValue, ov);
    return finalValue;
}

static BOOL SCIObjCMCGetBoolDefault(id self, SEL sel, unsigned long long pid, BOOL def) {
    BOOL (*orig)(id, SEL, unsigned long long, BOOL) = (BOOL (*)(id, SEL, unsigned long long, BOOL))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, pid, def) : def;
    SCIExpFlagOverride ov = SCIObjCMCOverrideForParam(pid);
    BOOL finalValue = SCIObjCMCApplyOverride(ov, original);
    SCIObjCMCRecord(self, sel, pid, nil, def, original, finalValue, ov);
    return finalValue;
}

static BOOL SCIObjCMCGetBoolOptions(id self, SEL sel, unsigned long long pid, id options) {
    BOOL (*orig)(id, SEL, unsigned long long, id) = (BOOL (*)(id, SEL, unsigned long long, id))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, pid, options) : NO;
    SCIExpFlagOverride ov = SCIObjCMCOverrideForParam(pid);
    BOOL finalValue = SCIObjCMCApplyOverride(ov, original);
    SCIObjCMCRecord(self, sel, pid, nil, original, original, finalValue, ov);
    return finalValue;
}

static BOOL SCIObjCMCGetBoolOptionsDefault(id self, SEL sel, unsigned long long pid, id options, BOOL def) {
    BOOL (*orig)(id, SEL, unsigned long long, id, BOOL) = (BOOL (*)(id, SEL, unsigned long long, id, BOOL))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, pid, options, def) : def;
    SCIExpFlagOverride ov = SCIObjCMCOverrideForParam(pid);
    BOOL finalValue = SCIObjCMCApplyOverride(ov, original);
    SCIObjCMCRecord(self, sel, pid, nil, def, original, finalValue, ov);
    return finalValue;
}

static BOOL SCIObjCMCGetBoolNameDefault(id self, SEL sel, id name, BOOL def) {
    BOOL (*orig)(id, SEL, id, BOOL) = (BOOL (*)(id, SEL, id, BOOL))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, name, def) : def;
    NSString *explicitName = SCIObjCMCNameFromObject(name);
    unsigned long long pseudo = explicitName.length ? (unsigned long long)explicitName.hash : 0;
    SCIExpFlagOverride ov = SCIObjCMCOverrideForName(name);
    BOOL finalValue = SCIObjCMCApplyOverride(ov, original);
    SCIObjCMCRecord(self, sel, pseudo, explicitName, def, original, finalValue, ov);
    return finalValue;
}

static void SCIObjCMCInstall(Class cls, NSString *selectorName, IMP replacement) {
    if (!cls || !selectorName.length || !replacement) return;

    SEL sel = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;

    IMP original = NULL;
    MSHookMessageEx(cls, sel, replacement, &original);
    if (!SCIObjCMCOriginalIMPs) SCIObjCMCOriginalIMPs = [NSMutableDictionary dictionary];
    if (original) SCIObjCMCOriginalIMPs[SCIObjCMCKey(cls, sel)] = [NSValue valueWithPointer:original];
}

static void SCIObjCMCInstallCommonGetters(NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return;

    SCIObjCMCInstall(cls, @"getBool:", (IMP)SCIObjCMCGetBool);
    SCIObjCMCInstall(cls, @"getBool:withDefault:", (IMP)SCIObjCMCGetBoolDefault);
    SCIObjCMCInstall(cls, @"getBool:withOptions:", (IMP)SCIObjCMCGetBoolOptions);
    SCIObjCMCInstall(cls, @"getBool:withOptions:withDefault:", (IMP)SCIObjCMCGetBoolOptionsDefault);
    SCIObjCMCInstall(cls, @"getBoolWithoutLogging:", (IMP)SCIObjCMCGetBool);
    SCIObjCMCInstall(cls, @"getBoolWithoutLogging:withDefault:", (IMP)SCIObjCMCGetBoolDefault);
}

%ctor {
    if (![SCIUtils getBoolPref:@"sci_exp_flags_enabled"] && ![SCIUtils getBoolPref:@"sci_exp_mc_hooks_enabled"]) return;

    NSArray<NSString *> *classes = @[
        @"FBMobileConfigContextManager",
        @"IGMobileConfigContextManager",
        @"IGMobileConfigSessionlessContextManager",
        @"IGMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigContextObjcImpl"
    ];

    for (NSString *className in classes) {
        SCIObjCMCInstallCommonGetters(className);
    }

    Class startup = NSClassFromString(@"FBMobileConfigStartupConfigs");
    SCIObjCMCInstall(startup, @"getBool:withDefault:", (IMP)SCIObjCMCGetBoolDefault);
    SCIObjCMCInstall(startup, @"getBool:withOptions:withDefault:", (IMP)SCIObjCMCGetBoolOptionsDefault);
    SCIObjCMCInstall(startup, @"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:", (IMP)SCIObjCMCGetBoolNameDefault);

    Class deprecated = NSClassFromString(@"FBMobileConfigStartupConfigsDeprecated");
    SCIObjCMCInstall(deprecated, @"getBool_XStackIncompatibleButUsedAcrossFBAndIG:withDefault:", (IMP)SCIObjCMCGetBoolNameDefault);

    NSLog(@"[RyukGram][MCOverride] ObjC MobileConfig getter hooks installed");
}
