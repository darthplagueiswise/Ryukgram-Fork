#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciFriendMapEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_directnotes_friendmap"];
}

static BOOL (*orig_fm_enabled_cls)(id, SEL) = NULL;
static BOOL new_fm_enabled_cls(id self, SEL _cmd) { return YES; }
static BOOL (*orig_fm_enabled_inst)(id, SEL) = NULL;
static BOOL new_fm_enabled_inst(id self, SEL _cmd) { return YES; }
static BOOL (*orig_dn_location)(id, SEL, id) = NULL;
static BOOL new_dn_location(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_dn_iteration)(id, SEL, id) = NULL;
static BOOL new_dn_iteration(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_dn_audience)(id, SEL, id) = NULL;
static BOOL new_dn_audience(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_user_muting_fm_cls)(id, SEL) = NULL;
static BOOL new_user_muting_fm_cls(id self, SEL _cmd) { return NO; }
static BOOL (*orig_user_muting_fmloc_cls)(id, SEL) = NULL;
static BOOL new_user_muting_fmloc_cls(id self, SEL _cmd) { return NO; }
static BOOL (*orig_user_muting_fm_inst)(id, SEL) = NULL;
static BOOL new_user_muting_fm_inst(id self, SEL _cmd) { return NO; }
static BOOL (*orig_user_muting_fmloc_inst)(id, SEL) = NULL;
static BOOL new_user_muting_fmloc_inst(id self, SEL _cmd) { return NO; }

static void hookClassBool0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, newImp, orig);
}

static void hookInstanceBool0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

static void hookClassBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, newImp, orig);
}

%ctor {
    if (!sciFriendMapEnabled()) return;

    hookClassBool0(@"_IGDirectNotesFriendMapEnabled", @"isEnabled", (IMP)new_fm_enabled_cls, (IMP *)&orig_fm_enabled_cls);
    hookClassBool0(@"_IGDirectNotesFriendMapEnabled", @"enabled", (IMP)new_fm_enabled_cls, NULL);
    hookInstanceBool0(@"_IGDirectNotesFriendMapEnabled", @"isEnabled", (IMP)new_fm_enabled_inst, (IMP *)&orig_fm_enabled_inst);
    hookInstanceBool0(@"_IGDirectNotesFriendMapEnabled", @"enabled", (IMP)new_fm_enabled_inst, NULL);

    NSString *directNotesHelper = @"_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper";
    hookClassBool1(directNotesHelper, @"locationNotesEnabled:", (IMP)new_dn_location, (IMP *)&orig_dn_location);
    hookClassBool1(directNotesHelper, @"locationNotesIterationEnabled:", (IMP)new_dn_iteration, (IMP *)&orig_dn_iteration);
    hookClassBool1(directNotesHelper, @"audienceAllFollowersEnabled:", (IMP)new_dn_audience, (IMP *)&orig_dn_audience);

    hookClassBool0(@"IGUser", @"isMutingFriendMap", (IMP)new_user_muting_fm_cls, (IMP *)&orig_user_muting_fm_cls);
    hookClassBool0(@"IGUser", @"isMutingFriendMapLocation", (IMP)new_user_muting_fmloc_cls, (IMP *)&orig_user_muting_fmloc_cls);
    hookInstanceBool0(@"IGUser", @"isMutingFriendMap", (IMP)new_user_muting_fm_inst, (IMP *)&orig_user_muting_fm_inst);
    hookInstanceBool0(@"IGUser", @"isMutingFriendMapLocation", (IMP)new_user_muting_fmloc_inst, (IMP *)&orig_user_muting_fmloc_inst);
}
