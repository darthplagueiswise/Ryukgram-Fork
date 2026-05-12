#import "../../Utils.h"
#import <objc/runtime.h>
#import <pthread.h>

static BOOL pref(NSString *key) { return [SCIUtils getBoolPref:key]; }

static NSMutableDictionary<NSString *, NSValue *> *gSCINavOriginals;
static pthread_mutex_t gSCINavLock = PTHREAD_MUTEX_INITIALIZER;

static NSString *SCINavOriginalKey(Class cls, NSString *selectorName) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), selectorName ?: @""];
}

static NSNumber *SCINavForcedValueForSelector(NSString *selectorName) {
    if ([selectorName isEqualToString:@"audioRampingOnSwipeEnabled"] && pref(@"igt_audio_ramping")) return @YES;
    if ([selectorName isEqualToString:@"enablePullToCarrera"] && pref(@"igt_pull_to_carrera")) return @YES;
    if (([selectorName isEqualToString:@"isReelsSecondEnabled"] || [selectorName isEqualToString:@"isReelsSecondOptInFlowEnabled"]) && pref(@"igt_reels_first")) return @YES;
    if ([selectorName isEqualToString:@"isDynamicTabStoryGridEnabled"] && (pref(@"igt_story_grid") || pref(@"igt_homecoming"))) return @YES;
    if (([selectorName isEqualToString:@"isFriendLaneFeedEnabled"] || [selectorName isEqualToString:@"isFriendsIVLaneInFeedSwitcherEnabled"] || [selectorName isEqualToString:@"isFriendsFeedSeeOlderPostsEnabled"]) && pref(@"igt_friends_feed")) return @YES;
    if ([selectorName isEqualToString:@"isRemovalOfFriendsFeedEnabled"] && pref(@"igt_friends_feed")) return @NO;
    if (([selectorName isEqualToString:@"isFeedSwitcherEnabled"] || [selectorName isEqualToString:@"useHomecomingEndpoint"] || [selectorName isEqualToString:@"isHomecomingStoriesAccessFaceClusterEnabled"]) && pref(@"igt_homecoming")) return @YES;
    if (([selectorName isEqualToString:@"isFeedCullingOnStoriesAccessEnabled"] || [selectorName isEqualToString:@"isFeedCullingOnStatusBarEnabled"]) && pref(@"igt_feed_culling")) return @YES;
    if (([selectorName isEqualToString:@"isFeedDedupEnabled"] || [selectorName isEqualToString:@"isFeedDedupFromReelsEnabled"] || [selectorName isEqualToString:@"isFeedDedupFromReelsOptimizationEnabled"]) && pref(@"igt_feed_dedup")) return @YES;
    if ([selectorName isEqualToString:@"isStoriesTrayOnAllTabsEnabled"] && (pref(@"igt_stories_tray_all_tabs") || pref(@"igt_homecoming"))) return @YES;
    if (([selectorName isEqualToString:@"isStoriesFetchHandledIndependently"] || [selectorName isEqualToString:@"isStoriesVPVNavChainFixEnabled"]) && (pref(@"igt_stories_tray_decoupling") || pref(@"igt_homecoming"))) return @YES;
    if ([selectorName isEqualToString:@"isStoriesFetchDisabledInFeedViewModel"] && pref(@"igt_stories_tray_decoupling")) return @NO;
    if ([selectorName isEqualToString:@"hideStoriesTrayOnClassicFeed"] && pref(@"igt_stories_show_classic")) return @NO;
    if ([selectorName isEqualToString:@"isVerticalStoriesTray"] && pref(@"igt_vertical_stories_tray")) return @YES;
    if ([selectorName isEqualToString:@"showCinemaStoriesTrayOnSwipeUp"] && (pref(@"igt_stories_tray_cinema_swipe") || pref(@"igt_homecoming"))) return @YES;
    return nil;
}

