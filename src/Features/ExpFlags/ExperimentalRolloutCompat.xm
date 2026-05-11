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

static BOOL sciQuickSnapDisableRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_quicksnap"]) return NO;
    return sciContainsAny(name, @[
        @"ig_instants_hide",
        @"instants_hide",
        @"quick_snap_hide",
        @"quicksnap_hide",
        @"hide_quicksnap"
    ]);
}

static BOOL sciQuickSnapRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_quicksnap"]) return NO;
    if (sciQuickSnapDisableRollout(name)) return NO;
    return sciContainsAny(name, @[
        @"quicksnap",
        @"quick_snap",
        @"instants",
        @"xma_quicksnap",
        @"ig_ios_quicksnap",
        @"ig_ios_quick_snap",
        @"ig_ios_instants",
        @"ig_quick_snap_show_peek"
    ]);
}

static BOOL sciFriendMapRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_directnotes_friendmap"]) return NO;
    return sciContainsAny(name, @[@"friendmap", @"friends_map", @"direct_notes", @"ig_direct_notes_ios", @"_ig_ios_friendmap_", @"_ig_ios_friends_map_"]);
}

static BOOL sciPrismRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_prism"]) return NO;

    // Keep Prism scoped to menu/IGDS rollout names. Do not force every experiment
    // containing "prism", because unrelated Prism surfaces can expect server data
    // and crash when enabled blindly.
    return sciContainsAny(name, @[
        @"igds_prism",
        @"prism_menu",
        @"prism_overflow_menu",
        @"prism_context_menu",
        @"prism_bottom_sheet",
        @"prism_toasts",
        @"prism_alert_dialog",
        @"prism_media_buttons",
        @"prism_controls",
        @"ig_ios_prism_menu"
    ]);
}

static BOOL sciFriendsFeedRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_friends_feed"]) return NO;
    return sciContainsAny(name, @[@"friends_feed", @"ig_ios_friends_feed", @"friends_only_feed",
                                  @"ig_friends_feed", @"friendsfeed", @"ig_ios_friendsfeed"]);
}

static BOOL sciFeedDedupRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_feed_dedup"]) return NO;
    return sciContainsAny(name, @[@"feed_dedup", @"feed_deduplication", @"ig_ios_feed_dedup",
                                  @"ig_feed_dedup", @"feeddedup", @"feed_deduplicate"]);
}

static BOOL sciReelsFirstRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_reels_first"]) return NO;
    return sciContainsAny(name, @[@"reels_first", @"ig_reels_first", @"ig_ios_reels_first",
                                  @"reels_first_experience", @"reelsfirst", @"ig_ios_reelsfirst"]);
}

static BOOL sciFeedCullingRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_feed_culling"]) return NO;
    return sciContainsAny(name, @[@"feed_culling", @"ig_feed_culling", @"ig_ios_feed_cull",
                                  @"feedculling", @"ig_ios_feedculling"]);
}

static BOOL sciPullToCarreraRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_pull_to_carrera"]) return NO;
    return sciContainsAny(name, @[@"carrera", @"pull_to_carrera", @"ig_ios_carrera",
                                  @"ig_carrera", @"pulltocarrera"]);
}

static BOOL sciAudioRampingRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_audio_ramping"]) return NO;
    return sciContainsAny(name, @[@"audio_ramp", @"audio_ramping", @"ig_ios_audio_ramp",
                                  @"ig_audio_ramp", @"audioramp", @"audio_ramp_swipe"]);
}

static BOOL sciTabSwipingRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_tab_swiping"]) return NO;
    return sciContainsAny(name, @[@"tab_swip", @"tab_swiping", @"ig_ios_tab_swipe",
                                  @"ig_tab_swipe", @"tabswipe", @"tabswiping"]);
}

static BOOL sciMutualInterestRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_mutual_interest"]) return NO;
    return sciContainsAny(name, @[@"mutual_interest", @"mutualinterest", @"mutual_liked",
                                  @"mutually_liked", @"ig_mutual", @"ig_ios_mutual"]);
}

static BOOL sciIcebreakerRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_icebreaker"]) return NO;
    return sciContainsAny(name, @[@"icebreaker", @"ice_breaker", @"ig_icebreaker",
                                  @"mutual_icebreaker", @"ig_ios_icebreaker"]);
}

