#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Reels like tap goes through a Swift class method on
// IGSundialViewerLikeButtonActionHandler since IG 426.
typedef void (*RygHandleTapFn)(Class, SEL, id, id, BOOL);
typedef void (*RygHandleTapCompFn)(Class, SEL, id, id, BOOL, id);
static RygHandleTapFn orig_rygHandleTap = NULL;
static RygHandleTapCompFn orig_rygHandleTapComp = NULL;

static void new_rygHandleTap(Class cls, SEL _cmd, id ctx, id btn, BOOL anim) {
    if (![RYGUtils getBoolPref:@"like_confirm_reels"]) {
        orig_rygHandleTap(cls, _cmd, ctx, btn, anim);
        return;
    }
    __strong id sCtx = ctx;
    __strong id sBtn = btn;
    [RYGUtils showConfirmation:^{
        @try { orig_rygHandleTap(cls, _cmd, sCtx, sBtn, anim); }
        @catch (__unused id e) {}
    } title:RYGLocalized(@"Confirm like: Reels")];
}

// Copy the completion block — it's a stack block and won't survive the alert.
static void new_rygHandleTapComp(Class cls, SEL _cmd, id ctx, id btn, BOOL anim, id comp) {
    if (![RYGUtils getBoolPref:@"like_confirm_reels"]) {
        orig_rygHandleTapComp(cls, _cmd, ctx, btn, anim, comp);
        return;
    }
    __strong id sCtx = ctx;
    __strong id sBtn = btn;
    id sComp = comp ? [comp copy] : nil;
    [RYGUtils showConfirmation:^{
        @try { orig_rygHandleTapComp(cls, _cmd, sCtx, sBtn, anim, sComp); }
        @catch (__unused id e) {}
    } title:RYGLocalized(@"Confirm like: Reels")];
}

__attribute__((constructor)) static void _rygHookReelsLikeHandler(void) {
    Class c = NSClassFromString(@"_TtC30IGSundialOverlayActionHandlers38IGSundialViewerLikeButtonActionHandler");
    if (!c) return;
    Class meta = object_getClass(c);
    SEL s1 = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:");
    SEL s2 = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:completion:");
    if (class_getClassMethod(c, s1))
        MSHookMessageEx(meta, s1, (IMP)new_rygHandleTap, (IMP *)&orig_rygHandleTap);
    if (class_getClassMethod(c, s2))
        MSHookMessageEx(meta, s2, (IMP)new_rygHandleTapComp, (IMP *)&orig_rygHandleTapComp);
}

#define CONFIRMPOSTLIKE(orig)                                                                    \
    if ([RYGUtils getBoolPref:@"like_confirm"])                                                  \
        [RYGUtils showConfirmation:^(void) { orig; } title:RYGLocalized(@"Confirm like: Posts")]; \
    else return orig;

#define CONFIRMREELSLIKE(orig)                                                                    \
    if ([RYGUtils getBoolPref:@"like_confirm_reels"])                                             \
        [RYGUtils showConfirmation:^(void) { orig; } title:RYGLocalized(@"Confirm like: Reels")]; \
    else return orig;

// Feed double-tap-to-like has several entry points across surfaces / A-B; confirm on
// all of them, guarded so one gesture through more than one only prompts once.
static BOOL rygDblTapInFlight = NO;
#define CONFIRMDBLTAP(orig)                                                                       \
    if ([RYGUtils getBoolPref:@"like_confirm"] && !rygDblTapInFlight) {                            \
        rygDblTapInFlight = YES;                                                                   \
        [RYGUtils showConfirmation:^(void) { orig; rygDblTapInFlight = NO; }                       \
                     cancelHandler:^(void) { rygDblTapInFlight = NO; }                             \
                             title:RYGLocalized(@"Confirm like: Posts")];                          \
    } else return orig;

// Liking posts
%hook IGUFIButtonBarView
- (void)_onLikeButtonPressed:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)_onLikeButtonPressed {
    CONFIRMPOSTLIKE(%orig);
}
%end
%hook IGFeedPhotoView
- (void)_onDoubleTap:(id)arg1 {
    CONFIRMDBLTAP(%orig);
}
- (void)_onDoubleTap {
    CONFIRMDBLTAP(%orig);
}
%end
%hook IGFeedItemPhotoCell
- (void)feedPhotoDidDoubleTapToLike:(id)arg1 locationInfo:(id)arg2 {
    CONFIRMDBLTAP(%orig);
}
%end
%hook _TtC33IGFeedCaptionDoubleTapLikeHandler33IGFeedCaptionDoubleTapLikeHandler
- (void)animateHeartAndPerformDoubleTapLikeForMediaCell:(id)cell locationInMediaCell:(CGPoint)loc {
    CONFIRMDBLTAP(%orig);
}
%end
%hook _TtC25IGModernFeedVideoOverlays33IGVideoPlayerOverlayContainerView
- (void)handleDoubleTapGesture:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
%end

// Liking reels
%hook IGSundialViewerVideoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(%orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSLIKE(%orig);
}
%end
%hook IGSundialViewerPhotoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(%orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSLIKE(%orig);
}
- (void)swift_photoCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    CONFIRMREELSLIKE(%orig);
}
%end
%hook IGSundialViewerCarouselCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(%orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSLIKE(%orig);
}
- (void)carouselCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    CONFIRMREELSLIKE(%orig);
}
%end

// Liking comments
%hook IGCommentCellController
- (void)commentCell:(id)arg1 didTapLikeButton:(id)arg2 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCell:(id)arg1 didTapLikedByButtonForUser:(id)arg2 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCellDidLongPressOnLikeButton:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCellDidEndLongPressOnLikeButton:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCellDidDoubleTap:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
%end
%hook IGFeedItemPreviewCommentCell
- (void)didTapLikeButton {
    CONFIRMPOSTLIKE(%orig);
}
%end

// Story like/emoji confirm handled by RYGStoryInteractionPipeline.