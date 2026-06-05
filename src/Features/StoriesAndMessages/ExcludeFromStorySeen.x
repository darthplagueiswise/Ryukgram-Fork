// Per-user story seen-receipt exclusions.
// Excluded users' stories behave normally.
// Provides owner detection helpers, 3-dot menu injection, and overlay refresh utilities.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "StoryHelpers.h"
#import "SCIExcludedStoryUsers.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSDictionary *sciOwnerInfoFromObject(id obj);

// ============ Active story VC tracking ============

__weak UIViewController *sciActiveStoryViewerVC = nil;

static id sciSafeCall0(id obj, SEL sel) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *sciString(id value) {
	if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] ? value : nil;
	if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
	return nil;
}

%hook IGStoryViewerViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	sciActiveStoryViewerVC = self;
}

- (void)viewWillDisappear:(BOOL)animated {
	if (sciActiveStoryViewerVC == (UIViewController *)self) {
		sciActiveStoryViewerVC = nil;
	}

	%orig;
}

%end

// ============ Owner extraction ============

NSDictionary *sciOwnerInfoFromObject(id obj) {
	if (!obj) return nil;

	@try {
		id pk = sciSafeCall0(obj, @selector(pk));
		id username = sciSafeCall0(obj, @selector(username));
		id fullName = sciSafeCall0(obj, @selector(fullName));

		if (!pk) pk = [SCIUtils fieldCacheValue:obj forKey:@"pk"] ?: [SCIUtils fieldCacheValue:obj forKey:@"strong_id__"] ?: [SCIUtils pkFromIGUser:obj];
		if (!username) username = [SCIUtils fieldCacheValue:obj forKey:@"username"];
		if (!fullName) fullName = [SCIUtils fieldCacheValue:obj forKey:@"full_name"];

		NSString *pkStr = sciString(pk);
		NSString *unStr = sciString(username);
		NSString *fnStr = sciString(fullName) ?: @"";

		if (pkStr.length && unStr.length) {
			return @{
				@"pk": pkStr,
				@"username": unStr,
				@"fullName": fnStr
			};
		}

		for (NSString *key in @[@"user", @"owner", @"author", @"reelUser", @"reelOwner"]) {
			id sub = nil;

			@try {
				sub = [obj valueForKey:key];
			} @catch (__unused id e) {}

			if (sub && sub != obj) {
				NSDictionary *info = sciOwnerInfoFromObject(sub);
				if (info) return info;
			}
		}
	} @catch (__unused id e) {}

	return nil;
}

static NSDictionary *sciOwnerInfoFromStoryItem(id item) {
	if (!item) return nil;

	NSDictionary *info = sciOwnerInfoFromObject(item);
	if (info) return info;

	id user = [SCIUtils fieldCacheValue:item forKey:@"user"] ?: sciSafeCall0(item, @selector(user));
	info = sciOwnerInfoFromObject(user);
	if (info) return info;

	id owner = [SCIUtils fieldCacheValue:item forKey:@"owner"] ?: sciSafeCall0(item, @selector(owner));
	return sciOwnerInfoFromObject(owner);
}

NSDictionary *sciOwnerInfoForStoryVC(UIViewController *vc) {
	if (!vc) return nil;

	@try {
		id item = sciSafeCall0(vc, @selector(currentStoryItem));
		NSDictionary *info = sciOwnerInfoFromStoryItem(item);
		if (info) return info;

		id section = sciSafeCall0(vc, @selector(currentlyDisplayedSectionController));
		item = sciSafeCall0(section, @selector(currentStoryItem));
		info = sciOwnerInfoFromStoryItem(item);
		if (info) return info;

		id vm = sciSafeCall0(vc, @selector(currentViewModel));
		info = sciOwnerInfoFromObject(sciSafeCall0(vm, @selector(owner)));
		if (info) return info;

		id owner = nil;

		@try {
			owner = [vm valueForKey:@"owner"];
		} @catch (__unused id e) {}

		return sciOwnerInfoFromObject(owner);
	} @catch (__unused id e) {
		return nil;
	}
}

NSDictionary *sciCurrentStoryOwnerInfo(void) {
	return sciOwnerInfoForStoryVC(sciActiveStoryViewerVC);
}

static id sciStoryItemFromContextProvider(id provider) {
	id ctx = sciSafeCall0(provider, @selector(currentStoryItemContext));
	if (!ctx) ctx = sciSafeCall0(provider, @selector(_currentStoryItemContext));

	id item = sciSafeCall0(ctx, @selector(storyItem));
	return item ?: ctx;
}

// Per-view owner lookup: use the overlay/cell's currentStoryItemContext first.
// This avoids the old expensive section-controller ivar scan.
NSDictionary *sciOwnerInfoForView(UIView *view) {
	if (!view) return nil;

	NSDictionary *info = sciOwnerInfoFromStoryItem(sciStoryItemFromContextProvider(view));
	if (info) return info;

	Class cellClass = NSClassFromString(@"IGStoryFullscreenCell");
	UIView *cur = view;

	while (cur) {
		if (cellClass && [cur isKindOfClass:cellClass]) {
			info = sciOwnerInfoFromStoryItem(sciStoryItemFromContextProvider(cur));
			if (info) return info;
			break;
		}

		cur = cur.superview;
	}

	UIViewController *vc = sciFindVC(view, @"IGStoryViewerViewController");
	return sciOwnerInfoForStoryVC(vc ?: sciActiveStoryViewerVC);
}

BOOL sciIsCurrentStoryOwnerExcluded(void) {
	NSDictionary *info = sciCurrentStoryOwnerInfo();

	// Unknown owner: block_selected → don't block; block_all → block.
	if (!info) return [SCIExcludedStoryUsers isBlockSelectedMode];

	return [SCIExcludedStoryUsers isUserPKExcluded:info[@"pk"]];
}

