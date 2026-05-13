#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>

//
// FeatureGatingCompat.xm  (dev2  binary-verified)
//
// Binary verification: Instagram arm64 + FBSharedFramework arm64 lief scan.
//
// WHAT THIS FILE DOES:
//   Hooks boolean getter methods on feature-gating classes to return YES
//   when the corresponding RyukGram toggle is on. Uses MSHookMessageEx on
//   ObjC classes  only touches __DATA (method IMP table), never __TEXT.
//   Safe for sideload: no code signing impact.
//
// VERIFIED CLASSES:
//    _TtC32IGDirectMutualInterestIcebreaker42IGDirectMutualInterestFeatureGatingService
//    _TtC32IGDirectMutualInterestIcebreaker33IGDirectMutualInterestEligibility
//    _TtC32IGDirectMutualInterestIcebreaker29IGDirectMutualInterestService
//    _TtC24IGMainFeedViewModelSwift36IGMainFeedDataControllerDedupManager
//    _TtC19IGFriendlyFeedUtils19IGFriendlyFeedUtils
//    _TtC26IGFriendlyViewModelHelpers37IGFriendlyFeedOverlayViewModelService
//    IGDirectMessageMenuStaticEligibilityContext
//
// CONFIRMED SELECTORS (from binary scan + Flex screenshots):
//    isMutuallyLikedReelsIcebreakerEnabled  (icebreaker)
//    isFeedDedupEnabled                     (feed dedup)
//    isFeedDedupFromReelsEnabled             (feed dedup)
//    isFriendLaneFeedEnabled                 (friends feed)
//    isRemovalOfFriendsFeedEnabled           (friends feed  INVERTED)
//    isStoriesTrayDecouplingEnabled          (stories tray)
//    _isStoriesTrayDecouplingEnabled         (stories tray)
//    isStoriesTrayTapPrefetchEnabled         (stories tray)
//    isHomeComingEnabled  (note: capital C  isHomecomingEnabled )
//    isPrismEnabled, _isPrismEnabled
//

static NSMutableDictionary<NSString *, NSValue *> *gFGOriginals;
static pthread_mutex_t gFGLock = PTHREAD_MUTEX_INITIALIZER;

// Returns pref keys for a given selector name, or nil if we don't own it.
static NSArray<NSString *> *sciPrefKeysForFGSel(NSString *sel) {
    if (!sel.length) return nil;
    NSString *l = sel.lowercaseString;

    // Icebreaker / MutualInterest
    if ([l containsString:@"icebreaker"] || [l containsString:@"mutuallyliked"])
        return @[@"igt_icebreaker", @"igt_mutual_interest"];
    if ([l containsString:@"mutualinterest"] || ([l containsString:@"mutual"] && [l containsString:@"interest"]))
        return @[@"igt_mutual_interest"];
    if ([l containsString:@"stickercard"] || [l containsString:@"sticker_card"])
        return @[@"igt_icebreaker", @"igt_mutual_interest"];
    if ([l containsString:@"mutualfollow"])
        return @[@"igt_mutual_interest"];

    // Friends Feed / Friend Lane
    if ([l containsString:@"friendlanefeed"] || [l containsString:@"friendlane"])
        return @[@"igt_friends_feed"];
    if ([l containsString:@"friendsfeed"] || [l containsString:@"friends_feed"] ||
        ([l containsString:@"friends"] && [l containsString:@"feed"]))
        return @[@"igt_friends_feed"];
    // isRemovalOfFriendsFeedEnabled  handled inverted below
    if ([l containsString:@"removaloffriendsf"] || [l containsString:@"removal_of_friends_feed"])
        return @[@"igt_friends_feed"];

    // Feed Dedup
    if ([l containsString:@"feeddedup"] || [l containsString:@"feed_dedup"])
        return @[@"igt_feed_dedup"];

    // Reels First
    if ([l containsString:@"reelsfirst"] || [l containsString:@"reels_first"] ||
        ([l containsString:@"reels"] && [l containsString:@"first"]))
        return @[@"igt_reels_first"];

    // Feed Culling
    if ([l containsString:@"feedculling"] || [l containsString:@"feed_culling"] || [l containsString:@"culling"])
        return @[@"igt_feed_culling"];

    // Pull to Carrera
    if ([l containsString:@"carrera"])
        return @[@"igt_pull_to_carrera"];

    // Audio Ramping
    if ([l containsString:@"audioramp"] || [l containsString:@"audio_ramp"])
        return @[@"igt_audio_ramping"];

    // Tab Swiping
    if ([l containsString:@"tabswip"] || [l containsString:@"tab_swip"])
        return @[@"igt_tab_swiping"];

    // QuickSnap
    if ([l containsString:@"quicksnap"] || [l containsString:@"quick_snap"])
        return @[@"igt_quicksnap"];
    if ([l containsString:@"instants"] && ![l containsString:@"instant_message"])
        return @[@"igt_quicksnap"];

    // Prism
    if ([l containsString:@"prism"])
        return @[@"igt_prism"];

    // Homecoming  note binary has isHomeComingEnabled (capital C), not isHomecomingEnabled
    if ([l containsString:@"homecoming"])
        return @[@"igt_homecoming"];

    // Story Grid
    if ([l containsString:@"storygrid"] || [l containsString:@"story_grid"] ||
        ([l containsString:@"story"] && [l containsString:@"grid"]))
        return @[@"igt_story_grid"];

    // Stories Tray Decoupling
    if ([l containsString:@"storiestray"] || [l containsString:@"stories_tray"] ||
        [l containsString:@"feeddecoupl"] || [l containsString:@"feed_decoupl"])
        return @[@"igt_stories_tray_decoupling"];

    // DM Inline Like
    if ([l containsString:@"inlinelike"] || [l containsString:@"inline_like"])
        return @[@"igt_dm_inline_like"];

    // Multiple Notes
    if ([l containsString:@"multiplenotes"] || [l containsString:@"multiple_notes"])
        return @[@"igt_multiple_notes"];

    // First Note Badge
    if ([l containsString:@"firstnotebadge"] || [l containsString:@"first_note_badge"])
        return @[@"igt_dn_first_badge"];

    return nil;
}

