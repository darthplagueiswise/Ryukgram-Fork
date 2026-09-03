// Story overlay buttons — action / audio / eye / mentions.
// Early-exits in DM context; DMOverlayButtons.xm handles that surface.

#import "OverlayHelpers.h"
#import "StoryHelpers.h"
#import "RYGExcludedStoryUsers.h"
#import "RYGStoryMarkedSeen.h"
#import "RYGStoryButtonLayout.h"
#import "Playback/RYGStoryPlayback.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import "../../ActionButton/RYGActionButton.h"
#import "../../ActionButton/RYGActionIcon.h"
#import "../../ActionButton/RYGMediaActions.h"
#import "../../ActionButton/RYGActionMenu.h"
#import "../../Downloader/Download.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern "C" BOOL rygSeenBypassActive;
extern "C" BOOL rygAdvanceBypassActive;
extern "C" BOOL rygStorySeenToggleEnabled;
extern "C" void rygAllowSeenForPK(id);
extern "C" void rygRefreshAllVisibleOverlays(UIViewController *storyVC);
extern "C" void rygTriggerStoryMarkSeen(UIViewController *storyVC);
extern "C" __weak UIViewController *rygActiveStoryViewerVC;
extern "C" NSDictionary *rygOwnerInfoForView(UIView *view);

static const NSInteger kStoryMentionsCountTag = 13450;

static char kStoryActionDefaultKey;
static char kStoryReelItemsProviderKey;
static char kStoryMentionsCountKey;
static char kStoryMentionsRetryGenKey;
static char kStoryLastAudioKey;
static char kStoryLastMediaPKKey;
static char kStoryInstallPendingKey;

typedef struct {
	BOOL action;
	BOOL audio;
	BOOL seen;
	BOOL mentions;
	BOOL mentionsCounter;
} RYGStoryOverlayPrefs;

static inline RYGStoryOverlayPrefs RYGStoryPrefs(void) {
	RYGStoryOverlayPrefs p;
	p.action = [RYGUtils getBoolPref:@"stories_action_button"];
	p.audio = [RYGUtils getBoolPref:@"story_audio_toggle"];
	p.seen = [RYGUtils getBoolPref:@"no_seen_receipt"] && [RYGUtils getBoolPref:@"show_story_seen_button"];
	p.mentions = [RYGUtils getBoolPref:@"story_mentions_button"];
	p.mentionsCounter = [RYGUtils getBoolPref:@"story_mentions_counter"];
	return p;
}

static void rygConfirmStoryMarkSeen(UIViewController *presenter, void (^onConfirm)(void), void (^onCancel)(void)) {
	[RYGUtils confirmIfNeeded:[RYGUtils getBoolPref:@"confirm_mark_seen_story"]
	                    title:RYGLocalized(@"Mark as seen?")
	                  message:RYGLocalized(@"This will send a story view receipt.")
	             confirmTitle:RYGLocalized(@"Mark seen")
	                     from:presenter
	                onConfirm:onConfirm
	                 onCancel:onCancel];
}

static inline BOOL RYGStoryHasAnyFeature(RYGStoryOverlayPrefs p) {
	return p.action || p.audio || p.seen || p.mentions;
}

static inline NSString *RYGStoryDefaultAction(void) {
	return [RYGUtils getStringPref:@"stories_action_default"] ?: @"";
}

