// Tracks the visible DM thread so per-chat seen gating works.
// Storage in RYGExcludedThreads; inbox menu moved to RYGInboxContextMenu.x.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "RYGExcludedThreads.h"

static id ryg_safeKey(id obj, NSString *k) {
    @try { return [obj valueForKey:k]; } @catch (__unused id e) { return nil; }
}

%hook IGDirectThreadViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NSString *tid = ryg_safeKey(self, @"threadId");
    if (tid) [RYGExcludedThreads setActiveThreadId:tid];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.isMovingFromParentViewController || self.isBeingDismissed || self.parentViewController == nil) {
        NSString *cur = [RYGExcludedThreads activeThreadId];
        NSString *mine = ryg_safeKey(self, @"threadId");
        if (cur && mine && [cur isEqualToString:mine]) {
            [RYGExcludedThreads setActiveThreadId:nil];
        }
    }
}

- (void)dealloc {
    NSString *cur = [RYGExcludedThreads activeThreadId];
    NSString *mine = ryg_safeKey(self, @"threadId");
    if (cur && mine && [cur isEqualToString:mine]) {
        [RYGExcludedThreads setActiveThreadId:nil];
    }
    %orig;
}

%end
