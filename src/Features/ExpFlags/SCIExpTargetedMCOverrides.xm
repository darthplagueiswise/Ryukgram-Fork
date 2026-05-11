#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Targeted MobileConfig bridge for beta2:
// - inert when all supported toggles are OFF
// - no broker router changes
// - no DoNotUseOrMock hooks
// - no constructor-time class scan
// - only hooks known MobileConfig ObjC getter selectors on known manager classes

typedef NS_ENUM(NSInteger, SCITargetedMCDecision) {
    SCITargetedMCDecisionNone = 0,
    SCITargetedMCDecisionForceFalse = -1,
    SCITargetedMCDecisionForceTrue = 1,
};

static NSMutableDictionary<NSString *, NSValue *> *gSCITMCOriginals;

static BOOL SCITMCBool(NSString *key) {
    return key.length && [SCIUtils getBoolPref:key];
}

static BOOL SCITMCAnyEnabled(void) {
    NSArray<NSString *> *keys = @[
        @"igt_quicksnap",
        @"igt_directnotes_friendmap",
        @"igt_icebreaker",
        @"igt_mutual_interest",
        @"igt_stories_tray_decoupling",
        @"igt_stories_tray_tap_prefetch",
        @"igt_stories_tray_title_interaction",
        @"igt_stories_feed_decoupling",
        @"igt_stories_independent_fetch",
        @"igt_dm_inline_like"
    ];
    for (NSString *key in keys) {
        if (SCITMCBool(key)) return YES;
    }
    return NO;
}

static NSString *SCITMCSafeSelectorString(id obj, SEL sel) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;
    id (*sendObj)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id value = nil;
    @try { value = sendObj(obj, sel); }
    @catch (__unused NSException *e) { value = nil; }
    if ([value isKindOfClass:NSString.class]) return value;
    return nil;
}

static NSString *SCITMCNameForParam(id param) {
    if (!param) return nil;
    if ([param isKindOfClass:NSString.class]) return (NSString *)param;

    NSString *s = SCITMCSafeSelectorString(param, @selector(name));
    if (s.length) return s;
    s = SCITMCSafeSelectorString(param, @selector(identifier));
    if (s.length) return s;
    s = SCITMCSafeSelectorString(param, @selector(key));
    if (s.length) return s;
    s = SCITMCSafeSelectorString(param, @selector(paramName));
    if (s.length) return s;
    s = SCITMCSafeSelectorString(param, @selector(mobileConfigName));
    if (s.length) return s;

    // Last resort for active toggles only. Avoid dictionaryRepresentation or
    // any resolver/store path here; this is just a bounded textual fallback.
    NSString *desc = nil;
    @try { desc = [param description]; }
    @catch (__unused NSException *e) { desc = nil; }
    if (desc.length > 0 && desc.length <= 512) return desc;
    return nil;
}

static BOOL SCITMCContainsAny(NSString *lower, NSArray<NSString *> *needles) {
    if (!lower.length) return NO;
    for (NSString *needle in needles) {
        if (needle.length && [lower containsString:needle]) return YES;
    }
    return NO;
}

