#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>

static NSMutableDictionary<NSString *, NSValue *> *gFGOriginals;
static pthread_mutex_t gFGLock = PTHREAD_MUTEX_INITIALIZER;

static NSArray<NSString *> *sciPrefKeysForFGSel(NSString *sel) {
    if (!sel.length) return nil;
    NSString *l = sel.lowercaseString;

    if ([l containsString:@"quicksnap"] || [l containsString:@"quick_snap"] || [l containsString:@"qpenabled"])
        return @[@"igt_quicksnap"];
    if ([l containsString:@"instants"] && ![l containsString:@"instant_message"])
        return @[@"igt_quicksnap"];

    if ([l containsString:@"friendmap"] || [l containsString:@"friend_map"] || [l containsString:@"friendsmap"] || [l containsString:@"friends_map"] || [l containsString:@"friendlane"] || [l containsString:@"friend_lane"])
        return @[@"igt_directnotes_friendmap"];
    if (([l containsString:@"directnotes"] || [l containsString:@"notes"]) && ([l containsString:@"audio"] || [l containsString:@"voice"]))
        return @[@"igt_directnotes_audio_reply"];
    if (([l containsString:@"directnotes"] || [l containsString:@"notes"]) && [l containsString:@"avatar"])
        return @[@"igt_directnotes_avatar_reply"];
    if (([l containsString:@"directnotes"] || [l containsString:@"notes"]) && ([l containsString:@"gif"] || [l containsString:@"sticker"]))
        return @[@"igt_directnotes_gifs_reply"];
    if (([l containsString:@"directnotes"] || [l containsString:@"notes"]) && ([l containsString:@"photo"] || [l containsString:@"camera"]))
        return @[@"igt_directnotes_photo_reply"];

    if ([l containsString:@"icebreaker"])
        return @[@"igt_icebreaker", @"igt_mutual_interest"];
    if ([l containsString:@"mutuallyliked"] || [l containsString:@"mutually_liked"])
        return @[@"igt_icebreaker", @"igt_mutual_interest"];
    if ([l containsString:@"mutualinterest"] ||
        ([l containsString:@"mutual"] && [l containsString:@"interest"]))
        return @[@"igt_mutual_interest"];
    if ([l containsString:@"friendsfeed"] ||
        [l containsString:@"friends_feed"] ||
        ([l containsString:@"friends"] && [l containsString:@"feed"]))
        return @[@"igt_friends_feed"];
    if ([l containsString:@"dedup"] || [l containsString:@"deduplicate"] || [l containsString:@"deduplication"])
        return @[@"igt_feed_dedup"];
    if ([l containsString:@"reelsfirst"] || [l containsString:@"reels_first"] ||
        ([l containsString:@"reels"] && [l containsString:@"first"]))
        return @[@"igt_reels_first"];
    if ([l containsString:@"feedculling"] || [l containsString:@"feed_culling"] || [l containsString:@"culling"])
        return @[@"igt_feed_culling"];
    if ([l containsString:@"carrera"])
        return @[@"igt_pull_to_carrera"];
    if ([l containsString:@"audioramp"] || [l containsString:@"audio_ramp"] ||
        ([l containsString:@"audio"] && [l containsString:@"ramp"]))
        return @[@"igt_audio_ramping"];
    if ([l containsString:@"tabswip"] || [l containsString:@"tab_swip"] ||
        ([l containsString:@"tab"] && [l containsString:@"swip"]))
        return @[@"igt_tab_swiping"];
    if ([l containsString:@"prism"])
        return @[@"igt_prism"];
    if ([l containsString:@"homecoming"])
        return @[@"igt_homecoming"];
    if ([l containsString:@"storygrid"] || [l containsString:@"story_grid"] ||
        ([l containsString:@"story"] && [l containsString:@"grid"]))
        return @[@"igt_story_grid"];
    if ([l containsString:@"mutualfollow"])
        return @[@"igt_mutual_interest"];
    if ([l containsString:@"stickercard"])
        return @[@"igt_icebreaker", @"igt_mutual_interest"];
    if ([l containsString:@"tapprefetch"] || [l containsString:@"tap_prefetch"])
        return @[@"igt_stories_tray_tap_prefetch"];
    if ([l containsString:@"traytitle"] || [l containsString:@"tray_title"])
        return @[@"igt_stories_tray_title_interaction"];
    if ([l containsString:@"storiestray"] || [l containsString:@"stories_tray"] || [l containsString:@"storytray"] || [l containsString:@"story_tray"])
        return @[@"igt_stories_tray_decoupling"];
    if ([l containsString:@"feeddecoupl"] || [l containsString:@"feed_decoupl"])
        return @[@"igt_stories_feed_decoupling"];
    if ([l containsString:@"inlinelike"] || [l containsString:@"inline_like"])
        return @[@"igt_dm_inline_like"];
    if ([l containsString:@"friendlanefeed"] || [l containsString:@"friendlane"])
        return @[@"igt_friends_feed"];
    if ([l containsString:@"storiesfetchhandled"] || [l containsString:@"storiesindependent"] || [l containsString:@"independentfetch"] || [l containsString:@"independent_fetch"])
        return @[@"igt_stories_independent_fetch"];

    return nil;
}

