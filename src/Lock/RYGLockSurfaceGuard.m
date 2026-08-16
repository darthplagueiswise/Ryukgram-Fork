#import "RYGLockSurfaceGuard.h"
#import "RYGLockManager.h"
#import "RYGLockGroups.h"
#import "UI/RYGLockPasscodeViewController.h"
#import "../UI/RYGPopupChrome.h"
#import "../Localization/RYGLocalization.h"
#import <objc/runtime.h>

@interface RYGLockSurfaceGuard ()
@property (nonatomic, weak)   UIViewController *vc;
@property (nonatomic, copy)   NSString *groupID;
@property (nonatomic, strong, nullable) UIView *coverView;
@property (nonatomic) BOOL prompting;
@property (nonatomic, copy, nullable) void (^onCancel)(UIViewController *);
@end

static const void *kRYGLockGuardKey = &kRYGLockGuardKey;

static NSHashTable<RYGLockSurfaceGuard *> *rygAllGuards(void) {
    static NSHashTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [NSHashTable weakObjectsHashTable]; });
    return t;
}

@implementation RYGLockSurfaceGuard

+ (void)attachToVC:(UIViewController *)vc forGroup:(NSString *)groupID {
    [self attachToVC:vc forGroup:groupID onCancel:nil];
}

+ (void)attachToVC:(UIViewController *)vc forGroup:(NSString *)groupID onCancel:(void (^)(UIViewController *))onCancel {
    if (!vc || !groupID.length) return;
    if (objc_getAssociatedObject(vc, kRYGLockGuardKey)) return;

    RYGLockSurfaceGuard *g = [self new];
    g.vc = vc;
    g.groupID = groupID;
    g.onCancel = onCancel;
    objc_setAssociatedObject(vc, kRYGLockGuardKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @synchronized (rygAllGuards()) { [rygAllGuards() addObject:g]; }
    [[NSNotificationCenter defaultCenter] addObserver:g
                                              selector:@selector(sessionChanged:)
                                                  name:RYGLockSessionDidChangeNotification
                                                object:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [g check]; });
}

+ (void)recheckForVC:(UIViewController *)vc {
    RYGLockSurfaceGuard *g = objc_getAssociatedObject(vc, kRYGLockGuardKey);
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [g check]; }); return; }
    [g check];
}

+ (void)recheckAll {
    NSArray<RYGLockSurfaceGuard *> *guards;
    @synchronized (rygAllGuards()) { guards = [rygAllGuards() allObjects]; }
    for (RYGLockSurfaceGuard *g in guards) {
        if ([NSThread isMainThread]) [g check];
        else dispatch_async(dispatch_get_main_queue(), ^{ [g check]; });
    }
}

+ (NSString *)attachedGroupIDForVC:(UIViewController *)vc {
    RYGLockSurfaceGuard *g = objc_getAssociatedObject(vc, kRYGLockGuardKey);
    return g.groupID;
}

+ (NSString *)visibleAttachedGroupID {
    NSArray<RYGLockSurfaceGuard *> *guards;
    @synchronized (rygAllGuards()) { guards = [rygAllGuards() allObjects]; }
    for (RYGLockSurfaceGuard *g in guards) {
        UIViewController *vc = g.vc;
        if (!vc || !vc.isViewLoaded || !vc.view.window) continue;
        if (g.groupID.length) return g.groupID;
    }
    return nil;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

#pragma mark - Notification

- (void)sessionChanged:(NSNotification *)note {
    if ([NSThread isMainThread]) { [self check]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self check]; });
}

- (void)check {
    UIViewController *vc = self.vc;
    if (!vc) return;
    BOOL locked = [[RYGLockManager shared] isGroupLocked:self.groupID];
    if (!locked) {
        [self removeCover];
        return;
    }
    if (self.prompting) return;
    if (!vc.view.window) {
        [self installCoverIfNeeded];
        return;
    }
    [self installCoverIfNeeded];
    [self presentPasscode];
}

#pragma mark - Cover

