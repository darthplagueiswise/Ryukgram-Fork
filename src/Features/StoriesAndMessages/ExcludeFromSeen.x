// Tracks the visible DM thread so per-chat seen gating works.
// Storage in SCIExcludedThreads; inbox menu moved to SCIInboxContextMenu.x.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "SCIExcludedThreads.h"

static id sci_safeKey(id obj, NSString *k) {
    @try { return [obj valueForKey:k]; } @catch (__unused id e) { return nil; }
}

%hook IGDirectThreadViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    NSString *tid = sci_safeKey(self, @"threadId");
    if (tid) [SCIExcludedThreads setActiveThreadId:tid];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.isMovingFromParentViewController || self.isBeingDismissed || self.parentViewController == nil) {
        NSString *cur = [SCIExcludedThreads activeThreadId];
        NSString *mine = sci_safeKey(self, @"threadId");
        if (cur && mine && [cur isEqualToString:mine]) {
            [SCIExcludedThreads setActiveThreadId:nil];
        }
    }
}

- (void)dealloc {
    NSString *cur = [SCIExcludedThreads activeThreadId];
    NSString *mine = sci_safeKey(self, @"threadId");
    if (cur && mine && [cur isEqualToString:mine]) {
        [SCIExcludedThreads setActiveThreadId:nil];
    }
    %orig;
}

%end
