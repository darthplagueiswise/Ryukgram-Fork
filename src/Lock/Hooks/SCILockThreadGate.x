// Gates a locked DM thread so chat content never paints before auth. Cancel
// pops the thread VC.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../SCILockManager.h"
#import "../SCILockGroups.h"
#import "../SCILockSurfaceGuard.h"

static id sciSafeKey(id obj, NSString *k) {
    @try { return [obj valueForKey:k]; } @catch (__unused id e) { return nil; }
}

static BOOL sciThreadLocked(id self) {
    SCILockManager *mgr = [SCILockManager shared];
    if (![mgr isMasterEnabled]) return NO;
    NSString *tid = sciSafeKey(self, @"threadId");
    if (!tid.length) return NO;
    return [[mgr lockedChatIDs] containsObject:tid];
}

// Per-thread chats lock wins; otherwise gate against messages_tab when the
// inbox was bypassed (profile DM button / notification / share sheet).
static NSString *sciGroupForThreadVC(id self) {
    SCILockManager *mgr = [SCILockManager shared];
    if (![mgr isMasterEnabled]) return nil;
    if (sciThreadLocked(self)) return SCILockGroupChats;
    if ([SCIUtils getBoolPref:SCILockPrefEnabled(SCILockGroupMessagesTab)]
        && [mgr isGroupLocked:SCILockGroupMessagesTab]) {
        return SCILockGroupMessagesTab;
    }
    return nil;
}

static void sciAttachThreadGuard(UIViewController *vc) {
    NSString *gid = sciGroupForThreadVC(vc);
    if (!gid) return;
    [SCILockSurfaceGuard attachToVC:vc
                            forGroup:gid
                             onCancel:^(UIViewController *v) {
        [v.navigationController popViewControllerAnimated:YES];
    }];
}

%hook IGDirectThreadViewController

- (void)viewDidLoad {
    %orig;
    sciAttachThreadGuard(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sciAttachThreadGuard(self);
    [SCILockSurfaceGuard recheckForVC:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sciAttachThreadGuard(self);
    [SCILockSurfaceGuard recheckForVC:self];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    BOOL leaving = self.isMovingFromParentViewController || self.parentViewController == nil;
    if (!leaving) return;
    // Re-lock against whichever group the guard was bound to.
    NSString *attached = [SCILockSurfaceGuard attachedGroupIDForVC:self];
    if (!attached.length) return;
    if (![SCIUtils getBoolPref:SCILockPrefRelockOnDismiss(attached)]) return;
    [[SCILockManager shared] markGroupLocked:attached];
}

%end
