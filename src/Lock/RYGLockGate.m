#import "RYGLockGate.h"
#import "RYGLockManager.h"
#import "RYGLockGroups.h"
#import "RYGLockSurfaceGuard.h"
#import "RYGLockedSurfaceNavigationController.h"
#import "UI/RYGLockPasscodeViewController.h"
#import "../UI/RYGPopupChrome.h"
#import "../Localization/RYGLocalization.h"

@implementation RYGLockGate

+ (UIViewController *)topVC {
    UIWindow *win = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) { win = w; break; }
        }
        if (win) break;
    }
    if (!win) win = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

+ (void)presentPasscode:(RYGLockPasscodeViewController *)pad from:(UIViewController *)presenter {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pad];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *from = presenter ?: [self topVC];
    [from presentViewController:nav animated:YES completion:nil];
}

// Surfaces that live under Settings; a shortcut into one of these must satisfy
// the Settings lock too, otherwise a passcode-protected Settings is bypassable.
static BOOL rygGroupInheritsSettingsLock(NSString *gid) {
    if (!gid.length) return NO;
    if ([gid isEqualToString:RYGLockGroupApp]) return NO;
    if ([gid isEqualToString:RYGLockGroupSettings]) return NO;
    if ([gid isEqualToString:RYGLockGroupMessagesTab]) return NO;
    if ([gid isEqualToString:RYGLockGroupHiddenReveal]) return NO;
    return YES;
}

+ (void)promptForGroup:(NSString *)groupID
                  from:(UIViewController *)presenter
                  then:(void (^)(void))block {
    RYGLockManager *mgr = [RYGLockManager shared];
    RYGLockGroupInfo *info = RYGLockGroupInfoFor(groupID);
    NSString *title = info.displayName.length
        ? [NSString stringWithFormat:RYGLocalized(@"Unlock %@"), info.displayName]
        : RYGLocalized(@"Unlock");
    RYGLockPasscodeViewController *pad = [[RYGLockPasscodeViewController alloc]
        initWithTitle:title
             subtitle:RYGLocalized(@"Enter your passcode to continue")];
    pad.allowsBiometric = YES;
    pad.allowsCancel = YES;
    pad.completion = ^(BOOL ok) {
        if (!ok) return;
        [mgr markGroupUnlocked:groupID];
        block();
    };
    [self presentPasscode:pad from:presenter];
}

+ (void)runGated:(NSString *)groupID from:(UIViewController *)presenter then:(void (^)(void))block {
    if (!block) return;
    RYGLockManager *mgr = [RYGLockManager shared];

    void (^proceed)(void) = ^{
        if (![mgr isGroupLocked:groupID]) {
            dispatch_async(dispatch_get_main_queue(), block);
            return;
        }
        [self promptForGroup:groupID from:presenter then:block];
    };

    // forceAuth (not promptForGroup) — verifies without unlocking the Settings session,
    // so a child shortcut auth doesn't silently grant access to Settings itself.
    if (rygGroupInheritsSettingsLock(groupID)
        && [mgr isGroupLocked:RYGLockGroupSettings]) {
        RYGLockGroupInfo *info = RYGLockGroupInfoFor(RYGLockGroupSettings);
        NSString *title = info.displayName.length
            ? [NSString stringWithFormat:RYGLocalized(@"Unlock %@"), info.displayName]
            : RYGLocalized(@"Unlock");
        [self forceAuthWithTitle:title subtitle:nil from:presenter then:proceed];
        return;
    }

    proceed();
}

+ (void)presentLockedVC:(UIViewController *)contentVC
                forGroup:(NSString *)groupID
                    from:(UIViewController *)presenter {
    if (!contentVC) return;
    [self runGated:groupID from:presenter then:^{
        RYGLockedSurfaceNavigationController *nav = [[RYGLockedSurfaceNavigationController alloc] initWithRootViewController:contentVC];
        nav.lockGroupID = groupID;
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [RYGPopupChrome applyBackdropTo:contentVC];
        if (!contentVC.navigationItem.leftBarButtonItem
            && !contentVC.navigationItem.leftBarButtonItems.count) {
            UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(closeTopMost:)];
            contentVC.navigationItem.leftBarButtonItem = close;
        }
        // Guard attaches to the nav (its view hosts every pushed sub-page) so
        // re-lock can cover inner pages too.
        UIViewController *top = [self topVC];
        [top presentViewController:nav animated:YES completion:nil];
        [RYGLockSurfaceGuard attachToVC:nav forGroup:groupID];
    }];
}

+ (void)closeTopMost:(UIBarButtonItem *)sender {
    UIViewController *top = [self topVC];
    [top dismissViewControllerAnimated:YES completion:nil];
}

+ (void)forceAuthWithTitle:(NSString *)title
                   subtitle:(NSString *)subtitle
                       from:(UIViewController *)presenter
                        then:(void (^)(void))block {
    if (!block) return;
    RYGLockManager *mgr = [RYGLockManager shared];
    if (![mgr hasPasscode]) {
        dispatch_async(dispatch_get_main_queue(), block);
        return;
    }
    RYGLockPasscodeViewController *pad = [[RYGLockPasscodeViewController alloc]
        initWithTitle:title ?: RYGLocalized(@"Confirm passcode")
             subtitle:subtitle ?: RYGLocalized(@"Enter your passcode to continue")];
    pad.allowsBiometric = YES;
    pad.allowsCancel = YES;
    pad.completion = ^(BOOL ok) {
        if (ok) block();
    };
    [self presentPasscode:pad from:presenter];
}

@end
