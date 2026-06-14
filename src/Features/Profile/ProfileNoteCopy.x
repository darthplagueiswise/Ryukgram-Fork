// Copy note text on long press — long-press the note bubble to copy text.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>

// IGDirectNotesThoughtBubbleView declared in InstagramHeaders.h

%hook IGDirectNotesThoughtBubbleView

- (void)layoutSubviews {
    %orig;
    if (![SCIUtils getBoolPref:@"profile_note_copy"]) return;

    UIView *view = (UIView *)self;

    // Only add once
    static const NSInteger kCopyGestureTag = 99791;
    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        if (gr.view.tag == kCopyGestureTag) return;
    }
    view.tag = kCopyGestureTag;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(sciCopyNoteLongPress:)];
    lp.minimumPressDuration = 0.5;
    [view addGestureRecognizer:lp];
}

%new - (void)sciCopyNoteLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    // noteText is a Swift String ivar (value type, unreadable via object_getIvar).
    // Read the displayed text off the notesTextView label instead.
    Ivar labelIvar = class_getInstanceVariable([self class], "notesTextView");
    if (!labelIvar) return;
    UILabel *label = object_getIvar(self, labelIvar);
    if (![label isKindOfClass:[UILabel class]]) return;

    NSString *text = label.attributedText.string;
    if (!text.length) return;

    [[UIPasteboard generalPasteboard] setString:text];
    SCINotifySuccess(SCI_NOTIF_COPY_NOTE, SCILocalized(@"Note copied"), nil);
}

%end

%ctor {
    %init(IGDirectNotesThoughtBubbleView = NSClassFromString(@"_TtC30IGDirectNotesThoughtBubbleView30IGDirectNotesThoughtBubbleView") ?: NSClassFromString(@"IGDirectNotesThoughtBubbleView"));
}