static SCITargetedMCDecision SCITMCDecisionForName(NSString *name) {
    if (!name.length) return SCITargetedMCDecisionNone;
    NSString *l = name.lowercaseString;

    if (SCITMCBool(@"igt_quicksnap")) {
        if ([l containsString:@"_ig_instants_hide"] || [l containsString:@"ig_instants_hide"]) {
            return SCITargetedMCDecisionForceFalse;
        }
        if (SCITMCContainsAny(l, @[
            @"_ig_ios_quick_snap",
            @"_ig_ios_quicksnap",
            @"_ig_ios_instants",
            @"_ig_quick_snap_show_peek_in_view_did_appear",
            @"ig_ios_quick_snap",
            @"ig_ios_quicksnap",
            @"ig_ios_instants",
            @"ig_quick_snap_show_peek_in_view_did_appear"
        ])) return SCITargetedMCDecisionForceTrue;
    }

    if (SCITMCBool(@"igt_directnotes_friendmap")) {
        if (SCITMCContainsAny(l, @[
            @"_ig_test_sessioned_mc_ig_notes_friend_map_enabled",
            @"_ig_friend_map_location_update",
            @"_ig_ios_friend_map",
            @"_ig_ios_friendmap",
            @"_ig_ios_friends_map",
            @"_ig_ios_friend_lane",
            @"ig_test_sessioned_mc_ig_notes_friend_map_enabled",
            @"ig_friend_map_location_update",
            @"ig_ios_friend_map",
            @"ig_ios_friendmap",
            @"ig_ios_friends_map",
            @"ig_ios_friend_lane"
        ])) return SCITargetedMCDecisionForceTrue;
    }

    if (SCITMCBool(@"igt_icebreaker") || SCITMCBool(@"igt_mutual_interest")) {
        if (SCITMCContainsAny(l, @[
            @"_ig_ios_notes_icebreakers",
            @"_ctd_in_thread_icebreakers_ios_mc",
            @"_biig_icebreaker_completeness_upsell_mc",
            @"_igd_ios_default_icebreakers_in_faq_settings",
            @"_ig_default_icebreaker_appointment",
            @"ig_ios_notes_icebreakers",
            @"ctd_in_thread_icebreakers_ios_mc",
            @"biig_icebreaker_completeness_upsell_mc",
            @"igd_ios_default_icebreakers_in_faq_settings",
            @"ig_default_icebreaker_appointment"
        ])) return SCITargetedMCDecisionForceTrue;
    }

    if (SCITMCBool(@"igt_stories_tray_tap_prefetch") &&
        SCITMCContainsAny(l, @[@"stories_tray_tap_prefetch", @"story_tray_tap_prefetch", @"tray_tap_prefetch", @"tap_prefetch"])) {
        return SCITargetedMCDecisionForceTrue;
    }
    if (SCITMCBool(@"igt_stories_tray_title_interaction") &&
        SCITMCContainsAny(l, @[@"stories_tray_title", @"story_tray_title", @"tray_title_interaction", @"title_interaction"])) {
        return SCITargetedMCDecisionForceTrue;
    }
    if (SCITMCBool(@"igt_stories_feed_decoupling") &&
        SCITMCContainsAny(l, @[@"stories_feed_decoupling", @"story_feed_decoupling", @"feed_decoupling"])) {
        return SCITargetedMCDecisionForceTrue;
    }
    if (SCITMCBool(@"igt_stories_independent_fetch") &&
        SCITMCContainsAny(l, @[@"stories_independent_fetch", @"story_independent_fetch", @"independent_fetch", @"storiesfetchhandled", @"stories_fetch"])) {
        return SCITargetedMCDecisionForceTrue;
    }
    if (SCITMCBool(@"igt_stories_tray_decoupling")) {
        if (SCITMCContainsAny(l, @[
            @"_ig_ios_stories_tray",
            @"_ig_ios_story_tray",
            @"_ig_story_tray",
            @"_ig_ios_stories_in_view_nav_tray",
            @"_ig_empty_story_tray_su_redesign",
            @"ig_ios_stories_tray",
            @"ig_ios_story_tray",
            @"ig_story_tray",
            @"ig_ios_stories_in_view_nav_tray",
            @"ig_empty_story_tray_su_redesign"
        ])) return SCITargetedMCDecisionForceTrue;
    }

    if (SCITMCBool(@"igt_dm_inline_like")) {
        if (SCITMCContainsAny(l, @[@"dm_inline_like", @"direct_inline_like", @"inline_like"])) {
            return SCITargetedMCDecisionForceTrue;
        }
    }

    return SCITargetedMCDecisionNone;
}

