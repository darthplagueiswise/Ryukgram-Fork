// App-lock + snapshot shroud. willResignActive paints the shroud so the
// app-switcher snapshot doesn't leak IG content; didBecomeActive resolves
// to a passcode prompt (App group locked) or dismisses the window.
//
// Shroud lights up when app-lock is on, or when a RYGLockSurfaceGuard is
// attached to an on-screen VC and its group's lock pref is on — the guards
// already drive auth re-prompt, so they're the single source of truth.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../RYGLockManager.h"
#import "../RYGLockGroups.h"
#import "../RYGLockAppWindow.h"
#import "../RYGLockSurfaceGuard.h"

static BOOL rygAnyLockGroupEnabled(void) {
    for (RYGLockGroupInfo *g in RYGLockAllGroups()) {
        if ([RYGUtils getBoolPref:RYGLockPrefEnabled(g.identifier)]) return YES;
    }
    return NO;
}

static BOOL rygVisibleSurfaceEngaged(void) {
    NSString *gid = [RYGLockSurfaceGuard visibleAttachedGroupID];
    if (!gid.length) return NO;
    return [RYGUtils getBoolPref:RYGLockPrefEnabled(gid)];
}

static void rygMaybeShowShroud(void) {
    RYGLockAppWindow *win = [RYGLockAppWindow shared];
    if (![[RYGLockManager shared] isMasterEnabled]) { [win hideShroud]; return; }
    if ([RYGUtils getBoolPref:RYGLockPrefEnabled(RYGLockGroupApp)]) { [win showShroud]; return; }
    if (rygVisibleSurfaceEngaged()) { [win showShroud]; return; }
    [win hideShroud];
}

%hook IGInstagramAppDelegate

- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
    _Bool result = %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        RYGLockManager *mgr = [RYGLockManager shared];
        if (![mgr isMasterEnabled]) return;
        if (!rygAnyLockGroupEnabled()) return;
        [[RYGLockAppWindow shared] prewarm];
        if (![RYGUtils getBoolPref:RYGLockPrefEnabled(RYGLockGroupApp)]) return;
        [mgr markGroupLocked:RYGLockGroupApp];
        [[RYGLockAppWindow shared] presentIfNeeded];
    });

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQ = [NSOperationQueue mainQueue];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:mainQ usingBlock:^(__unused id _) { rygMaybeShowShroud(); }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification  object:nil queue:mainQ usingBlock:^(__unused id _) {
        [[RYGLockAppWindow shared] resolveOnForeground];
        [RYGLockSurfaceGuard recheckAll];
    }];

    return result;
}

- (void)applicationWillResignActive:(id)arg1 {
    %orig;
    rygMaybeShowShroud();
}

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;
    [[RYGLockAppWindow shared] resolveOnForeground];
}

%end
