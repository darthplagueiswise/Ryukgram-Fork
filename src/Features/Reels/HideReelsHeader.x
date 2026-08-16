#import "../../Utils.h"

%hook IGSundialViewerNavigationBarOld
- (void)didMoveToWindow {
    %orig;
    if ([RYGUtils getBoolPref:@"hide_reels_header"]) [self removeFromSuperview];
}
%end