static NSString *SCITMCKey(Class cls, SEL sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

static IMP SCITMCOriginal(id self, SEL sel) {
    if (!self || !sel) return NULL;
    Class c = object_getClass(self);
    NSString *selName = NSStringFromSelector(sel);
    while (c) {
        NSValue *v = gSCITMCOriginals[[NSString stringWithFormat:@"%@:%@", NSStringFromClass(c), selName]];
        if (v) return (IMP)v.pointerValue;
        c = class_getSuperclass(c);
    }
    return NULL;
}

static BOOL SCITMCOverrideValueForParam(id param, BOOL *valueOut) {
    SCITargetedMCDecision d = SCITMCDecisionForName(SCITMCNameForParam(param));
    if (d == SCITargetedMCDecisionNone) return NO;
    if (valueOut) *valueOut = (d == SCITargetedMCDecisionForceTrue);
    return YES;
}

static BOOL SCITMCHook_getBool(id self, SEL _cmd, id param) {
    BOOL forced = NO;
    if (SCITMCOverrideValueForParam(param, &forced)) return forced;
    BOOL (*orig)(id, SEL, id) = (BOOL (*)(id, SEL, id))SCITMCOriginal(self, _cmd);
    return orig ? orig(self, _cmd, param) : NO;
}

static BOOL SCITMCHook_getBool_default(id self, SEL _cmd, id param, BOOL def) {
    BOOL forced = NO;
    if (SCITMCOverrideValueForParam(param, &forced)) return forced;
    BOOL (*orig)(id, SEL, id, BOOL) = (BOOL (*)(id, SEL, id, BOOL))SCITMCOriginal(self, _cmd);
    return orig ? orig(self, _cmd, param, def) : def;
}

static BOOL SCITMCHook_getBool_options(id self, SEL _cmd, id param, id options) {
    BOOL forced = NO;
    if (SCITMCOverrideValueForParam(param, &forced)) return forced;
    BOOL (*orig)(id, SEL, id, id) = (BOOL (*)(id, SEL, id, id))SCITMCOriginal(self, _cmd);
    return orig ? orig(self, _cmd, param, options) : NO;
}

static BOOL SCITMCHook_getBool_options_default(id self, SEL _cmd, id param, id options, BOOL def) {
    BOOL forced = NO;
    if (SCITMCOverrideValueForParam(param, &forced)) return forced;
    BOOL (*orig)(id, SEL, id, id, BOOL) = (BOOL (*)(id, SEL, id, id, BOOL))SCITMCOriginal(self, _cmd);
    return orig ? orig(self, _cmd, param, options, def) : def;
}

static void SCITMCHookMethod(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    char ret[8] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (ret[0] != 'B' && ret[0] != 'c' && ret[0] != 'C') return;

    IMP old = NULL;
    MSHookMessageEx(cls, sel, replacement, &old);
    if (old) gSCITMCOriginals[SCITMCKey(cls, sel)] = [NSValue valueWithPointer:(const void *)old];
}

static void SCITMCHookClassNamed(NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SCITMCHookMethod(cls, @selector(getBool:), (IMP)SCITMCHook_getBool);
    SCITMCHookMethod(cls, @selector(getBoolWithoutLogging:), (IMP)SCITMCHook_getBool);
    SCITMCHookMethod(cls, @selector(getBool:withDefault:), (IMP)SCITMCHook_getBool_default);
    SCITMCHookMethod(cls, @selector(getBoolWithoutLogging:withDefault:), (IMP)SCITMCHook_getBool_default);
    SCITMCHookMethod(cls, @selector(getBool:withOptions:), (IMP)SCITMCHook_getBool_options);
    SCITMCHookMethod(cls, @selector(getBool:withOptions:withDefault:), (IMP)SCITMCHook_getBool_options_default);
}

%ctor {
    if (!SCITMCAnyEnabled()) return;

    gSCITMCOriginals = [NSMutableDictionary dictionary];
    NSArray<NSString *> *classes = @[
        @"IGMobileConfigContextManager",
        @"IGMobileConfigUserSessionContextManager",
        @"IGMobileConfigSessionlessContextManager",
        @"FBMobileConfigContextManager",
        @"FBMobileConfigUserSessionContextManager",
        @"FBMobileConfigSessionlessContextManager"
    ];
    for (NSString *className in classes) SCITMCHookClassNamed(className);
}
