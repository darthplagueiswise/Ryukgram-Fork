// Hooks installed iff sci_exp_flags_enabled.
// Existing behavior: MetaLocalExperiment group{,Peek}Name override.
// Experimental additions for this branch:
//  - force-enable known FriendsMap / QuickSnap experiment-name prefixes
//  - use validated runtime Swift helper classes from the target IPA for
//    Direct Notes / QuickSnap instead of guessed class names

#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSArray<NSString *> *sciForcedExperimentNeedles(void) {
    static NSArray<NSString *> *needles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        needles = @[
            @"_ig_ios_friendmap_",
            @"ig_ios_friendmap_",
            @"_ig_ios_quicksnap_",
            @"ig_ios_quicksnap_",
            @"friendmapenabled",
            @"quicksnapenabled"
        ];
    });
    return needles;
}

static BOOL sciShouldForceEnableExperimentName(NSString *expName) {
    if (!expName.length) return NO;
    NSString *lower = expName.lowercaseString;
    for (NSString *needle in sciForcedExperimentNeedles()) {
        if ([lower containsString:needle]) return YES;
    }
    return NO;
}

static NSString *experimentNameOf(id obj) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), "_experimentName");
    if (!iv) return nil;
    @try {
        id v = object_getIvar(obj, iv);
        if ([v isKindOfClass:[NSString class]]) return v;
    } @catch (__unused id e) {}
    return nil;
}

static id overrideGroupFor(NSString *expName, id origGroup) {
    if (!expName.length) return origGroup;
    NSString *lower = expName.lowercaseString;

    for (NSString *key in [SCIExpFlags allOverriddenNames]) {
        if (![lower containsString:key.lowercaseString]) continue;
        SCIExpFlagOverride o = [SCIExpFlags overrideForName:key];
        if (o == SCIExpFlagOverrideTrue) return @"test";
        if (o == SCIExpFlagOverrideFalse) return nil;
    }

    if (sciShouldForceEnableExperimentName(lower)) return @"test";
    return origGroup;
}

static id (*orig_groupName)(id, SEL);
static id new_groupName(id self, SEL _cmd) {
    id orig = orig_groupName ? orig_groupName(self, _cmd) : nil;
    NSString *name = experimentNameOf(self);
    [SCIExpFlags recordExperimentName:name group:[orig isKindOfClass:[NSString class]] ? orig : nil];
    return overrideGroupFor(name, orig);
}

static id (*orig_peekGroupName)(id, SEL);
static id new_peekGroupName(id self, SEL _cmd) {
    id orig = orig_peekGroupName ? orig_peekGroupName(self, _cmd) : nil;
    NSString *name = experimentNameOf(self);
    [SCIExpFlags recordExperimentName:name group:[orig isKindOfClass:[NSString class]] ? orig : nil];
    return overrideGroupFor(name, orig);
}

static void installHook(Class cls, NSString *selName, IMP newImp, IMP *origOut) {
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, origOut);
}

static BOOL sciAlwaysTrueNoArgs(id self, SEL _cmd) { return YES; }
static BOOL sciAlwaysFalseNoArgs(id self, SEL _cmd) { return NO; }
static BOOL sciAlwaysTrueOneArg(id self, SEL _cmd, id arg1) { return YES; }

static void sciInstallBoolHookForClassMethod(NSString *className, NSString *selName, IMP newImp) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, s)) return;
    MSHookMessageEx(meta, s, newImp, NULL);
}

static void sciInstallBoolHookForInstanceMethod(NSString *className, NSString *selName, IMP newImp) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL s = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, s)) return;
    MSHookMessageEx(cls, s, newImp, NULL);
}

static void sciInstallConcreteEnablementHooks(void) {
    // Validated concrete gate found in the target IPA.
    sciInstallBoolHookForClassMethod(@"_IGDirectNotesFriendMapEnabled", @"isEnabled", (IMP)sciAlwaysTrueNoArgs);
    sciInstallBoolHookForClassMethod(@"_IGDirectNotesFriendMapEnabled", @"enabled", (IMP)sciAlwaysTrueNoArgs);
    sciInstallBoolHookForInstanceMethod(@"_IGDirectNotesFriendMapEnabled", @"isEnabled", (IMP)sciAlwaysTrueNoArgs);
    sciInstallBoolHookForInstanceMethod(@"_IGDirectNotesFriendMapEnabled", @"enabled", (IMP)sciAlwaysTrueNoArgs);

    // Validated Swift runtime helper class from the IPA.
    // strings -a shows:
    // _TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper
    // with selectors such as locationNotesEnabled:
    NSString *directNotesHelper = @"_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper";
    sciInstallBoolHookForClassMethod(directNotesHelper, @"locationNotesEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"locationNotesIterationEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"locationNotesBottomAttributionEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"themeEnhancementsEntryPointEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"hyperlinksEnabled:", (IMP)sciAlwaysTrueOneArg);

    // Validated Swift runtime helper class from the IPA.
    // strings -a shows:
    // _TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper
    NSString *quickSnapHelper = @"_TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper";
    sciInstallBoolHookForClassMethod(quickSnapHelper, @"isQuicksnapEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(quickSnapHelper, @"isQuicksnapEnabledInInbox:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(quickSnapHelper, @"isQuicksnapEnabledAsPeek:", (IMP)sciAlwaysTrueOneArg);

    // Suppression / mute gates seen in the IPA strings. Keep them off if the
    // selectors live on IGUser in this build.
    sciInstallBoolHookForClassMethod(@"IGUser", @"isMutingFriendMap", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForClassMethod(@"IGUser", @"isMutingFriendMapLocation", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForClassMethod(@"IGUser", @"isMutingQuickSnap", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"IGUser", @"isMutingFriendMap", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"IGUser", @"isMutingFriendMapLocation", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"IGUser", @"isMutingQuickSnap", (IMP)sciAlwaysFalseNoArgs);
}

%ctor {
    if (![SCIUtils getBoolPref:@"sci_exp_flags_enabled"]) return;

    if ([SCIExpFlags checkAndHandleCrashLoop]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [SCIUtils showToastForDuration:4.0 title:@"Exp flags reset after repeated crashes"];
        });
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [SCIExpFlags markLaunchStable];
    });

    Class meta = NSClassFromString(@"MetaLocalExperiment");
    installHook(meta, @"groupName", (IMP)new_groupName, (IMP *)&orig_groupName);
    installHook(meta, @"peekGroupName", (IMP)new_peekGroupName, (IMP *)&orig_peekGroupName);

    sciInstallConcreteEnablementHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciInstallConcreteEnablementHooks();
    });
}
