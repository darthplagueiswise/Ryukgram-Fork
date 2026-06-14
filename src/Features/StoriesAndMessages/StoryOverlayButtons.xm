// Story overlay buttons — action / audio / eye / mentions.
// Early-exits in DM context; DMOverlayButtons.xm handles that surface.

#import "OverlayHelpers.h"
#import "StoryHelpers.h"
#import "SCIExcludedStoryUsers.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "../../ActionButton/SCIActionButton.h"
#import "../../ActionButton/SCIActionIcon.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../Downloader/Download.h"
#import <objc/runtime.h>
#import <objc/message.h>

extern "C" BOOL sciSeenBypassActive;
extern "C" BOOL sciAdvanceBypassActive;
extern "C" BOOL sciStorySeenToggleEnabled;
extern "C" void sciAllowSeenForPK(id);
extern "C" void sciRefreshAllVisibleOverlays(UIViewController *storyVC);
extern "C" void sciTriggerStoryMarkSeen(UIViewController *storyVC);
extern "C" __weak UIViewController *sciActiveStoryViewerVC;
extern "C" NSDictionary *sciOwnerInfoForView(UIView *view);

static const NSInteger kStoryMentionsCountTag = 13450;
static const CGFloat kStoryBottomBaseOffset = -100.0;
static NSString *const kStoryBottomConstraintID = @"sci_story_bottom";

static char kStoryActionDefaultKey;
static char kStoryReelItemsProviderKey;
static char kStoryMentionsAnchorKey;
static char kStoryMentionsCountKey;
static char kStoryMentionsRetryGenKey;
static char kStoryEyeAnchorKey;
static char kStoryLastPKKey;
static char kStoryLastExcludedKey;
static char kStoryLastAudioKey;
static char kStoryLastMediaPKKey;
static char kStoryInstallPendingKey;

typedef struct {
	BOOL action;
	BOOL audio;
	BOOL seen;
	BOOL mentions;
	BOOL mentionsCounter;
} SCIStoryOverlayPrefs;

static inline SCIStoryOverlayPrefs SCIStoryPrefs(void) {
	SCIStoryOverlayPrefs p;
	p.action = [SCIUtils getBoolPref:@"stories_action_button"];
	p.audio = [SCIUtils getBoolPref:@"story_audio_toggle"];
	p.seen = [SCIUtils getBoolPref:@"no_seen_receipt"] && [SCIUtils getBoolPref:@"show_story_seen_button"];
	p.mentions = [SCIUtils getBoolPref:@"story_mentions_button"];
	p.mentionsCounter = [SCIUtils getBoolPref:@"story_mentions_counter"];
	return p;
}

static void sciConfirmStoryMarkSeen(UIViewController *presenter, void (^onConfirm)(void), void (^onCancel)(void)) {
	[SCIUtils confirmIfNeeded:[SCIUtils getBoolPref:@"confirm_mark_seen_story"]
	                    title:SCILocalized(@"Mark as seen?")
	                  message:SCILocalized(@"This will send a story view receipt.")
	             confirmTitle:SCILocalized(@"Mark seen")
	                     from:presenter
	                onConfirm:onConfirm
	                 onCancel:onCancel];
}

static inline BOOL SCIStoryHasAnyFeature(SCIStoryOverlayPrefs p) {
	return p.action || p.audio || p.seen || p.mentions;
}

static inline NSString *SCIStoryDefaultAction(void) {
	return [SCIUtils getStringPref:@"stories_action_default"] ?: @"";
}

static inline SCIChromeButton *SCIStoryButton(NSString *symbol, CGFloat pointSize, CGFloat diameter, NSInteger tag) {
	SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:diameter];
	button.tag = tag;
	return button;
}

static inline SCIChromeButton *SCIStoryExistingButton(UIView *root, NSInteger tag) {
	id button = [root viewWithTag:tag];
	return [button isKindOfClass:SCIChromeButton.class] ? button : nil;
}

static inline void SCIRemoveStoryButton(UIView *root, NSInteger tag) {
	[[root viewWithTag:tag] removeFromSuperview];
}

static void SCIRemoveAllStoryButtons(UIView *root) {
	SCIRemoveStoryButton(root, SCI_STORY_ACTION_TAG);
	SCIRemoveStoryButton(root, SCI_STORY_EYE_TAG);
	SCIRemoveStoryButton(root, SCI_STORY_AUDIO_TAG);
	SCIRemoveStoryButton(root, SCI_STORY_MENTIONS_TAG);
}

