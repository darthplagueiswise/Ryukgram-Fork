// Bypass the screenshot / screen-record block on Instants. IG's blocking-
// gate methods are Swift→Swift dispatched, so %hook never fires on them.
// Bypass at the view layer: spoof UIScreen.isCaptured, swallow the
// screenshot notification, and disarm the UITextField IG uses as the
// capture-protected canvas. Scoped to the Instants viewer only —
// password fields and SCInsta chrome elsewhere are untouched.
//
// Gate: instants_allow_screenshot

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../SCIChrome.h"

// Point-in-time check for any QuickSnap VC in the presented hierarchy. Beats
// a viewDidAppear/Disappear counter — IG arms capture protection before
// viewDidAppear fires on first open, so a counter would miss the first frame.
static BOOL sciContainsQuickSnapVC(UIViewController *vc) {
    if (!vc) return NO;
    if ([NSStringFromClass([vc class]) rangeOfString:@"QuickSnap"].location != NSNotFound) return YES;
    for (UIViewController *child in vc.childViewControllers) {
        if (sciContainsQuickSnapVC(child)) return YES;
    }
    return sciContainsQuickSnapVC(vc.presentedViewController);
}

static BOOL sciInstantsBypassActive(void) {
    if (![SCIUtils getBoolPref:@"instants_allow_screenshot"]) return NO;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (sciContainsQuickSnapVC(w.rootViewController)) return YES;
        }
    }
    return NO;
}

%hook UIScreen
- (BOOL)isCaptured {
    if (sciInstantsBypassActive()) return NO;
    return %orig;
}
%end

%hook NSNotificationCenter
- (void)postNotificationName:(NSNotificationName)name object:(id)obj userInfo:(NSDictionary *)info {
    if (sciInstantsBypassActive()
        && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}
- (void)postNotificationName:(NSNotificationName)name object:(id)obj {
    if (sciInstantsBypassActive()
        && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}
%end

// IG arms protection via setSecureTextEntry:YES on its content wrapper.
// Force NO during bypass, but skip SCInsta's own redaction fields.
%hook UITextField
- (void)setSecureTextEntry:(BOOL)secure {
    if (!secure || !sciInstantsBypassActive()) { %orig; return; }
    if (SCIChromeCanvasOwnsSecureField((UITextField *)self)) { %orig; return; }
    %orig(NO);
}
%end

// Identify the cover by its warning UILabel, hide the topmost ancestor
// below the window, and disarm the wrapping textField as a safety net.
static inline BOOL sciIsCoverString(NSString *s) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) return NO;
    return [s containsString:@"screenshot or record"]
        || [s containsString:@"only meant to be viewed once"]
        || [s containsString:@"only meant to be replayed once"];
}

static UIView *sciTopAncestorBelowWindow(UIView *v) {
    if (!v) return nil;
    UIView *cur = v;
    while (cur.superview && ![cur.superview isKindOfClass:[UIWindow class]]) cur = cur.superview;
    return cur.superview ? cur : nil;
}

static UITextField *sciFindCanvasTextFieldAncestor(UIView *v) {
    UIView *p = v.superview;
    while (p) {
        if ([p isKindOfClass:[UITextField class]]) return (UITextField *)p;
        p = p.superview;
    }
    return nil;
}

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (!sciIsCoverString(text)) return;
    if (!sciInstantsBypassActive()) return;
    UILabel *me = (UILabel *)self;
    UIView *cover = sciTopAncestorBelowWindow(me) ?: (me.superview ?: me);
    cover.hidden = YES;
    cover.alpha = 0.0;
    me.hidden = YES;
    me.alpha = 0.0;
    UITextField *tf = sciFindCanvasTextFieldAncestor(cover);
    if (tf && tf.secureTextEntry) tf.secureTextEntry = NO;
}
%end