static NSString *sciCompositeKey(Class cls, NSString *sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), sel];
}

// Central hook IMP  installed on any matching boolean getter.
static BOOL sciFeatureGateDynHook(id self, SEL _cmd) {
    NSString *selName = NSStringFromSelector(_cmd);
    NSArray<NSString *> *keys = sciPrefKeysForFGSel(selName);
    for (NSString *k in keys) {
        if ([SCIUtils getBoolPref:k]) {
            // isRemovalOfFriendsFeedEnabled must be INVERTED:
            // returning NO prevents the feed removal when friends-feed is on.
            NSString *sl = selName.lowercaseString;
            if ([sl containsString:@"removalof"] || [sl containsString:@"removal_of"])
                return NO;
            return YES;
        }
    }
    // Fall through to original IMP
    pthread_mutex_lock(&gFGLock);
    NSValue *val = nil;
    Class c = object_getClass(self);
    while (c && !val) {
        val = gFGOriginals[sciCompositeKey(c, selName)];
        c = class_getSuperclass(c);
    }
    pthread_mutex_unlock(&gFGLock);
    if (val) {
        BOOL (*origIMP)(id, SEL) = (BOOL (*)(id, SEL))(uintptr_t)val.pointerValue;
        return origIMP(self, _cmd);
    }
    return NO;
}

// Hook all matching boolean getters on a class.
static void sciHookFGClass(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *selName = NSStringFromSelector(sel);
        // Only zero-arg booleans
        if (method_getNumberOfArguments(methods[i]) != 2) continue;
        char ret[8] = {0};
        method_getReturnType(methods[i], ret, sizeof(ret));
        if (ret[0] != 'B' && ret[0] != 'c' && ret[0] != 'C') continue;
        if (!sciPrefKeysForFGSel(selName)) continue;
        IMP old = NULL;
        MSHookMessageEx(cls, sel, (IMP)sciFeatureGateDynHook, &old);
        if (old) {
            pthread_mutex_lock(&gFGLock);
            gFGOriginals[sciCompositeKey(cls, selName)] = [NSValue valueWithPointer:(const void *)old];
            pthread_mutex_unlock(&gFGLock);
        }
    }
    free(methods);
}