static BOOL sciFGSelectorIsSupported(NSString *selName) {
    if (!selName.length) return NO;
    static NSSet<NSString *> *explicitSelectors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        explicitSelectors = [NSSet setWithArray:@[
            @"isQuicksnapEnabled:",
            @"isQuicksnapEnabledInInbox:",
            @"isQuicksnapEnabledAsPeek:",
            @"isQPEnabled:",
            @"_isEligibleForQuicksnapCornerStackTransitionDialog"
        ]];
    });
    if ([explicitSelectors containsObject:selName]) return YES;
    if ([selName hasPrefix:@"is"] && [selName hasSuffix:@"Enabled"]) return YES;
    if ([selName hasPrefix:@"_is"] && [selName hasSuffix:@"Enabled"]) return YES;
    return sciPrefKeysForFGSel(selName) != nil;
}

static NSString *sciCompositeKey(Class cls, NSString *sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), sel];
}

static IMP sciOriginalFor(id self, SEL sel) {
    if (!self || !sel) return NULL;
    NSString *selName = NSStringFromSelector(sel);
    pthread_mutex_lock(&gFGLock);
    NSValue *val = nil;
    Class c = object_getClass(self);
    while (c && !val) {
        val = gFGOriginals[sciCompositeKey(c, selName)];
        c = class_getSuperclass(c);
    }
    pthread_mutex_unlock(&gFGLock);
    return val ? (IMP)(uintptr_t)val.pointerValue : NULL;
}

static BOOL sciFeatureGateForcedValue(SEL sel, BOOL *valueOut) {
    NSString *selName = NSStringFromSelector(sel);
    NSArray<NSString *> *keys = sciPrefKeysForFGSel(selName);
    for (NSString *k in keys) {
        if ([SCIUtils getBoolPref:k]) {
            if (valueOut) *valueOut = YES;
            return YES;
        }
    }
    return NO;
}

static BOOL sciFeatureGateDynHook0(id self, SEL _cmd) {
    BOOL forced = NO;
    if (sciFeatureGateForcedValue(_cmd, &forced)) return forced;
    BOOL(*origIMP)(id, SEL) = (BOOL(*)(id,SEL))sciOriginalFor(self, _cmd);
    return origIMP ? origIMP(self, _cmd) : NO;
}

static BOOL sciFeatureGateDynHook1(id self, SEL _cmd, id arg1) {
    BOOL forced = NO;
    if (sciFeatureGateForcedValue(_cmd, &forced)) return forced;
    BOOL(*origIMP)(id, SEL, id) = (BOOL(*)(id,SEL,id))sciOriginalFor(self, _cmd);
    return origIMP ? origIMP(self, _cmd, arg1) : NO;
}

static void sciHookFGClass(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *selName = NSStringFromSelector(sel);
        if (!sciFGSelectorIsSupported(selName)) continue;
        if (!sciPrefKeysForFGSel(selName)) continue;

        Method m = methods[i];
        unsigned int argc = method_getNumberOfArguments(m);
        if (argc != 2 && argc != 3) continue;

        char ret[8] = {0};
        method_getReturnType(m, ret, sizeof(ret));
        if (ret[0] != 'B' && ret[0] != 'c' && ret[0] != 'C') continue;

        IMP old = NULL;
        IMP replacement = (argc == 3) ? (IMP)sciFeatureGateDynHook1 : (IMP)sciFeatureGateDynHook0;
        MSHookMessageEx(cls, sel, replacement, &old);
        if (old) {
            pthread_mutex_lock(&gFGLock);
            gFGOriginals[sciCompositeKey(cls, selName)] = [NSValue valueWithPointer:(const void *)old];
            pthread_mutex_unlock(&gFGLock);
        }
    }
    free(methods);
}

%ctor {
    NSArray<NSString *> *featureKeys = @[
        @"igt_mutual_interest", @"igt_icebreaker", @"igt_friends_feed",
        @"igt_stories_tray_decoupling", @"igt_stories_tray_tap_prefetch",
        @"igt_stories_tray_title_interaction", @"igt_stories_feed_decoupling",
        @"igt_stories_independent_fetch", @"igt_dm_inline_like",
        @"igt_feed_dedup", @"igt_reels_first", @"igt_feed_culling",
        @"igt_pull_to_carrera", @"igt_audio_ramping", @"igt_tab_swiping",
        @"igt_quicksnap", @"igt_prism", @"igt_homecoming", @"igt_story_grid",
        @"igt_directnotes_friendmap", @"igt_directnotes_audio_reply",
        @"igt_directnotes_avatar_reply", @"igt_directnotes_gifs_reply",
        @"igt_directnotes_photo_reply"
    ];
    BOOL any = NO;
    for (NSString *k in featureKeys) {
        if ([SCIUtils getBoolPref:k]) { any = YES; break; }
    }
    if (!any) return;

    gFGOriginals = [NSMutableDictionary dictionary];
    NSArray<NSString *> *fgClassNames = @[
        @"_TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper",
        @"IGQuickSnapExperimentationHelper",
        @"_TtC21IGNotesTrayController21IGNotesTrayController",
        @"IGNotesTrayController",
        @"_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper",
        @"_TtC32IGDirectMutualInterestIcebreaker42IGDirectMutualInterestFeatureGatingService",
        @"_TtC23IGStoryAdsPrefetchSwift27IGStoriesAdsPrefetchManager",
        @"IGDirectMessageMenuStaticEligibilityContext",
        @"_TtC18IGNavConfiguration25IGHomecomingConfiguration",
        @"_TtC18IGNavConfiguration28IGHomecomingNavConfiguration",
        @"_TtC18IGNavConfiguration18IGNavConfiguration",
        @"FeatureGatingService",
        @"FeatureGate",
    ];
    for (NSString *className in fgClassNames) {
        sciHookFGClass(NSClassFromString(className));
    }
}
