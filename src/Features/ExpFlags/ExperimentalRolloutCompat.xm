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

static BOOL sciReelsRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_reels_first"]) return NO;
    return sciContainsAny(name, @[
        @"ig_h1_26_friending_in_reels_first_world",
        @"ig_ios_appstart_cold_start_open_to_reels_tab_test",
        @"open_to_reels",
        @"reels_first",
        @"reels_second",
        @"reels_viewer",
        @"ig_ios_reels_ptr",
        @"ig_ios_reels_eager_pagination",
        @"ig_reels_eager_refresh"
    ]);
}

static BOOL sciFriendsFeedRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_friends_feed"]) return NO;
    return sciContainsAny(name, @[
        @"feed_timeline_friends",
        @"feed_timeline_friend_lane",
        @"friendly_feed",
        @"ig_ios_friendly_feed",
        @"friending_in_reels",
        @"ig_ios_clips_friendly_viewer",
        @"ig_ios_reels_ads_friendly_viewer",
        @"ig_feed_ads_friendly_bubbles"
    ]);
}

static BOOL sciFeedDedupRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_feed_dedup"]) return NO;
    return sciContainsAny(name, @[
        @"dedup",
        @"dedupe",
        @"ig_ios_client_dedupe",
        @"ig_client_comment_dedup",
        @"p92_ios_main_feed_explicit_dedup",
        @"ig_ios_reels_p13n_dedup",
        @"igios_search_ta_deduping"
    ]);
}

static BOOL sciFeedCullingRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_feed_culling"]) return NO;
    return sciContainsAny(name, @[
        @"feed_culling",
        @"culling",
        @"marie_kondo",
        @"hide_from_feed_unit",
        @"feed_cleanup",
        @"feed_organic_ini_ui_refresh"
    ]);
}

static BOOL sciPullToCarreraRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_pull_to_carrera"]) return NO;
    return sciContainsAny(name, @[
        @"carrera",
        @"pull_to_refresh",
        @"_ptr",
        @"feed_ptr",
        @"reels_ptr",
        @"mainfeed_request_add_auto_refresh_to_pull_to_refresh",
        @"igios_homecoming_carrera"
    ]);
}

static BOOL sciMutualInterestRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_mutual_interest"]) return NO;
    return sciContainsAny(name, @[
        @"mutual_interest",
        @"mutualinterest",
        @"mutual_follow",
        @"mutual_followed",
        @"mutually_liked",
        @"mutuallyliked",
        @"direct_mutual_interest"
    ]);
}

static BOOL sciIcebreakerRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_icebreaker"]) return NO;
    return sciContainsAny(name, @[
        @"icebreaker",
        @"ice_breaker",
        @"quick_reply_icebreaker",
        @"mutual_icebreaker",
        @"xma_spark_icebreaker"
    ]);
}

static BOOL sciStoryGridRollout(NSString *name) {
    if (![SCIUtils getBoolPref:@"igt_story_grid"]) return NO;
    return sciContainsAny(name, @[
        @"story_grid",
        @"stories_grid",
        @"storygrid",
        @"stories_tray_grid",
        @"dynamic_tab_story_grid"
    ]);
}

static BOOL sciShouldForceOff(NSString *name) {
    return sciQuickSnapDisableRollout(name);
}

static BOOL sciShouldForceOn(NSString *name) {
    if (sciShouldForceOff(name)) return NO;
    return sciQuickSnapRollout(name) ||
           sciFriendMapRollout(name) ||
           sciPrismRollout(name) ||
           sciReelsRollout(name) ||
           sciFriendsFeedRollout(name) ||
           sciFeedDedupRollout(name) ||
           sciFeedCullingRollout(name) ||
           sciPullToCarreraRollout(name) ||
           sciMutualInterestRollout(name) ||
           sciIcebreakerRollout(name) ||
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
          [SCIUtils getBoolPref:@"igt_reels_first"] ||
          [SCIUtils getBoolPref:@"igt_friends_feed"] ||
          [SCIUtils getBoolPref:@"igt_feed_culling"] ||
          [SCIUtils getBoolPref:@"igt_feed_dedup"] ||
          [SCIUtils getBoolPref:@"igt_pull_to_carrera"] ||
          [SCIUtils getBoolPref:@"igt_mutual_interest"] ||
          [SCIUtils getBoolPref:@"igt_icebreaker"] ||
          [SCIUtils getBoolPref:@"igt_story_grid"])) return;

    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"isInExperiment", (IMP)new_meta_isInExperiment, (IMP *)&orig_meta_isInExperiment);
    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"groupName", (IMP)new_groupName, (IMP *)&orig_groupName);
    sciHookInst(NSClassFromString(@"MetaLocalExperiment"), @"peekGroupName", (IMP)new_peekGroupName, (IMP *)&orig_peekGroupName);
    sciHookInst(NSClassFromString(@"FamilyLocalExperiment"), @"isInExperiment", (IMP)new_family_isInExperiment, (IMP *)&orig_family_isInExperiment);
    sciHookInst(NSClassFromString(@"LIDExperimentGenerator"), @"isExperimentEnabled:", (IMP)new_lid_isExperimentEnabled, (IMP *)&orig_lid_isExperimentEnabled);
}