static void sciHookSpecificMethod(Class hookClass, NSString *selName) {
    if (!hookClass) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(hookClass, sel)) return;
    if (!sciPrefKeysForFGSel(selName)) return;
    IMP old = NULL;
    MSHookMessageEx(hookClass, sel, (IMP)sciFeatureGateDynHook, &old);
    if (old) {
        pthread_mutex_lock(&gFGLock);
        gFGOriginals[sciCompositeKey(hookClass, selName)] = [NSValue valueWithPointer:(const void *)old];
        pthread_mutex_unlock(&gFGLock);
    }
}

// Hook a specific selector directly (for confirmed selectors on unknown classes).
static void sciHookSpecificSel(Class cls, NSString *selName) {
    if (!cls) return;
    sciHookSpecificMethod(cls, selName);
    sciHookSpecificMethod(object_getClass(cls), selName);
}

%ctor {
    NSArray<NSString *> *featureKeys = @[
        @"igt_mutual_interest", @"igt_icebreaker", @"igt_friends_feed",
        @"igt_stories_tray_decoupling", @"igt_dm_inline_like", @"igt_multiple_notes",
        @"igt_dn_first_badge", @"igt_feed_dedup", @"igt_reels_first", @"igt_feed_culling",
        @"igt_pull_to_carrera", @"igt_audio_ramping", @"igt_tab_swiping",
        @"igt_quicksnap", @"igt_prism", @"igt_homecoming", @"igt_story_grid"
    ];
    BOOL any = NO;
    for (NSString *k in featureKeys) {
        if ([SCIUtils getBoolPref:k]) { any = YES; break; }
    }
    if (!any) return;

    gFGOriginals = [NSMutableDictionary dictionary];

    //  Binary-verified class list
    NSArray<NSString *> *fgClassNames = @[
        //  Icebreaker / MutualInterest
        // Feature gating service: isMutuallyLikedReelsIcebreakerEnabled
        @"_TtC32IGDirectMutualInterestIcebreaker42IGDirectMutualInterestFeatureGatingService",
        // Eligibility checker
        @"_TtC32IGDirectMutualInterestIcebreaker33IGDirectMutualInterestEligibility",
        // Service coordinator
        @"_TtC32IGDirectMutualInterestIcebreaker29IGDirectMutualInterestService",

        //  Feed Dedup
        // isFeedDedupEnabled, isFeedDedupFromReelsEnabled
        @"_TtC24IGMainFeedViewModelSwift36IGMainFeedDataControllerDedupManager",

        //  Friends Feed / FriendLane
        // isFriendLaneFeedEnabled, isRemovalOfFriendsFeedEnabled
        @"_TtC19IGFriendlyFeedUtils19IGFriendlyFeedUtils",
        @"_TtC26IGFriendlyViewModelHelpers37IGFriendlyFeedOverlayViewModelService",

        //  DM Inline Like
        @"IGDirectMessageMenuStaticEligibilityContext",
    ];

    for (NSString *className in fgClassNames) {
        sciHookFGClass(NSClassFromString(className));
    }

    //  Explicit confirmed selectors whose home class is not above
    // These were confirmed  in binary but home class is unknown at compile time.
    // Use runtime class scan  only once, after startup.
    static BOOL sDidScan = NO;
    if (!sDidScan) {
        sDidScan = YES;

        // Confirmed selectors not covered by above classes
        NSArray<NSString *> *looseSels = @[
            @"isFriendLaneFeedEnabled",            //
            @"isRemovalOfFriendsFeedEnabled",      //
            @"isStoriesTrayDecouplingEnabled",     //
            @"_isStoriesTrayDecouplingEnabled",    //
            @"isStoriesTrayTapPrefetchEnabled",    //
            @"isHomeComingEnabled",                //  (capital C  NOT isHomecomingEnabled)
            @"isHomecomingExperienceEnabled",      //
            @"isMutuallyLikedReelsIcebreakerEnabled", //
        ];

        unsigned int classCount = 0;
        Class *classList = objc_copyClassList(&classCount);
        for (unsigned int i = 0; i < classCount; i++) {
            Class cls = classList[i];
            for (NSString *selName in looseSels) {
                SEL sel = NSSelectorFromString(selName);
                if (!class_getInstanceMethod(cls, sel) && !class_getClassMethod(cls, sel)) continue;
                sciHookSpecificSel(cls, selName);
            }
        }
        free(classList);
    }
}
