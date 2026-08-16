#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static inline BOOL rygReelsScrollLocked(void) {
    return [RYGUtils getBoolPref:@"disable_scrolling_reels"];
}

%hook IGUnifiedVideoCollectionView
- (void)didMoveToWindow {
    %orig;
    if (rygReelsScrollLocked()) self.scrollEnabled = NO;
}
- (void)setScrollEnabled:(BOOL)enabled {
    %orig(rygReelsScrollLocked() ? NO : enabled);
}
%end

%hook _TtC19IGSundialAutoScroll19IGSundialAutoScroll
- (void)setIsEnabled:(BOOL)enabled {
    %orig(rygReelsScrollLocked() ? NO : enabled);
}
%end
