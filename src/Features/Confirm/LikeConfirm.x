#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Reels like tap goes through a Swift class method on
// IGSundialViewerLikeButtonActionHandler since IG 426.
typedef void (*SciHandleTapFn)(Class, SEL, id, id, BOOL);
typedef void (*SciHandleTapCompFn)(Class, SEL, id, id, BOOL, id);
static SciHandleTapFn orig_sciHandleTap = NULL;
static SciHandleTapCompFn orig_sciHandleTapComp = NULL;

static void new_sciHandleTap(Class cls, SEL _cmd, id ctx, id btn, BOOL anim) {
    if (![SCIUtils getBoolPref:@"like_confirm_reels"]) {
        orig_sciHandleTap(cls, _cmd, ctx, btn, anim);
        return;
    }
    __strong id sCtx = ctx;
    __strong id sBtn = btn;
    [SCIUtils showConfirmation:^{
        @try { orig_sciHandleTap(cls, _cmd, sCtx, sBtn, anim); }
        @catch (__unused id e) {}
    } title:SCILocalized(@"Confirm like: Reels")];
}

// Copy the completion block — it's a stack block and won't survive the alert.
static void new_sciHandleTapComp(Class cls, SEL _cmd, id ctx, id btn, BOOL anim, id comp) {
    if (![SCIUtils getBoolPref:@"like_confirm_reels"]) {
        orig_sciHandleTapComp(cls, _cmd, ctx, btn, anim, comp);
        return;
    }
    __strong id sCtx = ctx;
    __strong id sBtn = btn;
    id sComp = comp ? [comp copy] : nil;
    [SCIUtils showConfirmation:^{
        @try { orig_sciHandleTapComp(cls, _cmd, sCtx, sBtn, anim, sComp); }
        @catch (__unused id e) {}
    } title:SCILocalized(@"Confirm like: Reels")];
}

__attribute__((constructor)) static void _sciHookReelsLikeHandler(void) {
    Class c = NSClassFromString(@"_TtC30IGSundialOverlayActionHandlers38IGSundialViewerLikeButtonActionHandler");
    if (!c) return;
    Class meta = object_getClass(c);
    SEL s1 = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:");
    SEL s2 = NSSelectorFromString(@"handleTapWithActionContext:likeButton:willPlayRingsCustomLikeAnimation:completion:");
    if (class_getClassMethod(c, s1))
        MSHookMessageEx(meta, s1, (IMP)new_sciHandleTap, (IMP *)&orig_sciHandleTap);
    if (class_getClassMethod(c, s2))
        MSHookMessageEx(meta, s2, (IMP)new_sciHandleTapComp, (IMP *)&orig_sciHandleTapComp);
}

#define CONFIRMPOSTLIKE_BLOCK(blk)                                                              \
    if ([SCIUtils getBoolPref:@"like_confirm"])                                                  \
        [SCIUtils showConfirmation:blk title:SCILocalized(@"Confirm like: Posts")];               \
    else blk();

#define CONFIRMREELSLIKE_BLOCK(blk)                                                              \
    if ([SCIUtils getBoolPref:@"like_confirm_reels"])                                             \
        [SCIUtils showConfirmation:blk title:SCILocalized(@"Confirm like: Reels")];                \
    else blk();

// Feed double-tap-to-like has several entry points across surfaces / A-B; confirm on
// all of them, guarded so one gesture through more than one only prompts once.
static BOOL sciDblTapInFlight = NO;
#define CONFIRMDBLTAP_BLOCK(blk)                                                                  \
    if ([SCIUtils getBoolPref:@"like_confirm"] && !sciDblTapInFlight) {                            \
        sciDblTapInFlight = YES;                                                                   \
        [SCIUtils showConfirmation:^(void) { blk(); sciDblTapInFlight = NO; }                      \
                     cancelHandler:^(void) { sciDblTapInFlight = NO; }                             \
                             title:SCILocalized(@"Confirm like: Posts")];                          \
    } else blk();

// Liking posts
%hook IGUFIButtonBarView
- (void)_onLikeButtonPressed:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
- (void)_onLikeButtonPressed {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
%end
%hook IGFeedPhotoView
- (void)_onDoubleTap:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMDBLTAP_BLOCK(sciOrigBlk);
}
- (void)_onDoubleTap {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMDBLTAP_BLOCK(sciOrigBlk);
}
%end
%hook IGFeedItemPhotoCell
- (void)feedPhotoDidDoubleTapToLike:(id)arg1 locationInfo:(id)arg2 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMDBLTAP_BLOCK(sciOrigBlk);
}
%end
%hook _TtC33IGFeedCaptionDoubleTapLikeHandler33IGFeedCaptionDoubleTapLikeHandler
- (void)animateHeartAndPerformDoubleTapLikeForMediaCell:(id)cell locationInMediaCell:(CGPoint)loc {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMDBLTAP_BLOCK(sciOrigBlk);
}
%end
%hook _TtC25IGModernFeedVideoOverlays33IGVideoPlayerOverlayContainerView
- (void)handleDoubleTapGesture:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
%end

// Liking reels
%hook IGSundialViewerVideoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
%end
%hook IGSundialViewerPhotoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
- (void)swift_photoCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
%end
%hook IGSundialViewerCarouselCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
- (void)carouselCell:(id)arg1 didObserveDoubleTapWithLocationInfo:(id)arg2 gestureRecognizer:(id)arg3 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMREELSLIKE_BLOCK(sciOrigBlk);
}
%end

// Liking comments
%hook IGCommentCellController
- (void)commentCell:(id)arg1 didTapLikeButton:(id)arg2 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
- (void)commentCell:(id)arg1 didTapLikedByButtonForUser:(id)arg2 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
- (void)commentCellDidLongPressOnLikeButton:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
- (void)commentCellDidEndLongPressOnLikeButton:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
- (void)commentCellDidDoubleTap:(id)arg1 {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
%end
%hook IGFeedItemPreviewCommentCell
- (void)didTapLikeButton {
    void (^sciOrigBlk)(void) = ^{
        %orig;
    };
    CONFIRMPOSTLIKE_BLOCK(sciOrigBlk);
}
%end

// Story like/emoji confirm handled by SCIStoryInteractionPipeline.