#import "../../Utils.h"

// Hide Stories Midcards Trending / Music.

%group NoStoriesMidcardsGroup
%hook IGStoriesMidcardsController
- (void)fetchMidcards {
	return;
}
- (BOOL)_isEligibleForAYPromo {
	return NO;
}
- (BOOL)_isEligibleForSUMidcard {
	return NO;
}
%end
%end

%ctor {if ([SCIUtils getBoolPref:@"hide_stories_midcards"]) {
	%init(NoStoriesMidcardsGroup);
	}
}