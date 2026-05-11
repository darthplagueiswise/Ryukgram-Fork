#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>

// Lightweight validated feature hooks for symbols that exist in FBSharedFramework(83).
// This file intentionally does not install observers, does not call MobileConfig C++,
// does not scan NSUserDefaults, and does not do runtime discovery at launch.
// A hook is installed only when its explicit user default is ON, so OFF means
// the original framework implementation is left untouched after relaunch.

static BOOL SCIExpPrefOn(NSString *key) {
    return key.length && [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

static BOOL SCIExpForceYES(void) { return YES; }
static int SCIExpForceOne(void) { return 1; }

static void SCIExpHookIfEnabled(NSString *defaultsKey, const char *symbolName, void *replacement) {
    if (!SCIExpPrefOn(defaultsKey) || !symbolName || !replacement) return;

    void *symbol = MSFindSymbol(NULL, symbolName);
    if (!symbol) {
        NSLog(@"[RyukGram][ExperimentalHooks] symbol missing for %@: %s", defaultsKey, symbolName);
        return;
    }

    static NSMutableSet<NSString *> *installed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ installed = [NSMutableSet set]; });

    NSString *installKey = [NSString stringWithFormat:@"%@:%s", defaultsKey, symbolName];
    @synchronized(installed) {
        if ([installed containsObject:installKey]) return;
        [installed addObject:installKey];
    }

    void *orig = NULL;
    MSHookFunction(symbol, replacement, &orig);
    NSLog(@"[RyukGram][ExperimentalHooks] installed %@ -> %s", defaultsKey, symbolName);
}

static void SCIInstallValidatedDirectNotesHooks(void) {
    // These are direct exported bool wrappers confirmed in FBSharedFramework(83):
    // _IGDirectNotesFriendMapEnabled
    // _IGDirectNotesEnableAudioNoteReplyType
    // _IGDirectNotesEnableAvatarReplyTypes
    // _IGDirectNotesEnableGifsStickersReplyTypes
    // _IGDirectNotesEnablePhotoNoteReplyType
    SCIExpHookIfEnabled(@"igt_directnotes_friendmap", "_IGDirectNotesFriendMapEnabled", (void *)SCIExpForceYES);
    SCIExpHookIfEnabled(@"igt_directnotes_audio_reply", "_IGDirectNotesEnableAudioNoteReplyType", (void *)SCIExpForceYES);
    SCIExpHookIfEnabled(@"igt_directnotes_avatar_reply", "_IGDirectNotesEnableAvatarReplyTypes", (void *)SCIExpForceYES);
    SCIExpHookIfEnabled(@"igt_directnotes_gifs_reply", "_IGDirectNotesEnableGifsStickersReplyTypes", (void *)SCIExpForceYES);
    SCIExpHookIfEnabled(@"igt_directnotes_photo_reply", "_IGDirectNotesEnablePhotoNoteReplyType", (void *)SCIExpForceYES);
}

static void SCIInstallValidatedFeedNavigationHooks(void) {
    // Confirmed exported functions in FBSharedFramework(83).
    // These are installed only when the existing relaunch-required intent keys are ON.
    // _IGTabBarStyleForLauncherSet is enum-like; style 1 is the LiquidGlass/Homecoming path already used by prior patches.
    SCIExpHookIfEnabled(@"igt_homecoming", "_IGTabBarHomecomingWithFloatingTabEnabled", (void *)SCIExpForceYES);
    SCIExpHookIfEnabled(@"igt_homecoming", "_IGTabBarDynamicSizingEnabled", (void *)SCIExpForceYES);
    SCIExpHookIfEnabled(@"igt_homecoming", "_IGTabBarStyleForLauncherSet", (void *)SCIExpForceOne);
}

%ctor {
    SCIInstallValidatedDirectNotesHooks();
    SCIInstallValidatedFeedNavigationHooks();
}
