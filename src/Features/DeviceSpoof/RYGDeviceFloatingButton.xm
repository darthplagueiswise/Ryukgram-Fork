// Floating Device ID button for the signed-out login flow. The Bloks login UI
// has no VC to attach to, so the button rides its own passthrough overlay window.

#import "RYGDeviceIdentity.h"
#import "RYGDeviceMenu.h"
#import "../../Utils.h"

static void RYGRefreshButton(void);
static void RYGHideButtonForSession(void);

#pragma mark - Top VC

static UIViewController *RYGTopMostVC(void) {
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

static void RYGShowDeviceMenu(UIView *sourceView) {
    UIViewController *host = RYGTopMostVC();
    if (!host) return;
    void (^onChange)(void) = ^{ RYGRefreshButton(); };
    BOOL on = [RYGDeviceIdentity spoofingEnabled];
    NSString *cur = [RYGDeviceIdentity effectiveDeviceID];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"Device identity")
        message:[NSString stringWithFormat:@"%@ · %@",
                 on ? RYGLocalized(@"Masked") : RYGLocalized(@"Real"), cur]
        preferredStyle:UIAlertControllerStyleActionSheet];

    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Roll a new fingerprint")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [RYGDeviceMenu presentRollOptionsFrom:RYGTopMostVC() onChange:onChange];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Enter ID manually…")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [RYGDeviceMenu presentCustomIDFrom:RYGTopMostVC() onChange:onChange];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Copy current ID")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [RYGDeviceMenu copyCurrentID];
        }]];
    BOOL dcBlock = [RYGUtils getBoolPref:RYGDeviceSpoofBlockDeviceCheckKey];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:
            RYGLocalized(@"Block Apple attestation: %@"),
            dcBlock ? RYGLocalized(@"On") : RYGLocalized(@"Off")]
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            [RYGUtils setPref:@(!dcBlock) forKey:RYGDeviceSpoofBlockDeviceCheckKey];
            [RYGUtils showToastForDuration:2.2
                title:!dcBlock ? RYGLocalized(@"Attestation blocked") : RYGLocalized(@"Attestation allowed")
                subtitle:RYGLocalized(@"Roll + clear, then sign in fresh")];
        }]];
    if (on)
        [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Revert to my real device ID")
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
                [RYGDeviceMenu revertOnChange:onChange];
            }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Relaunch now")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            exit(0);
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Clear device & relaunch")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x) {
            [RYGDeviceMenu presentWipeConfirmFrom:RYGTopMostVC()];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Hide button until relaunch")
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) {
            RYGHideButtonForSession();
        }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Close")
        style:UIAlertActionStyleCancel handler:nil]];

    a.popoverPresentationController.sourceView = sourceView;
    a.popoverPresentationController.sourceRect = sourceView.bounds;
    [host presentViewController:a animated:YES completion:nil];
}

#pragma mark - Passthrough overlay window

@interface RYGDevPassthroughView : UIView @end
@implementation RYGDevPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    return (v == self) ? nil : v;
}
@end

@interface RYGDevWindow : UIWindow @end
@implementation RYGDevWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

@interface RYGDevButtonController : UIViewController
@property (nonatomic, strong) UIButton *btn;
@end

@implementation RYGDevButtonController

- (void)loadView {
    RYGDevPassthroughView *v = [RYGDevPassthroughView new];
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
    [b setTitle:RYGLocalized(@"Device ID") forState:UIControlStateNormal];
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

    // Left side, clear of a possible back chevron; IG's burger owns the top-right.
    [NSLayoutConstraint activateConstraints:@[
        [b.heightAnchor constraintEqualToConstant:36],
        [b.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [b.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:44],
    ]];
    [self refresh];
}

- (void)refresh {
    BOOL on = [RYGDeviceIdentity spoofingEnabled];
    self.btn.tintColor = [UIColor whiteColor];
    self.btn.backgroundColor = on ? [UIColor systemGreenColor] : [UIColor systemBlueColor];
}

- (void)onTap { RYGShowDeviceMenu(self.btn); }

@end

#pragma mark - Show / teardown

static RYGDevWindow *gWindow;
static BOOL gButtonPref;
static BOOL gHiddenThisSession;

static void RYGRefreshButton(void) {
    if (gWindow) [(RYGDevButtonController *)gWindow.rootViewController refresh];
}

static NSTimer *gTimer;

static void RYGTeardown(void) {
    if (!gWindow) return;
    gWindow.hidden = YES;
    gWindow = nil;
}

static void RYGHideButtonForSession(void) {
    gHiddenThisSession = YES;
    RYGTeardown();
    [gTimer invalidate];
    gTimer = nil;
}

static void RYGShowButton(void) {
    if (gWindow) { gWindow.hidden = NO; return; }
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    if (!scene) return; // scene not ready; retry next tick
    gWindow = [[RYGDevWindow alloc] initWithWindowScene:scene];
    gWindow.windowLevel = UIWindowLevelAlert + 50;
    gWindow.backgroundColor = [UIColor clearColor];
    gWindow.rootViewController = [RYGDevButtonController new];
    gWindow.hidden = NO;
}

static void RYGTick(void) {
    if (!gButtonPref || gHiddenThisSession || [RYGUtils activeUserSession] != nil) {
        RYGTeardown();
        [gTimer invalidate];
        gTimer = nil;
        return;
    }
    RYGShowButton();
}

static void RYGArm(void) {
    if (!gButtonPref || gHiddenThisSession) return;
    if ([RYGUtils activeUserSession] != nil) { RYGTick(); return; }
    if (gTimer) { RYGTick(); return; }
    gTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES
                                               block:^(__unused NSTimer *t) { RYGTick(); }];
    RYGTick();
}

// Re-arm on login (re)appearance; covers in-session logout where no scene notification fires.
%hook IGCAANavigationController
- (void)viewDidAppear:(BOOL)animated { %orig; RYGArm(); }
%end

%ctor {
    gButtonPref = [RYGUtils getBoolPref:@"ryg_devicespoof_login_button"];
    if (!gButtonPref) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UISceneDidActivateNotification object:nil
                     queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *n) { RYGArm(); }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                     queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *n) { RYGArm(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ RYGArm(); });
}
