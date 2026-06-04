// App-lock + snapshot shroud. willResignActive paints the shroud so the
// app-switcher snapshot doesn't leak IG content; didBecomeActive resolves
// to a passcode prompt (App group locked) or dismisses the window.
//
// Shroud lights up when app-lock is on, or when a SCILockSurfaceGuard is
// attached to an on-screen VC and its group's lock pref is on — the guards
// already drive auth re-prompt, so they're the single source of truth.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../SCILockManager.h"
#import "../SCILockGroups.h"
#import "../SCILockAppWindow.h"
#import "../SCILockSurfaceGuard.h"

static BOOL sciAnyLockGroupEnabled(void) {
    for (SCILockGroupInfo *g in SCILockAllGroups()) {
        if ([SCIUtils getBoolPref:SCILockPrefEnabled(g.identifier)]) return YES;
    }
    return NO;
}

static BOOL sciVisibleSurfaceEngaged(void) {
    NSString *gid = [SCILockSurfaceGuard visibleAttachedGroupID];
    if (!gid.length) return NO;
    return [SCIUtils getBoolPref:SCILockPrefEnabled(gid)];
}

static void sciMaybeShowShroud(void) {
    SCILockAppWindow *win = [SCILockAppWindow shared];
    if (![[SCILockManager shared] isMasterEnabled]) { [win hideShroud]; return; }
    if ([SCIUtils getBoolPref:SCILockPrefEnabled(SCILockGroupApp)]) { [win showShroud]; return; }
    if (sciVisibleSurfaceEngaged()) { [win showShroud]; return; }
    [win hideShroud];
}

%hook IGInstagramAppDelegate

- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
    _Bool result = %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        SCILockManager *mgr = [SCILockManager shared];
        if (![mgr isMasterEnabled]) return;
        if (!sciAnyLockGroupEnabled()) return;
        [[SCILockAppWindow shared] prewarm];
        if (![SCIUtils getBoolPref:SCILockPrefEnabled(SCILockGroupApp)]) return;
        [mgr markGroupLocked:SCILockGroupApp];
        [[SCILockAppWindow shared] presentIfNeeded];
    });

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSOperationQueue *mainQ = [NSOperationQueue mainQueue];
    [nc addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:mainQ usingBlock:^(__unused id _) { sciMaybeShowShroud(); }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification  object:nil queue:mainQ usingBlock:^(__unused id _) {
        [[SCILockAppWindow shared] resolveOnForeground];
        [SCILockSurfaceGuard recheckAll];
    }];

    return result;
}

- (void)applicationWillResignActive:(id)arg1 {
    %orig;
    sciMaybeShowShroud();
}

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;
    [[SCILockAppWindow shared] resolveOnForeground];
}

%end
