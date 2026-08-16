#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%hook IGCoreTextView
- (void)didMoveToSuperview {
    %orig;
    if ([RYGUtils getBoolPref:@"copy_description"]) [self addHandleLongPress];
}

%new - (void)addHandleLongPress {
    UILongPressGestureRecognizer *gr = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    gr.minimumPressDuration = 0.5;
    [self addGestureRecognizer:gr];
}

%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSString *text = self.text ?: @"";
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSInteger end = (NSInteger)text.length;
    while (end > 0) {
        while (end > 0 && [ws characterIsMember:[text characterAtIndex:end - 1]]) end--;
        if (end == 0) break;
        NSInteger start = end;
        while (start > 0 && ![ws characterIsMember:[text characterAtIndex:start - 1]]) start--;
        if ([text characterAtIndex:start] == '#') { end = start; continue; }
        break;
    }
    NSString *clean = [[text substringToIndex:end] stringByTrimmingCharactersInSet:ws];

    UIPasteboard.generalPasteboard.string = clean;
    RYGNotifySuccess(RYG_NOTIF_COPY_DESCRIPTION, RYGLocalized(@"Copied text to clipboard"), nil);
}
%end
