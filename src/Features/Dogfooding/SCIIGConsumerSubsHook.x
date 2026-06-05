// ============================================================================
// SCIIGConsumerSubsHook.x
// ============================================================================
// IGPlus client benefit forcing. Uses named ObjC runtime hooks only.
// Hardened for Swift module classes: resolve by objc_getClass(mangled),
// NSClassFromString(module.name), and class-list suffix matching. Also records
// installation status in Dogfood Runtime so the runtime browser shows what is
// actually hooked.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"
#import "SCIDogfoodObjectRuntime.h"

#define SCILOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlus " fmt, ##__VA_ARGS__)

static NSString *const kMaster = @"sci_force_igplus_all";
static inline BOOL ON(NSString *k){ return [SCIInternalGatePrefs individualGateEnabledForKey:kMaster] || [SCIInternalGatePrefs individualGateEnabledForKey:k]; }

typedef struct { const char *sel; NSString *key; } SCIBenefit;
static SCIBenefit benefits[] = {
    {"hasAccessToIGPlus", @"sci_igplus_has_access"},
    {"hasAnyActiveBenefit", @"sci_igplus_any_active"},
    {"isCustomListsBenefitEnabled", @"sci_igplus_custom_lists"},
    {"isStorySuperlikesBenefitEnabled", @"sci_igplus_story_superlikes"},
    {"isSearchStoryViewersBenefitEnabled", @"sci_igplus_search_story_viewers"},
    {"isStoryExtendBenefitEnabled", @"sci_igplus_story_extend"},
    {"isStoryRewatchBenefitEnabled", @"sci_igplus_story_rewatch"},
    {"isStoryPeeksBenefitEnabled", @"sci_igplus_story_peeks"},
    {"isStorySpotlightBenefitEnabled", @"sci_igplus_story_spotlight"},
    {"isSilentPostToHighlightsBenefitEnabled", @"sci_igplus_silent_post_highlights"},
    {"isDirectMessagePeekBenefitEnabled", @"sci_igplus_dm_peek"},
    {"isCustomAppIconBenefitEnabled", @"sci_igplus_custom_app_icon"},
    {"isBrandedThreadsBenefitEnabled", @"sci_igplus_branded_threads"},
    {"isTimestampViewersListBenefitEnabled", @"sci_igplus_timestamp_viewers"},
    {"isCustomBioFontInProfileBenefitEnabled", @"sci_igplus_custom_bio_font"},
    {"isSilentPostToProfileBenefitEnabled", @"sci_igplus_silent_post_profile"},
    {"isPinnedPostsIncreasedLimitEnabled", @"sci_igplus_pinned_posts_limit"},
    {NULL, nil}
};

#define MAXH 48
static IMP gOrig[MAXH];
static SEL gSel[MAXH];
static NSString *gKey[MAXH];
static int gN = 0;
static IMP gOrigActive = NULL; static SEL gSelActive = NULL;
static NSMutableSet<NSString *> *gDone;

static Class SCIClassByNames(NSArray<NSString *> *names) {
    for (NSString *n in names) {
        if (!n.length) continue;
        Class c = NSClassFromString(n);
        if (c) return c;
        c = objc_getClass(n.UTF8String);
        if (c) return c;
    }
    unsigned int count = 0; Class *classes = objc_copyClassList(&count);
    Class found = Nil;
    for (unsigned int i = 0; classes && i < count && !found; i++) {
        const char *cn = class_getName(classes[i]);
        if (!cn) continue;
        NSString *s = [NSString stringWithUTF8String:cn];
        for (NSString *n in names) {
            if ([s isEqualToString:n] || [s hasSuffix:n] || [s containsString:n]) { found = classes[i]; break; }
        }
    }
    if (classes) free(classes);
    return found;
}

static Class SCIConsumerSubsServiceClass(void) {
    return SCIClassByNames(@[@"_TtC21IGConsumerSubsService21IGConsumerSubsService",
                             @"IGConsumerSubsService.IGConsumerSubsService",
                             @"IGConsumerSubsService"]);
}

static void note(NSString *status, NSString *detail) {
    [SCIDogfoodObjectRuntime noteAction:@"IGPlus hook install" status:status ?: @"" detail:detail ?: @""];
}

static void hookGetter(Class cls, SEL sel, NSString *prefKey) {
    if (gN >= MAXH || !cls || !sel || !prefKey.length) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    NSString *tag = [NSString stringWithFormat:@"%s#%s", class_getName(cls), sel_getName(sel)];
    if ([gDone containsObject:tag]) return;
    int idx = gN++;
    gSel[idx] = sel;
    gKey[idx] = [prefKey copy];
    IMP newImp = imp_implementationWithBlock(^BOOL(id self){
        if (ON(gKey[idx])) return YES;
        BOOL(*o)(id,SEL) = (BOOL(*)(id,SEL))gOrig[idx];
        return o ? o(self, gSel[idx]) : NO;
    });
    IMP orig = NULL;
    MSHookMessageEx(cls, sel, newImp, &orig);
    gOrig[idx] = orig;
    [gDone addObject:tag];
    SCILOG("%{public}@ -> %{public}s", tag, orig ? "HOOKED" : "FAILED");
    note(orig ? @"hooked" : @"failed", tag);
}

static void hookIsBenefitActive(Class cls) {
    SEL sel = NSSelectorFromString(@"isBenefitActive:");
    if (gOrigActive || !cls || !class_getInstanceMethod(cls, sel)) return;
    gSelActive = sel;
    IMP newImp = imp_implementationWithBlock(^BOOL(id self, id benefit){
        if (ON(@"sci_igplus_any_active") || ON(kMaster)) return YES;
        BOOL(*o)(id,SEL,id) = (BOOL(*)(id,SEL,id))gOrigActive;
        return o ? o(self, gSelActive, benefit) : NO;
    });
    IMP orig = NULL;
    MSHookMessageEx(cls, sel, newImp, &orig);
    gOrigActive = orig;
    SCILOG("isBenefitActive: %{public}s", orig ? "HOOKED" : "FAILED");
    note(orig ? @"hooked" : @"failed", [NSString stringWithFormat:@"%s#isBenefitActive:", class_getName(cls)]);
}

static void install(void) {
    if (!gDone) gDone = [NSMutableSet set];
    Class svc = SCIConsumerSubsServiceClass();
    if (!svc) { note(@"class not loaded", @"IGConsumerSubsService"); return; }
    for (int i = 0; benefits[i].sel; i++) hookGetter(svc, NSSelectorFromString(@(benefits[i].sel)), benefits[i].key);
    hookIsBenefitActive(svc);

    Class peek = SCIClassByNames(@[@"_TtC23IGConsumerSubsStoryPeek34IGConsumerSubsStoryPeekCoordinator",
                                   @"IGConsumerSubsStoryPeek.IGConsumerSubsStoryPeekCoordinator",
                                   @"IGConsumerSubsStoryPeekCoordinator"]);
    if (peek) hookGetter(peek, NSSelectorFromString(@"isPeekActive"), @"sci_igplus_story_peek_active");
}

%ctor {
    @autoreleasepool {
        [SCIInternalGatePrefs installCrashGuardIfNeeded];
        install();
        double delays[] = {0.5, 1.5, 3.0, 6.0, 10.0};
        for (NSUInteger i = 0; i < sizeof(delays)/sizeof(delays[0]); i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ install(); });
        }
    }
}
