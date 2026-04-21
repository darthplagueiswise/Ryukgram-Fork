#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciHomecomingEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_homecoming"];
}

static BOOL sciContainsHomecomingName(NSString *s) {
    if (![s isKindOfClass:[NSString class]] || !s.length) return NO;
    return [s.lowercaseString containsString:@"homecoming"];
}

static NSString *sciGroupNameFromExperiment(id self) {
    if (!self) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_experimentGroupName");
    if (!iv) iv = class_getInstanceVariable(object_getClass(self), "_experimentName");
    if (!iv) return nil;
    @try {
        id v = object_getIvar(self, iv);
        if ([v isKindOfClass:[NSString class]]) return v;
    } @catch (__unused id e) {}
    return nil;
}

static BOOL (*orig_meta_isInExperiment_hc)(id, SEL) = NULL;
static BOOL new_meta_isInExperiment_hc(id self, SEL _cmd) {
    NSString *name = sciGroupNameFromExperiment(self);
    if (sciContainsHomecomingName(name)) return sciHomecomingEnabled();
    return orig_meta_isInExperiment_hc ? orig_meta_isInExperiment_hc(self, _cmd) : NO;
}

static BOOL (*orig_family_isInExperiment_hc)(id, SEL) = NULL;
static BOOL new_family_isInExperiment_hc(id self, SEL _cmd) {
    NSString *name = sciGroupNameFromExperiment(self);
    if (sciContainsHomecomingName(name)) return sciHomecomingEnabled();
    return orig_family_isInExperiment_hc ? orig_family_isInExperiment_hc(self, _cmd) : NO;
}

static BOOL (*orig_lid_enabled_hc)(id, SEL, NSString *) = NULL;
static BOOL new_lid_enabled_hc(id self, SEL _cmd, NSString *experimentName) {
    if (sciContainsHomecomingName(experimentName)) return sciHomecomingEnabled();
    return orig_lid_enabled_hc ? orig_lid_enabled_hc(self, _cmd, experimentName) : NO;
}

static BOOL (*orig_nav_isHomecomingEnabled_hc)(id, SEL) = NULL;
static BOOL new_nav_isHomecomingEnabled_hc(id self, SEL _cmd) {
    return sciHomecomingEnabled();
}

static void sciHookInst(Class cls, NSString *selName, IMP newImp, IMP *orig) {
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, orig);
}

%ctor {
    Class metaExp = NSClassFromString(@"MetaLocalExperiment");
    sciHookInst(metaExp, @"isInExperiment", (IMP)new_meta_isInExperiment_hc, (IMP *)&orig_meta_isInExperiment_hc);

    Class familyExp = NSClassFromString(@"FamilyLocalExperiment");
    sciHookInst(familyExp, @"isInExperiment", (IMP)new_family_isInExperiment_hc, (IMP *)&orig_family_isInExperiment_hc);

    Class lidGen = NSClassFromString(@"LIDExperimentGenerator");
    sciHookInst(lidGen, @"isExperimentEnabled:", (IMP)new_lid_enabled_hc, (IMP *)&orig_lid_enabled_hc);

    Class navCfg = NSClassFromString(@"_TtC18IGNavConfiguration18IGNavConfiguration");
    sciHookInst(navCfg, @"isHomecomingEnabled", (IMP)new_nav_isHomecomingEnabled_hc, (IMP *)&orig_nav_isHomecomingEnabled_hc);
}
