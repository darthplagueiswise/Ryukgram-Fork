#import "../../Utils.h"
#import <objc/runtime.h>
#import <pthread.h>

static NSMutableDictionary<NSString *, NSValue *> *gSCIDfdOriginals;
static pthread_mutex_t gSCIDfdLock = PTHREAD_MUTEX_INITIALIZER;
static void (*origSCIDfdSetShowNotes)(id, SEL, BOOL) = NULL;

static BOOL RYKDfdPref(NSString *key) {
    return [SCIUtils getBoolPref:key];
}

static NSString *SCIDfdOriginalKey(Class cls, NSString *selectorName) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), selectorName ?: @""];
}

static NSString *SCIDfdPrefForSelector(NSString *selectorName) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"canSeeNotes": @"igt_dn_dfd_can_see",
            @"showNotes": @"igt_dn_dfd_show",
            @"enableGIFNotes": @"igt_dn_dfd_gif",
            @"enableIcebreakerNotes": @"igt_dn_dfd_icebreaker",
            @"enableLocationNotes": @"igt_dn_dfd_location",
            @"enableLyricsNotes": @"igt_dn_dfd_lyrics",
            @"enableMusicNotes": @"igt_dn_dfd_music",
            @"enableWatchingNowNotes": @"igt_dn_dfd_watching",
            @"enableMediaNotesProduction": @"igt_dn_dfd_media_prod",
            @"enableOriginalAudio": @"igt_dn_dfd_original_audio",
            @"enableAnimatedEmojisInCreation": @"igt_dn_dfd_animated_emoji",
            @"enableBubbleCustomization": @"igt_dn_dfd_bubble",
            @"enableTagging": @"igt_dn_dfd_tagging",
            @"enableListeningNow": @"igt_dn_dfd_listening"
        };
    });
    return map[selectorName ?: @""];
}

static BOOL SCIDfdBoolRouter(id self, SEL _cmd) {
    NSString *selectorName = NSStringFromSelector(_cmd);
    NSString *prefKey = SCIDfdPrefForSelector(selectorName);
    if (prefKey.length && RYKDfdPref(prefKey)) return YES;

    NSValue *origValue = nil;
    pthread_mutex_lock(&gSCIDfdLock);
    Class cls = object_getClass(self);
    while (cls && !origValue) {
        origValue = gSCIDfdOriginals[SCIDfdOriginalKey(cls, selectorName)];
        cls = class_getSuperclass(cls);
    }
    pthread_mutex_unlock(&gSCIDfdLock);

    if (!origValue) return NO;
    BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))origValue.pointerValue;
    return orig ? orig(self, _cmd) : NO;
}

static void SCIDfdSetShowNotes(id self, SEL _cmd, BOOL value) {
    BOOL forced = RYKDfdPref(@"igt_dn_dfd_show") ? YES : value;
    if (origSCIDfdSetShowNotes) origSCIDfdSetShowNotes(self, _cmd, forced);
}

static BOOL SCIDfdMethodIsBoolGetter(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char rt[16] = {0};
    method_getReturnType(method, rt, sizeof(rt));
    return rt[0] == 'B' || rt[0] == 'c' || rt[0] == 'C';
}

static BOOL SCIDfdMethodIsBoolSetter(Method method) {
    if (!method || method_getNumberOfArguments(method) != 3) return NO;
    char rt[16] = {0};
    method_getReturnType(method, rt, sizeof(rt));
    char arg[16] = {0};
    method_getArgumentType(method, 2, arg, sizeof(arg));
    return rt[0] == 'v' && (arg[0] == 'B' || arg[0] == 'c' || arg[0] == 'C');
}

static void SCIDfdHookBoolGetter(Class cls, NSString *selectorName) {
    if (!cls || !selectorName.length) return;
    SEL sel = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!SCIDfdMethodIsBoolGetter(method)) return;
    IMP original = method_setImplementation(method, (IMP)SCIDfdBoolRouter);
    if (!original) return;
    pthread_mutex_lock(&gSCIDfdLock);
    gSCIDfdOriginals[SCIDfdOriginalKey(cls, selectorName)] = [NSValue valueWithPointer:(const void *)original];
    pthread_mutex_unlock(&gSCIDfdLock);
}

%ctor {
    BOOL any = NO;
    for (NSString *key in @[
        @"igt_dn_dfd_can_see",
        @"igt_dn_dfd_show",
        @"igt_dn_dfd_gif",
        @"igt_dn_dfd_icebreaker",
        @"igt_dn_dfd_location",
        @"igt_dn_dfd_lyrics",
        @"igt_dn_dfd_music",
        @"igt_dn_dfd_watching",
        @"igt_dn_dfd_media_prod",
        @"igt_dn_dfd_original_audio",
        @"igt_dn_dfd_animated_emoji",
        @"igt_dn_dfd_bubble",
        @"igt_dn_dfd_tagging",
        @"igt_dn_dfd_listening"
    ]) {
        if (RYKDfdPref(key)) { any = YES; break; }
    }
    if (!any) return;

    Class cls = NSClassFromString(@"IGDirectNotesDogfoodingSettings");
    if (!cls) cls = NSClassFromString(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettings");
    if (!cls) return;

    gSCIDfdOriginals = [NSMutableDictionary dictionary];
    for (NSString *selectorName in @[
        @"canSeeNotes",
        @"showNotes",
        @"enableGIFNotes",
        @"enableIcebreakerNotes",
        @"enableLocationNotes",
        @"enableLyricsNotes",
        @"enableMusicNotes",
        @"enableWatchingNowNotes",
        @"enableMediaNotesProduction",
        @"enableOriginalAudio",
        @"enableAnimatedEmojisInCreation",
        @"enableBubbleCustomization",
        @"enableTagging",
        @"enableListeningNow"
    ]) {
        SCIDfdHookBoolGetter(cls, selectorName);
    }

    SEL setShow = NSSelectorFromString(@"setShowNotes:");
    Method setter = class_getInstanceMethod(cls, setShow);
    if (SCIDfdMethodIsBoolSetter(setter)) {
        origSCIDfdSetShowNotes = (void (*)(id, SEL, BOOL))method_setImplementation(setter, (IMP)SCIDfdSetShowNotes);
    }
}
