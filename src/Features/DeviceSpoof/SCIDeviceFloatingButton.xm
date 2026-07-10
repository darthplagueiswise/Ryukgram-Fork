// Floating "Device ID" button for the login flow. The login UI is Bloks-driven
// with no native VC or nav bar to attach to, so the button rides its own
// passthrough overlay window. Shown only while no account is logged in; once
// signed in the window is torn down and only a light timer guard remains.

#import "SCIDeviceIdentity.h"
#import "SCIDeviceMenu.h"
#import "../../Utils.h"

static void SCIRefreshButton(void);

#pragma mark - Top VC (for presenting from the key window so the keyboard works)

static UIViewController *SCITopMostVC(void) {
    UIWindow *key = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if (w.isKeyWindow) { key = w; break; }
        if (key) break;
    }
    if (!key)
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:UIWindowScene.class])
                for (UIWindow *w in ((UIWindowScene *)s).windows)
                    if ([w isKindOfClass:NSClassFromString(@"IGWindow")]) { key = w; break; }
    UIViewController *vc = key.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

#pragma mark - Menu

static void SCIShowDeviceMenu(UIView *sourceView) {
    UIViewController *host = SCITopMostVC();
    if (!host) return;
    void (^onChange)(void) = ^{ SCIRefreshButton(); };
    BOOL on = [SCIDeviceIdentity spoofingEnabled];
    NSString *cur = [SCIDeviceIdentity effectiveDeviceID];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Device identity")
        message:[NSString stringWithFormat:@"%@ · %@",
                 on ? SCILocalized(@"Masked") : SCILocalized(@"Real"), cur]
        preferredStyle:UIAlertControllerStyleActionSheet];

    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Roll a new fingerprint")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [SCIDeviceMenu presentRollOptionsFrom:SCITopMostVC() onChange:onChange];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Enter ID manually…")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [SCIDeviceMenu presentCustomIDFrom:SCITopMostVC() onChange:onChange];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Copy current ID")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [SCIDeviceMenu copyCurrentID];
        }]];
    BOOL dcBlock = [SCIUtils getBoolPref:SCIDeviceSpoofBlockDeviceCheckKey];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:
            SCILocalized(@"Block Apple attestation: %@"),
            dcBlock ? SCILocalized(@"On") : SCILocalized(@"Off")]
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [SCIUtils setPref:@(!dcBlock) forKey:SCIDeviceSpoofBlockDeviceCheckKey];
            [SCIUtils showToastForDuration:2.2
                title:!dcBlock ? SCILocalized(@"Attestation blocked") : SCILocalized(@"Attestation allowed")
                subtitle:SCILocalized(@"Roll + clear, then sign in fresh")];
        }]];
    if (on)
        [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Revert to my real device ID")
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
                [SCIDeviceMenu revertOnChange:onChange];
            }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Relaunch now")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            exit(0);
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Clear device & relaunch")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
            [SCIDeviceMenu presentWipeConfirmFrom:SCITopMostVC()];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Close")
        style:UIAlertActionStyleCancel handler:nil]];

    a.popoverPresentationController.sourceView = sourceView;
    a.popoverPresentationController.sourceRect = sourceView.bounds;
    [host presentViewController:a animated:YES completion:nil];
}

#pragma mark - Passthrough overlay window

@interface SCIDevPassthroughView : UIView @end
@implementation SCIDevPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return (v == self) ? nil : v;
}
@end

@interface SCIDevWindow : UIWindow @end
@implementation SCIDevWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface SCIDevButtonController : UIViewController
@property (nonatomic, strong) UIButton *btn;
@end

@implementation SCIDevButtonController

- (void)loadView {
    SCIDevPassthroughView *v = [SCIDevPassthroughView new];
    v.backgroundColor = [UIColor clearColor];
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.adjustsImageWhenHighlighted = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
    [b setImage:[UIImage systemImageNamed:@"shield.lefthalf.filled" withConfiguration:cfg]
       forState:UIControlStateNormal];
    [b setTitle:SCILocalized(@"Device ID") forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    b.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    b.layer.cornerRadius = 18;
    b.layer.shadowColor = [UIColor blackColor].CGColor;
    b.layer.shadowOpacity = 0.18;
    b.layer.shadowRadius = 5;
    b.layer.shadowOffset = CGSizeMake(0, 2);
    [b addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    self.btn = b;

    // Left side, nudged in past a possible back chevron; the IG burger owns the
    // top-right corner.
    [NSLayoutConstraint activateConstraints:@[
        [b.heightAnchor constraintEqualToConstant:36],
        [b.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [b.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:44],
    ]];
    [self refresh];
}

- (void)refresh {
    BOOL on = [SCIDeviceIdentity spoofingEnabled];
    self.btn.tintColor = [UIColor whiteColor];
    self.btn.backgroundColor = on ? [UIColor systemGreenColor] : [UIColor systemBlueColor];
}

- (void)onTap { SCIShowDeviceMenu(self.btn); }

@end

#pragma mark - Show / teardown

static SCIDevWindow *gWindow;
static BOOL gButtonPref;

static void SCIRefreshButton(void) {
    if (gWindow) [(SCIDevButtonController *)gWindow.rootViewController refresh];
}

static NSTimer *gTimer;

static void SCITeardown(void) {
    if (!gWindow) return;
    gWindow.hidden = YES;
    gWindow = nil; // ARC releases the window + controller → no residual work
}

static void SCIShowButton(void) {
    if (gWindow) { gWindow.hidden = NO; return; }
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    if (!scene) return; // scene not ready yet — the timer retries next tick
    gWindow = [[SCIDevWindow alloc] initWithWindowScene:scene];
    gWindow.windowLevel = UIWindowLevelAlert + 50;
    gWindow.backgroundColor = [UIColor clearColor];
    gWindow.rootViewController = [SCIDevButtonController new];
    gWindow.hidden = NO;
}

// One rule: no account logged in → the button is up. Logged in → window gone
// and the timer is stopped, so there is zero residual work in normal use.
static void SCITick(void) {
    if (!gButtonPref || [SCIUtils activeUserSession] != nil) {
        SCITeardown();
        [gTimer invalidate];
        gTimer = nil;
        return;
    }
    SCIShowButton();
}

static void SCIArm(void) {
    if (!gButtonPref) return;
    if ([SCIUtils activeUserSession] != nil) { SCITick(); return; } // logged in → ensure off
    if (gTimer) { SCITick(); return; }
    gTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES
                                               block:^(__unused NSTimer *t) { SCITick(); }];
    SCITick();
}

// Re-arm when the login flow (re)appears — covers in-session logout, where no
// scene/app notification fires.
%hook IGCAANavigationController
- (void)viewDidAppear:(BOOL)animated {
	%orig;
	SCIArm();
}
%end

%ctor {
    gButtonPref = [SCIUtils getBoolPref:@"sci_devicespoof_login_button"];
    if (!gButtonPref) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UISceneDidActivateNotification object:nil
                     queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *n) { SCIArm(); }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                     queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *n) { SCIArm(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ SCIArm(); });
}