- (void)installCoverIfNeeded {
    UIViewController *vc = self.vc;
    if (!vc) return;
    // Window-level when available so it sits above IG's chrome (camera nub etc).
    UIView *targetHost = vc.view.window ?: vc.view;
    if (self.coverView.superview == targetHost) {
        [targetHost bringSubviewToFront:self.coverView];
        return;
    }
    if (self.coverView) {
        [self.coverView removeFromSuperview];
        self.coverView = nil;
    }

    UIView *cover = [UIView new];
    cover.frame = targetHost.bounds;
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    cover.backgroundColor = [RYGPopupChrome backgroundColor];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10;
    [cover addSubview:stack];

    UIImageView *icon = [UIImageView new];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:52 weight:UIImageSymbolWeightSemibold];
    icon.image = [UIImage systemImageNamed:@"lock.fill" withConfiguration:cfg];
    icon.tintColor = [UIColor tertiaryLabelColor];
    [stack addArrangedSubview:icon];
    [stack setCustomSpacing:18 afterView:icon];

    UILabel *title = [UILabel new];
    title.text = RYGLocalized(@"Tap Unlock");
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    title.textColor = [UIColor labelColor];
    title.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:title];

    UILabel *sub = [UILabel new];
    sub.text = RYGLocalized(@"Tap Unlock or enter your passcode");
    sub.font = [UIFont systemFontOfSize:14];
    sub.textColor = [UIColor secondaryLabelColor];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.numberOfLines = 0;
    [stack addArrangedSubview:sub];
    [stack setCustomSpacing:22 afterView:sub];

    UIButton *unlockBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [unlockBtn setTitle:RYGLocalized(@"Unlock") forState:UIControlStateNormal];
    unlockBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    unlockBtn.tintColor = [UIColor systemBlueColor];
    unlockBtn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
    unlockBtn.layer.cornerRadius = 18;
    unlockBtn.layer.cornerCurve = kCACornerCurveContinuous;
    unlockBtn.contentEdgeInsets = UIEdgeInsetsMake(9, 24, 9, 24);
    [unlockBtn addTarget:self action:@selector(tapUnlockFromCover) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:unlockBtn];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapUnlockFromCover)];
    [cover addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:cover.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:cover.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:cover.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:cover.trailingAnchor constant:-24],
    ]];

    [targetHost addSubview:cover];
    [targetHost bringSubviewToFront:cover];
    self.coverView = cover;
}

- (void)removeCover {
    UIView *cover = self.coverView;
    self.coverView = nil;
    if (!cover) return;
    [cover.layer removeAllAnimations];
    [cover removeFromSuperview];
}

- (void)tapUnlockFromCover {
    if (self.prompting) return;
    if (![[RYGLockManager shared] isGroupLocked:self.groupID]) {
        [self removeCover];
        return;
    }
    [self presentPasscode];
}

#pragma mark - Passcode

- (void)presentPasscode {
    self.prompting = YES;
    UIViewController *vc = self.vc;
    NSString *gid = self.groupID;

    RYGLockGroupInfo *info = RYGLockGroupInfoFor(gid);
    NSString *title = info.displayName.length
        ? [NSString stringWithFormat:RYGLocalized(@"Unlock %@"), info.displayName]
        : RYGLocalized(@"Unlock");

    RYGLockPasscodeViewController *pad = [[RYGLockPasscodeViewController alloc]
        initWithTitle:title
             subtitle:RYGLocalized(@"Enter your passcode to continue")];
    pad.allowsBiometric = YES;
    pad.allowsCancel = YES;
    pad.instantDismissOnSuccess = YES;
    __weak typeof(self) weak = self;
    pad.completion = ^(BOOL ok) {
        RYGLockSurfaceGuard *strong = weak;
        if (!strong) return;
        strong.prompting = NO;
        if (ok) {
            [[RYGLockManager shared] markGroupUnlocked:gid];
            [strong removeCover];
            return;
        }
        UIViewController *target = strong.vc;
        if (strong.onCancel) {
            strong.onCancel(target);
        } else {
            [target.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        }
    };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:pad];
    // OverFullScreen keeps the underlying VC mounted so the tab bar host
    // doesn't come back broken after the modal dismisses.
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;

    UIViewController *presenter = [self bestPresenterForVC:vc];
    if (!presenter || !presenter.view.window) {
        self.prompting = NO;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf check]; });
        return;
    }
    [presenter presentViewController:nav animated:NO completion:nil];
}

- (UIViewController *)bestPresenterForVC:(UIViewController *)vc {
    UIWindow *win = vc.view.window;
    if (!win) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
    }
    UIViewController *root = win.rootViewController ?: vc;
    UIViewController *top = root;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top;
}

@end