static inline RYGChromeButton *RYGStoryButton(NSString *symbol, CGFloat pointSize, CGFloat diameter, NSInteger tag) {
	RYGChromeButton *button = [[RYGChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:diameter];
	button.tag = tag;
	return button;
}

static inline RYGChromeButton *RYGStoryExistingButton(UIView *root, NSInteger tag) {
	id button = [root viewWithTag:tag];
	return [button isKindOfClass:RYGChromeButton.class] ? button : nil;
}

static inline void RYGRemoveStoryButton(UIView *root, NSInteger tag) {
	[[root viewWithTag:tag] removeFromSuperview];
}

static void RYGRemoveAllStoryButtons(UIView *root) {
	RYGRemoveStoryButton(root, RYG_STORY_ACTION_TAG);
	RYGRemoveStoryButton(root, RYG_STORY_EYE_TAG);
	RYGRemoveStoryButton(root, RYG_STORY_AUDIO_TAG);
	RYGRemoveStoryButton(root, RYG_STORY_MENTIONS_TAG);
}

static NSString *rygLayoutIDForTag(NSInteger tag) {
	switch (tag) {
		case RYG_STORY_ACTION_TAG: return RYGStoryBtnAction;
		case RYG_STORY_AUDIO_TAG: return RYGStoryBtnAudio;
		case RYG_STORY_EYE_TAG: return RYGStoryBtnEye;
		case RYG_STORY_MENTIONS_TAG: return RYGStoryBtnMentions;
	}
	return nil;
}

// Hidden while a comment sheet / keyboard is up — IG shrinks the overlay safe area
// then, which otherwise yanks the buttons to the middle and leaves them stuck.
static BOOL rygStoryButtonsKbHidden = NO;

// Frame-positions each present button at its saved normalized point in the safe area.
static void rygLayoutStoryButtons(UIView *host) {
	CGRect safe = host.safeAreaLayoutGuide.layoutFrame;
	if (safe.size.width <= 0 || safe.size.height <= 0) return;

	UIEdgeInsets ins = [RYGStoryButtonLayout placeableInsetsNormalized];
	CGRect area = CGRectMake(safe.origin.x + ins.left * safe.size.width,
							 safe.origin.y + ins.top * safe.size.height,
							 safe.size.width * (1.0 - ins.left - ins.right),
							 safe.size.height * (1.0 - ins.top - ins.bottom));

	NSInteger allTags[] = { RYG_STORY_ACTION_TAG, RYG_STORY_AUDIO_TAG, RYG_STORY_EYE_TAG, RYG_STORY_MENTIONS_TAG };

	NSMutableArray<NSString *> *presentIDs = NSMutableArray.array;
	for (NSUInteger i = 0; i < 4; i++) {
		if ([host viewWithTag:allTags[i]]) [presentIDs addObject:rygLayoutIDForTag(allTags[i])];
	}
	NSDictionary<NSString *, NSValue *> *resolved = [RYGStoryButtonLayout resolvedPositionsForIDs:presentIDs inSize:safe.size];

	for (NSUInteger i = 0; i < 4; i++) {
		UIView *button = [host viewWithTag:allTags[i]];
		if (!button) continue;

		if (rygStoryButtonsKbHidden) { button.hidden = YES; continue; }
		button.hidden = NO;

		NSString *bid = rygLayoutIDForTag(allTags[i]);
		CGFloat d = [RYGStoryButtonLayout diameterForID:bid];
		CGPoint norm = resolved[bid] ? resolved[bid].CGPointValue : [RYGStoryButtonLayout positionForID:bid];

		CGFloat half = d / 2.0;
		CGFloat cx = safe.origin.x + norm.x * safe.size.width;
		CGFloat cy = safe.origin.y + norm.y * safe.size.height;
		cx = MIN(MAX(cx, CGRectGetMinX(area) + half), CGRectGetMaxX(area) - half);
		cy = MIN(MAX(cy, CGRectGetMinY(area) + half), CGRectGetMaxY(area) - half);

		button.bounds = CGRectMake(0, 0, d, d);
		button.center = CGPointMake(cx, cy);
	}
}

static NSHashTable<UIView *> *rygLiveStoryOverlays(void) {
	static NSHashTable *table;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		table = NSHashTable.weakObjectsHashTable;
	});

	return table;
}

static void rygRegisterLiveStoryOverlay(UIView *overlay) {
	if (overlay.window && !rygOverlayIsInDMContext(overlay)) {
		[rygLiveStoryOverlays() addObject:overlay];
	}
}

static void rygSetStoryButtonsKbHidden(BOOL hidden) {
	if (rygStoryButtonsKbHidden == hidden) return;
	rygStoryButtonsKbHidden = hidden;
	for (UIView *host in rygLiveStoryOverlays().allObjects) rygLayoutStoryButtons(host);
}

