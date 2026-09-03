// Hide the trending-searches pill bar inside the search-typeahead screen.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// IG 433 swift-ified the typeahead header: the pill bar's delegate is now
// IGSearchTypeaheadSearchBarContainerView (owns `serpPillsView`).
static BOOL rygIsTypeaheadPillBarDelegate(id delegate) {
    if (!delegate) return NO;
    static Class oldCls = Nil, newCls = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        oldCls = NSClassFromString(@"IGSearchTypeaheadNavigationHeaderView");
        newCls = NSClassFromString(@"_TtC15IGGenericSearch39IGSearchTypeaheadSearchBarContainerView");
    });
    return (oldCls && [delegate isKindOfClass:oldCls]) ||
           (newCls && [delegate isKindOfClass:newCls]);
}

%group HideTrendingSearchesGroup
%hook IGDSSegmentedPillBarView
- (void)didMoveToSuperview {
    %orig;
    if (!rygIsTypeaheadPillBarDelegate([self delegate])) return;
    self.hidden = YES;
}
- (void)layoutSubviews {
    %orig;
    if (!rygIsTypeaheadPillBarDelegate([self delegate])) return;
    self.hidden = YES;
}
%end
%end

%ctor {
    if ([RYGUtils getBoolPref:@"hide_trending_searches"] ||
        [RYGUtils getBoolPref:@"messages_only"] ||
        [RYGUtils getBoolPref:@"messages_only_schedule_enabled"]) {
        %init(HideTrendingSearchesGroup);
    }
}