static BOOL sciStoryGridRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_story_grid"]) return NO;
    return sciContainsAny(name, @[@"story_grid", @"stories_grid", @"ig_story_grid",
                                  @"ig_ios_story_grid", @"storygrid", @"story_tray_grid"]);
}

static BOOL sciShouldForceOff(NSString *name) {
    return sciQuickSnapDisableRollout(name);
}

static BOOL sciShouldForceOn(NSString *name) {
    if (sciShouldForceOff(name)) return NO;
    return sciQuickSnapRollout(name) || sciFriendMapRollout(name) || sciPrismRollout(name) ||
           sciFriendsFeedRollout(name) || sciFeedDedupRollout(name) || sciReelsFirstRollout(name) ||
           sciFeedCullingRollout(name) || sciPullToCarreraRollout(name) || sciAudioRampingRollout(name) ||
           sciTabSwipingRollout(name) || sciMutualInterestRollout(name) || sciIcebreakerRollout(name) ||
           sciStoryGridRollout(name);
}

static BOOL (*orig_meta_isInExperiment)(id, SEL) = NULL;
static BOOL new_meta_isInExperiment(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOff(name)) return NO;
    if (sciShouldForceOn(name)) return YES;
    return orig_meta_isInExperiment ? orig_meta_isInExperiment(self, _cmd) : NO;
}

static BOOL (*orig_family_isInExperiment)(id, SEL) = NULL;
static BOOL new_family_isInExperiment(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOff(name)) return NO;
    if (sciShouldForceOn(name)) return YES;
    return orig_family_isInExperiment ? orig_family_isInExperiment(self, _cmd) : NO;
}

static BOOL (*orig_lid_isExperimentEnabled)(id, SEL, NSString *) = NULL;
static BOOL new_lid_isExperimentEnabled(id self, SEL _cmd, NSString *experimentName) {
    if (sciShouldForceOff(experimentName)) return NO;
    if (sciShouldForceOn(experimentName)) return YES;
    return orig_lid_isExperimentEnabled ? orig_lid_isExperimentEnabled(self, _cmd, experimentName) : NO;
}

static id (*orig_groupName)(id, SEL) = NULL;
static id new_groupName(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOff(name)) return nil;
    if (sciShouldForceOn(name)) return @"test";
    return orig_groupName ? orig_groupName(self, _cmd) : nil;
}

static id (*orig_peekGroupName)(id, SEL) = NULL;
static id new_peekGroupName(id self, SEL _cmd) {
    NSString *name = sciExperimentName(self);
    if (sciShouldForceOff(name)) return nil;
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
          [SCIUtils getBoolPref:@"igt_prism"] ||
          [SCIUtils getBoolPref:@"igt_friends_feed"] ||
          [SCIUtils getBoolPref:@"igt_feed_dedup"] ||
          [SCIUtils getBoolPref:@"igt_reels_first"] ||
          [SCIUtils getBoolPref:@"igt_feed_culling"] ||
          [SCIUtils getBoolPref:@"igt_pull_to_carrera"] ||
          [SCIUtils getBoolPref:@"igt_audio_ramping"] ||
          [SCIUtils getBoolPref:@"igt_tab_swiping"] ||
          [SCIUtils getBoolPref:@"igt_mutual_interest"] ||
          [SCIUtils getBoolPref:@"igt_icebreaker"] ||
          [SCIUtils getBoolPref:@"igt_story_grid"])) return;

    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"isInExperiment", (IMP)new_meta_isInExperiment, (IMP *)&orig_meta_isInExperiment);
    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"groupName", (IMP)new_groupName, (IMP *)&orig_groupName);
    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"peekGroupName", (IMP)new_peekGroupName, (IMP *)&orig_peekGroupName);
    sciHookInst(NSClassFromString(@"FamilyLocalExperiment"), @"isInExperiment", (IMP)new_family_isInExperiment, (IMP *)&orig_family_isInExperiment);
    sciHookInst(NSClassFromString(@"LIDExperimentGenerator"), @"isExperimentEnabled:", (IMP)new_lid_isExperimentEnabled, (IMP *)&orig_lid_isExperimentEnabled);
}
