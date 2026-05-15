// Story overlay buttons — action / audio / eye / mentions.
// Early-exits in DM context; DMOverlayButtons.xm handles that surface.

#import "OverlayHelpers.h"
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

static char kStoryActionDefaultKey;
static char kStoryReelItemsProviderKey;
static char kStoryMentionsAnchorKey;
static char kStoryMentionsCountKey;
static char kStoryMentionsRetryGenKey;
static char kStoryLastPKKey;
static char kStoryLastExcludedKey;
static char kStoryLastAudioKey;
static char kStoryLastMentionsKey;
static char kStoryLastMediaPKKey;
static char kStoryInstallPendingKey;

static inline BOOL SCIStoryActionEnabled(void) { return [SCIUtils getBoolPref:@"stories_action_button"]; }
static inline NSString *SCIStoryDefaultAction(void) { return [SCIUtils getStringPref:@"stories_action_default"] ?: @""; }

static inline SCIChromeButton *SCIStoryButton(NSString *symbol, CGFloat pointSize, CGFloat diameter, NSInteger tag) {
	SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:diameter];
	button.tag = tag;
	return button;
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

static NSHashTable<UIView *> *sciLiveStoryOverlays(void) {
	static NSHashTable *table;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ table = NSHashTable.weakObjectsHashTable; });
	return table;
}

static void sciRegisterLiveStoryOverlay(UIView *overlay) {
	if (overlay.window && !sciOverlayIsInDMContext(overlay)) [sciLiveStoryOverlays() addObject:overlay];
}

static id sciSafeCall0(id target, SEL sel) {
	if (!target || ![target respondsToSelector:sel]) return nil;
	@try { return ((id (*)(id, SEL))objc_msgSend)(target, sel); }
	@catch (__unused id e) { return nil; }
}

static void sciSafeCall1(id target, SEL sel, id arg) {
	if (!target || ![target respondsToSelector:sel]) return;
	@try { ((void (*)(id, SEL, id))objc_msgSend)(target, sel, arg); }
	@catch (__unused id e) {}
}

static NSString *sciPKFromObject(id obj) {
	id pk = sciSafeCall0(obj, @selector(pk));
	if (!pk) pk = [SCIUtils fieldCacheValue:obj forKey:@"pk"];
	if (!pk) pk = [SCIUtils fieldCacheValue:obj forKey:@"id"];
	return [pk respondsToSelector:@selector(stringValue)] ? [pk stringValue] : ([pk isKindOfClass:NSString.class] ? pk : nil);
}

static UIViewController *sciStoryVCForView(UIView *view) {
	UIViewController *vc = sciFindVC(view, @"IGStoryViewerViewController");
	return vc ?: sciActiveStoryViewerVC;
}

static id sciStorySectionController(UIViewController *storyVC) {
	id sc = sciSafeCall0(storyVC, @selector(currentlyDisplayedSectionController));
	return sc ?: sciFindSectionController(storyVC);
}

static id sciCurrentStoryItemFromVC(UIViewController *storyVC) {
	id item = sciSafeCall0(storyVC, @selector(currentStoryItem));
	if (item) return item;
	id sc = sciStorySectionController(storyVC);
	return sciSafeCall0(sc, @selector(currentStoryItem));
}

static id sciCurrentStoryMedia(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	id item = sciCurrentStoryItemFromVC(storyVC);
	if (!item) item = sciGetCurrentStoryItem(sourceView);
	if ([item isKindOfClass:NSClassFromString(@"IGMedia")]) return item;
	return sciExtractMediaFromItem(item) ?: (id)kCFNull;
}

static NSString *sciCurrentStoryMediaPK(UIView *sourceView) {
	id media = sciCurrentStoryMedia(sourceView);
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
	if ([storyVC respondsToSelector:@selector(pauseWithReason:)])
		((void (*)(id, SEL, NSInteger))objc_msgSend)(storyVC, @selector(pauseWithReason:), 10);
}