static id rygSafeCall0(id target, SEL sel) {
	if (!target || ![target respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(target, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static void rygSafeCall1(id target, SEL sel, id arg) {
	if (!target || ![target respondsToSelector:sel]) return;

	@try {
		((void (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
	} @catch (__unused id e) {}
}

static NSString *rygPKFromObject(id obj) {
	id pk = rygSafeCall0(obj, @selector(pk));
	if (!pk) pk = [RYGUtils fieldCacheValue:obj forKey:@"pk"];
	if (!pk) pk = [RYGUtils fieldCacheValue:obj forKey:@"id"];

	if ([pk respondsToSelector:@selector(stringValue)]) return [pk stringValue];
	return [pk isKindOfClass:NSString.class] ? pk : nil;
}

static UIViewController *rygStoryVCForView(UIView *view) {
	UIViewController *vc = rygFindVC(view, @"IGStoryViewerViewController");
	return vc ?: rygActiveStoryViewerVC;
}

static id rygStorySectionController(UIViewController *storyVC) {
	return rygSafeCall0(storyVC, @selector(currentlyDisplayedSectionController));
}

static id rygOverlayMedia(UIView *view) {
	id media = [RYGUtils getIvarForObj:view name:"_media"];
	Class cls = NSClassFromString(@"IGMedia");
	return (cls && [media isKindOfClass:cls]) ? media : nil;
}

static id rygStoryItemFromContextProvider(id provider) {
	id ctx = rygSafeCall0(provider, @selector(currentStoryItemContext));
	if (!ctx) ctx = rygSafeCall0(provider, @selector(_currentStoryItemContext));

	id item = rygSafeCall0(ctx, @selector(storyItem));
	return item ?: ctx;
}

static id rygCurrentStoryItemFromView(UIResponder *sourceView) {
	UIViewController *storyVC = rygFindVC(sourceView, @"IGStoryViewerViewController");
	storyVC = storyVC ?: rygActiveStoryViewerVC;
	if (!storyVC) return nil;

	id item = rygStoryItemFromContextProvider(sourceView);
	if (item) return item;

	item = rygSafeCall0(storyVC, @selector(currentStoryItem));
	if (item) return item;

	id section = rygStorySectionController(storyVC);
	item = rygSafeCall0(section, @selector(currentStoryItem));
	if (item) return item;

	id vm = rygSafeCall0(storyVC, @selector(currentViewModel));
	return rygSafeCall0(vm, @selector(currentStoryItem)) ?: rygCall1(storyVC, @selector(currentStoryItemForViewModel:), vm);
}

static id rygCurrentStoryMedia(UIView *sourceView) {
	id media = rygOverlayMedia(sourceView);
	if (media) return media;

	id item = rygCurrentStoryItemFromView(sourceView);

	if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return item;
	return rygExtractMediaFromItem(item) ?: (id)kCFNull;
}

static NSString *rygCurrentStoryMediaPK(UIView *sourceView) {
	id media = rygOverlayMedia(sourceView);
	if (media) return rygPKFromObject(media);

	media = rygCurrentStoryMedia(sourceView);
	return media && media != (id)kCFNull ? rygPKFromObject(media) : nil;
}

static NSArray *rygStoryReelItemsForSource(UIView *sourceView) {
	UIViewController *storyVC = rygStoryVCForView(sourceView);
	id vm = rygSafeCall0(storyVC, @selector(currentViewModel));
	id items = rygSafeCall0(vm, @selector(items));
	return ([items isKindOfClass:NSArray.class] && [(NSArray *)items count] > 1) ? items : nil;
}

static void rygPauseStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = rygStoryVCForView(sourceView);
	id section = rygStorySectionController(storyVC);

	if ([section respondsToSelector:@selector(pauseWithReason:)]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(section, @selector(pauseWithReason:), 10);
		return;
	}

	if ([storyVC respondsToSelector:@selector(pauseWithReason:)]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(storyVC, @selector(pauseWithReason:), 10);
	}
}

static void rygResumeStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = rygStoryVCForView(sourceView);
	id section = rygStorySectionController(storyVC);

	if ([section respondsToSelector:@selector(tryResumePlaybackWithReason:)]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(section, @selector(tryResumePlaybackWithReason:), 10);
		return;
	}

	if ([storyVC respondsToSelector:@selector(tryResumePlayback)]) {
		((void (*)(id, SEL))objc_msgSend)(storyVC, @selector(tryResumePlayback));
	}
}

// showsMenuAsPrimaryAction bypasses UIContextMenuInteractionDelegate, so the
// usual willEnd callback never fires — poll the window hierarchy instead.
static BOOL rygAnyContextMenuVisible(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *win in ((UIWindowScene *)scene).windows) {
			NSMutableArray *q = [NSMutableArray arrayWithObject:win];

			while (q.count) {
				UIView *cur = q.lastObject;
				[q removeLastObject];

				NSString *cls = NSStringFromClass(cur.class);
				if ([cls containsString:@"ContextMenuContainerView"] || [cls containsString:@"_UIContextMenuView"] || [cls containsString:@"ContextMenuPlatterView"]) {
					return YES;
				}

				for (UIView *s in cur.subviews) {
					[q addObject:s];
				}
			}
		}
	}

	return NO;
}

static void rygWatchForMenuDismiss(void (^onDismiss)(void)) {
	if (!onDismiss) return;

	__block BOOL appeared = NO;
	__block NSInteger ticks = 0;

	[NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *t) {
		BOOL visible = rygAnyContextMenuVisible();
		if (visible) appeared = YES;

		if ((appeared && !visible) || (!appeared && ++ticks > 120)) {
			[t invalidate];
			onDismiss();
		}
	}];
}

static void RYGConfigureStoryActionButton(RYGChromeButton *button) {
	if (!button) return;

	__weak UIButton *weakBtn = button;

	RYGActionMediaProvider provider = ^id (UIView *sourceView) {
		rygPauseStoryPlayback(sourceView);

		rygWatchForMenuDismiss(^{
			UIButton *b = weakBtn;
			if (b) rygResumeStoryPlayback(b);
		});

		id media = rygCurrentStoryMedia(sourceView);
		return media == (id)kCFNull ? nil : media;
	};

	[RYGActionButton configureButton:button context:RYGActionContextStories prefKey:@"stories_action_default" mediaProvider:provider];

	objc_setAssociatedObject(button, &kStoryReelItemsProviderKey, ^NSArray *(UIView *sourceView) {
		return rygStoryReelItemsForSource(sourceView);
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);

	__weak RYGChromeButton *weakButton = button;

	objc_setAssociatedObject(button, kRYGDismissKey, ^{
		RYGChromeButton *strongButton = weakButton;
		if (strongButton) rygResumeStoryPlayback(strongButton);
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void rygApplyMentionsCounter(RYGChromeButton *button, NSInteger count, BOOL enabled) {
	if (!button) return;

	UILabel *label = (UILabel *)[button viewWithTag:kStoryMentionsCountTag];

	if (!enabled || count <= 0) {
		[label removeFromSuperview];
		objc_setAssociatedObject(button, &kStoryMentionsCountKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	NSNumber *old = objc_getAssociatedObject(button, &kStoryMentionsCountKey);
	if (label && old.integerValue == count) return;

	if (!label) {
		label = [UILabel new];
		label.tag = kStoryMentionsCountTag;
		label.translatesAutoresizingMaskIntoConstraints = NO;
		label.textAlignment = NSTextAlignmentCenter;
		label.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
		label.textColor = UIColor.whiteColor;
		label.backgroundColor = UIColor.systemRedColor;
		label.layer.cornerRadius = 8.0;
		label.layer.masksToBounds = YES;
		label.adjustsFontSizeToFitWidth = YES;
		label.minimumScaleFactor = 0.7;
		label.userInteractionEnabled = NO;

		UIView *host = button.captureContentView;
		[host addSubview:label];

		[NSLayoutConstraint activateConstraints:@[
			[label.topAnchor constraintEqualToAnchor:host.topAnchor constant:-3.0],
			[label.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:3.0],
			[label.widthAnchor constraintGreaterThanOrEqualToConstant:16.0],
			[label.heightAnchor constraintEqualToConstant:16.0]
		]];
	}

	label.text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)count];
	objc_setAssociatedObject(button, &kStoryMentionsCountKey, @(count), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%group StoryOverlayGroup

%hook IGStoryFullscreenOverlayView

- (void)didMoveToWindow {
	%orig;

	if (!self.window) return;

	if (rygOverlayIsInDMContext(self)) {
		RYGRemoveAllStoryButtons(self);
		return;
	}

	rygRegisterLiveStoryOverlay((UIView *)self);

	if ([objc_getAssociatedObject(self, &kStoryInstallPendingKey) boolValue]) return;
	objc_setAssociatedObject(self, &kStoryInstallPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	__weak __typeof(self) weakSelf = self;

	dispatch_async(dispatch_get_main_queue(), ^{
		__strong __typeof(weakSelf) self = weakSelf;
		if (!self) return;

		objc_setAssociatedObject(self, &kStoryInstallPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		if (self.window && !rygOverlayIsInDMContext(self)) {
			((void (*)(id, SEL))objc_msgSend)(self, @selector(rygUpdateStoryOverlayButtons));
		}
	});
}

- (void)didMoveToSuperview {
	%orig;

	if (self.superview && !rygOverlayIsInDMContext(self)) {
		((void (*)(id, SEL))objc_msgSend)(self, @selector(rygUpdateStoryOverlayButtons));
	} else if (rygOverlayIsInDMContext(self)) {
		RYGRemoveAllStoryButtons(self);
	}
}

- (void)prepareForReuse {
	%orig;

	RYGRemoveAllStoryButtons(self);
	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastAudioKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastMediaPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)dealloc {
	RYGRemoveAllStoryButtons(self);
	%orig;
}

%new
- (void)rygUpdateStoryOverlayButtons {
	RYGStoryOverlayPrefs prefs = RYGStoryPrefs();
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygUpdateStoryOverlayButtonsWithPrefs:), prefs);
}

%new
- (void)rygUpdateStoryOverlayButtonsWithPrefs:(RYGStoryOverlayPrefs)prefs {
	if (!self.superview || rygOverlayIsInDMContext(self)) return;

	if (!RYGStoryHasAnyFeature(prefs)) {
		RYGRemoveAllStoryButtons(self);
		return;
	}

	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshStoryActionButtonWithPrefs:), prefs);
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshStoryAudioButtonWithPrefs:), prefs);
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshSeenButtonWithPrefs:), prefs);
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshStoryMentionsButtonWithPrefs:), prefs);
	rygLayoutStoryButtons(self);
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygKickMentionsRetryChainWithPrefs:), prefs);
}

