// Close the Instants viewer once all instants are seen, instead of parking on the camera.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"

static __weak id sViewerVC;
static __weak id sViewerDelegate;
static BOOL sViewedInstants;
static CFTimeInterval sCameraTapTime;

static id rygIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    return iv ? object_getIvar(obj, iv) : nil;
}

%group RYGInstantsAutoClose

%hook _TtC11IGQuickSnap25IGQuickSnapViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sViewerVC = self;
    sViewerDelegate = rygIvar(self, "delegate");
    sViewedInstants = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    sViewerVC = nil;
    sViewerDelegate = nil;
    sViewedInstants = NO;
}

%end

%hook _TtC26IGQuickSnapConsumptionCore36IGQuickSnapConsumptionViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sViewedInstants = YES;
}

%end

%hook _TtC45IGQuickSnapNavigationV3HeaderButtonController45IGQuickSnapNavigationV3HeaderButtonController

- (void)didTapCameraButton {
    %orig;
    sCameraTapTime = CACurrentMediaTime();
}

%end

%hook _TtC23IGQuickSnapCreationCore33IGQuickSnapCreationViewController

// The camera button's action fires just after this VC appears, so defer the decision
// one hop: a manual camera tap refreshes the timestamp, an end-of-reel park leaves it stale.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!sViewedInstants) return;
    id delegate = sViewerDelegate, vc = sViewerVC;
    if (!delegate || !vc) return;
    SEL sel = @selector(quickSnapImmersiveViewerViewControllerDidTapToDismiss:);
    if (![delegate respondsToSelector:sel]) return;
    CFTimeInterval appeared = CACurrentMediaTime();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!sViewedInstants || sCameraTapTime > appeared - 0.3) return;
        sViewedInstants = NO;
        ((void (*)(id, SEL, id))objc_msgSend)(delegate, sel, vc);
    });
}

%end

%end

%ctor {
    if ([RYGUtils getBoolPref:@"instants_auto_close"]) %init(RYGInstantsAutoClose);
}
