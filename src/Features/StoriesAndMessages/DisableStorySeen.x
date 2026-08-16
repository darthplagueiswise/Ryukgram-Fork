// Story seen-receipt blocking. Lets IG's natural pipeline run for visual
// state and filters server uploads at IGStorySeenState construction —
// every `/media/seen/` request body is built from one of those snapshots,
// so dropping blocked-owner keys at construction prevents the receipt
// reaching the wire across all flush paths (mid-session, dismiss, restart).
// Per-PK allow-set (`rygAllowedSeenPKs`) lets the eye button slot one
// explicit media into the same batch flush.

#import "StoryHelpers.h"
#import "RYGStoryInteractionPipeline.h"
#import "RYGExcludedStoryUsers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

BOOL rygSeenBypassActive = NO;
BOOL rygAdvanceBypassActive = NO;
BOOL rygStorySeenToggleEnabled = NO;
NSMutableSet *rygAllowedSeenPKs = nil;

extern BOOL rygIsCurrentStoryOwnerExcluded(void);
extern BOOL rygIsObjectStoryOwnerExcluded(id obj);

static inline BOOL rygToggleAllowsSeen(void) {
	return [[RYGUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"] && rygStorySeenToggleEnabled;
}

static inline NSString *rygString(id value) {
	return value ? [NSString stringWithFormat:@"%@", value] : nil;
}

static Ivar rygFindIvar(Class cls, const char *name) {
	for (Class c = cls; c; c = class_getSuperclass(c)) {
		Ivar ivar = class_getInstanceVariable(c, name);
		if (ivar) return ivar;
	}
	return NULL;
}

void rygAllowSeenForPK(id media) {
	NSString *pk = rygString(rygCall(media, @selector(pk)));
	if (!pk.length) return;
	if (!rygAllowedSeenPKs) rygAllowedSeenPKs = [NSMutableSet set];
	[rygAllowedSeenPKs addObject:pk];
}

static BOOL rygIsMediaPKAllowed(NSString *pk) {
	return pk.length > 0 && rygAllowedSeenPKs.count > 0 && [rygAllowedSeenPKs containsObject:pk];
}

static BOOL rygIsPKAllowed(id media) {
	if (!media) return NO;
	return rygIsMediaPKAllowed(rygString(rygCall(media, @selector(pk))));
}

static NSString *rygExtractOwnerPKFromItem(id item) {
	if (!item) return nil;
	@try {
		id reelPK = rygCall(item, NSSelectorFromString(@"reelPk"));
		if (reelPK) return [reelPK description];
		id media = rygCall(item, @selector(media)) ?: item;
		id user = rygCall(media, @selector(user)) ?: rygCall(media, @selector(owner));
		if (!user) return nil;
		Ivar pkIvar = rygFindIvar([user class], "_pk");
		id pk = pkIvar ? object_getIvar(user, pkIvar) : rygCall(user, @selector(pk));
		return pk ? [pk description] : nil;
	} @catch (__unused id e) { return nil; }
}

static BOOL rygShouldBlockOwnerPK(NSString *ownerPK) {
	if (![RYGUtils getBoolPref:@"no_seen_receipt"]) return NO;
	if (rygSeenBypassActive || rygToggleAllowsSeen()) return NO;
	if (![RYGExcludedStoryUsers isFeatureEnabled]) return YES;
	return ownerPK.length && ![RYGExcludedStoryUsers isUserPKExcluded:ownerPK];
}

// ============ Visual gates ============

static BOOL rygShouldBlockSeenVisual(void) {
	if (![RYGUtils getBoolPref:@"no_seen_receipt"] || [RYGUtils getBoolPref:@"keep_seen_visual_local"]) return NO;
	if (rygSeenBypassActive || rygToggleAllowsSeen()) return NO;
	return !rygIsCurrentStoryOwnerExcluded();
}

static BOOL rygShouldBlockSeenVisualForObj(id obj) {
	if (![RYGUtils getBoolPref:@"no_seen_receipt"] || [RYGUtils getBoolPref:@"keep_seen_visual_local"]) return NO;
	if (rygSeenBypassActive || rygToggleAllowsSeen()) return NO;
	return !rygIsObjectStoryOwnerExcluded(obj);
}

// ============ Visual-seen hooks ============

%hook IGStoryFullscreenSectionController

- (void)markItemAsSeen:(id)arg1 {
	if (rygShouldBlockSeenVisual() && !rygIsPKAllowed(arg1)) return;
	%orig;
}

- (void)_markItemAsSeen:(id)arg1 {
	if (rygShouldBlockSeenVisual() && !rygIsPKAllowed(arg1)) return;
	%orig;
}

- (void)storySeenStateDidChange:(id)arg1 {
	if (rygShouldBlockSeenVisual()) return;
	%orig;
}

- (void)markCurrentItemAsSeen {
	if (rygShouldBlockSeenVisual()) return;
	%orig;
}

- (void)storyPlayerMediaViewDidPlayToEnd:(id)arg1 {
	if (!rygAdvanceBypassActive && [RYGUtils getBoolPref:@"stop_story_auto_advance"]) return;
	%orig;
}

- (void)advanceToNextReelForAutoScroll {
	if (!rygAdvanceBypassActive && [RYGUtils getBoolPref:@"stop_story_auto_advance"]) return;
	%orig;
}

%end

%hook IGStoryTrayViewModel

- (void)markAsSeen {
	if (rygShouldBlockSeenVisualForObj(self)) return;
	%orig;
}

- (void)setHasUnseenMedia:(BOOL)arg1 {
	if (rygShouldBlockSeenVisualForObj(self)) {
		%orig(YES);
		return;
	}
	%orig;
}

- (BOOL)hasUnseenMedia {
	return rygShouldBlockSeenVisualForObj(self) ? YES : %orig;
}

- (void)setIsSeen:(BOOL)arg1 {
	if (rygShouldBlockSeenVisualForObj(self)) {
		%orig(NO);
		return;
	}
	%orig;
}

- (BOOL)isSeen {
	return rygShouldBlockSeenVisualForObj(self) ? NO : %orig;
}

%end

%hook IGStoryItem

- (void)setHasSeen:(BOOL)arg1 {
	RYGProbeOnce(@"hook.storyseen.item", @"IGStoryItem.setHasSeen fired");
	if (rygShouldBlockSeenVisualForObj(self)) {
		%orig(NO);
		return;
	}
	%orig;
}

- (BOOL)hasSeen {
	return rygShouldBlockSeenVisualForObj(self) ? NO : %orig;
}

%end

%hook IGStoryGradientRingView

- (void)setIsSeen:(BOOL)arg1 {
	if (rygShouldBlockSeenVisual()) {
		%orig(NO);
		return;
	}
	%orig;
}

- (void)setSeen:(BOOL)arg1 {
	if (rygShouldBlockSeenVisual()) {
		%orig(NO);
		return;
	}
	%orig;
}

- (void)updateRingForSeenState:(BOOL)arg1 {
	if (rygShouldBlockSeenVisual()) {
		%orig(NO);
		return;
	}
	%orig;
}

%end

// ============ Active story VC tracking + dismiss flush ============

static NSHashTable *rygPendingStores = nil;

static id (*rygOrigPendingStoreInit)(id, SEL, id, id, id, BOOL);
static id rygNewPendingStoreInit(id self, SEL _cmd, id sessionPK, id uploader, id fileMgr, BOOL bgTask) {
	id result = rygOrigPendingStoreInit(self, _cmd, sessionPK, uploader, fileMgr, bgTask);
	if (result) {
		if (!rygPendingStores) rygPendingStores = [NSHashTable weakObjectsHashTable];
		[rygPendingStores addObject:result];
	}
	return result;
}

// Force-fire each cached IGStoryPendingSeenStateStore's `_uploadTimer`
// (an FBTimer) so an eye-press immediately followed by dismiss still
// flushes within the session instead of waiting for the next launch.
static void rygFlushPendingStores(void) {
	if (!rygPendingStores) return;
	SEL fbFire = NSSelectorFromString(@"_fireTheTimer");
	for (id store in rygPendingStores.allObjects) {
		@try {
			Ivar t = rygFindIvar([store class], "_uploadTimer");
			if (!t) continue;
			id timer = object_getIvar(store, t);
			if (timer && [timer respondsToSelector:fbFire]) {
				((void(*)(id, SEL))objc_msgSend)(timer, fbFire);
			}
		} @catch (__unused id e) {}
	}
}

__weak UIViewController *rygActiveStoryVC = nil;

%hook IGStoryViewerViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygActiveStoryVC = self;
}

- (void)viewWillDisappear:(BOOL)animated {
	if (rygActiveStoryVC == (UIViewController *)self) rygActiveStoryVC = nil;
	if ([RYGUtils getBoolPref:@"no_seen_receipt"] && rygAllowedSeenPKs.count > 0) {
		rygFlushPendingStores();
	}
	%orig;
}

%end

// ============ Mark-seen delegate hook ============
//
// Visual-local mode runs orig (visual updates locally, server upload gets
// filtered at IGStorySeenState construction). Hard-block mode skips orig
// so IG's local state never marks seen.

typedef void (*RYGOrigDelegateMarkSeen)(id, SEL, id, id);

static void rygHandleDelegateMarkSeen(RYGOrigDelegateMarkSeen orig, id self, SEL _cmd, id ctrl, id item) {
	if (!orig) return;

	if (rygSeenBypassActive || rygToggleAllowsSeen() || ![RYGUtils getBoolPref:@"no_seen_receipt"]) {
		orig(self, _cmd, ctrl, item);
		return;
	}

	NSString *ownerPK = rygExtractOwnerPKFromItem(item);
	if (!rygShouldBlockOwnerPK(ownerPK)) {
		orig(self, _cmd, ctrl, item);
		return;
	}

	if ([RYGUtils getBoolPref:@"keep_seen_visual_local"]) {
		orig(self, _cmd, ctrl, item);
	}
}

static RYGOrigDelegateMarkSeen orig_delegateViewer = NULL;
static RYGOrigDelegateMarkSeen orig_delegateUpdater = NULL;
static RYGOrigDelegateMarkSeen orig_delegateViewModel = NULL;
static RYGOrigDelegateMarkSeen orig_delegateManager = NULL;

static void new_delegateViewer(id self, SEL _cmd, id ctrl, id item) {
	rygHandleDelegateMarkSeen(orig_delegateViewer, self, _cmd, ctrl, item);
}

static void new_delegateUpdater(id self, SEL _cmd, id ctrl, id item) {
	rygHandleDelegateMarkSeen(orig_delegateUpdater, self, _cmd, ctrl, item);
}

static void new_delegateViewModel(id self, SEL _cmd, id ctrl, id item) {
	rygHandleDelegateMarkSeen(orig_delegateViewModel, self, _cmd, ctrl, item);
}

static void new_delegateManager(id self, SEL _cmd, id ctrl, id item) {
	rygHandleDelegateMarkSeen(orig_delegateManager, self, _cmd, ctrl, item);
}

// ============ Seen-state filter ============
//
// Dict key encodes the media identity itself:
//   "<innerMediaId>_<mediaOwnerPK>_<reelOwnerPK>"
// First two segments form the full mediaPK that `rygAllowedSeenPKs`
// stores. Values are timestamp tuples (`<takenAt>_<seenAt>`); we never
// look inside them.

static id rygFilterSeenContainer(id container) {
	if (![container isKindOfClass:[NSDictionary class]]) return container;
	NSDictionary *dict = (NSDictionary *)container;
	if (!dict.count) return dict;

	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (NSString *key in dict) {
		NSArray *segs = [key componentsSeparatedByString:@"_"];
		NSString *ownerPK = segs.lastObject;
		NSString *mediaPK = segs.count >= 2
			? [NSString stringWithFormat:@"%@_%@", segs[0], segs[1]]
			: key;

		if (!rygShouldBlockOwnerPK(ownerPK)) {
			out[key] = dict[key];
			continue;
		}
		if (rygAllowedSeenPKs.count && [rygAllowedSeenPKs containsObject:mediaPK]) {
			out[key] = dict[key];
		}
	}
	return out;
}

%hook IGStorySeenState

- (id)initWithReelSeenDictionary:(id)reel
              liveSeenDictionary:(id)live
           reelSkippedDictionary:(id)reelSkipped
           liveSkippedDictionary:(id)liveSkipped
                 containerModule:(id)mod
                    pushCategory:(id)cat
                    forceSeenIds:(id)forceSeen {
	if ([RYGUtils getBoolPref:@"no_seen_receipt"] && !rygSeenBypassActive && !rygToggleAllowsSeen()) {
		reel        = rygFilterSeenContainer(reel);
		live        = rygFilterSeenContainer(live);
		reelSkipped = rygFilterSeenContainer(reelSkipped);
		liveSkipped = rygFilterSeenContainer(liveSkipped);
	}
	return %orig(reel, live, reelSkipped, liveSkipped, mod, cat, forceSeen);
}

%end

// ============ Like → mark-seen side effects ============

static void (*orig_didLikeSundial)(id, SEL, id);
static void new_didLikeSundial(id self, SEL _cmd, id pk) {
	if (orig_didLikeSundial) orig_didLikeSundial(self, _cmd, pk);
	rygStoryInteractionSideEffects(RYGStoryInteractionLike);
}

static void (*orig_overlaySetIsLiked)(id, SEL, BOOL, BOOL);
static void new_overlaySetIsLiked(id self, SEL _cmd, BOOL isLiked, BOOL animated) {
	if (orig_overlaySetIsLiked) orig_overlaySetIsLiked(self, _cmd, isLiked, animated);
	if (isLiked) rygStoryInteractionSideEffects(RYGStoryInteractionLike);
}

static void (*orig_likeButtonSetIsLiked)(id, SEL, BOOL, BOOL);
static void new_likeButtonSetIsLiked(id self, SEL _cmd, BOOL isLiked, BOOL animated) {
	if (orig_likeButtonSetIsLiked) orig_likeButtonSetIsLiked(self, _cmd, isLiked, animated);
	if (isLiked) rygStoryInteractionSideEffects(RYGStoryInteractionLike);
}

static void rygHookIfExists(Class cls, SEL sel, IMP replacement, IMP *original) {
	if (cls && class_getInstanceMethod(cls, sel)) {
		MSHookMessageEx(cls, sel, replacement, original);
	}
}

%ctor {
	%init(IGStoryGradientRingView = NSClassFromString(@"_TtC13IGRingViewKit23IGStoryGradientRingView") ?: NSClassFromString(@"IGStoryGradientRingView"));

	Class overlayController = NSClassFromString(@"IGSundialViewerControlsOverlayController");
	SEL setLikedSel = @selector(setIsLiked:animated:);

	rygHookIfExists(overlayController, NSSelectorFromString(@"didLikeSundialWithMediaPK:"), (IMP)new_didLikeSundial, (IMP *)&orig_didLikeSundial);
	rygHookIfExists(overlayController, setLikedSel, (IMP)new_overlaySetIsLiked, (IMP *)&orig_overlaySetIsLiked);
	rygHookIfExists(NSClassFromString(@"IGSundialViewerUFI.IGSundialLikeButton"), setLikedSel, (IMP)new_likeButtonSetIsLiked, (IMP *)&orig_likeButtonSetIsLiked);

	// Mark-seen delegate. Each class needs its own orig pointer — sharing
	// one across hooks lets a later registration clobber an earlier IMP.
	SEL delegateSel = NSSelectorFromString(@"fullscreenSectionController:didMarkItemAsSeen:");
	rygHookIfExists(NSClassFromString(@"IGStoryViewerViewController"), delegateSel, (IMP)new_delegateViewer, (IMP *)&orig_delegateViewer);
	rygHookIfExists(NSClassFromString(@"IGStoryViewerUpdater"),         delegateSel, (IMP)new_delegateUpdater, (IMP *)&orig_delegateUpdater);
	rygHookIfExists(NSClassFromString(@"IGStoryFullscreenViewModel"),   delegateSel, (IMP)new_delegateViewModel, (IMP *)&orig_delegateViewModel);
	rygHookIfExists(NSClassFromString(@"IGStoriesManager"),             delegateSel, (IMP)new_delegateManager, (IMP *)&orig_delegateManager);

	rygHookIfExists(NSClassFromString(@"_TtC26IGStoryPendingSeenStateKit28IGStoryPendingSeenStateStore") ?: NSClassFromString(@"IGStoryPendingSeenStateStore"),
		NSSelectorFromString(@"initWithUserSessionPK:uploader:fileManager:uploadInBackgroundTask:"),
		(IMP)rygNewPendingStoreInit, (IMP *)&rygOrigPendingStoreInit);
}
