#import "../../Utils.h"

%hook IGPendingRequestView
- (void)_onApproveButtonTapped {
    if ([SCIUtils getBoolPref:@"follow_request_confirm"]) {
        {
        	void (^sciOrigBlock)(void) = ^(void) {
        		%orig;
        	};
        	[SCIUtils showConfirmation:sciOrigBlock title:SCILocalized(@"Confirm follow requests")];
        }
    } else {
        return %orig;
    }
}
- (void)_onIgnoreButtonTapped {
    if ([SCIUtils getBoolPref:@"follow_request_confirm"]) {
        {
        	void (^sciOrigBlock)(void) = ^(void) {
        		%orig;
        	};
        	[SCIUtils showConfirmation:sciOrigBlock title:SCILocalized(@"Confirm follow requests")];
        }
    } else {
        return %orig;
    }
}
%end
