// Per-user story seen-receipt exclusions.
// Excluded users' stories behave normally.
// Provides owner detection helpers, 3-dot menu injection, and overlay refresh utilities.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "StoryHelpers.h"
#import "RYGExcludedStoryUsers.h"
#import "StoryMenuItems.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSDictionary *rygOwnerInfoFromObject(id obj);

// ============ Active story VC tracking ============

__weak UIViewController *rygActiveStoryViewerVC = nil;

static id rygSafeCall0(id obj, SEL sel) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *rygString(id value) {
	if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] ? value : nil;
	if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
	return nil;
}

%hook IGStoryViewerViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygActiveStoryViewerVC = self;
}

- (void)viewWillDisappear:(BOOL)animated {
	if (rygActiveStoryViewerVC == (UIViewController *)self) {
		rygActiveStoryViewerVC = nil;
	}

	%orig;
}

%end

// ============ Owner extraction ============

NSDictionary *rygOwnerInfoFromObject(id obj) {
	if (!obj) return nil;

	@try {
		id pk = rygSafeCall0(obj, @selector(pk));
		id username = rygSafeCall0(obj, @selector(username));
		id fullName = rygSafeCall0(obj, @selector(fullName));

		if (!pk) pk = [RYGUtils fieldCacheValue:obj forKey:@"pk"] ?: [RYGUtils fieldCacheValue:obj forKey:@"strong_id__"] ?: [RYGUtils pkFromIGUser:obj];
		if (!username) username = [RYGUtils fieldCacheValue:obj forKey:@"username"];
		if (!fullName) fullName = [RYGUtils fieldCacheValue:obj forKey:@"full_name"];

		NSString *pkStr = rygString(pk);
		NSString *unStr = rygString(username);
		NSString *fnStr = rygString(fullName) ?: @"";

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
				NSDictionary *info = rygOwnerInfoFromObject(sub);
				if (info) return info;
			}
		}
	} @catch (__unused id e) {}

	return nil;
}

static NSDictionary *rygOwnerInfoFromStoryItem(id item) {
	if (!item) return nil;

	NSDictionary *info = rygOwnerInfoFromObject(item);
	if (info) return info;

	id user = [RYGUtils fieldCacheValue:item forKey:@"user"] ?: rygSafeCall0(item, @selector(user));
	info = rygOwnerInfoFromObject(user);
	if (info) return info;

	id owner = [RYGUtils fieldCacheValue:item forKey:@"owner"] ?: rygSafeCall0(item, @selector(owner));
	return rygOwnerInfoFromObject(owner);
}

NSDictionary *rygOwnerInfoForStoryVC(UIViewController *vc) {
	if (!vc) return nil;

	@try {
		id item = rygSafeCall0(vc, @selector(currentStoryItem));
		NSDictionary *info = rygOwnerInfoFromStoryItem(item);
		if (info) return info;

		id section = rygSafeCall0(vc, @selector(currentlyDisplayedSectionController));
		item = rygSafeCall0(section, @selector(currentStoryItem));
		info = rygOwnerInfoFromStoryItem(item);
		if (info) return info;

		id vm = rygSafeCall0(vc, @selector(currentViewModel));
		info = rygOwnerInfoFromObject(rygSafeCall0(vm, @selector(owner)));
		if (info) return info;

		id owner = nil;

		@try {
			owner = [vm valueForKey:@"owner"];
		} @catch (__unused id e) {}

		return rygOwnerInfoFromObject(owner);
	} @catch (__unused id e) {
		return nil;
	}
}

NSDictionary *rygCurrentStoryOwnerInfo(void) {
	return rygOwnerInfoForStoryVC(rygActiveStoryViewerVC);
}

static id rygStoryItemFromContextProvider(id provider) {
	id ctx = rygSafeCall0(provider, @selector(currentStoryItemContext));
	if (!ctx) ctx = rygSafeCall0(provider, @selector(_currentStoryItemContext));

	id item = rygSafeCall0(ctx, @selector(storyItem));
	return item ?: ctx;
}

