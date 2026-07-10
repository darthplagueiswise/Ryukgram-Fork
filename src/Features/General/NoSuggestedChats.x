#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Channels dms tab (header)
%hook IGDirectInboxHeaderSectionController
- (id)viewModel {
    id sciOrigViewModel = %orig;

    if ([[sciOrigViewModel title] isEqualToString:@"Suggested"]) {

        if ([SCIUtils getBoolPref:@"no_suggested_chats"]) {
            return nil;
        }

    }

    return sciOrigViewModel;
}
%end

%ctor {
    %init(IGDirectInboxHeaderSectionController = NSClassFromString(@"_TtC32IGDirectInboxViewControllerSwift36IGDirectInboxHeaderSectionController") ?: NSClassFromString(@"IGDirectInboxHeaderSectionController"));
}