#import "../../InstagramHeaders.h"
#import "../../Utils.h"

%hook IGStoryEyedropperToggleButton
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"detailed_color_picker"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}

%new - (void)addLongPressGestureRecognizer {
    if ([self.gestureRecognizers count] == 0) {

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.25;
        [self addGestureRecognizer:longPress];
    }
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    UIColorPickerViewController *colorPickerController = [[UIColorPickerViewController alloc] init];

    colorPickerController.delegate = (id<UIColorPickerViewControllerDelegate>)self; // cast to suppress warnings
    colorPickerController.title = SCILocalized(@"Select color");
    colorPickerController.modalPresentationStyle = UIModalPresentationPopover;
    colorPickerController.supportsAlpha = NO;
    colorPickerController.selectedColor = self.color;

    UIViewController *presentingVC = [SCIUtils nearestViewControllerForView:self];

    if (presentingVC != nil) {
        [presentingVC presentViewController:colorPickerController animated:YES completion:nil];
    }
}

%new - (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                        didSelectColor:(UIColor *)color
                          continuously:(BOOL)continuously
{
    UIColor *opaque = [color colorWithAlphaComponent:1.0];
    self.color = opaque;

    [self setPushedDown:YES];

    id presentingVC = [SCIUtils nearestViewControllerForView:self];

    if ([presentingVC isKindOfClass:%c(IGStoryTextEntryViewController)]) {
        if ([presentingVC respondsToSelector:@selector(textViewControllerDidUpdateWithColor:colorSource:)])
            [presentingVC textViewControllerDidUpdateWithColor:color colorSource:0];
        else if ([presentingVC respondsToSelector:@selector(textEntryControls:didSelectColor:)])
            [presentingVC textEntryControls:nil didSelectColor:color];
    }
    else if (
        [presentingVC isKindOfClass:(NSClassFromString(@"_TtC25IGStoryPostCaptureDrawing36IGStoryCreationDrawingViewController") ?: NSClassFromString(@"IGStoryCreationDrawingViewController"))]
        || [presentingVC isKindOfClass:%c(IGDirectThreadViewDrawingViewController)]
    ) {
        if ([presentingVC respondsToSelector:@selector(drawingControls:didSelectColor:)])
            [presentingVC drawingControls:nil didSelectColor:color];
    }

};
%end

%hook IGStoryColorPaletteView
- (CGFloat)collectionView:(id)view didSelectItemAtIndexPath:(id)index {
    UIView *colorPickingControls = [self superview];

    if (
        [colorPickingControls isKindOfClass:(NSClassFromString(@"_TtC33IGStoryPostCaptureDrawingControls27IGStoryColorPickingControls") ?: NSClassFromString(@"IGStoryColorPickingControls"))]
        || [colorPickingControls isKindOfClass:%c(IGDirectThreadColorPickingControls)]
    ) {
        // Probe before reading — blind MSHookIvar on a missing ivar crashes. IG renamed it to the Swift name (no underscore); keep old name as fallback.
        Ivar iv = class_getInstanceVariable([colorPickingControls class], "eyedropperToggleButton")
                ?: class_getInstanceVariable([colorPickingControls class], "_eyedropperToggleButton");
        if (iv) {
            IGStoryEyedropperToggleButton *eyedropper = object_getIvar(colorPickingControls, iv);
            if (eyedropper != nil) {
                [eyedropper setPushedDown:NO];
            }
        }
    }

    return %orig;
}
%end