static void SCIActivateBottomTrailing(UIView *host, UIView *button, CGFloat size, CGFloat trailing) {
	NSLayoutConstraint *bottom = [button.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:kStoryBottomBaseOffset];
	bottom.identifier = kStoryBottomConstraintID;

	[NSLayoutConstraint activateConstraints:@[
		bottom,
		[button.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:trailing],
		[button.widthAnchor constraintEqualToConstant:size],
		[button.heightAnchor constraintEqualToConstant:size]
	]];
}

static void SCIActivateBottomLeading(UIView *host, UIView *button, CGFloat size, CGFloat leading) {
	NSLayoutConstraint *bottom = [button.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:kStoryBottomBaseOffset];
	bottom.identifier = kStoryBottomConstraintID;

	[NSLayoutConstraint activateConstraints:@[
		bottom,
		[button.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:leading],
		[button.widthAnchor constraintEqualToConstant:size],
		[button.heightAnchor constraintEqualToConstant:size]
	]];
}

static void SCIActivateLeftOfAnchor(UIView *button, UIView *anchor, CGFloat size) {
	[NSLayoutConstraint activateConstraints:@[
		[button.centerYAnchor constraintEqualToAnchor:anchor.centerYAnchor],
		[button.trailingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:-10.0],
		[button.widthAnchor constraintEqualToConstant:size],
		[button.heightAnchor constraintEqualToConstant:size]
	]];
}

static NSHashTable<UIView *> *sciLiveStoryOverlays(void) {
	static NSHashTable *table;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		table = NSHashTable.weakObjectsHashTable;
	});

	return table;
}

static void sciRegisterLiveStoryOverlay(UIView *overlay) {
	if (overlay.window && !sciOverlayIsInDMContext(overlay)) {
		[sciLiveStoryOverlays() addObject:overlay];
	}
}

static id sciSafeCall0(id target, SEL sel) {
	if (!target || ![target respondsToSelector:sel]) return nil;

	@try {
		return ((id (*)(id, SEL))objc_msgSend)(target, sel);
	} @catch (__unused id e) {
		return nil;
	}
}