static BOOL SCINavBoolRouter(id self, SEL _cmd) {
    NSString *selectorName = NSStringFromSelector(_cmd);
    NSNumber *forced = SCINavForcedValueForSelector(selectorName);
    if (forced) return forced.boolValue;

    NSValue *origValue = nil;
    pthread_mutex_lock(&gSCINavLock);
    Class cls = object_getClass(self);
    while (cls && !origValue) {
        origValue = gSCINavOriginals[SCINavOriginalKey(cls, selectorName)];
        cls = class_getSuperclass(cls);
    }
    pthread_mutex_unlock(&gSCINavLock);

    if (!origValue) return NO;
    BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
    return orig ? orig(self, _cmd) : NO;
}

static BOOL SCINavMethodIsBoolGetter(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char rt[16] = {0};
    method_getReturnType(method, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c' || rt[0] == 'C';
}

static void SCINavHookBoolGetter(Class cls, NSString *selectorName) {
    if (!cls || !selectorName.length) return;
    SEL sel = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!SCINavMethodIsBoolGetter(method)) return;
    IMP original = method_setImplementation(method, (IMP)SCINavBoolRouter);
    if (!original) return;
    pthread_mutex_lock(&gSCINavLock);
    gSCINavOriginals[SCINavOriginalKey(cls, selectorName)] = [NSValue valueWithPointer:(const void *)original];
    pthread_mutex_unlock(&gSCINavLock);
}

static void SCINavHookClassNames(NSArray<NSString *> *classNames, NSArray<NSString *> *selectors) {
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        for (NSString *selectorName in selectors) SCINavHookBoolGetter(cls, selectorName);
    }
}

%ctor {
    BOOL any = pref(@"igt_feed_culling") ||
               pref(@"igt_feed_dedup") ||
               pref(@"igt_friends_feed") ||
               pref(@"igt_reels_first") ||
               pref(@"igt_pull_to_carrera") ||
               pref(@"igt_audio_ramping") ||
               pref(@"igt_story_grid") ||
               pref(@"igt_homecoming") ||
               pref(@"igt_stories_tray_decoupling") ||
               pref(@"igt_stories_tray_all_tabs") ||
               pref(@"igt_stories_show_classic") ||
               pref(@"igt_vertical_stories_tray") ||
               pref(@"igt_stories_tray_cinema_swipe");
    if (!any) return;

    gSCINavOriginals = [NSMutableDictionary dictionary];
    SCINavHookClassNames(@[
        @"_TtC18IGNavConfiguration18IGNavConfiguration",
        @"IGNavConfiguration.IGNavConfiguration",
        @"IGNavConfiguration"
    ], @[
        @"audioRampingOnSwipeEnabled",
        @"enablePullToCarrera",
        @"isReelsSecondEnabled",
        @"isReelsSecondOptInFlowEnabled"
    ]);

    SCINavHookClassNames(@[
        @"_TtC18IGNavConfiguration25IGHomecomingConfiguration",
        @"IGNavConfiguration.IGHomecomingConfiguration",
        @"IGHomecomingConfiguration"
    ], @[
        @"isReelsSecondOptInFlowEnabled",
        @"isDynamicTabStoryGridEnabled",
        @"isFriendLaneFeedEnabled",
        @"isFriendsIVLaneInFeedSwitcherEnabled",
        @"isFriendsFeedSeeOlderPostsEnabled",
        @"isRemovalOfFriendsFeedEnabled",
        @"isFeedSwitcherEnabled",
        @"useHomecomingEndpoint",
        @"isHomecomingStoriesAccessFaceClusterEnabled",
        @"isFeedCullingOnStoriesAccessEnabled",
        @"isFeedCullingOnStatusBarEnabled",
        @"isFeedDedupEnabled",
        @"isFeedDedupFromReelsEnabled",
        @"isFeedDedupFromReelsOptimizationEnabled",
        @"isStoriesTrayOnAllTabsEnabled",
        @"isStoriesFetchHandledIndependently",
        @"isStoriesFetchDisabledInFeedViewModel",
        @"isStoriesVPVNavChainFixEnabled",
        @"hideStoriesTrayOnClassicFeed",
        @"isVerticalStoriesTray",
        @"showCinemaStoriesTrayOnSwipeUp"
    ]);
}
