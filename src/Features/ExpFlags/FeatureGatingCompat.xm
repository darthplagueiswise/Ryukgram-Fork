#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>

// ─────────────────────────────────────────────────────────────────────────────
// FeatureGatingCompat.xm  (beta2 — binary-verified class/selector names)
//
// Binary verification sources:
//   Instagram (arm64) — 280 MB
//   FBSharedFramework (arm64) — 52 MB
//
// All class names below were confirmed ✅ in the Instagram binary via lief
// __objc_methnames / __cstring section scan.
// ─────────────────────────────────────────────────────────────────────────────

static NSMutableDictionary<NSString *, NSValue *> *gFGOriginals;
static pthread_mutex_t gFGLock = PTHREAD_MUTEX_INITIALIZER;

// Maps a selector name to the NSUserDefaults keys it should check.
// Returns nil → do not hook this selector.
static NSArray<NSString *> *sciPrefKeysForFGSel(NSString *sel) {
    if (!sel.length) return nil;
    NSString *l = sel.lowercaseString;

    // ── Icebreaker / MutualInterest ──────────────────────────────────────────
    if ([l containsString:@"icebreaker"] || [l containsString:@"mutuallyliked"] || [l containsString:@"mutually_liked"])
        return @[@"igt_icebreaker", @"igt_mutual_interest"];
    if ([l containsString:@"mutualinterest"] || ([l containsString:@"mutual"] && [l containsString:@"interest"]))
        return @[@"igt_mutual_interest"];
    if ([l containsString:@"stickercard"] || [l containsString:@"sticker_card"])
        return @[@"igt_icebreaker", @"igt_mutual_interest"];

    // ── Friends Feed / Friend Lane ───────────────────────────────────────────
    if ([l containsString:@"friendsfeed"] || [l containsString:@"friends_feed"] ||
        ([l containsString:@"friends"] && [l containsString:@"feed"]))
        return @[@"igt_friends_feed"];
    if ([l containsString:@"friendlanefeed"] || [l containsString:@"friend_lane_feed"] ||
        [l containsString:@"friendlanecenter"])
        return @[@"igt_friends_feed"];
    // isRemovalOfFriendsFeedEnabled — invert: we want friends feed ON, so block
    // the removal gate (return NO so removal does not happen)
    if ([l containsString:@"removaloffriendsf"] || [l containsString:@"removal_of_friends_feed"])
        return @[@"igt_friends_feed"]; // handled inverted in hook

    // ── Feed Dedup ───────────────────────────────────────────────────────────
    if ([l containsString:@"feeddedup"] || [l containsString:@"feed_dedup"])
        return @[@"igt_feed_dedup"];

    // ── Reels First ──────────────────────────────────────────────────────────
    if ([l containsString:@"reelsfirst"] || [l containsString:@"reels_first"] ||
        ([l containsString:@"reels"] && [l containsString:@"first"]))
        return @[@"igt_reels_first"];

    // ── Feed Culling ─────────────────────────────────────────────────────────
    if ([l containsString:@"feedculling"] || [l containsString:@"feed_culling"] || [l containsString:@"culling"])
        return @[@"igt_feed_culling"];

    // ── Pull to Carrera ──────────────────────────────────────────────────────
    if ([l containsString:@"carrera"])
        return @[@"igt_pull_to_carrera"];

    // ── Audio Ramping ────────────────────────────────────────────────────────
    if ([l containsString:@"audioramp"] || [l containsString:@"audio_ramp"] ||
        ([l containsString:@"audio"] && [l containsString:@"ramp"]))
        return @[@"igt_audio_ramping"];

    // ── Tab Swiping ──────────────────────────────────────────────────────────
    if ([l containsString:@"tabswip"] || [l containsString:@"tab_swip"] ||
        ([l containsString:@"tab"] && [l containsString:@"swip"]))
        return @[@"igt_tab_swiping"];

    // ── QuickSnap / Instants ─────────────────────────────────────────────────
    if ([l containsString:@"quicksnap"] || [l containsString:@"quick_snap"])
        return @[@"igt_quicksnap"];
    if ([l containsString:@"instants"] && ![l containsString:@"instant_message"])
        return @[@"igt_quicksnap"];

    // ── Prism ────────────────────────────────────────────────────────────────
    if ([l containsString:@"prism"])
        return @[@"igt_prism"];

    // ── Homecoming ───────────────────────────────────────────────────────────
    if ([l containsString:@"homecoming"])
        return @[@"igt_homecoming"];

    // ── Story Grid ───────────────────────────────────────────────────────────
    if ([l containsString:@"storygrid"] || [l containsString:@"story_grid"] ||
        ([l containsString:@"story"] && [l containsString:@"grid"]))
        return @[@"igt_story_grid"];

    // ── Stories Tray Decoupling ──────────────────────────────────────────────
    if ([l containsString:@"storiestray"] || [l containsString:@"stories_tray"])
        return @[@"igt_stories_tray_decoupling"];
    if ([l containsString:@"feeddecoupl"] || [l containsString:@"feed_decoupl"])
        return @[@"igt_stories_tray_decoupling"];

    // ── DM Inline Like ───────────────────────────────────────────────────────
    if ([l containsString:@"inlinelike"] || [l containsString:@"inline_like"])
        return @[@"igt_dm_inline_like"];

    // ── Multiple Notes ───────────────────────────────────────────────────────
    if ([l containsString:@"multiplenotes"] || [l containsString:@"multiple_notes"])
        return @[@"igt_multiple_notes"];

    // ── First Note Badge ─────────────────────────────────────────────────────
    if ([l containsString:@"firstnotebadge"] || [l containsString:@"first_note_badge"])
        return @[@"igt_dn_first_badge"];

    return nil;
}

