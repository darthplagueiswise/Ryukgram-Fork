// Hooks installed iff sci_exp_flags_enabled.
// Existing behavior: MetaLocalExperiment group{,Peek}Name override.
// Experimental additions for this branch:
//  - force-enable known FriendsMap / QuickSnap experiment-name prefixes
//  - use validated runtime Swift helper classes from the target IPA for
//    Direct Notes / QuickSnap instead of guessed class names
//  - observe and override IGMobileConfigContextManager getters by raw param ID

#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL sciQuickSnapEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_quicksnap"];
}

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

static BOOL sciContainsQuickSnapName(NSString *expName) {
    if (![expName isKindOfClass:[NSString class]] || !expName.length) return NO;
    NSString *lower = expName.lowercaseString;
    return [lower containsString:@"quicksnap"] ||
           [lower containsString:@"ig_ios_quicksnap_"] ||
           [lower containsString:@"_ig_ios_quicksnap_"];
}

static BOOL sciShouldForceEnableExperimentName(NSString *expName) {
    if (!expName.length) return NO;
    NSString *lower = expName.lowercaseString;
    if (!sciQuickSnapEnabled() && sciContainsQuickSnapName(lower)) return NO;
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

    if (!sciQuickSnapEnabled() && sciContainsQuickSnapName(lower)) return nil;

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
static BOOL sciQuickSnapTrueOrFalseNoArgs(id self, SEL _cmd) { return sciQuickSnapEnabled() ? YES : NO; }
static BOOL sciQuickSnapTrueOrFalseOneArg(id self, SEL _cmd, id arg1) { return sciQuickSnapEnabled() ? YES : NO; }

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

// IGMobileConfigContextManager hooks
static NSNumber *sciMCBoolOverride(unsigned long long pid) { return [SCIExpFlags mcOverrideObjectForParamID:pid type:SCIExpMCTypeBool]; }
static NSNumber *sciMCIntOverride(unsigned long long pid) { return [SCIExpFlags mcOverrideObjectForParamID:pid type:SCIExpMCTypeInt]; }
static NSNumber *sciMCDoubleOverride(unsigned long long pid) { return [SCIExpFlags mcOverrideObjectForParamID:pid type:SCIExpMCTypeDouble]; }
static NSString *sciMCStringOverride(unsigned long long pid) { return [SCIExpFlags mcOverrideObjectForParamID:pid type:SCIExpMCTypeString]; }

static BOOL (*orig_mc_bool_wd)(id, SEL, unsigned long long, BOOL);
static BOOL new_mc_bool_wd(id self, SEL _cmd, unsigned long long pid, BOOL def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeBool defaultValue:def ? @"YES" : @"NO"];
    NSNumber *o = sciMCBoolOverride(pid);
    return o ? o.boolValue : (orig_mc_bool_wd ? orig_mc_bool_wd(self, _cmd, pid, def) : def);
}
static BOOL (*orig_mc_bool_wo)(id, SEL, unsigned long long, id);
static BOOL new_mc_bool_wo(id self, SEL _cmd, unsigned long long pid, id opts) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeBool defaultValue:@""];
    NSNumber *o = sciMCBoolOverride(pid);
    return o ? o.boolValue : (orig_mc_bool_wo ? orig_mc_bool_wo(self, _cmd, pid, opts) : NO);
}
static BOOL (*orig_mc_bool_wowd)(id, SEL, unsigned long long, id, BOOL);
static BOOL new_mc_bool_wowd(id self, SEL _cmd, unsigned long long pid, id opts, BOOL def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeBool defaultValue:def ? @"YES" : @"NO"];
    NSNumber *o = sciMCBoolOverride(pid);
    return o ? o.boolValue : (orig_mc_bool_wowd ? orig_mc_bool_wowd(self, _cmd, pid, opts, def) : def);
}

