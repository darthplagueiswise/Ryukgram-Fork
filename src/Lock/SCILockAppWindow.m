#import "SCILockAppWindow.h"
#import "SCILockManager.h"
#import "SCILockGroups.h"
#import "../Utils.h"
#import "UI/SCILockPasscodeViewController.h"
#import "../Localization/SCILocalization.h"

@interface SCILockAppWindow ()
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, strong, nullable) UIViewController *shroudVC;
@property (nonatomic) BOOL inPasscodeMode;
@end

@implementation SCILockAppWindow

+ (instancetype)shared {
    static SCILockAppWindow *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (BOOL)isPresenting { return self.window && self.window.alpha > 0; }

- (UIWindowScene *)activeScene {
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

- (BOOL)appLockEnabled {
    return [[SCILockManager shared] isMasterEnabled]
        && [SCIUtils getBoolPref:SCILockPrefEnabled(SCILockGroupApp)];
}

- (BOOL)masterEnabled { return [[SCILockManager shared] isMasterEnabled]; }

#pragma mark - Public

- (void)prewarm {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self prewarm]; });
        return;
    }
    if (self.window) return;
    UIWindowScene *scene = [self activeScene];
    if (!scene) return;
    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.windowLevel = UIWindowLevelAlert + 100;
    w.backgroundColor = [UIColor systemBackgroundColor];
    w.rootViewController = [self buildShroudVC];
    // Toggling `hidden` was unreliable on first willResignActive — gate visibility on alpha instead.
    w.alpha = 0;
    w.userInteractionEnabled = NO;
    w.hidden = NO;
    [w layoutIfNeeded];
    self.window = w;
    self.shroudVC = w.rootViewController;
    self.inPasscodeMode = NO;
}

- (void)presentIfNeeded {
    if (![self appLockEnabled]) return;
    if (![[SCILockManager shared] isGroupLocked:SCILockGroupApp]) return;
    [self showPasscode];
}

- (void)hideShroud {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideShroud]; });
        return;
    }
    if (!self.window) return;
    if (self.inPasscodeMode) return;
    [self.window.layer removeAllAnimations];
    self.window.alpha = 0;
    self.window.userInteractionEnabled = NO;
}

- (void)showShroud {
    if (![self masterEnabled]) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showShroud]; });
        return;
    }
    [self ensureWindow];
    if (!self.window) return;
    if (self.inPasscodeMode) return;
    if (!self.shroudVC) self.shroudVC = [self buildShroudVC];
    if (self.window.rootViewController != self.shroudVC) self.window.rootViewController = self.shroudVC;
    [self.window.layer removeAllAnimations];
    self.window.userInteractionEnabled = YES;
    self.window.alpha = 1;
}

- (void)showPasscode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showPasscode]; });
        return;
    }
    [self ensureWindow];
    if (!self.window) return;
    if (self.inPasscodeMode && self.window.alpha > 0) return;
    SCILockPasscodeViewController *pad = [[SCILockPasscodeViewController alloc]
        initWithTitle:SCILocalized(@"Unlock Instagram")
             subtitle:SCILocalized(@"Enter your passcode to continue")];
    pad.allowsBiometric = YES;
    pad.allowsCancel = NO;
    pad.instantDismissOnSuccess = YES;
    pad.completion = ^(BOOL ok) {
        if (!ok) return;
        [[SCILockManager shared] markGroupUnlocked:SCILockGroupApp];
        [[SCILockAppWindow shared] dismiss];
    };
    self.window.rootViewController = pad;
    self.inPasscodeMode = YES;
    self.window.userInteractionEnabled = YES;
    self.window.alpha = 1;
    [self.window makeKeyAndVisible];
}

- (void)resolveOnForeground {
    if (![self appLockEnabled]) { [self dismiss]; return; }
    if ([[SCILockManager shared] isGroupLocked:SCILockGroupApp]) {
        [self showPasscode];
    } else {
        [self dismiss];
    }
}

- (void)dismiss {
    if (!self.window || self.window.alpha == 0) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismiss]; });
        return;
    }
    UIWindow *w = self.window;
    [w.layer removeAllAnimations];
    w.alpha = 0;
    w.userInteractionEnabled = NO;
    if (self.shroudVC && w.rootViewController != self.shroudVC) w.rootViewController = self.shroudVC;
    self.inPasscodeMode = NO;
}

#pragma mark - Internals

- (UIViewController *)buildShroudVC {
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor systemBackgroundColor];

    UIImageView *icon = [UIImageView new];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:48 weight:UIImageSymbolWeightSemibold];
    icon.image = [UIImage systemImageNamed:@"lock.fill" withConfiguration:cfg];
    icon.tintColor = [UIColor tertiaryLabelColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
    ]];
    return vc;
}

- (void)ensureWindow {
    if (self.window) return;
    [self prewarm];
}

@end