%new
- (void)rygRefreshStoryActionButtonWithPrefs:(RYGStoryOverlayPrefs)prefs {
	RYGChromeButton *button = RYGStoryExistingButton(self, RYG_STORY_ACTION_TAG);

	if (!prefs.action) {
		[button removeFromSuperview];
		return;
	}

	NSString *currentAction = RYGStoryDefaultAction();
	NSString *oldAction = objc_getAssociatedObject(button, &kStoryActionDefaultKey);

	if (button && oldAction && [oldAction isEqualToString:currentAction]) return;

	[button removeFromSuperview];

	button = RYGStoryButton(@"", 18.0, 36.0, RYG_STORY_ACTION_TAG);
	button.translatesAutoresizingMaskIntoConstraints = YES;
	[self addSubview:button];

	[RYGActionIcon attachAutoUpdate:button source:RYGActionSourceStories pointSize:18.0 style:RYGActionIconStylePlain];
	RYGConfigureStoryActionButton(button);

	objc_setAssociatedObject(button, &kStoryActionDefaultKey, currentAction, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

%new
- (void)rygStoryAudioToggleTapped:(RYGChromeButton *)sender {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];

	rygToggleStoryAudio();

	BOOL audioOn = rygIsStoryAudioEnabled();
	sender.symbolName = audioOn ? @"speaker.wave.2" : @"speaker.slash";
	objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)rygRefreshStoryAudioButtonWithPrefs:(RYGStoryOverlayPrefs)prefs {
	RYGChromeButton *button = RYGStoryExistingButton(self, RYG_STORY_AUDIO_TAG);

	if (!prefs.audio) {
		[button removeFromSuperview];
		return;
	}

	BOOL audioOn = rygIsStoryAudioEnabled();
	NSNumber *oldAudio = objc_getAssociatedObject(self, &kStoryLastAudioKey);

	if (button) {
		if (!oldAudio || oldAudio.boolValue != audioOn) {
			button.symbolName = audioOn ? @"speaker.wave.2" : @"speaker.slash";
		}

		objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	rygInitStoryAudioState();

	button = RYGStoryButton(audioOn ? @"speaker.wave.2" : @"speaker.slash", 14.0, 28.0, RYG_STORY_AUDIO_TAG);
	button.translatesAutoresizingMaskIntoConstraints = YES;
	[button addTarget:self action:@selector(rygStoryAudioToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
	rygInstallStoryPlaybackLongPress(button);
	[self addSubview:button];

	objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)rygRefreshSeenButtonWithPrefs:(RYGStoryOverlayPrefs)prefs {
	RYGChromeButton *button = RYGStoryExistingButton(self, RYG_STORY_EYE_TAG);

	if (!prefs.seen) {
		[button removeFromSuperview];
		return;
	}

	NSDictionary *ownerInfo = rygOwnerInfoForView(self);
	NSString *ownerPK = ownerInfo[@"pk"] ?: @"";
	BOOL excluded = ownerPK.length && [RYGExcludedStoryUsers isUserPKExcluded:ownerPK];

	if (excluded) {
		[button removeFromSuperview];
		return;
	}

	NSString *indicator = [RYGUtils getStringPref:@"story_seen_marked_indicator"];
	BOOL marked = ![indicator isEqualToString:@"off"] && [RYGStoryMarkedSeen isMarkedMediaPK:rygCurrentStoryMediaPK(self)];

	if (marked && [indicator isEqualToString:@"hide"]) {
		[button removeFromSuperview];
		return;
	}

	BOOL toggleMode = [[RYGUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"];
	BOOL filled = marked || (toggleMode && rygStorySeenToggleEnabled);
	NSString *symbol = filled ? @"eye.fill" : @"eye";
	UIColor *tint = marked ? UIColor.systemGreenColor : (filled ? RYGUtils.RYGColor_Primary : UIColor.whiteColor);

	if (!button) {
		button = RYGStoryButton(@"", 18.0, 36.0, RYG_STORY_EYE_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;
		[button addTarget:self action:@selector(rygStorySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
		[button addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self]];
		[self addSubview:button];
	}

	[button setIconResource:symbol pointSize:18.0];
	button.iconTint = tint;
}

%new
- (void)rygRefreshStoryMentionsButtonWithPrefs:(RYGStoryOverlayPrefs)prefs {
	RYGChromeButton *button = RYGStoryExistingButton(self, RYG_STORY_MENTIONS_TAG);

	if (!prefs.mentions || !rygStoryHasMentionsOrShares(self)) {
		[button removeFromSuperview];
		return;
	}

	NSInteger count = prefs.mentionsCounter ? rygStoryMentionsCount(self) : 0;

	if (!button) {
		button = RYGStoryButton(@"at", 18.0, 36.0, RYG_STORY_MENTIONS_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;
		[button addTarget:self action:@selector(rygStoryMentionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self addSubview:button];
	}

	rygApplyMentionsCounter(button, count, prefs.mentionsCounter);
}

%new
- (void)rygKickMentionsRetryChainWithPrefs:(RYGStoryOverlayPrefs)prefs {
	if (!prefs.mentions || [self viewWithTag:RYG_STORY_MENTIONS_TAG]) return;

	NSInteger gen = [objc_getAssociatedObject(self, &kStoryMentionsRetryGenKey) integerValue] + 1;
	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	((void (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(self, @selector(rygScheduleMentionsRetryGeneration:remaining:), gen, 4);
}

%new
- (void)rygScheduleMentionsRetryGeneration:(NSInteger)gen remaining:(NSInteger)remaining {
	if (remaining <= 0) return;

	__weak __typeof(self) weakSelf = self;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		__strong __typeof(weakSelf) self = weakSelf;
		if (!self || !self.superview) return;
		if ([objc_getAssociatedObject(self, &kStoryMentionsRetryGenKey) integerValue] != gen) return;

		RYGStoryOverlayPrefs prefs = RYGStoryPrefs();
		((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshStoryMentionsButtonWithPrefs:), prefs);

		if ([self viewWithTag:RYG_STORY_MENTIONS_TAG]) {
			rygLayoutStoryButtons(self);
		} else {
			((void (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(self, @selector(rygScheduleMentionsRetryGeneration:remaining:), gen, remaining - 1);
		}
	});
}

%new
- (void)rygStoryMentionsButtonTapped:(RYGChromeButton *)sender {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];

	UIViewController *storyVC = rygStoryVCForView(self);
	if (!storyVC) return;

	rygPauseStoryPlayback(self);
	rygShowStoryMentions(storyVC, self);
}

- (void)layoutSubviews {
	%orig;

	if (rygOverlayIsInDMContext(self)) {
		RYGRemoveAllStoryButtons(self);
		return;
	}

	rygRegisterLiveStoryOverlay((UIView *)self);

	RYGStoryOverlayPrefs prefs = RYGStoryPrefs();

	if (!RYGStoryHasAnyFeature(prefs)) {
		RYGRemoveAllStoryButtons(self);
		return;
	}

	NSString *mediaPK = rygCurrentStoryMediaPK(self) ?: @"";
	NSString *oldMediaPK = objc_getAssociatedObject(self, &kStoryLastMediaPKKey);
	BOOL mediaChanged = !oldMediaPK || ![oldMediaPK isEqualToString:mediaPK];

	if (mediaChanged) {
		objc_setAssociatedObject(self, &kStoryLastMediaPKKey, mediaPK, OBJC_ASSOCIATION_COPY_NONATOMIC);
		((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygUpdateStoryOverlayButtonsWithPrefs:), prefs);
		return;
	}

	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshStoryActionButtonWithPrefs:), prefs);
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshStoryAudioButtonWithPrefs:), prefs);
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshSeenButtonWithPrefs:), prefs);
	((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshStoryMentionsButtonWithPrefs:), prefs);
	rygLayoutStoryButtons(self);
}

%new
- (void)rygStorySeenButtonTapped:(RYGChromeButton *)sender {
	if ([[RYGUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"]) {
		rygStorySeenToggleEnabled = !rygStorySeenToggleEnabled;

		[sender setIconResource:(rygStorySeenToggleEnabled ? @"eye.fill" : @"eye") pointSize:18.0];
		sender.iconTint = rygStorySeenToggleEnabled ? RYGUtils.RYGColor_Primary : UIColor.whiteColor;

		RYGNotifySuccess(RYG_NOTIF_SEEN_STORY, rygStorySeenToggleEnabled ? RYGLocalized(@"Story read receipts enabled") : RYGLocalized(@"Story read receipts disabled"), nil);
		return;
	}

	((void (*)(id, SEL, id))objc_msgSend)(self, @selector(rygStoryMarkSeenTapped:), sender);
}

%new
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
	__weak __typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		__strong __typeof(weakSelf) self = weakSelf;
		if (!self) return nil;

		NSDictionary *ownerInfo = rygOwnerInfoForView(self);
		NSString *pk = ownerInfo[@"pk"];
		NSString *username = ownerInfo[@"username"] ?: @"";
		NSString *fullName = ownerInfo[@"fullName"] ?: @"";
		BOOL inList = pk.length && [RYGExcludedStoryUsers isInList:pk];
		BOOL blockMode = [RYGExcludedStoryUsers isBlockSelectedMode];

		NSMutableArray<UIMenuElement *> *items = NSMutableArray.array;

		[items addObject:[UIAction actionWithTitle:RYGLocalized(@"Mark seen") image:[RYGIcon imageNamed:@"eye"] identifier:nil handler:^(__unused UIAction *action) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				((void (*)(id, SEL, id))objc_msgSend)(self, @selector(rygStoryMarkSeenTapped:), nil);
			});
		}]];

		if (pk.length) {
			NSString *title = inList ? (blockMode ? RYGLocalized(@"Remove from block list") : RYGLocalized(@"Un-exclude story seen")) : (blockMode ? RYGLocalized(@"Add to block list") : RYGLocalized(@"Exclude story seen"));

			UIAction *exclude = [UIAction actionWithTitle:title image:[RYGIcon imageNamed:(inList ? @"minus.circle" : @"eye.slash")] identifier:nil handler:^(__unused UIAction *action) {
				if (inList) {
					[RYGExcludedStoryUsers removePK:pk];
					RYGNotifySuccess(blockMode ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_STORY, blockMode ? RYGLocalized(@"Unblocked") : RYGLocalized(@"Un-excluded"), nil);
					if (blockMode) rygTriggerStoryMarkSeen(rygActiveStoryViewerVC);
				} else {
					[RYGExcludedStoryUsers addOrUpdateEntry:@{ @"pk": pk, @"username": username, @"fullName": fullName }];
					RYGNotifySuccess(blockMode ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_STORY, blockMode ? RYGLocalized(@"Blocked") : RYGLocalized(@"Excluded"), nil);
					if (!blockMode) rygTriggerStoryMarkSeen(rygActiveStoryViewerVC);
				}

				rygRefreshAllVisibleOverlays(rygActiveStoryViewerVC);
			}];

			if (inList) exclude.attributes = UIMenuElementAttributesDestructive;
			[items addObject:exclude];
		}

		return [UIMenu menuWithTitle:@"" children:items];
	}];
}

%new
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
	rygPauseStoryPlayback(self);
}

%new
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
	__weak __typeof(self) weakSelf = self;

	void (^resume)(void) = ^{
		__strong __typeof(weakSelf) self = weakSelf;
		if (self) rygResumeStoryPlayback(self);
	};

	if (animator) [animator addCompletion:resume];
	else resume();
}

%new
- (void)rygStoryMarkSeenTapped:(UIButton *)sender {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];

	if (sender) {
		[UIView animateWithDuration:0.1 animations:^{
			sender.transform = CGAffineTransformMakeScale(0.8, 0.8);
			sender.alpha = 0.6;
		} completion:^(__unused BOOL finished) {
			[UIView animateWithDuration:0.15 animations:^{
				sender.transform = CGAffineTransformIdentity;
				sender.alpha = 1.0;
			}];
		}];
	}

	UIViewController *presenter = rygStoryVCForView(self);
	BOOL confirmActive = presenter && [RYGUtils getBoolPref:@"confirm_mark_seen_story"];

	__weak __typeof(self) weakSelf = self;
	__weak UIButton *weakSender = sender;

	if (confirmActive) rygPauseStoryPlayback(self);

	rygConfirmStoryMarkSeen(confirmActive ? presenter : nil, ^{
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (strongSelf) {
			((void (*)(id, SEL, id))objc_msgSend)(strongSelf, @selector(rygStoryDoMarkSeen:), weakSender);
		}
	}, ^{
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (strongSelf) rygResumeStoryPlayback(strongSelf);
	});
}

