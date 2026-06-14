#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%hook IGMainStoryTrayDataSource
- (BOOL)isEmpty {
    if ([SCIUtils getBoolPref:@"hide_stories_tray"]) return YES;
    return %orig;
}
%end

// Expiring-soon stories tray has its own fetch path.
%hook IGStoryExpiringSoonTrayFetcher
- (BOOL)fetchTray {
    if ([SCIUtils getBoolPref:@"hide_stories_tray"]) return NO;
    return %orig;
}
%end
