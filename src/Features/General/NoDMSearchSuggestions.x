#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Strip suggestion sections (More suggestions / More accounts / Channels) from DM search.
%group DMSuggestGroup

%hook IGDirectInboxSearchListAdapterDataSource

- (id)objectsForListAdapter:(id)adapter {
	NSArray *objs = %orig;
	if (![SCIUtils getBoolPref:@"no_dm_search_suggestions"]) return objs;
	if (![objs isKindOfClass:NSArray.class]) return objs;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:objs.count];
	BOOL dropping = NO;
	for (id o in objs) {
		if ([o isKindOfClass:%c(IGLabelItemViewModel)]) {
			id tag = nil;
			@try { tag = [o valueForKey:@"tag"]; } @catch (__unused id e) {}
			int tg = [tag respondsToSelector:@selector(intValue)] ? [tag intValue] : -1;
			// tag is language-independent: 2 = More suggestions, 9 = More accounts, 13 = Channels
			BOOL isSuggest = (tg == 2 || tg == 9 || tg == 13);
			if (isSuggest) { dropping = YES; continue; }
			dropping = NO;
			[out addObject:o];
			continue;
		}
		if (dropping && [o isKindOfClass:%c(IGDirectRecipientCellViewModel)]) continue;
		[out addObject:o];
	}
	return out.copy;
}

%end

%end

%ctor {
	Class cls = NSClassFromString(@"IGDirectInboxSearchListAdapterDataSource");
	if (cls) %init(DMSuggestGroup, IGDirectInboxSearchListAdapterDataSource = cls);
}
