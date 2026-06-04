#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"

static char kSCISnapPressStartKey;

// Hold-to-record fires a different selector and passes through.
%hook _TtC34IGQuickSnapCameraControlController28IGQuickSnapCameraControlView

- (void)captureButtonDidReleaseBeforeExpandingFinished {
    if (![SCIUtils getBoolPref:@"instants_capture_confirm"]) { %orig; return; }
    [SCIUtils showConfirmation:^{ %orig; }
                         title:SCILocalized(@"Confirm Instants capture")];
}

%end

// Tap + swipe share this recognizer. Filter on press start/end so swipe
// passes through. After confirm, %orig is stale — drive handleTap directly.
%hook _TtC39IGQuickSnapImmersiveViewerSnapStackView48IGQuickSnapImmersiveViewerAnimatingSnapStackView

- (void)didPressWithGestureRecognizer:(UIGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) {
        CGPoint loc = [gr locationInView:(UIView *)self];
        NSDictionary *info = @{ @"t": @(CACurrentMediaTime()),
                                @"x": @(loc.x),
                                @"y": @(loc.y) };
        objc_setAssociatedObject(self, &kSCISnapPressStartKey, info,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig;
        return;
    }
    if (gr.state != UIGestureRecognizerStateEnded) { %orig; return; }
    if (![SCIUtils getBoolPref:@"instants_advance_confirm"]) { %orig; return; }

    NSDictionary *start = objc_getAssociatedObject(self, &kSCISnapPressStartKey);
    CGPoint endLoc = [gr locationInView:(UIView *)self];
    NSTimeInterval dur = start ? CACurrentMediaTime() - [start[@"t"] doubleValue] : 0;
    CGFloat dx = start ? endLoc.x - [start[@"x"] doubleValue] : 0;
    CGFloat dy = start ? endLoc.y - [start[@"y"] doubleValue] : 0;
    if (dur > 0.4 || (dx * dx + dy * dy) > (12.0 * 12.0)) { %orig; return; }

    id stackView = self;
    [SCIUtils showConfirmation:^{
        SEL tap = NSSelectorFromString(@"handleTap");
        if ([stackView respondsToSelector:tap]) {
            ((void(*)(id,SEL))objc_msgSend)(stackView, tap);
        }
    } title:SCILocalized(@"Confirm switching Instant")];
}

%end
