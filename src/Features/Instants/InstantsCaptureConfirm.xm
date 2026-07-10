#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"

extern "C" BOOL SCIInstantsShouldSwallowCaptureRelease(void);

static BOOL sciQuickSnapVCTree(UIViewController *vc) {
    if (!vc) return NO;
    if ([NSStringFromClass(vc.class) rangeOfString:@"QuickSnap"].location != NSNotFound) return YES;
    for (UIViewController *c in vc.childViewControllers) if (sciQuickSnapVCTree(c)) return YES;
    return sciQuickSnapVCTree(vc.presentedViewController);
}

static BOOL sciQuickSnapActive(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            if (sciQuickSnapVCTree(w.rootViewController)) return YES;
    }
    return NO;
}

#pragma mark - Capture confirm (tap = photo, hold = video)

// Release the hold before confirming, else IG rolls the held button into a recording.
// Hold path: arm on press, confirm on first AVAssetWriter finishWriting, clear on a tap.
static __weak id sInstantCaptureButton;
static volatile BOOL sVideoGateArmed;

static void sciClearCaptureHold(void) {
    id btn = sInstantCaptureButton;
    if (!btn) return;
    UIGestureRecognizer *gr = ((id (*)(id, SEL))objc_msgSend)(btn, @selector(longPressGestureRecognizer));
    if ([gr isKindOfClass:UIGestureRecognizer.class]) { gr.enabled = NO; gr.enabled = YES; }
    ((void (*)(id, SEL, long long))objc_msgSend)(btn, @selector(setButtonState:), 1);
}

%group SCIInstantCaptureConfirm

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
        %orig(handler);
        return;
    }
    if (!sciQuickSnapActive()) {
        sVideoGateArmed = NO;
        %orig(handler);
        return;
    }
    sVideoGateArmed = NO;

    void (^orig)(void) = [handler copy];
    void (^gated)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            {
            	void (^sciOrigBlock)(void) = ^ {
            		if (orig) orig();
            	};
            	[SCIUtils showConfirmation:sciOrigBlock title:SCILocalized(@"Confirm Instants capture")];
            }
        });
    };
    %orig(gated);
}

%end

%hook _TtC34IGQuickSnapCameraControlController28IGQuickSnapCameraControlView

- (void)captureButtonDidReleaseBeforeExpandingFinished {
    if (SCIInstantsShouldSwallowCaptureRelease()) return;
    sVideoGateArmed = NO;
    sciClearCaptureHold();
    {
    	void (^sciOrigBlock)(void) = ^ {
    		%orig;
    	};
    	[SCIUtils showConfirmation:sciOrigBlock title:SCILocalized(@"Confirm Instants capture")];
    }
}

%end

%end

#pragma mark - Switch-Instant confirm

// Tap-to-advance lives in a Swift-internal tapController with no callable advance, so we
// re-enter didPressWithGestureRecognizer: with a stand-in recognizer (state Ended, seeded
// pressStartLocation) that IG reads as a tap.
@interface SCIInstantAdvanceGR : UILongPressGestureRecognizer
@property (nonatomic, assign) CGPoint sciLoc;
@property (nonatomic, weak) UIView *sciView;
@end
@implementation SCIInstantAdvanceGR
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateEnded; }
- (CGPoint)locationInView:(UIView *)view { return self.sciLoc; }
- (UIView *)view { return self.sciView; }
@end

static id SCITapControllerForStack(UIView *stack) {
    if (!stack) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(stack), "tapController");
    return iv ? object_getIvar(stack, iv) : nil;
}

extern "C" void SCIDriveInstantAdvanceForStack(UIView *stack, CGPoint loc) {
    id tc = SCITapControllerForStack(stack);
    if (!tc) return;
    Ivar psl = class_getInstanceVariable(object_getClass(tc), "pressStartLocation");
    if (psl) *(CGPoint *)((char *)(__bridge void *)tc + ivar_getOffset(psl)) = loc;
    SCIInstantAdvanceGR *gr = [SCIInstantAdvanceGR new];
    gr.sciLoc = loc;
    gr.sciView = stack;
    SEL sel = @selector(didPressWithGestureRecognizer:);
    if ([tc respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(tc, sel, gr);
}

%group SCIInstantAdvanceConfirm

%hook _TtC39IGQuickSnapImmersiveViewerSnapStackView61IGQuickSnapImmersiveViewerAnimatingSnapStackViewTapController

- (void)didPressWithGestureRecognizer:(UIGestureRecognizer *)gr {
    if ([gr isKindOfClass:[SCIInstantAdvanceGR class]]) {
    	%orig;
    	return;
    }
    if (gr.state != UIGestureRecognizerStateEnded) {
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

    {
    	void (^sciOrigBlock)(void) = ^ {
    		SCIDriveInstantAdvanceForStack(stack, loc);
    	};
    	[SCIUtils showConfirmation:sciOrigBlock title:SCILocalized(@"Confirm switching Instant")];
    }
}

%end

%end

%ctor {
    if ([SCIUtils getBoolPref:@"instants_capture_confirm"]) %init(SCIInstantCaptureConfirm);
    if ([SCIUtils getBoolPref:@"instants_advance_confirm"]) %init(SCIInstantAdvanceConfirm);
}