static void sciResumeStoryPlayback(UIView *sourceView) {
	UIViewController *storyVC = sciStoryVCForView(sourceView);
	if ([storyVC respondsToSelector:@selector(tryResumePlayback)])
		((void (*)(id, SEL))objc_msgSend)(storyVC, @selector(tryResumePlayback));
}

static void SCIConfigureStoryActionButton(SCIChromeButton *button) {
	if (!button) return;

	SCIActionMediaProvider provider = ^id (UIView *sourceView) {
		sciPauseStoryPlayback(sourceView);
		return sciCurrentStoryMedia(sourceView);
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

static void sciApplyMentionsCounter(SCIChromeButton *button, NSInteger count) {
	if (!button) return;

	UILabel *label = (UILabel *)[button viewWithTag:kStoryMentionsCountTag];
	if (![SCIUtils getBoolPref:@"story_mentions_counter"] || count <= 0) {
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
		[button addSubview:label];

		[NSLayoutConstraint activateConstraints:@[
			[label.topAnchor constraintEqualToAnchor:button.topAnchor constant:-3.0],
			[label.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:3.0],
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

	if (sciOverlayIsInDMContext(self)) {
		SCIRemoveAllStoryButtons(self);
		return;
	}

	sciRegisterLiveStoryOverlay((UIView *)self);

	if ([objc_getAssociatedObject(self, &kStoryInstallPendingKey) boolValue]) return;
	objc_setAssociatedObject(self, &kStoryInstallPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	dispatch_async(dispatch_get_main_queue(), ^{
		objc_setAssociatedObject(self, &kStoryInstallPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		if (self.window && !sciOverlayIsInDMContext(self))
			((void (*)(id, SEL))objc_msgSend)(self, @selector(sciUpdateStoryOverlayButtons));
	});
}

- (void)didMoveToSuperview {
	%orig;
	if (self.superview && !sciOverlayIsInDMContext(self))
		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciUpdateStoryOverlayButtons));
	else if (sciOverlayIsInDMContext(self))
		SCIRemoveAllStoryButtons(self);
}

- (void)prepareForReuse {
	%orig;
	SCIRemoveAllStoryButtons(self);
	objc_setAssociatedObject(self, &kStoryMentionsRetryGenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastExcludedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastAudioKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastMentionsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastMediaPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)dealloc {
	SCIRemoveAllStoryButtons(self);
	%orig;
}

%new
- (void)sciUpdateStoryOverlayButtons {
	if (!self.superview || sciOverlayIsInDMContext(self)) return;

	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryActionButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryAudioButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciKickMentionsRetryChain));
}

%new
- (void)sciRefreshStoryActionButton {
	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_ACTION_TAG];

	if (!SCIStoryActionEnabled()) {
		SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG);
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
		SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG);
		return;
	}

	NSString *currentAction = SCIStoryDefaultAction();
	NSString *oldAction = objc_getAssociatedObject(button, &kStoryActionDefaultKey);

	if ([button isKindOfClass:SCIChromeButton.class] && oldAction && [oldAction isEqualToString:currentAction]) return;

	SCIRemoveStoryButton(self, SCI_STORY_ACTION_TAG);
	SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
	SCIRemoveStoryButton(self, SCI_STORY_MENTIONS_TAG);

	button = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_ACTION_TAG);
	[self addSubview:button];

	[NSLayoutConstraint activateConstraints:@[
		[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
		[button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
		[button.widthAnchor constraintEqualToConstant:36.0],
		[button.heightAnchor constraintEqualToConstant:36.0]
	]];

	[SCIActionIcon attachAutoUpdate:button pointSize:18.0 style:SCIActionIconStylePlain];
	SCIConfigureStoryActionButton(button);
	objc_setAssociatedObject(button, &kStoryActionDefaultKey, currentAction, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

%new
- (void)sciStoryAudioToggleTapped:(SCIChromeButton *)sender {
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	sciToggleStoryAudio();
	sender.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
	objc_setAssociatedObject(self, &kStoryLastAudioKey, @(sciIsStoryAudioEnabled()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciRefreshStoryAudioButton {
	if (![SCIUtils getBoolPref:@"story_audio_toggle"]) {
		SCIRemoveStoryButton(self, SCI_STORY_AUDIO_TAG);
		return;
	}

	BOOL audioOn = sciIsStoryAudioEnabled();
	NSNumber *previous = objc_getAssociatedObject(self, &kStoryLastAudioKey);
	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_AUDIO_TAG];

	if ([button isKindOfClass:SCIChromeButton.class]) {
		if (!previous || previous.boolValue != audioOn) button.symbolName = audioOn ? @"speaker.wave.2" : @"speaker.slash";
		objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	sciInitStoryAudioState();
	button = SCIStoryButton(audioOn ? @"speaker.wave.2" : @"speaker.slash", 14.0, 28.0, SCI_STORY_AUDIO_TAG);
	[button addTarget:self action:@selector(sciStoryAudioToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:button];

	[NSLayoutConstraint activateConstraints:@[
		[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
		[button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
		[button.widthAnchor constraintEqualToConstant:28.0],
		[button.heightAnchor constraintEqualToConstant:28.0]
	]];

	objc_setAssociatedObject(self, &kStoryLastAudioKey, @(audioOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciRefreshSeenButton {
	if (![SCIUtils getBoolPref:@"no_seen_receipt"]) {
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
		return;
	}

	NSDictionary *ownerInfo = sciOwnerInfoForView(self);
	NSString *ownerPK = ownerInfo[@"pk"] ?: @"";
	BOOL excluded = ownerPK.length && [SCIExcludedStoryUsers isUserPKExcluded:ownerPK];

	NSString *oldPK = objc_getAssociatedObject(self, &kStoryLastPKKey);
	NSNumber *oldExcluded = objc_getAssociatedObject(self, &kStoryLastExcludedKey);
	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_EYE_TAG];

	if ([button isKindOfClass:SCIChromeButton.class] && oldPK && [oldPK isEqualToString:ownerPK] && oldExcluded && oldExcluded.boolValue == excluded) return;

	objc_setAssociatedObject(self, &kStoryLastPKKey, ownerPK, OBJC_ASSOCIATION_COPY_NONATOMIC);
	objc_setAssociatedObject(self, &kStoryLastExcludedKey, @(excluded), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (excluded) {
		SCIRemoveStoryButton(self, SCI_STORY_EYE_TAG);
		return;
	}

	BOOL toggleMode = [[SCIUtils getStringPref:@"story_seen_mode"] isEqualToString:@"toggle"];
	NSString *symbol = (toggleMode && sciStorySeenToggleEnabled) ? @"eye.fill" : @"eye";
	UIColor *tint = (toggleMode && sciStorySeenToggleEnabled) ? SCIUtils.SCIColor_Primary : UIColor.whiteColor;

	if (![button isKindOfClass:SCIChromeButton.class]) {
		button = SCIStoryButton(@"", 18.0, 36.0, SCI_STORY_EYE_TAG);
		[button addTarget:self action:@selector(sciStorySeenButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
		[button addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)self]];
		[self addSubview:button];

		UIView *anchor = [self viewWithTag:SCI_STORY_ACTION_TAG];
		if (anchor) {
			[NSLayoutConstraint activateConstraints:@[
				[button.centerYAnchor constraintEqualToAnchor:anchor.centerYAnchor],
				[button.trailingAnchor constraintEqualToAnchor:anchor.leadingAnchor constant:-10.0],
				[button.widthAnchor constraintEqualToConstant:36.0],
				[button.heightAnchor constraintEqualToConstant:36.0]
			]];
		} else {
			[NSLayoutConstraint activateConstraints:@[
				[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
				[button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
				[button.widthAnchor constraintEqualToConstant:36.0],
				[button.heightAnchor constraintEqualToConstant:36.0]
			]];
		}
	}

	[button setIconResource:symbol pointSize:18.0];
	button.iconTint = tint;
}

%new
- (void)sciRefreshStoryMentionsButton {
	BOOL hasContent = [SCIUtils getBoolPref:@"story_mentions_button"] && sciStoryHasMentionsOrShares(self);
	SCIChromeButton *button = (SCIChromeButton *)[self viewWithTag:SCI_STORY_MENTIONS_TAG];

	if (![button isKindOfClass:SCIChromeButton.class]) button = nil;

	if (!hasContent || (self.window && self.bounds.size.width < self.window.bounds.size.width * 0.5)) {
		[button removeFromSuperview];
		return;
	}

	BOOL hasEye = [self viewWithTag:SCI_STORY_EYE_TAG] != nil;
	BOOL hasAction = [self viewWithTag:SCI_STORY_ACTION_TAG] != nil;
	NSInteger anchorState = (hasEye ? 1 : 0) | (hasAction ? 2 : 0);
	NSInteger count = [SCIUtils getBoolPref:@"story_mentions_counter"] ? sciStoryMentionsCount(self) : 0;
	NSNumber *oldAnchor = objc_getAssociatedObject(button, &kStoryMentionsAnchorKey);
	NSNumber *oldCount = objc_getAssociatedObject(button, &kStoryMentionsCountKey);

	if (button && oldAnchor.integerValue == anchorState) {
		if (oldCount.integerValue != count) sciApplyMentionsCounter(button, count);
		return;
	}

	[button removeFromSuperview];

	button = SCIStoryButton(@"at", 18.0, 36.0, SCI_STORY_MENTIONS_TAG);
	[button addTarget:self action:@selector(sciStoryMentionsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self addSubview:button];

	CGFloat trailing = -12.0 - (hasAction ? 46.0 : 0.0) - (hasEye ? 46.0 : 0.0);
	[NSLayoutConstraint activateConstraints:@[
		[button.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100.0],
		[button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:trailing],
		[button.widthAnchor constraintEqualToConstant:36.0],
		[button.heightAnchor constraintEqualToConstant:36.0]
	]];

	objc_setAssociatedObject(button, &kStoryMentionsAnchorKey, @(anchorState), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	sciApplyMentionsCounter(button, count);
}

%new
- (void)sciKickMentionsRetryChain {
	if (![SCIUtils getBoolPref:@"story_mentions_button"] || [self viewWithTag:SCI_STORY_MENTIONS_TAG]) return;

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

		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButton));
		if (![self viewWithTag:SCI_STORY_MENTIONS_TAG])
			((void (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(self, @selector(sciScheduleMentionsRetryGeneration:remaining:), gen, remaining - 1);
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

	NSString *mediaPK = sciCurrentStoryMediaPK(self) ?: @"";
	NSString *oldMediaPK = objc_getAssociatedObject(self, &kStoryLastMediaPKKey);
	BOOL mediaChanged = !oldMediaPK || ![oldMediaPK isEqualToString:mediaPK];

	if (mediaChanged) {
		objc_setAssociatedObject(self, &kStoryLastMediaPKKey, mediaPK, OBJC_ASSOCIATION_COPY_NONATOMIC);
		objc_setAssociatedObject(self, &kStoryLastPKKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
		objc_setAssociatedObject(self, &kStoryLastExcludedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(self, &kStoryLastMentionsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		((void (*)(id, SEL))objc_msgSend)(self, @selector(sciUpdateStoryOverlayButtons));
		return;
	}

	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryActionButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryAudioButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshSeenButton));
	((void (*)(id, SEL))objc_msgSend)(self, @selector(sciRefreshStoryMentionsButton));
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
			((void (*)(id, SEL, id))objc_msgSend)(self, @selector(sciStoryMarkSeenTapped:), nil);
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

	@try {
		UIViewController *storyVC = sciStoryVCForView(self);
		if (!storyVC) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"VC not found")];
			return;
		}

		id sectionController = sciStorySectionController(storyVC);
		id storyItem = sciCurrentStoryItemFromVC(storyVC);
		if (!storyItem) storyItem = sciGetCurrentStoryItem(self);

		IGMedia *media = [storyItem isKindOfClass:NSClassFromString(@"IGMedia")] ? storyItem : sciExtractMediaFromItem(storyItem);
		if (!media) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find story media")];
			return;
		}

		sciAllowSeenForPK(media);
		sciSeenBypassActive = YES;

		SEL delegateSel = @selector(fullscreenSectionController:didMarkItemAsSeen:);
		if ([storyVC respondsToSelector:delegateSel])
			((void (*)(id, SEL, id, id))objc_msgSend)(storyVC, delegateSel, sectionController, media);

		sciSafeCall1(sectionController, NSSelectorFromString(@"markItemAsSeen:"), media);

		id seenManager = sciSafeCall0(storyVC, @selector(viewingSessionSeenStateManager));
		id viewModel = sciSafeCall0(storyVC, @selector(currentViewModel));
		SEL setSeenSel = NSSelectorFromString(@"setSeenMediaId:forReelPK:");

		if (seenManager && viewModel && [seenManager respondsToSelector:setSeenSel]) {
			id mediaPK = sciSafeCall0(media, @selector(pk));
			id reelPK = sciSafeCall0(viewModel, @selector(reelPK));
			if (mediaPK && reelPK)
				((void (*)(id, SEL, id, id))objc_msgSend)(seenManager, setSeenSel, mediaPK, reelPK);
		}

		sciSeenBypassActive = NO;
		SCINotifySuccess(SCI_NOTIF_SEEN_STORY, SCILocalized(@"Story marked as seen"), nil);

		if (sender && [SCIUtils getBoolPref:@"advance_on_mark_seen"] && sectionController) {
			__weak __typeof(self) weakSelf = self;
			__block id weakSection = sectionController;

			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				sciAdvanceBypassActive = YES;

				if ([weakSection respondsToSelector:@selector(advanceToNextItemWithNavigationAction:)])
					((void (*)(id, SEL, NSInteger))objc_msgSend)(weakSection, @selector(advanceToNextItemWithNavigationAction:), 1);

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

	for (UIView *current = sourceView; current.superview; current = current.superview) {
		for (UIView *sibling in current.superview.subviews) {
			if (![sibling isKindOfClass:overlayClass]) continue;

			for (NSNumber *tag in @[@(SCI_STORY_EYE_TAG), @(SCI_STORY_ACTION_TAG), @(SCI_STORY_AUDIO_TAG), @(SCI_STORY_MENTIONS_TAG)])
				[sibling viewWithTag:tag.integerValue].alpha = alpha;
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
	if (![SCIUtils getBoolPref:@"story_mentions_button"]) return;

	for (UIView *overlay in sciLiveStoryOverlays().allObjects) {
		if (!overlay.window || sciOverlayIsInDMContext(overlay)) continue;

		if ([overlay respondsToSelector:@selector(sciRefreshStoryMentionsButton)])
			((void (*)(id, SEL))objc_msgSend)(overlay, @selector(sciRefreshStoryMentionsButton));

		if ([overlay respondsToSelector:@selector(sciKickMentionsRetryChain)])
			((void (*)(id, SEL))objc_msgSend)(overlay, @selector(sciKickMentionsRetryChain));
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
	if (SCIStoryActionEnabled() || [SCIUtils getBoolPref:@"story_audio_toggle"] || [SCIUtils getBoolPref:@"no_seen_receipt"] || [SCIUtils getBoolPref:@"story_mentions_button"])
		%init(StoryOverlayGroup);
}