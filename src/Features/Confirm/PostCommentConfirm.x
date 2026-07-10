#import "../../Utils.h"

%hook IGCommentComposer.IGCommentComposerController
- (void)onSendButtonTap {
    if ([SCIUtils getBoolPref:@"post_comment_confirm"]) {
        {
        	void (^sciOrigBlock)(void) = ^(void) {
        		%orig;
        	};
        	[SCIUtils showConfirmation:sciOrigBlock title:SCILocalized(@"Confirm posting comment")];
        }
    } else {
        return %orig;
    }
}
%end