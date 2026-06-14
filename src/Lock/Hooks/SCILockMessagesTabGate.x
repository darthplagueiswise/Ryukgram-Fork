// Gates the whole DM inbox. Cancel drops the user onto another tab so they
// aren't trapped on a covered inbox.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../SCILockManager.h"
#import "../SCILockGroups.h"
#import "../SCILockSurfaceGuard.h"

static BOOL sciMsgsTabFeatureOn(void) {
    SCILockManager *mgr = [SCILockManager shared];
    if (![mgr isMasterEnabled]) return NO;
    return [SCIUtils getBoolPref:SCILockPrefEnabled(SCILockGroupMessagesTab)];
}

static void sciAttachInboxGuard(UIViewController *vc) {
    if (!sciMsgsTabFeatureOn()) return;
    [SCILockSurfaceGuard attachToVC:vc
                            forGroup:SCILockGroupMessagesTab
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
    sciAttachInboxGuard(self);
}

// Re-attach on appear too — covers live pref toggles and the rare case where
// viewDidLoad fired before our hook chain was warm. attachToVC is idempotent.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sciAttachInboxGuard(self);
    [SCILockSurfaceGuard recheckForVC:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sciAttachInboxGuard(self);
    [SCILockSurfaceGuard recheckForVC:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!sciMsgsTabFeatureOn()) return;
    if (![SCIUtils getBoolPref:SCILockPrefRelockOnDismiss(SCILockGroupMessagesTab)]) return;
    // A pushed thread sits on top of us in the stack — that's drilling in, not
    // leaving DMs, so don't relock. Tab switch / pop keeps us top, those relock.
    UINavigationController *nav = self.navigationController;
    if (nav && nav.topViewController != self && [nav.viewControllers containsObject:self]) return;
    [[SCILockManager shared] markGroupLocked:SCILockGroupMessagesTab];
}

%end
