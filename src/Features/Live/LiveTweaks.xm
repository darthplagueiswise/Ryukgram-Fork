// Live-stream tweaks — anonymous viewing + long-press heart to hide comments.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - Anonymous viewing

static void rygDisableViewerCountPuller(id feedbackController) {
    Ivar pullerIvar = class_getInstanceVariable([feedbackController class], "_viewCountPuller");
    if (!pullerIvar) return;
    id puller = object_getIvar(feedbackController, pullerIvar);
    if (!puller) return;

    // Ivars live on the IGLiveIntervalPuller superclass.
    Ivar activeIvar = NULL;
    Ivar timerIvar = NULL;
    for (Class c = [puller class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        if (!activeIvar) activeIvar = class_getInstanceVariable(c, "_isActive");
        if (!timerIvar)  timerIvar  = class_getInstanceVariable(c, "_nextFetchTimer");
        if (activeIvar && timerIvar) break;
    }
    if (activeIvar) {
        ptrdiff_t off = ivar_getOffset(activeIvar);
        *(BOOL *)((char *)(__bridge void *)puller + off) = NO;
    }
    if (timerIvar) {
        id timer = object_getIvar(puller, timerIvar);
        if (timer && [timer respondsToSelector:@selector(invalidate)]) {
            ((void(*)(id, SEL))objc_msgSend)(timer, @selector(invalidate));
        }
    }
}

%hook IGLiveFeedbackController
- (void)start {
    %orig;
    if ([RYGUtils getBoolPref:@"live_anonymous_view"]) {
        rygDisableViewerCountPuller(self);
    }
}
%end

// MARK: - Hide comments (session-only)

// Session-only — state resets on each new comments VC appearance.
static __weak UIViewController *gActiveLiveCommentsVC = nil;
static BOOL gCommentsHidden = NO;
static const void *kRYGHeartAttachedKey = &kRYGHeartAttachedKey;

// Only hide the scrolling collection — keep input + like usable.
static void rygHideCommentCollections(UIView *root, BOOL hide, int depth) {
    if (!root || depth > 8) return;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:[UICollectionView class]]) {
            sub.alpha = hide ? 0.0 : 1.0;
            sub.userInteractionEnabled = !hide;
            continue;
        }
        rygHideCommentCollections(sub, hide, depth + 1);
    }
}

static void rygApplyCommentsStateTo(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return;
    rygHideCommentCollections(vc.view, gCommentsHidden, 0);
}

extern "C" void rygRefreshLiveCommentsHidden(void) {
    rygApplyCommentsStateTo(gActiveLiveCommentsVC);
}

static void rygAttachLongPressToView(UIView *v);

// Heart lives in the footer's _likeButton ivar.
%hook IGLiveFooterButtonsView
- (void)layoutSubviews {
    %orig;
    id obj = (id)self;
    Ivar iv = class_getInstanceVariable([obj class], "_likeButton");
    if (!iv) return;
    UIView *btn = object_getIvar(obj, iv);
    if (btn) rygAttachLongPressToView(btn);
}
%end

%hook IGLiveCommentsContainerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gActiveLiveCommentsVC = self;
    gCommentsHidden = NO;
    rygApplyCommentsStateTo(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (gActiveLiveCommentsVC == self) gActiveLiveCommentsVC = nil;
}
%end

// MARK: - Long-press heart → toggle comments

@interface RYGLiveLikeLongPress : NSObject
+ (instancetype)shared;
- (void)fired:(UILongPressGestureRecognizer *)g;
@end

@implementation RYGLiveLikeLongPress
+ (instancetype)shared {
    static RYGLiveLikeLongPress *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [RYGLiveLikeLongPress new]; });
    return s;
}
- (void)fired:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (![RYGUtils getBoolPref:@"live_hide_comments"]) return;
    gCommentsHidden = !gCommentsHidden;
    rygRefreshLiveCommentsHidden();
    RYGNotifySuccess(RYG_NOTIF_LIVE_TOGGLE,
                     gCommentsHidden ? RYGLocalized(@"Comments hidden") : RYGLocalized(@"Comments shown"),
                     nil);
}
@end

static void rygAttachLongPressToView(UIView *v) {
    if (!v || objc_getAssociatedObject(v, kRYGHeartAttachedKey)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[RYGLiveLikeLongPress shared] action:@selector(fired:)];
    g.minimumPressDuration = 0.5;
    // Swallow the tap so the reactions sheet doesn't open.
    g.cancelsTouchesInView = YES;
    [v addGestureRecognizer:g];
    objc_setAssociatedObject(v, kRYGHeartAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
