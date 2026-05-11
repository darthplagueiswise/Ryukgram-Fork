#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL pref(NSString *key) { return [SCIUtils getBoolPref:key]; }

static BOOL (*orig_bool_nav)(id, SEL) = NULL;
static BOOL ret_true(id self, SEL _cmd) { return YES; }
static BOOL ret_false(id self, SEL _cmd) { return NO; }

static void hookBool0(NSString *className, NSString *selName, IMP repl, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, repl, orig);
}

static void hookNavBool(NSString *selName, IMP repl) {
    NSArray<NSString *> *classes = @[
        @"_TtC18IGNavConfiguration18IGNavConfiguration",
        @"IGNavConfiguration"
    ];
    for (NSString *className in classes) hookBool0(className, selName, repl, (IMP *)&orig_bool_nav);
}

static void hookHomecomingBool(NSString *selName, IMP repl) {
    NSArray<NSString *> *classes = @[
        @"_TtC18IGNavConfiguration012IGHomecomingB0C",
        @"IGNavConfiguration.IGHomecomingConfiguration",
        @"IGHomecomingConfiguration"
    ];
    for (NSString *className in classes) hookBool0(className, selName, repl, (IMP *)&orig_bool_nav);
}

%ctor {
    BOOL any = pref(@"igt_feed_culling") ||
               pref(@"igt_feed_dedup") ||
               pref(@"igt_friends_feed") ||
               pref(@"igt_reels_first") ||
               pref(@"igt_pull_to_carrera") ||
               pref(@"igt_tab_swiping") ||
               pref(@"igt_audio_ramping") ||
               pref(@"igt_homecoming");
    if (!any) return;

    if (pref(@"igt_tab_swiping")) hookNavBool(@"isTabSwipingEnabled", (IMP)ret_true);
    if (pref(@"igt_audio_ramping")) hookNavBool(@"audioRampingOnSwipeEnabled", (IMP)ret_true);
    if (pref(@"igt_pull_to_carrera")) hookNavBool(@"enablePullToCarrera", (IMP)ret_true);

    if (pref(@"igt_reels_first")) {
        hookNavBool(@"isReelsSecondEnabled", (IMP)ret_true);
        hookNavBool(@"isReelsSecondOptInFlowEnabled", (IMP)ret_true);
        hookHomecomingBool(@"isReelsSecondOptInFlowEnabled", (IMP)ret_true);
    }

    if (pref(@"igt_feed_culling")) {
        hookHomecomingBool(@"isFeedCullingOnStoriesAccessEnabled", (IMP)ret_true);
        hookHomecomingBool(@"isFeedCullingOnStatusBarEnabled", (IMP)ret_true);
    }

    if (pref(@"igt_feed_dedup")) {
        hookHomecomingBool(@"isFeedDedupFromReelsOptimizationEnabled", (IMP)ret_true);
    }

    if (pref(@"igt_friends_feed")) {
        hookHomecomingBool(@"isFriendLaneFeedEnabled", (IMP)ret_true);
        hookHomecomingBool(@"isFriendsIVLaneInFeedSwitcherEnabled", (IMP)ret_true);
        hookHomecomingBool(@"isFriendsFeedSeeOlderPostsEnabled", (IMP)ret_true);
        hookHomecomingBool(@"isRemovalOfFriendsFeedEnabled", (IMP)ret_false);
    }

    if (pref(@"igt_homecoming")) {
        hookHomecomingBool(@"isDynamicTabStoryGridEnabled", (IMP)ret_true);
        hookHomecomingBool(@"isStoriesTrayOnAllTabsEnabled", (IMP)ret_true);
        hookHomecomingBool(@"isStoriesFetchHandledIndependently", (IMP)ret_true);
        hookHomecomingBool(@"isStoriesVPVNavChainFixEnabled", (IMP)ret_true);
        hookHomecomingBool(@"showCinemaStoriesTrayOnSwipeUp", (IMP)ret_true);
    }
}
