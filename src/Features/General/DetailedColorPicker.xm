#import "../../InstagramHeaders.h"
#import "../../Utils.h"

%hook IGStoryEyedropperToggleButton
- (void)didMoveToWindow {
    %orig;
    if ([RYGUtils getBoolPref:@"detailed_color_picker"]) [self addLongPressGestureRecognizer];
}

%new - (void)addLongPressGestureRecognizer {
    if (self.gestureRecognizers.count) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.25;
    [self addGestureRecognizer:lp];
}

%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    UIViewController *host = [RYGUtils nearestViewControllerForView:self];
    if (!host) return;

    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = (id<UIColorPickerViewControllerDelegate>)self;
    picker.title = RYGLocalized(@"Select color");
    picker.modalPresentationStyle = UIModalPresentationPopover;
    picker.supportsAlpha = NO;
    picker.selectedColor = self.color;
    [host presentViewController:picker animated:YES completion:nil];
}

%new - (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                        didSelectColor:(UIColor *)color
                          continuously:(BOOL)continuously {
    self.color = [color colorWithAlphaComponent:1.0];
    [self setPushedDown:YES];

    id host = [RYGUtils nearestViewControllerForView:self];
    Class drawStory = NSClassFromString(@"_TtC25IGStoryPostCaptureDrawing36IGStoryCreationDrawingViewController")
                    ?: NSClassFromString(@"IGStoryCreationDrawingViewController");

    if ([host isKindOfClass:%c(IGStoryTextEntryViewController)]) {
        if ([host respondsToSelector:@selector(textViewControllerDidUpdateWithColor:colorSource:)])
            [host textViewControllerDidUpdateWithColor:color colorSource:0];
        else if ([host respondsToSelector:@selector(textEntryControls:didSelectColor:)])
            [host textEntryControls:nil didSelectColor:color];
    } else if ([host isKindOfClass:drawStory] || [host isKindOfClass:%c(IGDirectThreadViewDrawingViewController)]) {
        if ([host respondsToSelector:@selector(drawingControls:didSelectColor:)])
            [host drawingControls:nil didSelectColor:color];
    }
}
%end

%hook IGStoryColorPaletteView
- (CGFloat)collectionView:(id)view didSelectItemAtIndexPath:(id)index {
    UIView *controls = self.superview;
    Class drawControls = NSClassFromString(@"_TtC33IGStoryPostCaptureDrawingControls27IGStoryColorPickingControls")
                       ?: NSClassFromString(@"IGStoryColorPickingControls");
    if ([controls isKindOfClass:drawControls] || [controls isKindOfClass:%c(IGDirectThreadColorPickingControls)]) {
        Ivar iv = class_getInstanceVariable(controls.class, "eyedropperToggleButton")
                ?: class_getInstanceVariable(controls.class, "_eyedropperToggleButton");
        IGStoryEyedropperToggleButton *eyedropper = iv ? object_getIvar(controls, iv) : nil;
        [eyedropper setPushedDown:NO];
    }
    return %orig;
}
%end
