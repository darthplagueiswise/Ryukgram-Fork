// Supplemental QuickSnap hooks for the notes tray path.
//
// Real runtime findings from Instagram 425.0.0 IPA:
//  - _TtC21IGNotesTrayController21IGNotesTrayController
//  - IGDirectNotesTrayRowSectionController
//  - selectors seen in strings: tryShowQuickSnapPeek,
//    _isEligibleForQuicksnapDialog,
//    _isEligibleForQuicksnapCornerStackTransitionDialog,
//    _showQuicksnapIntroDialog,
//    isQPEnabled:
//
// Symptom motivating this file:
// QuickSnap peek can appear, but continuing still reports the feature as
// unavailable. That strongly suggests a second gating layer in the notes tray
// controller path, separate from the experimentation helper.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciQSNAlwaysTrueNoArgs(id self, SEL _cmd) { return YES; }
static BOOL sciQSNAlwaysTrueOneArg(id self, SEL _cmd, id arg1) { return YES; }

static void sciQSNInstallBoolHookForInstanceMethod(NSString *className, NSString *selName, IMP newImp) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, NULL);
}

static void sciInstallQuickSnapNotesTrayHooks(void) {
    NSString *notesTrayController = @"_TtC21IGNotesTrayController21IGNotesTrayController";
    sciQSNInstallBoolHookForInstanceMethod(notesTrayController, @"_isEligibleForQuicksnapDialog", (IMP)sciQSNAlwaysTrueNoArgs);
    sciQSNInstallBoolHookForInstanceMethod(notesTrayController, @"_isEligibleForQuicksnapCornerStackTransitionDialog", (IMP)sciQSNAlwaysTrueNoArgs);
    sciQSNInstallBoolHookForInstanceMethod(notesTrayController, @"isQPEnabled:", (IMP)sciQSNAlwaysTrueOneArg);

    NSString *trayRowController = @"IGDirectNotesTrayRowSectionController";
    sciQSNInstallBoolHookForInstanceMethod(trayRowController, @"isQPEnabled:", (IMP)sciQSNAlwaysTrueOneArg);
}

%ctor {
    if (![SCIUtils getBoolPref:@"sci_exp_flags_enabled"]) return;
    sciInstallQuickSnapNotesTrayHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciInstallQuickSnapNotesTrayHooks();
    });
}
