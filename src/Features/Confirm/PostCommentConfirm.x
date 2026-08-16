#import "../../Utils.h"

%hook IGCommentComposer.IGCommentComposerController
- (void)onSendButtonTap {
    if (![RYGUtils getBoolPref:@"post_comment_confirm"]) {
        %orig;
        return;
    }
    [RYGUtils showConfirmation:^{
        %orig;
    } title:RYGLocalized(@"Confirm posting comment")];
}
%end
