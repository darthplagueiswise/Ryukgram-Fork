#import "../../Utils.h"

%hook IGPendingRequestView
- (void)_onApproveButtonTapped {
    if ([RYGUtils getBoolPref:@"follow_request_confirm"]) {
        [RYGUtils showConfirmation:^(void) {
            %orig;
        } title:RYGLocalized(@"Confirm follow requests")];
    } else {
        return %orig;
    }
}
- (void)_onIgnoreButtonTapped {
    if ([RYGUtils getBoolPref:@"follow_request_confirm"]) {
        [RYGUtils showConfirmation:^(void) {
            %orig;
        } title:RYGLocalized(@"Confirm follow requests")];
    } else {
        return %orig;
    }
}
%end