%new
- (void)rygStoryDoMarkSeen:(UIButton *)sender {
	@try {
		UIViewController *storyVC = rygStoryVCForView(self);

		if (!storyVC) {
			[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"VC not found")];
			return;
		}

		id sectionController = rygStorySectionController(storyVC);
		id storyItem = rygCurrentStoryItemFromView(self);

		IGMedia *media = [storyItem isKindOfClass:NSClassFromString(@"IGMedia")] ? storyItem : rygExtractMediaFromItem(storyItem);

		if (!media) {
			[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not find story media")];
			return;
		}

		rygAllowSeenForPK(media);
		rygSeenBypassActive = YES;

		SEL delegateSel = @selector(fullscreenSectionController:didMarkItemAsSeen:);
		if ([storyVC respondsToSelector:delegateSel]) {
			((void (*)(id, SEL, id, id))objc_msgSend)(storyVC, delegateSel, sectionController, media);
		}

		rygSafeCall1(sectionController, NSSelectorFromString(@"markItemAsSeen:"), media);

		id seenManager = rygSafeCall0(storyVC, @selector(viewingSessionSeenStateManager));
		id viewModel = rygSafeCall0(storyVC, @selector(currentViewModel));
		SEL setSeenSel = NSSelectorFromString(@"setSeenMediaId:forReelPK:");

		if (seenManager && viewModel && [seenManager respondsToSelector:setSeenSel]) {
			id mediaPK = rygSafeCall0(media, @selector(pk));
			id reelPK = rygSafeCall0(viewModel, @selector(reelPK));

			if (mediaPK && reelPK) {
				((void (*)(id, SEL, id, id))objc_msgSend)(seenManager, setSeenSel, mediaPK, reelPK);
			}
		}

		rygSeenBypassActive = NO;
		RYGNotifySuccess(RYG_NOTIF_SEEN_STORY, RYGLocalized(@"Story marked as seen"), nil);

		NSString *markedPK = rygPKFromObject(media);
		if (markedPK.length) {
			[RYGStoryMarkedSeen recordMediaPK:markedPK];
			((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(self, @selector(rygRefreshSeenButtonWithPrefs:), RYGStoryPrefs());
			rygLayoutStoryButtons(self);
		}

		if (sender && [RYGUtils getBoolPref:@"advance_on_mark_seen"] && sectionController) {
			__weak __typeof(self) weakSelf = self;
			__block id weakSection = sectionController;

			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				rygAdvanceBypassActive = YES;

				if ([weakSection respondsToSelector:@selector(advanceToNextItemWithNavigationAction:)]) {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(weakSection, @selector(advanceToNextItemWithNavigationAction:), 1);
				}

				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					__strong __typeof(weakSelf) self = weakSelf;
					if (self) rygResumeStoryPlayback(self);
					rygAdvanceBypassActive = NO;
				});
			});
		}
	} @catch (NSException *exception) {
		rygSeenBypassActive = NO;
		rygAdvanceBypassActive = NO;
		[RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:RYGLocalized(@"Error: %@"), exception.reason]];
	}
}

