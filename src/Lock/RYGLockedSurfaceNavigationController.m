#import "RYGLockedSurfaceNavigationController.h"
#import "RYGLockManager.h"
#import "RYGLockGroups.h"
#import "../Utils.h"

static BOOL RYGIsForeignVC(UIViewController *vc) {
    NSString *cls = vc ? NSStringFromClass([vc class]) : @"";
    if ([cls hasPrefix:@"RYG"] || [cls hasPrefix:@"RyukGram"]) return NO;
    if ([cls hasPrefix:@"IG"]) return YES;
    return [cls hasPrefix:@"_TtC"] && [cls rangeOfString:@"IG"].location != NSNotFound;
}

static UINavigationController *RYGFindIGNav(UIViewController *root) {
    if (!root) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIViewController *vc = stack.lastObject;
        [stack removeLastObject];
        if ([vc isKindOfClass:[UINavigationController class]]
            && ![vc isKindOfClass:[RYGLockedSurfaceNavigationController class]]) {
            return (UINavigationController *)vc;
        }
        for (UIViewController *c in vc.childViewControllers) [stack addObject:c];
        if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
    }
    return nil;
}

static UIWindow *RYGKeyWindow(void) {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

@implementation RYGLockedSurfaceNavigationController

// IG push-notif deep links target topmost nav. If we're up, IG would push
// into our stack — detect foreign VCs, unwind all lock surfaces, forward to IG.
- (void)pushViewController:(UIViewController *)vc animated:(BOOL)animated {
    if (!RYGIsForeignVC(vc)) { [super pushViewController:vc animated:animated]; return; }

    UIViewController *root = self.presentingViewController;
    while (root.presentingViewController) root = root.presentingViewController;
    [root dismissViewControllerAnimated:NO completion:^{
        UINavigationController *nav = RYGFindIGNav(root) ?: RYGFindIGNav(RYGKeyWindow().rootViewController);
        if (nav) [nav pushViewController:vc animated:animated];
        else if (root) [root presentViewController:vc animated:animated completion:nil];
    }];
}

- (void)setViewControllers:(NSArray<UIViewController *> *)vcs animated:(BOOL)animated {
    if (vcs.count >= 2 && RYGIsForeignVC(vcs.lastObject)) {
        [self pushViewController:vcs.lastObject animated:animated];
        return;
    }
    [super setViewControllers:vcs animated:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    BOOL dismissed = self.isBeingDismissed || self.presentingViewController == nil;
    if (!dismissed) return;
    if (!self.lockGroupID.length) return;
    if (![RYGUtils getBoolPref:RYGLockPrefRelockOnDismiss(self.lockGroupID)]) return;
    [[RYGLockManager shared] markGroupLocked:self.lockGroupID];
}

@end