// Per-view owner lookup: use the overlay/cell's currentStoryItemContext first.
// This avoids the old expensive section-controller ivar scan.
NSDictionary *rygOwnerInfoForView(UIView *view) {
	if (!view) return nil;

	NSDictionary *info = rygOwnerInfoFromStoryItem(rygStoryItemFromContextProvider(view));
	if (info) return info;

	Class cellClass = NSClassFromString(@"IGStoryFullscreenCell");
	UIView *cur = view;

	while (cur) {
		if (cellClass && [cur isKindOfClass:cellClass]) {
			info = rygOwnerInfoFromStoryItem(rygStoryItemFromContextProvider(cur));
			if (info) return info;
			break;
		}

		cur = cur.superview;
	}

	UIViewController *vc = rygFindVC(view, @"IGStoryViewerViewController");
	return rygOwnerInfoForStoryVC(vc ?: rygActiveStoryViewerVC);
}

BOOL rygIsCurrentStoryOwnerExcluded(void) {
	NSDictionary *info = rygCurrentStoryOwnerInfo();

	// Unknown owner: block_selected → don't block; block_all → block.
	if (!info) return [RYGExcludedStoryUsers isBlockSelectedMode];

	return [RYGExcludedStoryUsers isUserPKExcluded:info[@"pk"]];
}

BOOL rygIsObjectStoryOwnerExcluded(id obj) {
	NSDictionary *info = rygOwnerInfoFromObject(obj);

	if (!info) return [RYGExcludedStoryUsers isBlockSelectedMode];

	return [RYGExcludedStoryUsers isUserPKExcluded:info[@"pk"]];
}

// ============ Overlay utilities ============

static Class rygOverlayClass(void) {
	Class cls = NSClassFromString(@"IGStoryFullscreenOverlayView");
	return cls ?: NSClassFromString(@"IGStoryFullscreenOverlayMetalLayerView");
}

void rygTriggerStoryMarkSeen(UIViewController *storyVC) {
	if (!storyVC) return;

	Class cls = rygOverlayClass();
	if (!cls) return;

	SEL markSel = @selector(rygStoryMarkSeenTapped:);
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

void rygRefreshAllVisibleOverlays(UIViewController *storyVC) {
	if (!storyVC) return;

	Class cls = rygOverlayClass();
	if (!cls) return;

	SEL updateSel = @selector(rygUpdateStoryOverlayButtons);
	SEL seenSel = @selector(rygRefreshSeenButton);
	SEL audioSel = @selector(rygRefreshAudioButton);

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

// ============ story-menu entry ============

RYGStoryMenuEntry *rygStoryExcludeMenuEntry(void) {
	if (!rygActiveStoryViewerVC) return nil;

	NSDictionary *ownerInfo = rygCurrentStoryOwnerInfo();
	if (!ownerInfo) return nil;

	NSString *pk = ownerInfo[@"pk"];
	NSString *username = ownerInfo[@"username"] ?: @"";
	NSString *fullName = ownerInfo[@"fullName"] ?: @"";
	if (!pk.length) return nil;

	BOOL inList = [RYGExcludedStoryUsers isInList:pk];
	BOOL blockSelected = [RYGExcludedStoryUsers isBlockSelectedMode];

	NSString *addLabel = blockSelected ? RYGLocalized(@"Add to block list") : RYGLocalized(@"Exclude story seen");
	NSString *removeLabel = blockSelected ? RYGLocalized(@"Remove from block list") : RYGLocalized(@"Un-exclude story seen");
	NSString *title = inList ? removeLabel : addLabel;
	NSString *symbol = inList ? @"eye" : @"eye.slash";

	__weak UIViewController *weakVC = rygActiveStoryViewerVC;

	void (^handler)(void) = ^{
		UIViewController *vc = weakVC;

		if (inList) {
			[RYGExcludedStoryUsers removePK:pk];

			RYGNotifySuccess(blockSelected ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_STORY,
							 blockSelected ? RYGLocalized(@"Unblocked") : RYGLocalized(@"Un-excluded"),
							 nil);

			// Removing in block_selected = normal behavior → mark seen.
			if (blockSelected) rygTriggerStoryMarkSeen(vc);
		} else {
			[RYGExcludedStoryUsers addOrUpdateEntry:@{
				@"pk": pk,
				@"username": username,
				@"fullName": fullName
			}];

			RYGNotifySuccess(blockSelected ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_STORY,
							 blockSelected ? RYGLocalized(@"Blocked") : RYGLocalized(@"Excluded"),
							 nil);

			// Adding in block_all = normal behavior → mark seen.
			if (!blockSelected) rygTriggerStoryMarkSeen(vc);
		}

		rygRefreshAllVisibleOverlays(vc);
	};

	return [RYGStoryMenuEntry entryWithTitle:title symbol:symbol handler:handler];
}