static void sciSafeCall1(id target, SEL sel, id arg) {
	if (!target || ![target respondsToSelector:sel]) return;

	@try {
		((void (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
	} @catch (__unused id e) {}
}

static NSString *sciPKFromObject(id obj) {
	id pk = sciSafeCall0(obj, @selector(pk));
	if (!pk) pk = [SCIUtils fieldCacheValue:obj forKey:@"pk"];
	if (!pk) pk = [SCIUtils fieldCacheValue:obj forKey:@"id"];

	if ([pk respondsToSelector:@selector(stringValue)]) return [pk stringValue];
	return [pk isKindOfClass:NSString.class] ? pk : nil;
}

static UIViewController *sciStoryVCForView(UIView *view) {
	UIViewController *vc = sciFindVC(view, @"IGStoryViewerViewController");
	return vc ?: sciActiveStoryViewerVC;
}

static id sciStorySectionController(UIViewController *storyVC) {
	return sciSafeCall0(storyVC, @selector(currentlyDisplayedSectionController));
}

static id sciOverlayMedia(UIView *view) {
	id media = [SCIUtils getIvarForObj:view name:"_media"];
	Class cls = NSClassFromString(@"IGMedia");
	return (cls && [media isKindOfClass:cls]) ? media : nil;
}

static id sciStoryItemFromContextProvider(id provider) {
	id ctx = sciSafeCall0(provider, @selector(currentStoryItemContext));
	if (!ctx) ctx = sciSafeCall0(provider, @selector(_currentStoryItemContext));

	id item = sciSafeCall0(ctx, @selector(storyItem));
	return item ?: ctx;
}

static id sciCurrentStoryItemFromView(UIResponder *sourceView) {
	UIViewController *storyVC = sciFindVC(sourceView, @"IGStoryViewerViewController");
	storyVC = storyVC ?: sciActiveStoryViewerVC;
	if (!storyVC) return nil;

	id item = sciStoryItemFromContextProvider(sourceView);
	if (item) return item;

	item = sciSafeCall0(storyVC, @selector(currentStoryItem));
	if (item) return item;

	id section = sciStorySectionController(storyVC);
	item = sciSafeCall0(section, @selector(currentStoryItem));
	if (item) return item;

	id vm = sciSafeCall0(storyVC, @selector(currentViewModel));
	return sciSafeCall0(vm, @selector(currentStoryItem)) ?: sciCall1(storyVC, @selector(currentStoryItemForViewModel:), vm);
}

static id sciCurrentStoryMedia(UIView *sourceView) {
	id media = sciOverlayMedia(sourceView);
	if (media) return media;

	id item = sciCurrentStoryItemFromView(sourceView);

	if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return item;
	return sciExtractMediaFromItem(item) ?: (id)kCFNull;
}

static NSString *sciCurrentStoryMediaPK(UIView *sourceView) {
	id media = sciOverlayMedia(sourceView);
	if (media) return sciPKFromObject(media);

	media = sciCurrentStoryMedia(sourceView);
	return media && media != (id)kCFNull ? sciPKFromObject(media) : nil;
}

static NSArray *sciStoryReelItemsForSource(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	id vm = sciSafeCall0(storyVC, @selector(currentViewModel));
	id items = sciSafeCall0(vm, @selector(items));
	return ([items isKindOfClass:NSArray.class] && [(NSArray *)items count] > 1) ? items : nil;
}

static void sciPauseStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	id section = sciStorySectionController(storyVC);

	if ([section respondsToSelector:@selector(pauseWithReason:)]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(section, @selector(pauseWithReason:), 10);
		return;
	}

	if ([storyVC respondsToSelector:@selector(pauseWithReason:)]) {
		((void (*)(id, SEL, NSInteger))objc_msgSend)(storyVC, @selector(pauseWithReason:), 10);
	}
}

static void sciResumeStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	id section = sciStorySectionController(storyVC);

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
static BOOL sciAnyContextMenuVisible(void) {
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

static void sciWatchForMenuDismiss(void (^onDismiss)(void)) {
	if (!onDismiss) return;

	__block BOOL appeared = NO;
	__block NSInteger ticks = 0;

	[NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *t) {
		BOOL visible = sciAnyContextMenuVisible();
		if (visible) appeared = YES;

		if ((appeared && !visible) || (!appeared && ++ticks > 120)) {
			[t invalidate];
			onDismiss();
		}
	}];
}

static void SCIConfigureStoryActionButton(SCIChromeButton *button) {
	if (!button) return;

	__weak UIButton *weakBtn = button;

	SCIActionMediaProvider provider = ^id (UIView *sourceView) {
		sciPauseStoryPlayback(sourceView);

		sciWatchForMenuDismiss(^{
			UIButton *b = weakBtn;
			if (b) sciResumeStoryPlayback(b);
		});

		id media = sciCurrentStoryMedia(sourceView);
		return media == (id)kCFNull ? nil : media;
	};

	[SCIActionButton configureButton:button context:SCIActionContextStories prefKey:@"stories_action_default" mediaProvider:provider];

	objc_setAssociatedObject(button, &kStoryReelItemsProviderKey, ^NSArray *(UIView *sourceView) {
		return sciStoryReelItemsForSource(sourceView);
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);

	__weak SCIChromeButton *weakButton = button;

	objc_setAssociatedObject(button, kSCIDismissKey, ^{
		SCIChromeButton *strongButton = weakButton;
		if (strongButton) sciResumeStoryPlayback(strongButton);
	}, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void sciApplyMentionsCounter(SCIChromeButton *button, NSInteger count, BOOL enabled) {
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

// Music attribution/highlight buttons can overlap our custom bottom-right column.
// Prefer scanning known overlay/header/footer roots instead of the whole story VC tree.
static CGFloat sciStoryMusicClearance(UIView *overlay) {
	CGFloat OW = overlay.bounds.size.width;
	CGFloat H = overlay.bounds.size.height;
	if (OW <= 0 || H <= 0) return 0;

	static Class tapCls;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		tapCls = NSClassFromString(@"IGTapButton");
	});

	if (!tapCls) return 0;

	UIViewController *storyVC = sciStoryVCForView(overlay);
	UIView *root = storyVC.view ?: overlay.window ?: overlay;

	CGFloat safeBottom = H - overlay.safeAreaInsets.bottom;
	CGFloat ourBottomEdgeY = safeBottom + kStoryBottomBaseOffset;
	CGRect zone = CGRectMake(OW - 220.0, ourBottomEdgeY - 44.0, 220.0, 60.0);
	const CGFloat pad = 10.0;

	CGFloat clearance = 0;
	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];

	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];

		for (UIView *s in v.subviews) {
			[stack addObject:s];
		}

		if (![v isKindOfClass:tapCls] || v.hidden || v.alpha < 0.01 || !v.window) continue;
		if (v.bounds.size.width > 120.0 || v.bounds.size.height > 120.0) continue;

		CGRect f = [v convertRect:v.bounds toView:overlay];
		if (!CGRectIntersectsRect(f, zone)) continue;

		CGFloat need = ourBottomEdgeY - (CGRectGetMinY(f) - pad);
		if (need > clearance) clearance = need;
	}

	return clearance;
}

%group StoryOverlayGroup

%hook IGStoryFullscreenOverlayView

- (void)didMoveToWindow {
	%orig;

	if (!self.window) return;

	if (sciOverlayIsInDMContext(self)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	sciRegisterLiveStoryOverlay((UIView *)self);

	if ([objc_getAssociatedObject(self, &kStoryInstallPendingKey) boolValue]) return;
	objc_setAssociatedObject(self, &kStoryInstallPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	__weak __typeof(self) weakSelf = self;

	dispatch_async(dispatch_get_main_queue(), ^{
		__strong __typeof(weakSelf) self = weakSelf;
		if (!self) return;

		objc_setAssociatedObject(self, &kStoryInstallPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		if (self.window && !sciOverlayIsInDMContext(self)) {
			((void (*)(id, SEL))objc_msgSend)(self, @selector(sciUpdateStoryOverlayButtons));
		}
	});
}

- (void)didMoveToSuperview {
	%orig;

	if (self.superview && !sciOverlayIsInDMContext(self)) {
		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciUpdateStoryOverlayButtons));
	} else if (sciOverlayIsInDMContext(self)) {
		SCIRemoveAllStoryButtons(self);
	}
}

- (void)prepareForReuse {
	%orig;

	SCIRemoveAllStoryButtons(self);
	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryEyeAnchorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastExcludedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastAudioKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastMediaPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)dealloc {
	SCIRemoveAllStoryButtons(self);
	%orig;
}

%new
- (void)sciUpdateStoryOverlayButtons {
	SCIStoryOverlayPrefs prefs = SCIStoryPrefs();
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciUpdateStoryOverlayButtonsWithPrefs:), prefs);
}

