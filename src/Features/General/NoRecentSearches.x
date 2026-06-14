#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Disable logging of searches at server-side
%hook IGSearchEntityRouter
- (id)initWithUserSession:(id)arg1 analyticsModule:(id)arg2 shouldAddToRecents:(BOOL)shouldAddToRecents {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		shouldAddToRecents = NO;
	}

	return %orig(arg1, arg2, shouldAddToRecents);
}

- (id)initWithUserSession:(id)arg1 analyticsModule:(id)arg2 shouldAddToRecents:(BOOL)shouldAddToRecents mode:(NSUInteger)arg3 {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		shouldAddToRecents = NO;
	}

	return %orig(arg1, arg2, shouldAddToRecents, arg3);
}
%end

// Most in-app search bars
%hook _TtC19IGRecentSearchStore19IGRecentSearchStore
- (id)initWithDiskManager:(id)arg1 recentSearchStoreConfiguration:(id)arg2 {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		return nil;
	}

	return %orig;
}

- (BOOL)addItem:(id)arg1 {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		return NO;
	}

	return %orig;
}

// other write/persist paths, in case the store is built around the nil-init
- (BOOL)insertItem:(id)arg1 atPosition:(NSInteger)arg2 {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		return NO;
	}

	return %orig(arg1, arg2);
}

- (void)archive {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		return;
	}

	%orig;
}

- (void)archiveRecentItems {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		return;
	}

	%orig;
}
%end

// Recent dm message recipients search bar
%hook IGDirectRecipientRecentSearchStorage
- (id)initWithDiskManager:(id)arg1 directRepo:(id)arg2 launcherSet:(id)arg3 {
	if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
		return nil;
	}
	return %orig(arg1, arg2, arg3);
}
%end
