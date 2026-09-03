// Gates the whole DM inbox. Cancel drops the user onto another tab so they
// aren't trapped on a covered inbox.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../RYGLockManager.h"
#import "../RYGLockGroups.h"
#import "../RYGLockSurfaceGuard.h"

static BOOL rygMsgsTabFeatureOn(void) {
    RYGLockManager *mgr = [RYGLockManager shared];
    if (![mgr isMasterEnabled]) return NO;
    return [RYGUtils getBoolPref:RYGLockPrefEnabled(RYGLockGroupMessagesTab)];
}

static void rygAttachInboxGuard(UIViewController *vc) {
    if (!rygMsgsTabFeatureOn()) return;
    [RYGLockSurfaceGuard attachToVC:vc
                            forGroup:RYGLockGroupMessagesTab
                             onCancel:^(UIViewController *v) {
        UIViewController *p = v;
        while (p && ![p isKindOfClass:[UITabBarController class]]) p = p.parentViewController;
        if (![p isKindOfClass:[UITabBarController class]]) return;
        UITabBarController *tbc = (UITabBarController *)p;
        // messages_only kills the home tab — fall back to whichever tab isn't
        // the inbox so the bar doesn't wedge on a missing index.
        NSUInteger inboxIdx = [tbc.viewControllers indexOfObject:v];
        if (inboxIdx == NSNotFound) inboxIdx = tbc.selectedIndex;
        for (NSUInteger i = 0; i < tbc.viewControllers.count; i++) {
            if (i == inboxIdx) continue;
            tbc.selectedIndex = i;
            return;
        }
    }];
}

%hook IGDirectInboxViewController

- (void)viewDidLoad {
    %orig;
    rygAttachInboxGuard(self);
}

// Re-attach on appear too — covers live pref toggles and the rare case where
// viewDidLoad fired before our hook chain was warm. attachToVC is idempotent.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    rygAttachInboxGuard(self);
    [RYGLockSurfaceGuard recheckForVC:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    rygAttachInboxGuard(self);
    [RYGLockSurfaceGuard recheckForVC:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!rygMsgsTabFeatureOn()) return;
    if (![RYGUtils getBoolPref:RYGLockPrefRelockOnDismiss(RYGLockGroupMessagesTab)]) return;
    // A pushed thread sits on top of us in the stack — that's drilling in, not
    // leaving DMs, so don't relock. Tab switch / pop keeps us top, those relock.
    UINavigationController *nav = self.navigationController;
    if (nav && nav.topViewController != self && [nav.viewControllers containsObject:self]) return;
    [[RYGLockManager shared] markGroupLocked:RYGLockGroupMessagesTab];
}

%end