%new
- (void)sciUpdateStoryOverlayButtonsWithPrefs:(SCIStoryOverlayPrefs)prefs {
	if (!self.superview || sciOverlayIsInDMContext(self)) return;

	if (!SCIStoryHasAnyFeature(prefs)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshStoryActionButtonWithPrefs:), prefs);
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshStoryAudioButtonWithPrefs:), prefs);
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshSeenButtonWithPrefs:), prefs);
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButtonWithPrefs:), prefs);
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciKickMentionsRetryChainWithPrefs:), prefs);
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciApplyMusicButtonClearance));
}

%new
- (void)sciApplyMusicButtonClearance {
	NSMutableArray<NSLayoutConstraint *> *bottoms = nil;

	for (NSLayoutConstraint *c in self.constraints) {
		if (![c.identifier isEqualToString:kStoryBottomConstraintID]) continue;
		if (!bottoms) bottoms = NSMutableArray.array;
		[bottoms addObject:c];
	}

	if (!bottoms.count) return;

	CGFloat offset = kStoryBottomBaseOffset - sciStoryMusicClearance(self);

	for (NSLayoutConstraint *c in bottoms) {
		if (c.constant != offset) c.constant = offset;
	}
}

%new
- (void)sciRefreshStoryActionButtonWithPrefs:(SCIStoryOverlayPrefs)prefs {
	SCIChromeButton *button = SCIStoryExistingButton(self, SCI_STORY_ACTION_TAG);

	if (!prefs.action) {
		[button removeFromSuperview];
		return;
	}

	NSString *currentAction = SCIStoryDefaultAction();
	NSString *oldAction = objc_getAssociatedObject(button, &kStoryActionDefaultKey);

	if (button && oldAction && [oldAction isEqualToString:currentAction]) return;

	[button removeFromSuperview];

	button = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_ACTION_TAG);
	[self addSubview:button];

	SCIActivateBottomTrailing(self, button, 36.0, -12.0);
	[SCIActionIcon attachAutoUpdate:button source:SCIActionSourceStories pointSize:18.0 style:SCIActionIconStylePlain];
	SCIConfigureStoryActionButton(button);

	objc_setAssociatedObject(button, &kStoryActionDefaultKey, currentAction, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryEyeAnchorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciStoryAudioToggleTapped:(SCIChromeButton *)sender {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];

	sciToggleStoryAudio();

	BOOL audioOn = sciIsStoryAudioEnabled();
	sender.symbolName = audioOn ? @"speaker.wave.2" : @"speaker.slash";
	objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciRefreshStoryAudioButtonWithPrefs:(SCIStoryOverlayPrefs)prefs {
	SCIChromeButton *button = SCIStoryExistingButton(self, SCI_STORY_AUDIO_TAG);

	if (!prefs.audio) {
		[button removeFromSuperview];
		return;
	}

	BOOL audioOn = sciIsStoryAudioEnabled();
	NSNumber *oldAudio = objc_getAssociatedObject(self, &kStoryLastAudioKey);

	if (button) {
		if (!oldAudio || oldAudio.boolValue != audioOn) {
			button.symbolName = audioOn ? @"speaker.wave.2" : @"speaker.slash";
		}

		objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	sciInitStoryAudioState();

	button = SCIStoryButton(audioOn ? @"speaker.wave.2" : @"speaker.slash", 14.0, 28.0, SCI_STORY_AUDIO_TAG);
	[button addTarget:self action:@selector(sciStoryAudioToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:button];

	SCIActivateBottomLeading(self, button, 28.0, 12.0);
	objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciRefreshSeenButtonWithPrefs:(SCIStoryOverlayPrefs)prefs {
	SCIChromeButton *button = SCIStoryExistingButton(self, SCI_STORY_EYE_TAG);

	if (!prefs.seen) {
		[button removeFromSuperview];
		objc_setAssociatedObject(self, &kStoryEyeAnchorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	NSDictionary *ownerInfo = sciOwnerInfoForView(self);
	NSString *ownerPK = ownerInfo[@"pk"] ?: @"";
	BOOL excluded = ownerPK.length && [SCIExcludedStoryUsers isUserPKExcluded:ownerPK];

	NSString *oldPK = objc_getAssociatedObject(self, &kStoryLastPKKey);
	NSNumber *oldExcluded = objc_getAssociatedObject(self, &kStoryLastExcludedKey);
	BOOL hasAction = [self viewWithTag:SCI_STORY_ACTION_TAG] != nil;
	NSNumber *oldAnchor = objc_getAssociatedObject(self, &kStoryEyeAnchorKey);

	BOOL sameOwner = oldPK && [oldPK isEqualToString:ownerPK] && oldExcluded && oldExcluded.boolValue == excluded;
	BOOL sameAnchor = oldAnchor && oldAnchor.boolValue == hasAction;

	if (button && sameOwner && sameAnchor) return;

	objc_setAssociatedObject(self, &kStoryLastPKKey, ownerPK, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastExcludedKey, @(excluded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryEyeAnchorKey, @(hasAction), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (excluded) {
		[button removeFromSuperview];
		return;
	}

	BOOL toggleMode = [[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"];
	NSString *symbol = (toggleMode && sciStorySeenToggleEnabled) ? @"eye.fill" : @"eye";
	UIColor *tint = (toggleMode && sciStorySeenToggleEnabled) ? SCIUtils.SCIColor_Primary : UIColor.whiteColor;

	if (!button || !sameAnchor) {
		[button removeFromSuperview];

		button = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_EYE_TAG);
		[button addTarget:self action:@selector(sciStorySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
		[button addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self]];
		[self addSubview:button];

		UIView *action = [self viewWithTag:SCI_STORY_ACTION_TAG];
		if (action) SCIActivateLeftOfAnchor(button, action, 36.0);
		else SCIActivateBottomTrailing(self, button, 36.0, -12.0);

		SCIChromeButton *mentions = SCIStoryExistingButton(self, SCI_STORY_MENTIONS_TAG);
		objc_setAssociatedObject(mentions, &kStoryMentionsAnchorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	[button setIconResource:symbol pointSize:18.0];
	button.iconTint = tint;
}

%new
- (void)sciRefreshStoryMentionsButtonWithPrefs:(SCIStoryOverlayPrefs)prefs {
	SCIChromeButton *button = SCIStoryExistingButton(self, SCI_STORY_MENTIONS_TAG);

	if (!prefs.mentions || !sciStoryHasMentionsOrShares(self)) {
		[button removeFromSuperview];
		return;
	}

	UIView *eye = [self viewWithTag:SCI_STORY_EYE_TAG];
	UIView *action = [self viewWithTag:SCI_STORY_ACTION_TAG];
	UIView *anchor = eye ?: action;

	NSInteger anchorState = (eye ? 1 : 0) | (action ? 2 : 0);
	NSInteger count = prefs.mentionsCounter ? sciStoryMentionsCount(self) : 0;

	NSNumber *oldAnchor = objc_getAssociatedObject(button, &kStoryMentionsAnchorKey);
	NSNumber *oldCount = objc_getAssociatedObject(button, &kStoryMentionsCountKey);

	if (button && oldAnchor && oldAnchor.integerValue == anchorState) {
		if (!oldCount || oldCount.integerValue != count) {
			sciApplyMentionsCounter(button, count, prefs.mentionsCounter);
		}
		return;
	}

	[button removeFromSuperview];

	button = SCIStoryButton(@"at", 18.0, 36.0, SCI_STORY_MENTIONS_TAG);
	[button addTarget:self action:@selector(sciStoryMentionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:button];

	if (anchor) SCIActivateLeftOfAnchor(button, anchor, 36.0);
	else SCIActivateBottomTrailing(self, button, 36.0, -12.0);

	objc_setAssociatedObject(button, &kStoryMentionsAnchorKey, @(anchorState), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	sciApplyMentionsCounter(button, count, prefs.mentionsCounter);
}

%new
- (void)sciKickMentionsRetryChainWithPrefs:(SCIStoryOverlayPrefs)prefs {
	if (!prefs.mentions || [self viewWithTag:SCI_STORY_MENTIONS_TAG]) return;

	NSInteger gen = [objc_getAssociatedObject(self, &kStoryMentionsRetryGenKey) integerValue] + 1;
	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	((void (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(self, @selector(sciScheduleMentionsRetryGeneration:remaining:), gen, 4);
}

%new
- (void)sciScheduleMentionsRetryGeneration:(NSInteger)gen remaining:(NSInteger)remaining {
	if (remaining <= 0) return;

	__weak __typeof(self) weakSelf = self;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		__strong __typeof(weakSelf) self = weakSelf;
		if (!self || !self.superview) return;
		if ([objc_getAssociatedObject(self, &kStoryMentionsRetryGenKey) integerValue] != gen) return;

		SCIStoryOverlayPrefs prefs = SCIStoryPrefs();
		((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButtonWithPrefs:), prefs);

		if (![self viewWithTag:SCI_STORY_MENTIONS_TAG]) {
			((void (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(self, @selector(sciScheduleMentionsRetryGeneration:remaining:), gen, remaining - 1);
		}
	});
}

%new
- (void)sciStoryMentionsButtonTapped:(SCIChromeButton *)sender {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];

	UIViewController *storyVC = sciStoryVCForView(self);
	if (!storyVC) return;

	sciPauseStoryPlayback(self);
	sciShowStoryMentions(storyVC, self);
}

- (void)layoutSubviews {
	%orig;

	if (sciOverlayIsInDMContext(self)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	sciRegisterLiveStoryOverlay((UIView *)self);

	SCIStoryOverlayPrefs prefs = SCIStoryPrefs();

	if (!SCIStoryHasAnyFeature(prefs)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	NSString *mediaPK = sciCurrentStoryMediaPK(self) ?: @"";
	NSString *oldMediaPK = objc_getAssociatedObject(self, &kStoryLastMediaPKKey);
	BOOL mediaChanged = !oldMediaPK || ![oldMediaPK isEqualToString:mediaPK];

	if (mediaChanged) {
		objc_setAssociatedObject(self, &kStoryLastMediaPKKey, mediaPK, OBJC_ASSOCIATION_COPY_NONATOMIC);
		objc_setAssociatedObject(self, &kStoryEyeAnchorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(self, &kStoryLastPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
		objc_setAssociatedObject(self, &kStoryLastExcludedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciUpdateStoryOverlayButtonsWithPrefs:), prefs);
		return;
	}

	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshStoryActionButtonWithPrefs:), prefs);
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshStoryAudioButtonWithPrefs:), prefs);
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshSeenButtonWithPrefs:), prefs);
	((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButtonWithPrefs:), prefs);
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciApplyMusicButtonClearance));
}

%new
- (void)sciStorySeenButtonTapped:(SCIChromeButton *)sender {
	if ([[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"]) {
		sciStorySeenToggleEnabled = !sciStorySeenToggleEnabled;

		[sender setIconResource:(sciStorySeenToggleEnabled ? @"eye.fill" : @"eye") pointSize:18.0];
		sender.iconTint = sciStorySeenToggleEnabled ? SCIUtils.SCIColor_Primary : UIColor.whiteColor;

		SCINotifySuccess(SCI_NOTIF_SEEN_STORY, sciStorySeenToggleEnabled ? SCILocalized(@"Story read receipts enabled") : SCILocalized(@"Story read receipts disabled"), nil);
		return;
	}

	((void (*)(id, SEL, id))objc_msgSend)(self, @selector(sciStoryMarkSeenTapped:), sender);
}

%new
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
	__weak __typeof(self) weakSelf = self;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
		__strong __typeof(weakSelf) self = weakSelf;
		if (!self) return nil;

		NSDictionary *ownerInfo = sciOwnerInfoForView(self);
		NSString *pk = ownerInfo[@"pk"];
		NSString *username = ownerInfo[@"username"] ?: @"";
		NSString *fullName = ownerInfo[@"fullName"] ?: @"";
		BOOL inList = pk.length && [SCIExcludedStoryUsers isInList:pk];
		BOOL blockMode = [SCIExcludedStoryUsers isBlockSelectedMode];

		NSMutableArray<UIMenuElement *> *items = NSMutableArray.array;

		[items addObject:[UIAction actionWithTitle:SCILocalized(@"Mark seen") image:[SCIIcon imageNamed:@"eye"] identifier:nil handler:^(__unused UIAction *action) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				((void (*)(id, SEL, id))objc_msgSend)(self, @selector(sciStoryMarkSeenTapped:), nil);
			});
		}]];

		if (pk.length) {
			NSString *title = inList ? (blockMode ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude story seen")) : (blockMode ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude story seen"));

			UIAction *exclude = [UIAction actionWithTitle:title image:[SCIIcon imageNamed:(inList ? @"minus.circle" : @"eye.slash")] identifier:nil handler:^(__unused UIAction *action) {
				if (inList) {
					[SCIExcludedStoryUsers removePK:pk];
					SCINotifySuccess(blockMode ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY, blockMode ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded"), nil);
					if (blockMode) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
				} else {
					[SCIExcludedStoryUsers addOrUpdateEntry:@{ @"pk": pk, @"username": username, @"fullName": fullName }];
					SCINotifySuccess(blockMode ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY, blockMode ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded"), nil);
					if (!blockMode) sciTriggerStoryMarkSeen(sciActiveStoryViewerVC);
				}

				sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
			}];

			if (inList) exclude.attributes = UIMenuElementAttributesDestructive;
			[items addObject:exclude];
		}

		return [UIMenu menuWithTitle:@"" children:items];
	}];
}

%new
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
	sciPauseStoryPlayback(self);
}

%new
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
	__weak __typeof(self) weakSelf = self;

	void (^resume)(void) = ^{
		__strong __typeof(weakSelf) self = weakSelf;
		if (self) sciResumeStoryPlayback(self);
	};

	if (animator) [animator addCompletion:resume];
	else resume();
}

%new
- (void)sciStoryMarkSeenTapped:(UIButton *)sender {
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

	UIViewController *presenter = sciStoryVCForView(self);
	BOOL confirmActive = presenter && [SCIUtils getBoolPref:@"confirm_mark_seen_story"];

	__weak __typeof(self) weakSelf = self;
	__weak UIButton *weakSender = sender;

	if (confirmActive) sciPauseStoryPlayback(self);

	sciConfirmStoryMarkSeen(confirmActive ? presenter : nil, ^{
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (strongSelf) {
			((void (*)(id, SEL, id))objc_msgSend)(strongSelf, @selector(sciStoryDoMarkSeen:), weakSender);
		}
	}, ^{
		__strong __typeof(weakSelf) strongSelf = weakSelf;
		if (strongSelf) sciResumeStoryPlayback(strongSelf);
	});
}

%new
- (void)sciStoryDoMarkSeen:(UIButton *)sender {
	@try {
		UIViewController *storyVC = sciStoryVCForView(self);

		if (!storyVC) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"VC not found")];
			return;
		}

		id sectionController = sciStorySectionController(storyVC);
		id storyItem = sciCurrentStoryItemFromView(self);

		IGMedia *media = [storyItem isKindOfClass:NSClassFromString(@"IGMedia")] ? storyItem : sciExtractMediaFromItem(storyItem);

		if (!media) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find story media")];
			return;
		}

		sciAllowSeenForPK(media);
		sciSeenBypassActive = YES;

		SEL delegateSel = @selector(fullscreenSectionController:didMarkItemAsSeen:);
		if ([storyVC respondsToSelector:delegateSel]) {
			((void (*)(id, SEL, id, id))objc_msgSend)(storyVC, delegateSel, sectionController, media);
		}

		sciSafeCall1(sectionController, NSSelectorFromString(@"markItemAsSeen:"), media);

		id seenManager = sciSafeCall0(storyVC, @selector(viewingSessionSeenStateManager));
		id viewModel = sciSafeCall0(storyVC, @selector(currentViewModel));
		SEL setSeenSel = NSSelectorFromString(@"setSeenMediaId:forReelPK:");

		if (seenManager && viewModel && [seenManager respondsToSelector:setSeenSel]) {
			id mediaPK = sciSafeCall0(media, @selector(pk));
			id reelPK = sciSafeCall0(viewModel, @selector(reelPK));

			if (mediaPK && reelPK) {
				((void (*)(id, SEL, id, id))objc_msgSend)(seenManager, setSeenSel, mediaPK, reelPK);
			}
		}

		sciSeenBypassActive = NO;
		SCINotifySuccess(SCI_NOTIF_SEEN_STORY, SCILocalized(@"Story marked as seen"), nil);

		if (sender && [SCIUtils getBoolPref:@"advance_on_mark_seen"] && sectionController) {
			__weak __typeof(self) weakSelf = self;
			__block id weakSection = sectionController;

			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				sciAdvanceBypassActive = YES;

				if ([weakSection respondsToSelector:@selector(advanceToNextItemWithNavigationAction:)]) {
					((void (*)(id, SEL, NSInteger))objc_msgSend)(weakSection, @selector(advanceToNextItemWithNavigationAction:), 1);
				}

				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					__strong __typeof(weakSelf) self = weakSelf;
					if (self) sciResumeStoryPlayback(self);
					sciAdvanceBypassActive = NO;
				});
			});
		}
	} @catch (NSException *exception) {
		sciSeenBypassActive = NO;
		sciAdvanceBypassActive = NO;
		[SCIUtils showErrorHUDWithDescription:[NSString stringWithFormat:SCILocalized(@"Error: %@"), exception.reason]];
	}
}