static long long (*orig_mc_int_wd)(id, SEL, unsigned long long, long long);
static long long new_mc_int_wd(id self, SEL _cmd, unsigned long long pid, long long def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeInt defaultValue:[NSString stringWithFormat:@"%lld", def]];
    NSNumber *o = sciMCIntOverride(pid);
    return o ? o.longLongValue : (orig_mc_int_wd ? orig_mc_int_wd(self, _cmd, pid, def) : def);
}
static long long (*orig_mc_int_wo)(id, SEL, unsigned long long, id);
static long long new_mc_int_wo(id self, SEL _cmd, unsigned long long pid, id opts) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeInt defaultValue:@""];
    NSNumber *o = sciMCIntOverride(pid);
    return o ? o.longLongValue : (orig_mc_int_wo ? orig_mc_int_wo(self, _cmd, pid, opts) : 0);
}
static long long (*orig_mc_int_wowd)(id, SEL, unsigned long long, id, long long);
static long long new_mc_int_wowd(id self, SEL _cmd, unsigned long long pid, id opts, long long def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeInt defaultValue:[NSString stringWithFormat:@"%lld", def]];
    NSNumber *o = sciMCIntOverride(pid);
    return o ? o.longLongValue : (orig_mc_int_wowd ? orig_mc_int_wowd(self, _cmd, pid, opts, def) : def);
}

static double (*orig_mc_double_wd)(id, SEL, unsigned long long, double);
static double new_mc_double_wd(id self, SEL _cmd, unsigned long long pid, double def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeDouble defaultValue:[NSString stringWithFormat:@"%f", def]];
    NSNumber *o = sciMCDoubleOverride(pid);
    return o ? o.doubleValue : (orig_mc_double_wd ? orig_mc_double_wd(self, _cmd, pid, def) : def);
}
static double (*orig_mc_double_wo)(id, SEL, unsigned long long, id);
static double new_mc_double_wo(id self, SEL _cmd, unsigned long long pid, id opts) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeDouble defaultValue:@""];
    NSNumber *o = sciMCDoubleOverride(pid);
    return o ? o.doubleValue : (orig_mc_double_wo ? orig_mc_double_wo(self, _cmd, pid, opts) : 0.0);
}
static double (*orig_mc_double_wowd)(id, SEL, unsigned long long, id, double);
static double new_mc_double_wowd(id self, SEL _cmd, unsigned long long pid, id opts, double def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeDouble defaultValue:[NSString stringWithFormat:@"%f", def]];
    NSNumber *o = sciMCDoubleOverride(pid);
    return o ? o.doubleValue : (orig_mc_double_wowd ? orig_mc_double_wowd(self, _cmd, pid, opts, def) : def);
}

static id (*orig_mc_string_wd)(id, SEL, unsigned long long, id);
static id new_mc_string_wd(id self, SEL _cmd, unsigned long long pid, id def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeString defaultValue:[def isKindOfClass:[NSString class]] ? def : @""];
    NSString *o = sciMCStringOverride(pid);
    return o ?: (orig_mc_string_wd ? orig_mc_string_wd(self, _cmd, pid, def) : def);
}
static id (*orig_mc_string_wo)(id, SEL, unsigned long long, id);
static id new_mc_string_wo(id self, SEL _cmd, unsigned long long pid, id opts) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeString defaultValue:@""];
    NSString *o = sciMCStringOverride(pid);
    return o ?: (orig_mc_string_wo ? orig_mc_string_wo(self, _cmd, pid, opts) : nil);
}
static id (*orig_mc_string_wowd)(id, SEL, unsigned long long, id, id);
static id new_mc_string_wowd(id self, SEL _cmd, unsigned long long pid, id opts, id def) {
    [SCIExpFlags recordMCParamID:pid type:SCIExpMCTypeString defaultValue:[def isKindOfClass:[NSString class]] ? def : @""];
    NSString *o = sciMCStringOverride(pid);
    return o ?: (orig_mc_string_wowd ? orig_mc_string_wowd(self, _cmd, pid, opts, def) : def);
}

static void sciInstallMobileConfigHooks(void) {
    Class mc = NSClassFromString(@"IGMobileConfigContextManager");
    if (!mc) return;
    installHook(mc, @"getBool:withDefault:", (IMP)new_mc_bool_wd, (IMP *)&orig_mc_bool_wd);
    installHook(mc, @"getBool:withOptions:", (IMP)new_mc_bool_wo, (IMP *)&orig_mc_bool_wo);
    installHook(mc, @"getBool:withOptions:withDefault:", (IMP)new_mc_bool_wowd, (IMP *)&orig_mc_bool_wowd);
    installHook(mc, @"getInt64:withDefault:", (IMP)new_mc_int_wd, (IMP *)&orig_mc_int_wd);
    installHook(mc, @"getInt64:withOptions:", (IMP)new_mc_int_wo, (IMP *)&orig_mc_int_wo);
    installHook(mc, @"getInt64:withOptions:withDefault:", (IMP)new_mc_int_wowd, (IMP *)&orig_mc_int_wowd);
    installHook(mc, @"getDouble:withDefault:", (IMP)new_mc_double_wd, (IMP *)&orig_mc_double_wd);
    installHook(mc, @"getDouble:withOptions:", (IMP)new_mc_double_wo, (IMP *)&orig_mc_double_wo);
    installHook(mc, @"getDouble:withOptions:withDefault:", (IMP)new_mc_double_wowd, (IMP *)&orig_mc_double_wowd);
    installHook(mc, @"getString:withDefault:", (IMP)new_mc_string_wd, (IMP *)&orig_mc_string_wd);
    installHook(mc, @"getString:withOptions:", (IMP)new_mc_string_wo, (IMP *)&orig_mc_string_wo);
    installHook(mc, @"getString:withOptions:withDefault:", (IMP)new_mc_string_wowd, (IMP *)&orig_mc_string_wowd);
}