BOOL sciIsObjectStoryOwnerExcluded(id obj) {
	NSDictionary *info = sciOwnerInfoFromObject(obj);

	if (!info) return [SCIExcludedStoryUsers isBlockSelectedMode];

	return [SCIExcludedStoryUsers isUserPKExcluded:info[@"pk"]];
}

// ============ Overlay utilities ============

static Class sciOverlayClass(void) {
	Class cls = NSClassFromString(@"IGStoryFullscreenOverlayView");
	return cls ?: NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
}

void sciTriggerStoryMarkSeen(UIViewController *storyVC) {
	if (!storyVC) return;

	Class cls = sciOverlayClass();
	if (!cls) return;

	SEL markSel = @selector(sciStoryMarkSeenTapped:);
	NSMutableArray *stack = [NSMutableArray arrayWithObject:storyVC.view];

	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];

		if ([view isKindOfClass:cls] && [view respondsToSelector:markSel]) {
			((void (*)(id, SEL, id))objc_msgSend)(view, markSel, nil);
			return;
		}

		[stack addObjectsFromArray:view.subviews];
	}
}

void sciRefreshAllVisibleOverlays(UIViewController *storyVC) {
	if (!storyVC) return;

	Class cls = sciOverlayClass();
	if (!cls) return;

	SEL updateSel = @selector(sciUpdateStoryOverlayButtons);
	SEL seenSel = @selector(sciRefreshSeenButton);
	SEL audioSel = @selector(sciRefreshAudioButton);

	NSMutableArray *stack = [NSMutableArray arrayWithObject:storyVC.view];

	while (stack.count) {
		UIView *view = stack.lastObject;
		[stack removeLastObject];

		if ([view isKindOfClass:cls]) {
			if ([view respondsToSelector:updateSel]) {
				((void (*)(id, SEL))objc_msgSend)(view, updateSel);
			} else {
				if ([view respondsToSelector:seenSel]) {
					((void (*)(id, SEL))objc_msgSend)(view, seenSel);
				}

				if ([view respondsToSelector:audioSel]) {
					((void (*)(id, SEL))objc_msgSend)(view, audioSel);
				}
			}
		}

		[stack addObjectsFromArray:view.subviews];
	}
}

// ============ 3-dot menu injection ============
// Hooks into the existing IGDSMenu hook in Tweak.x via sciMaybeAppendStoryExcludeMenuItem.
// Always present regardless of master toggle.

NSArray *sciMaybeAppendStoryExcludeMenuItem(NSArray *items) {
	if (!sciActiveStoryViewerVC) return items;

	BOOL storyMenu = NO;

	for (id item in items) {
		@try {
			id image = [item valueForKey:@"image"];
			NSString *imageName = [image respondsToSelector:@selector(name)] ? [image performSelector:@selector(name)] : nil;
			NSString *title = [NSString stringWithFormat:@"%@", [item valueForKey:@"title"] ?: @""];

			if ([imageName isEqualToString:@"report_pano_outline_24"] ||
				[imageName isEqualToString:@"mute_24"] ||
				[imageName isEqualToString:@"hide_pano_outline_24"] ||
				[imageName isEqualToString:@"following_24"] ||
				[imageName isEqualToString:@"plus_pano_outline_24"] ||
				[title isEqualToString:@"Report"] ||
				[title isEqualToString:@"Mute"] ||
				[title isEqualToString:@"Unfollow"] ||
				[title isEqualToString:@"Follow"] ||
				[title isEqualToString:@"Hide"]) {
				storyMenu = YES;
				break;
			}
		} @catch (__unused id e) {}
	}

	if (!storyMenu) return items;

	NSDictionary *ownerInfo = sciCurrentStoryOwnerInfo();
	if (!ownerInfo) return items;

	NSString *pk = ownerInfo[@"pk"];
	NSString *username = ownerInfo[@"username"] ?: @"";
	NSString *fullName = ownerInfo[@"fullName"] ?: @"";

	if (!pk.length) return items;

	BOOL inList = [SCIExcludedStoryUsers isInList:pk];
	BOOL blockSelected = [SCIExcludedStoryUsers isBlockSelectedMode];

	Class menuItemCls = NSClassFromString(@"IGDSMenuItem");
	if (!menuItemCls) return items;

	NSString *addLabel = blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude story seen");
	NSString *removeLabel = blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude story seen");
	NSString *title = inList ? removeLabel : addLabel;

	__weak UIViewController *weakVC = sciActiveStoryViewerVC;

	void (^handler)(void) = ^{
		UIViewController *vc = weakVC;

		if (inList) {
			[SCIExcludedStoryUsers removePK:pk];

			SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
							 blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded"),
							 nil);

			// Removing in block_selected = normal behavior → mark seen.
			if (blockSelected) sciTriggerStoryMarkSeen(vc);
		} else {
			[SCIExcludedStoryUsers addOrUpdateEntry:@{
				@"pk": pk,
				@"username": username,
				@"fullName": fullName
			}];

			SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY,
							 blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded"),
							 nil);

			// Adding in block_all = normal behavior → mark seen.
			if (!blockSelected) sciTriggerStoryMarkSeen(vc);
		}

		sciRefreshAllVisibleOverlays(vc);
	};

	id newItem = nil;

	@try {
		newItem = ((id (*)(id, SEL, id, id, id))objc_msgSend)(
			[menuItemCls alloc],
			@selector(initWithTitle:image:handler:),
			title,
			nil,
			handler
		);
	} @catch (__unused id e) {}

	if (!newItem) return items;

	NSMutableArray *out = items.mutableCopy ?: NSMutableArray.array;
	[out addObject:newItem];

	return out.copy;
}