%end

static void rygSyncStoryButtonsAlpha(UIView *sourceView, CGFloat alpha) {
	Class overlayClass = NSClassFromString(@"IGStoryFullscreenOverlayView");
	if (!overlayClass) return;

	NSInteger tags[] = {
		RYG_STORY_EYE_TAG,
		RYG_STORY_ACTION_TAG,
		RYG_STORY_AUDIO_TAG,
		RYG_STORY_MENTIONS_TAG
	};

	for (UIView *current = sourceView; current.superview; current = current.superview) {
		for (UIView *sibling in current.superview.subviews) {
			if (![sibling isKindOfClass:overlayClass]) continue;

			for (NSInteger i = 0; i < 4; i++) {
				[sibling viewWithTag:tags[i]].alpha = alpha;
			}

			return;
		}
	}
}

%hook IGStoryFullscreenHeaderView

- (void)setAlpha:(CGFloat)alpha {
	%orig;
	rygSyncStoryButtonsAlpha((UIView *)self, alpha);
}

%end

static void rygRefreshMentionsInVisibleOverlays(id storyVC) {
	RYGStoryOverlayPrefs prefs = RYGStoryPrefs();

	for (UIView *overlay in rygLiveStoryOverlays().allObjects) {
		if (!overlay.window || rygOverlayIsInDMContext(overlay)) continue;

		if (!prefs.mentions) continue;

		if ([overlay respondsToSelector:@selector(rygRefreshStoryMentionsButtonWithPrefs:)]) {
			((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(overlay, @selector(rygRefreshStoryMentionsButtonWithPrefs:), prefs);
			rygLayoutStoryButtons(overlay);
		}

		if ([overlay respondsToSelector:@selector(rygKickMentionsRetryChainWithPrefs:)]) {
			((void (*)(id, SEL, RYGStoryOverlayPrefs))objc_msgSend)(overlay, @selector(rygKickMentionsRetryChainWithPrefs:), prefs);
		}
	}
}

%hook IGStoryViewerViewController

- (void)fullscreenSectionController:(id)sc didDisplayStoryModel:(id)model {
	%orig;
	rygRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didStartToProgressWithStoryItem:(id)item {
	%orig;
	rygRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didUpdateFromStoryModel:(id)fromModel toStoryModel:(id)toModel storyItem:(id)item {
	%orig;
	rygRefreshMentionsInVisibleOverlays(self);
}

%end

%end

%ctor {
	if (RYGStoryHasAnyFeature(RYGStoryPrefs())) {
		%init(StoryOverlayGroup);
		[[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillShowNotification
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
				rygSetStoryButtonsKbHidden(YES);
			}];
		[[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillHideNotification
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
				rygSetStoryButtonsKbHidden(NO);
			}];
	}
}