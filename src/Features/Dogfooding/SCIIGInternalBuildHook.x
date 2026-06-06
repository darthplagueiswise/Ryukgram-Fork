// SCIIGInternalBuildHook.x
//
// Forces the internal/employee build flags needed to unlock IG-Only and
// Internal-Only contextual menus.
//
// MECHANISM (confirmed via binary analysis + CSV xref catalog):
//
// 1. ig_isInternal — ObjC method confirmed in Instagram __objc_methname.
//    Multiple classes expose this (including IGFacebookUserInfo-adjacent classes).
//    XPlugin _checker objects read this to decide menu eligibility.
//
// 2. kIGIsInternalBuildKey — NSUserDefaults key. Confirmed in binary:
//    `kIGIsInternalBuildKey` cstring. Used by `_internalBuildChecker` XPlugin
//    entries (e.g. ios_purge_26_q2_IGStoryItemAdSubmitFeedbackAction_internalBuildChecker).
//    Writing YES to this key unlocks all _internalBuildChecker-gated menus.
//
// 3. isInternal / isInternalOnly — BOOL getters on various IG classes.
//    Gating mechanism used by feed items and media actions.
//
// 4. isInternalToggleOn — BOOL getter that controls internal toggle-enabled paths.
//
// GATING: all hooks under sci_force_ig_internal_employee (same pref as isEmployee).
// Shared pref so enabling the employee gate enables all internal paths at once.
//
// SIDELOAD SAFE: MSHookMessageEx only (no __TEXT patches, no fishhook of imports).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"

#define HLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] InternalBuild " fmt, ##__VA_ARGS__)

static NSString *const kPref = @"sci_force_ig_internal_employee";
static inline BOOL SCIInternalBuildEnabled(void) {
    return [SCIInternalGatePrefs objCGateEnabledForKey:kPref];
}

// ── Cached defaults key string ────────────────────────────────────────────
// kIGIsInternalBuildKey — the actual NSUserDefaults string key. Written at
// install time; read by _internalBuildChecker XPlugin entries to gate menus.
static NSString *sInternalBuildDefaultsKey = nil;

static void SCIForceInternalBuildDefaultsKey(void) {
    if (!SCIInternalBuildEnabled()) return;
    // Common values the key might have. We write YES under all candidates.
    NSArray *candidates = @[
        @"kIGIsInternalBuildKey",
        @"ig_is_internal_build",
        @"IGIsInternalBuild",
        @"ig_internal_build",
    ];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in candidates) {
        [ud setBool:YES forKey:k];
    }
    // Also write the "show_internal_settings" and "ig.internal" keys used by
    // the bug reporter and contextual menus.
    [ud setBool:YES forKey:@"show_internal_settings"];
    [ud setBool:YES forKey:@"ig_internal"];
    [ud synchronize];
    HLOG("Wrote internal build keys to NSUserDefaults");
}

// ── BOOL getter hook factory ──────────────────────────────────────────────
static NSMutableSet<NSString *> *gHooked;

static void SCIHookBoolGetter_IB(NSString *clsName, SEL sel) {
    if (!SCIInternalBuildEnabled()) return;
    Class cls = NSClassFromString(clsName);
    if (!cls) return;
    if (!class_getInstanceMethod(cls, sel)) return;
    NSString *tag = [NSString stringWithFormat:@"%@#%s", clsName, sel_getName(sel)];
    if ([gHooked containsObject:tag]) return;
    IMP newIMP = imp_implementationWithBlock(^BOOL(__unused id self) { return YES; });
    IMP orig = NULL;
    MSHookMessageEx(cls, sel, newIMP, &orig);
    [gHooked addObject:tag];
    HLOG("%{public}@ → YES (%{public}s)", tag, orig ? "ok" : "noorig");
}

// ── Install ───────────────────────────────────────────────────────────────
static void SCIInstallInternalBuildHooks(void) {
    if (!gHooked) gHooked = [NSMutableSet set];
    if (!SCIInternalBuildEnabled()) return;

    // Force NSUserDefaults internal build keys (picked up by XPlugin checkers)
    SCIForceInternalBuildDefaultsKey();

    // Hook BOOL getters on classes that control internal menu eligibility.
    // These classes are confirmed in the Instagram binary's __objc_methname.
    // Using a broad list of known holders of isInternal/isInternalOnly:
    NSArray<NSString *> *classes = @[
        @"IGFacebookUserInfo",
        @"IGUserSession",
        @"_TtC17IGBugReporterMenu29IGBugReportMenuViewController",
    ];
    SEL selInternal        = NSSelectorFromString(@"isInternal");
    SEL selInternalOnly    = NSSelectorFromString(@"isInternalOnly");
    SEL selInternalToggle  = NSSelectorFromString(@"isInternalToggleOn");
    SEL selIgIsInternal    = NSSelectorFromString(@"ig_isInternal");

    for (NSString *cn in classes) {
        SCIHookBoolGetter_IB(cn, selInternal);
        SCIHookBoolGetter_IB(cn, selInternalOnly);
        SCIHookBoolGetter_IB(cn, selInternalToggle);
        SCIHookBoolGetter_IB(cn, selIgIsInternal);
    }

    // Broad scan: hook isInternal/isInternalOnly on ANY loaded IG class.
    // Bounded list — only classes whose name contains "IGFacebook", "IGUser",
    // "IGInternal", or "IGEmployee" to avoid accidental false positives.
    unsigned int count = 0;
    Class *classes_list = objc_copyClassList(&count);
    if (classes_list) {
        for (unsigned int i = 0; i < count; i++) {
            const char *name = class_getName(classes_list[i]);
            if (!name) continue;
            if (!strstr(name, "IGFacebook") && !strstr(name, "IGUserInfo") &&
                !strstr(name, "IGInternal") && !strstr(name, "InternalBuild") &&
                !strstr(name, "IGEmployee") && !strstr(name, "isEmployee")) continue;
            NSString *cn = @(name);
            SCIHookBoolGetter_IB(cn, selInternal);
            SCIHookBoolGetter_IB(cn, selInternalOnly);
            SCIHookBoolGetter_IB(cn, selIgIsInternal);
        }
        free(classes_list);
    }
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        SCIInstallInternalBuildHooks();
        double delays[] = {1.0, 3.0, 6.0, 10.0};
        for (NSUInteger i = 0; i < 4; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ SCIInstallInternalBuildHooks(); });
        }
    }
}
