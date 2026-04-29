#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../SCIExpFlags.h"
#import "../../../Utils.h"

static NSMutableDictionary<NSString *, NSValue *> *SCIObjCMCOriginalIMPs;

static NSString *SCIObjCMCKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

static IMP SCIObjCMCOriginalIMP(id self, SEL sel) {
    Class cls = object_getClass(self);
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

static void SCIObjCMCRecord(id self, SEL sel, unsigned long long pid, BOOL defaultValue, BOOL originalValue) {
    NSString *detail = [NSString stringWithFormat:@"source=ObjC MobileConfig getter · selector=%@ · context=%@ · default=%d · original=%d · shadowTrue=1 · wouldChangeIfTrue=%d",
                        NSStringFromSelector(sel),
                        SCIObjCMCContextName(self),
                        defaultValue,
                        originalValue,
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
    SCIObjCMCRecord(self, sel, pid, original, original);
    return original;
}

static BOOL SCIObjCMCGetBoolDefault(id self, SEL sel, unsigned long long pid, BOOL def) {
    BOOL (*orig)(id, SEL, unsigned long long, BOOL) = (BOOL (*)(id, SEL, unsigned long long, BOOL))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, pid, def) : def;
    SCIObjCMCRecord(self, sel, pid, def, original);
    return original;
}

static BOOL SCIObjCMCGetBoolOptions(id self, SEL sel, unsigned long long pid, id options) {
    BOOL (*orig)(id, SEL, unsigned long long, id) = (BOOL (*)(id, SEL, unsigned long long, id))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, pid, options) : NO;
    SCIObjCMCRecord(self, sel, pid, original, original);
    return original;
}

static BOOL SCIObjCMCGetBoolOptionsDefault(id self, SEL sel, unsigned long long pid, id options, BOOL def) {
    BOOL (*orig)(id, SEL, unsigned long long, id, BOOL) = (BOOL (*)(id, SEL, unsigned long long, id, BOOL))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, pid, options, def) : def;
    SCIObjCMCRecord(self, sel, pid, def, original);
    return original;
}

static BOOL SCIObjCMCGetBoolNameDefault(id self, SEL sel, id name, BOOL def) {
    BOOL (*orig)(id, SEL, id, BOOL) = (BOOL (*)(id, SEL, id, BOOL))SCIObjCMCOriginalIMP(self, sel);
    BOOL original = orig ? orig(self, sel, name, def) : def;
    unsigned long long pseudo = (unsigned long long)[[name description] hash];
    SCIObjCMCRecord(self, sel, pseudo, def, original);
    return original;
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
    if (![SCIUtils getBoolPref:@"sci_exp_flags_enabled"]) return;

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

    NSLog(@"[RyukGram][ExpObserver] ObjC MobileConfig shadow observer installed");
}