static void sciInstallConcreteEnablementHooks(void) {
    // Validated concrete gate found in the target IPA.
    sciInstallBoolHookForClassMethod(@"_IGDirectNotesFriendMapEnabled", @"isEnabled", (IMP)sciAlwaysTrueNoArgs);
    sciInstallBoolHookForClassMethod(@"_IGDirectNotesFriendMapEnabled", @"enabled", (IMP)sciAlwaysTrueNoArgs);
    sciInstallBoolHookForInstanceMethod(@"_IGDirectNotesFriendMapEnabled", @"isEnabled", (IMP)sciAlwaysTrueNoArgs);
    sciInstallBoolHookForInstanceMethod(@"_IGDirectNotesFriendMapEnabled", @"enabled", (IMP)sciAlwaysTrueNoArgs);

    // Validated Swift runtime helper class from the IPA.
    NSString *directNotesHelper = @"_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper";
    sciInstallBoolHookForClassMethod(directNotesHelper, @"locationNotesEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"locationNotesIterationEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"locationNotesBottomAttributionEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"themeEnhancementsEntryPointEnabled:", (IMP)sciAlwaysTrueOneArg);
    sciInstallBoolHookForClassMethod(directNotesHelper, @"hyperlinksEnabled:", (IMP)sciAlwaysTrueOneArg);

    // QuickSnap runtime gated by igt_quicksnap.
    NSString *quickSnapHelper = @"_TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper";
    sciInstallBoolHookForClassMethod(quickSnapHelper, @"isQuicksnapEnabled:", (IMP)sciQuickSnapTrueOrFalseOneArg);
    sciInstallBoolHookForClassMethod(quickSnapHelper, @"isQuicksnapEnabledInInbox:", (IMP)sciQuickSnapTrueOrFalseOneArg);
    sciInstallBoolHookForClassMethod(quickSnapHelper, @"isQuicksnapEnabledAsPeek:", (IMP)sciQuickSnapTrueOrFalseOneArg);

    // Suppression / mute gates seen in the IPA strings. Keep them off if the
    // selectors live on IGUser in this build.
    sciInstallBoolHookForClassMethod(@"IGUser", @"isMutingFriendMap", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForClassMethod(@"IGUser", @"isMutingFriendMapLocation", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForClassMethod(@"IGUser", @"isMutingQuickSnap", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"IGUser", @"isMutingFriendMap", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"IGUser", @"isMutingFriendMapLocation", (IMP)sciAlwaysFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"IGUser", @"isMutingQuickSnap", (IMP)sciAlwaysFalseNoArgs);

    // Notes tray QuickSnap gates.
    sciInstallBoolHookForInstanceMethod(@"_TtC21IGNotesTrayController21IGNotesTrayController", @"_isEligibleForQuicksnapDialog", (IMP)sciQuickSnapTrueOrFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"_TtC21IGNotesTrayController21IGNotesTrayController", @"_isEligibleForQuicksnapCornerStackTransitionDialog", (IMP)sciQuickSnapTrueOrFalseNoArgs);
    sciInstallBoolHookForInstanceMethod(@"_TtC21IGNotesTrayController21IGNotesTrayController", @"isQPEnabled:", (IMP)sciQuickSnapTrueOrFalseOneArg);
    sciInstallBoolHookForInstanceMethod(@"IGDirectNotesTrayRowSectionController", @"isQPEnabled:", (IMP)sciQuickSnapTrueOrFalseOneArg);
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

    sciInstallMobileConfigHooks();
    sciInstallConcreteEnablementHooks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciInstallMobileConfigHooks();
        sciInstallConcreteEnablementHooks();
    });
}
