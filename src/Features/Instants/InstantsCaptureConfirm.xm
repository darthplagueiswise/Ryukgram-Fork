#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"

extern "C" BOOL RYGInstantsShouldSwallowCaptureRelease(void);

static BOOL rygQuickSnapVCTree(UIViewController *vc) {
    if (!vc) return NO;
    if ([NSStringFromClass(vc.class) rangeOfString:@"QuickSnap"].location != NSNotFound) return YES;
    for (UIViewController *c in vc.childViewControllers) if (rygQuickSnapVCTree(c)) return YES;
    return rygQuickSnapVCTree(vc.presentedViewController);
}

static BOOL rygQuickSnapActive(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            if (rygQuickSnapVCTree(w.rootViewController)) return YES;
    }
    return NO;
}

#pragma mark - Capture confirm (tap = photo, hold = video)

// Release the hold before confirming, else IG rolls the held button into a recording.
// Hold path: arm on press, confirm on first AVAssetWriter finishWriting, clear on a tap.
static __weak id sInstantCaptureButton;
static volatile BOOL sVideoGateArmed;

static void rygClearCaptureHold(void) {
    id btn = sInstantCaptureButton;
    if (!btn) return;
    UIGestureRecognizer *gr = ((id (*)(id, SEL))objc_msgSend)(btn, @selector(longPressGestureRecognizer));
    if ([gr isKindOfClass:UIGestureRecognizer.class]) { gr.enabled = NO; gr.enabled = YES; }
    ((void (*)(id, SEL, long long))objc_msgSend)(btn, @selector(setButtonState:), 1);
}

%group RYGInstantCaptureConfirm

%hook IGCameraCaptureButton

- (void)_longPress:(id)gr {
    sInstantCaptureButton = self;
    if ([gr respondsToSelector:@selector(state)]
        && [(UIGestureRecognizer *)gr state] == UIGestureRecognizerStateBegan) {
        sVideoGateArmed = YES;
    }
    %orig;
}

%end

%hook AVAssetWriter

- (void)finishWritingWithCompletionHandler:(void (^)(void))handler {
    if (!sVideoGateArmed) {
        %orig;
        return;
    }
    sVideoGateArmed = NO;
    if (![RYGUtils getBoolPref:@"instants_capture_confirm"] || !rygQuickSnapActive()) {
        %orig;
        return;
    }

    void (^orig)(void) = [handler copy];
    void (^gated)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [RYGUtils showConfirmation:^{ if (orig) orig(); }
                                 title:RYGLocalized(@"Confirm Instants capture")];
        });
    };
    handler = gated;
    %orig;
}

%end

%hook _TtC34IGQuickSnapCameraControlController28IGQuickSnapCameraControlView

- (void)captureButtonDidReleaseBeforeExpandingFinished {
    if (![RYGUtils getBoolPref:@"instants_capture_confirm"]) {
        %orig;
        return;
    }
    if (RYGInstantsShouldSwallowCaptureRelease()) return;
    sVideoGateArmed = NO;
    rygClearCaptureHold();
    [RYGUtils showConfirmation:^{
        %orig;
    } title:RYGLocalized(@"Confirm Instants capture")];
}

%end

%end

#pragma mark - Switch-Instant confirm

// Tap-to-advance lives in a Swift-internal tapController with no callable advance, so we
// re-enter didPressWithGestureRecognizer: with a stand-in recognizer (state Ended, seeded
// pressStartLocation) that IG reads as a tap.
@interface RYGInstantAdvanceGR : UILongPressGestureRecognizer
@property (nonatomic, assign) CGPoint rygLoc;
@property (nonatomic, weak) UIView *rygView;
@end
@implementation RYGInstantAdvanceGR
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateEnded; }
- (CGPoint)locationInView:(UIView *)view { return self.rygLoc; }
- (UIView *)view { return self.rygView; }
@end

static id RYGTapControllerForStack(UIView *stack) {
    if (!stack) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(stack), "tapController");
    return iv ? object_getIvar(stack, iv) : nil;
}

extern "C" void RYGDriveInstantAdvanceForStack(UIView *stack, CGPoint loc) {
    id tc = RYGTapControllerForStack(stack);
    if (!tc) return;
    Ivar psl = class_getInstanceVariable(object_getClass(tc), "pressStartLocation");
    if (psl) *(CGPoint *)((char *)(__bridge void *)tc + ivar_getOffset(psl)) = loc;
    RYGInstantAdvanceGR *gr = [RYGInstantAdvanceGR new];
    gr.rygLoc = loc;
    gr.rygView = stack;
    SEL sel = @selector(didPressWithGestureRecognizer:);
    if ([tc respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(tc, sel, gr);
}

%group RYGInstantAdvanceConfirm

%hook _TtC39IGQuickSnapImmersiveViewerSnapStackView61IGQuickSnapImmersiveViewerAnimatingSnapStackViewTapController

- (void)didPressWithGestureRecognizer:(UIGestureRecognizer *)gr {
    if ([gr isKindOfClass:[RYGInstantAdvanceGR class]]) {
        %orig;
        return;
    }
    if (gr.state != UIGestureRecognizerStateEnded) {
        %orig;
        return;
    }
    if (![RYGUtils getBoolPref:@"instants_advance_confirm"]) {
        %orig;
        return;
    }

    UIView *stack = gr.view;
    Ivar psl = class_getInstanceVariable(object_getClass(self), "pressStartLocation");
    CGPoint start = psl ? *(CGPoint *)((char *)(__bridge void *)self + ivar_getOffset(psl)) : CGPointZero;
    CGPoint loc = [gr locationInView:stack];
    CGFloat dx = loc.x - start.x, dy = loc.y - start.y;
    if ((dx * dx + dy * dy) > (12.0 * 12.0)) {
        %orig;
        return;
    }  // travelled => swipe

    [RYGUtils showConfirmation:^{ RYGDriveInstantAdvanceForStack(stack, loc); }
                         title:RYGLocalized(@"Confirm switching Instant")];
}

%end

%end

%ctor {
    if ([RYGUtils getBoolPref:@"instants_capture_confirm"]) %init(RYGInstantCaptureConfirm);
    if ([RYGUtils getBoolPref:@"instants_advance_confirm"] || [RYGUtils getBoolPref:@"instants_confirm_toggle_btn"])
        %init(RYGInstantAdvanceConfirm);
}