%end

static void sciSyncStoryButtonsAlpha(UIView *sourceView, CGFloat alpha) {
	Class overlayClass = NSClassFromString(@"IGStoryFullscreenOverlayView");
	if (!overlayClass) return;

	NSInteger tags[] = {
		SCI_STORY_EYE_TAG,
		SCI_STORY_ACTION_TAG,
		SCI_STORY_AUDIO_TAG,
		SCI_STORY_MENTIONS_TAG
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
	sciSyncStoryButtonsAlpha((UIView *)self, alpha);
}

%end

static void sciRefreshMentionsInVisibleOverlays(id storyVC) {
	SCIStoryOverlayPrefs prefs = SCIStoryPrefs();

	for (UIView *overlay in sciLiveStoryOverlays().allObjects) {
		if (!overlay.window || sciOverlayIsInDMContext(overlay)) continue;

		if ([overlay respondsToSelector:@selector(sciApplyMusicButtonClearance)]) {
			((void (*)(id, SEL))objc_msgSend)(overlay, @selector(sciApplyMusicButtonClearance));
		}

		if (!prefs.mentions) continue;

		if ([overlay respondsToSelector:@selector(sciRefreshStoryMentionsButtonWithPrefs:)]) {
			((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(overlay, @selector(sciRefreshStoryMentionsButtonWithPrefs:), prefs);
		}

		if ([overlay respondsToSelector:@selector(sciKickMentionsRetryChainWithPrefs:)]) {
			((void (*)(id, SEL, SCIStoryOverlayPrefs))objc_msgSend)(overlay, @selector(sciKickMentionsRetryChainWithPrefs:), prefs);
		}
	}
}

%hook IGStoryViewerViewController

- (void)fullscreenSectionController:(id)sc didDisplayStoryModel:(id)model {
	%orig;
	sciRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didStartToProgressWithStoryItem:(id)item {
	%orig;
	sciRefreshMentionsInVisibleOverlays(self);
}

- (void)fullscreenSectionController:(id)sc didUpdateFromStoryModel:(id)fromModel toStoryModel:(id)toModel storyItem:(id)item {
	%orig;
	sciRefreshMentionsInVisibleOverlays(self);
}

%end

%end

%ctor {
	if (SCIStoryHasAnyFeature(SCIStoryPrefs())) {
		%init(StoryOverlayGroup);
	}
}