// Composite key: ClassName:selectorName
static NSString *sciCompositeKey(Class cls, NSString *sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), sel];
}

// Dynamic hook IMP — fired for every hooked boolean getter.
// Special case: isRemovalOfFriendsFeedEnabled must return NO when friends-feed
// override is active (removing friends feed = bad when we want it ON).
static BOOL sciFeatureGateDynHook(id self, SEL _cmd) {
    NSString *selName = NSStringFromSelector(_cmd);
    NSArray<NSString *> *keys = sciPrefKeysForFGSel(selName);
    for (NSString *k in keys) {
        if ([SCIUtils getBoolPref:k]) {
            // Invert: removal gates should return NO when the feature is forced on
            NSString *sl = selName.lowercaseString;
            if ([sl containsString:@"removalof"] || [sl containsString:@"removal_of"])
                return NO;
            return YES;
        }
    }
    // Fall through to original
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

// Hook all zero-argument boolean getters on a class whose selector name
// maps to at least one pref key.
static void sciHookFGClass(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *selName = NSStringFromSelector(sel);
        // Only zero-arg boolean returns
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

%ctor {
    // Only install if at least one relevant toggle is active.
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

    // ── VERIFIED CLASS NAMES (lief scan of Instagram arm64 binary) ────────────
    NSArray<NSString *> *fgClassNames = @[
        // Mutual Interest + Icebreaker — confirmed ✅ IG binary
        @"_TtC32IGDirectMutualInterestIcebreaker42IGDirectMutualInterestFeatureGatingService",
        // Eligibility gate — confirmed ✅ IG binary
        @"_TtC32IGDirectMutualInterestIcebreaker33IGDirectMutualInterestEligibility",

        // Stories Tray decoupling — isStoriesTrayDecouplingEnabled / isStoriesTrayTapPrefetchEnabled
        // These are on the main feed VC; class unknown, hooked via selector scan below.

        // Homecoming Nav Configuration — confirmed ✅ FB binary (isHomecomingEnabled)
        @"_TtC18IGNavConfiguration28IGHomecomingNavConfiguration",
        @"_TtC18IGNavConfiguration18IGNavConfiguration",

        // Feed DedupManager — confirmed ✅ IG binary
        @"_TtC24IGMainFeedViewModelSwift36IGMainFeedDataControllerDedupManager",

        // DM message menu inline like
        @"IGDirectMessageMenuStaticEligibilityContext",
    ];

    for (NSString *className in fgClassNames) {
        sciHookFGClass(NSClassFromString(className));
    }

    // ── Runtime selector scan for loose boolean getters ──────────────────────
    // Scan every loaded class that contains a relevant selector without a known
    // home class. This is deferred to catch lazy-loaded Swift classes.
    // NOTE: We only do this once; not in a hot-path.
    static BOOL sDidScan = NO;
    if (!sDidScan) {
        sDidScan = YES;
        NSArray<NSString *> *selectorTargets = @[
            @"isStoriesTrayDecouplingEnabled",
            @"_isStoriesTrayDecouplingEnabled",
            @"isStoriesTrayTapPrefetchEnabled",
            @"_isStoriesTrayTapPrefetchEnabled",
            @"isFeedDedupEnabled",
            @"isFeedDedupFromReelsEnabled",
            @"isFriendLaneFeedEnabled",
            @"isRemovalOfFriendsFeedEnabled",
            @"isHomeComingEnabled",
            @"isHomecomingExperienceEnabled",
            @"isMutuallyLikedReelsIcebreakerEnabled",
        ];
        unsigned int classCount = 0;
        Class *classList = objc_copyClassList(&classCount);
        for (unsigned int i = 0; i < classCount; i++) {
            Class cls = classList[i];
            for (NSString *selName in selectorTargets) {
                SEL sel = NSSelectorFromString(selName);
                if (!class_getInstanceMethod(cls, sel) && !class_getClassMethod(cls, sel)) continue;
                if (!sciPrefKeysForFGSel(selName)) continue;
                // Already hooked?
                pthread_mutex_lock(&gFGLock);
                BOOL already = gFGOriginals[sciCompositeKey(cls, selName)] != nil;
                pthread_mutex_unlock(&gFGLock);
                if (already) continue;
                sciHookFGClass(cls);
            }
        }
        free(classList);
    }
}
