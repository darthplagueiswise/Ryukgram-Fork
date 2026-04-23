#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSString *sciExperimentName(id self) {
    if (!self) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_experimentGroupName");
    if (!iv) iv = class_getInstanceVariable(object_getClass(self), "_experimentName");
    if (!iv) return nil;
    @try {
        id value = object_getIvar(self, iv);
        if ([value isKindOfClass:[NSString class]]) return value;
    } @catch (__unused id e) {}
    return nil;
}

static BOOL sciContainsAny(NSString *value, NSArray<NSString *> *needles) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    NSString *lower = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL sciQuickSnapRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_quicksnap"]) return NO;
    return sciContainsAny(name, @[@"quicksnap", @"quick_snap", @"instants", @"xma_quicksnap", @"_ig_ios_quicksnap_", @"_ig_ios_quick_snap_", @"_ig_ios_instants_"]);
}

static BOOL sciFriendMapRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_directnotes_friendmap"]) return NO;
    return sciContainsAny(name, @[@"friendmap", @"friends_map", @"direct_notes", @"ig_direct_notes_ios", @"_ig_ios_friendmap_", @"_ig_ios_friends_map_"]);
}

static BOOL sciPrismRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_prism"]) return NO;
    return sciContainsAny(name, @[@"prism"]);
}

static BOOL sciShouldForceOn(NSString *name) {
    return sciQuickSnapRollout(name) || sciFriendMapRollout(name) || sciPrismRollout(name);
}

static BOOL (*orig_meta_isInExperiment)(id, SEL) = NULL;
static BOOL new_meta_isInExperiment(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOn(name)) return YES;
    return orig_meta_isInExperiment ? orig_meta_isInExperiment(self, _cmd) : NO;
}

static BOOL (*orig_family_isInExperiment)(id, SEL) = NULL;
static BOOL new_family_isInExperiment(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOn(name)) return YES;
    return orig_family_isInExperiment ? orig_family_isInExperiment(self, _cmd) : NO;
}

static BOOL (*orig_lid_isExperimentEnabled)(id, SEL, NSString *) = NULL;
static BOOL new_lid_isExperimentEnabled(id self, SEL _cmd, NSString *experimentName) {
    if (sciShouldForceOn(experimentName)) return YES;
    return orig_lid_isExperimentEnabled ? orig_lid_isExperimentEnabled(self, _cmd, experimentName) : NO;
}

static id (*orig_groupName)(id, SEL) = NULL;
static id new_groupName(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOn(name)) return @"test";
    return orig_groupName ? orig_groupName(self, _cmd) : nil;
}

static id (*orig_peekGroupName)(id, SEL) = NULL;
static id new_peekGroupName(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOn(name)) return @"test";
    return orig_peekGroupName ? orig_peekGroupName(self, _cmd) : nil;
}

static void sciHookInst(Class cls, NSString *selName, IMP newImp, IMP *orig) {
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

%ctor {
    if (!([SCIUtils getBoolPref:@"igt_quicksnap"] ||
          [SCIUtils getBoolPref:@"igt_directnotes_friendmap"] ||
          [SCIUtils getBoolPref:@"igt_prism"])) return;

    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"isInExperiment", (IMP)new_meta_isInExperiment, (IMP *)&orig_meta_isInExperiment);
    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"groupName", (IMP)new_groupName, (IMP *)&orig_groupName);
    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"peekGroupName", (IMP)new_peekGroupName, (IMP *)&orig_peekGroupName);
    sciHookInst(NSClassFromString(@"FamilyLocalExperiment"), @"isInExperiment", (IMP)new_family_isInExperiment, (IMP *)&orig_family_isInExperiment);
    sciHookInst(NSClassFromString(@"LIDExperimentGenerator"), @"isExperimentEnabled:", (IMP)new_lid_isExperimentEnabled, (IMP *)&orig_lid_isExperimentEnabled);
}
