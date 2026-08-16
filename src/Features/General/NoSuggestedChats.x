#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%hook IGDirectInboxHeaderSectionController
- (id)viewModel {
    id vm = %orig;
    if ([RYGUtils getBoolPref:@"no_suggested_chats"] && [[vm title] isEqualToString:@"Suggested"]) {
        return nil;
    }
    return vm;
}
%end

%ctor {
    Class cls = NSClassFromString(@"_TtC32IGDirectInboxViewControllerSwift36IGDirectInboxHeaderSectionController")
        ?: NSClassFromString(@"IGDirectInboxHeaderSectionController");
    %init(IGDirectInboxHeaderSectionController = cls);
}
