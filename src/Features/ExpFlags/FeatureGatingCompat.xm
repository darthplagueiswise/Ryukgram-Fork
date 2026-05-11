#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <pthread.h>

static NSMutableDictionary<NSString *, NSValue *> *gFGOriginals;
static pthread_mutex_t gFGLock = PTHREAD_MUTEX_INITIALIZER;

static NSArray<NSString *> *sciPrefKeysForFGSel(NSString *sel) {
    if (!sel.length) return nil;
    NSString *l = sel.lowercaseString;
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
    if ([l containsString:@"quicksnap"] || [l containsString:@"quick_snap"])
        return @[@"igt_quicksnap"];
    if ([l containsString:@"instants"] && ![l containsString:@"instant_message"])
        return @[@"igt_quicksnap"];
    if ([l containsString:@"prism"])
        return @[@"igt_prism"];
    if ([l containsString:@"homecoming"])
        return @[@"igt_homecoming"];
    if ([l containsString:@"storygrid"] || [l containsString:@"story_grid"] ||
        ([l containsString:@"story"] && [l containsString:@"grid"]))
        return @[@"igt_story_grid"];
    return nil;
}

// Composite key: ClassName:selectorName — mirrors SCIObjCMobileConfigGetterObserver.xm's K() pattern.
static NSString *sciCompositeKey(Class cls, NSString *sel) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), sel];
}

static BOOL sciFeatureGateDynHook(id self, SEL _cmd) {
    NSString *selName = NSStringFromSelector(_cmd);
    NSArray<NSString *> *keys = sciPrefKeysForFGSel(selName);
    for (NSString *k in keys) {
        if ([SCIUtils getBoolPref:k]) return YES;
    }
    pthread_mutex_lock(&gFGLock);
    NSValue *val = nil;
    Class c = object_getClass(self);
    while (c && !val) {
        val = gFGOriginals[sciCompositeKey(c, selName)];
        c = class_getSuperclass(c);
    }
    pthread_mutex_unlock(&gFGLock);
    if (val) {
        BOOL(*origIMP)(id, SEL) = (BOOL(*)(id,SEL))(uintptr_t)val.pointerValue;
        return origIMP(self, _cmd);
    }
    return NO;
}

static void sciHookFGClass(Class cls) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *selName = NSStringFromSelector(sel);
        if (![selName hasPrefix:@"is"] || ![selName hasSuffix:@"Enabled"]) continue;
        Method m = methods[i];
        if (method_getNumberOfArguments(m) != 2) continue;
        char ret[8] = {0};
        method_getReturnType(m, ret, sizeof(ret));
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
    NSArray<NSString *> *featureKeys = @[
        @"igt_mutual_interest", @"igt_icebreaker", @"igt_friends_feed",
        @"igt_feed_dedup", @"igt_reels_first", @"igt_feed_culling",
        @"igt_pull_to_carrera", @"igt_audio_ramping", @"igt_tab_swiping",
        @"igt_quicksnap", @"igt_prism", @"igt_homecoming", @"igt_story_grid"
    ];
    BOOL any = NO;
    for (NSString *k in featureKeys) {
        if ([SCIUtils getBoolPref:k]) { any = YES; break; }
    }
    if (!any) return;

    gFGOriginals = [NSMutableDictionary dictionary];
    for (NSString *className in @[@"FeatureGatingService", @"FeatureGate"]) {
        sciHookFGClass(NSClassFromString(className));
    }
}
