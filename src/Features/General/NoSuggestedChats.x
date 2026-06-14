#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Channels dms tab (header)
%hook IGDirectInboxHeaderSectionController
- (id)viewModel {
    if ([[%orig title] isEqualToString:@"Suggested"]) {

        if ([SCIUtils getBoolPref:@"no_suggested_chats"]) {
            return nil;
        }

    }

    return %orig;
}
%end

%ctor {
    %init(IGDirectInboxHeaderSectionController = NSClassFromString(@"_TtC32IGDirectInboxViewControllerSwift36IGDirectInboxHeaderSectionController") ?: NSClassFromString(@"IGDirectInboxHeaderSectionController"));
}
