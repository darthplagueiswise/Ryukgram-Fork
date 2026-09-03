// Gates a locked DM thread so chat content never paints before auth. Cancel
// pops the thread VC.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../RYGLockManager.h"
#import "../RYGLockGroups.h"
#import "../RYGLockSurfaceGuard.h"

static id rygSafeKey(id obj, NSString *k) {
    @try { return [obj valueForKey:k]; } @catch (__unused id e) { return nil; }
}

static BOOL rygThreadLocked(id self) {
    RYGLockManager *mgr = [RYGLockManager shared];
    if (![mgr isMasterEnabled]) return NO;
    NSString *tid = rygSafeKey(self, @"threadId");
    if (!tid.length) return NO;
    return [[mgr lockedChatIDs] containsObject:tid];
}

// Per-thread chats lock wins; otherwise gate against messages_tab when the
// inbox was bypassed (profile DM button / notification / share sheet).
static NSString *rygGroupForThreadVC(id self) {
    RYGLockManager *mgr = [RYGLockManager shared];
    if (![mgr isMasterEnabled]) return nil;
    if (rygThreadLocked(self)) return RYGLockGroupChats;
    if ([RYGUtils getBoolPref:RYGLockPrefEnabled(RYGLockGroupMessagesTab)]
        && [mgr isGroupLocked:RYGLockGroupMessagesTab]) {
        return RYGLockGroupMessagesTab;
    }
    return nil;
}

static void rygAttachThreadGuard(UIViewController *vc) {
    NSString *gid = rygGroupForThreadVC(vc);
    if (!gid) return;
    [RYGLockSurfaceGuard attachToVC:vc
                            forGroup:gid
                             onCancel:^(UIViewController *v) {
        [v.navigationController popViewControllerAnimated:YES];
    }];
}

%hook IGDirectThreadViewController

- (void)viewDidLoad {
    %orig;
    rygAttachThreadGuard(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    rygAttachThreadGuard(self);
    [RYGLockSurfaceGuard recheckForVC:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    rygAttachThreadGuard(self);
    [RYGLockSurfaceGuard recheckForVC:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    BOOL leaving = self.isMovingFromParentViewController || self.parentViewController == nil;
    if (!leaving) return;
    // Re-lock against whichever group the guard was bound to.
    NSString *attached = [RYGLockSurfaceGuard attachedGroupIDForVC:self];
    if (!attached.length) return;
    if (![RYGUtils getBoolPref:RYGLockPrefRelockOnDismiss(attached)]) return;
    [[RYGLockManager shared] markGroupLocked:attached];
}

%end
