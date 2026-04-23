#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciQuickSnapEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_quicksnap"];
}

static BOOL (*orig_qs_enabled)(id, SEL, id) = NULL;
static BOOL new_qs_enabled(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_inbox)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_inbox(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_peek)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_peek(id self, SEL _cmd, id arg1) { return YES; }

static BOOL (*orig_qs_eligible_corner)(id, SEL) = NULL;
static BOOL new_qs_eligible_corner(id self, SEL _cmd) { return YES; }
static BOOL (*orig_qs_eligible_dialog)(id, SEL) = NULL;
static BOOL new_qs_eligible_dialog(id self, SEL _cmd) { return YES; }
static BOOL (*orig_qs_isqp)(id, SEL, id) = NULL;
static BOOL new_qs_isqp(id self, SEL _cmd, id arg1) { return YES; }
static void (*orig_qs_show_intro)(id, SEL) = NULL;
static void new_qs_show_intro(id self, SEL _cmd) {
    if (orig_qs_show_intro) orig_qs_show_intro(self, _cmd);
}

static BOOL (*orig_user_muting_qs_cls)(id, SEL) = NULL;
static BOOL new_user_muting_qs_cls(id self, SEL _cmd) { return NO; }
static BOOL (*orig_user_muting_qs_inst)(id, SEL) = NULL;
static BOOL new_user_muting_qs_inst(id self, SEL _cmd) { return NO; }

static void hookClassBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
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

static void hookInstanceBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

static void hookInstanceVoid0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

static void hookClassBool0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, newImp, orig);
}

%ctor {
    if (!sciQuickSnapEnabled()) return;

    NSString *quickSnapHelper = @"_TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper";
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabled:", (IMP)new_qs_enabled, (IMP *)&orig_qs_enabled);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledInInbox:", (IMP)new_qs_enabled_inbox, (IMP *)&orig_qs_enabled_inbox);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledAsPeek:", (IMP)new_qs_enabled_peek, (IMP *)&orig_qs_enabled_peek);

    NSString *trayController = @"_TtC21IGNotesTrayController21IGNotesTrayController";
    hookInstanceBool0(trayController, @"_isEligibleForQuicksnapCornerStackTransitionDialog", (IMP)new_qs_eligible_corner, (IMP *)&orig_qs_eligible_corner);
    hookInstanceBool0(trayController, @"_isEligibleForQuicksnapDialog", (IMP)new_qs_eligible_dialog, (IMP *)&orig_qs_eligible_dialog);
    hookInstanceBool1(trayController, @"isQPEnabled:", (IMP)new_qs_isqp, (IMP *)&orig_qs_isqp);
    hookInstanceVoid0(trayController, @"_showQuicksnapIntroDialog", (IMP)new_qs_show_intro, (IMP *)&orig_qs_show_intro);

    hookInstanceBool1(@"IGDirectNotesTrayRowSectionController", @"isQPEnabled:", (IMP)new_qs_isqp, NULL);
    hookInstanceBool1(@"_TtC24IGDirectNotesTrayUISwift37IGDirectNotesTrayRowSectionController", @"isQPEnabled:", (IMP)new_qs_isqp, NULL);

    hookClassBool0(@"IGUser", @"isMutingQuickSnap", (IMP)new_user_muting_qs_cls, (IMP *)&orig_user_muting_qs_cls);
    hookInstanceBool0(@"IGUser", @"isMutingQuickSnap", (IMP)new_user_muting_qs_inst, (IMP *)&orig_user_muting_qs_inst);
}
