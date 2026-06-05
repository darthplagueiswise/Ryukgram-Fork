#import "../../InstagramHeaders.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "SCIExcludedThreads.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#pragma mark - Helpers

static NSString *sciThreadIdForVC(id vc) {
	if (!vc) return nil;
	@try {
		NSString *tid = [vc valueForKey:@"threadId"];
		return [tid isKindOfClass:NSString.class] ? tid : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

static id sciFeatureManagerForThreadVC(id vc) {
	if (!vc) return nil;

	@try {
		id manager = [vc valueForKey:@"featureManager"];
		if (manager) return manager;
	} @catch (__unused id e) {}

	Ivar ivar = class_getInstanceVariable([vc class], "_featureManager");
	return ivar ? object_getIvar(vc, ivar) : nil;
}

static BOOL sciMarkThreadSeenSafely(id vcOrManager) {
	if (!vcOrManager) return NO;

	dispatch_async(dispatch_get_main_queue(), ^{
		id target = vcOrManager;

		if (![target respondsToSelector:@selector(markLastMessageAsSeen)]) {
			target = sciFeatureManagerForThreadVC(vcOrManager);
		}

		if (!target || ![target respondsToSelector:@selector(markLastMessageAsSeen)]) return;

		@try {
			((void (*)(id, SEL))objc_msgSend)(target, @selector(markLastMessageAsSeen));
		} @catch (__unused id e) {}
	});

	return YES;
}

static id sciThreadVCForAnchor(UIView *anchor) {
	id vc = [SCIUtils nearestViewControllerForView:anchor];
	Class threadCls = NSClassFromString(@"IGDirectThreadViewController");
	return (threadCls && [vc isKindOfClass:threadCls]) ? vc : nil;
}

static BOOL sciSeenToggleMode(void) {
	return [[SCIUtils getStringPref:@"seen_mode"] isEqualToString:@"toggle"];
}

BOOL dmSeenToggleEnabled = NO;
static NSInteger sciSeenAutoBypassCount = 0;
__weak id sciActiveThreadVC = nil;

static BOOL sciAutoInteractEnabled(void) {
	if ([SCIExcludedThreads isActiveThreadExcluded]) return NO;
	return [SCIUtils getBoolPref:@"remove_lastseen"] && [SCIUtils getBoolPref:@"seen_auto_on_interact"];
}

BOOL sciAutoTypingEnabled(void) {
	if ([SCIExcludedThreads isActiveThreadExcluded]) return NO;
	return [SCIUtils getBoolPref:@"remove_lastseen"] && [SCIUtils getBoolPref:@"seen_auto_on_typing"];
}

void sciDoAutoSeen(id threadVC) {
	if (!threadVC) return;

	sciSeenAutoBypassCount++;
	sciMarkThreadSeenSafely(threadVC);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (sciSeenAutoBypassCount > 0) sciSeenAutoBypassCount--;
	});
}

#pragma mark - Auto Seen On Send

static void (*orig_setHasSent)(id self, SEL _cmd, BOOL sent);
static void new_setHasSent(id self, SEL _cmd, BOOL sent) {
	orig_setHasSent(self, _cmd, sent);

	if (!sent || !sciAutoInteractEnabled()) return;

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		sciDoAutoSeen(self);
	});
}

#pragma mark - Active Thread Tracking

%hook IGDirectThreadViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	sciActiveThreadVC = self;
	NSString *tid = sciThreadIdForVC(self);
	if (tid.length) [SCIExcludedThreads setActiveThreadId:tid];
}

- (void)viewWillDisappear:(BOOL)animated {
	if (sciActiveThreadVC == self) {
		sciActiveThreadVC = nil;
		[SCIExcludedThreads setActiveThreadId:nil];
	}

	%orig;
}

%end

#pragma mark - Navigation Buttons

void sciRefreshNavBarItems(UIView *anchor) {
	if (!anchor || ![anchor respondsToSelector:@selector(setRightBarButtonItems:)]) return;

	NSArray *items = nil;
	if ([anchor respondsToSelector:@selector(rightBarButtonItems)]) {
		items = ((NSArray *(*)(id, SEL))objc_msgSend)(anchor, @selector(rightBarButtonItems));
	}

	((void (*)(id, SEL, id))objc_msgSend)(anchor, @selector(setRightBarButtonItems:), items ?: @[]);
}

static NSDictionary *sciEntryFromThreadVC(id vc);

static void sciOpenMessagesSettingsFromView(UIView *view, UIWindow *window) {
	UIWindow *win = window ?: view.window;

	if (!win) {
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if (![scene isKindOfClass:UIWindowScene.class]) continue;
			for (UIWindow *w in ((UIWindowScene *)scene).windows) {
				if (w.isKeyWindow) {
					win = w;
					break;
				}
			}
			if (win) break;
		}
	}

	if (win) [SCIUtils showSettingsVC:win atTopLevelEntry:SCILocalized(@"Messages")];
}

static UIMenu *sciBuildThreadActionsMenu(UIView *anchor, NSString *threadId, UIWindow *window) {
	BOOL inList = threadId.length && [SCIExcludedThreads isInList:threadId];
	BOOL excluded = threadId.length && [SCIExcludedThreads isThreadIdExcluded:threadId];
	BOOL blockSelected = [SCIExcludedThreads isBlockSelectedMode];
	BOOL seenFeatureOn = [SCIUtils getBoolPref:@"remove_lastseen"];

	NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
	__weak UIView *weakAnchor = anchor;

	if (seenFeatureOn && !excluded) {
		if (sciSeenToggleMode()) {
			NSString *title = dmSeenToggleEnabled ? SCILocalized(@"Disable read receipts") : SCILocalized(@"Enable read receipts");

			UIAction *toggle = [UIAction actionWithTitle:title
												   image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
											  identifier:nil
												 handler:^(__kindof UIAction *_) {
				dmSeenToggleEnabled = !dmSeenToggleEnabled;

				if (dmSeenToggleEnabled) {
					sciMarkThreadSeenSafely(sciThreadVCForAnchor(weakAnchor));
				}

				SCINotifySuccess(SCI_NOTIF_SEEN_DM,
					dmSeenToggleEnabled ? SCILocalized(@"Read receipts enabled") : SCILocalized(@"Read receipts disabled"),
					nil);

				sciRefreshNavBarItems(weakAnchor);
			}];

			toggle.state = dmSeenToggleEnabled ? UIMenuElementStateOn : UIMenuElementStateOff;
			[items addObject:toggle];
		}

		UIAction *markSeen = [UIAction actionWithTitle:SCILocalized(@"Mark messages as seen")
												 image:[SCIIcon imageNamed:@"eye"]
											identifier:nil
											   handler:^(__kindof UIAction *_) {
			if (sciMarkThreadSeenSafely(sciThreadVCForAnchor(weakAnchor))) {
				SCINotifySuccess(SCI_NOTIF_SEEN_DM, SCILocalized(@"Marked messages as seen"), nil);
			}
		}];

		[items addObject:markSeen];
	}

	NSString *addLabel = blockSelected ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude chat");
	NSString *removeLabel = blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude chat");

	UIAction *listToggle = [UIAction actionWithTitle:(inList ? removeLabel : addLabel)
											  image:[SCIIcon imageNamed:(inList ? @"eye.fill" : @"eye.slash")]
										 identifier:nil
											handler:^(__kindof UIAction *_) {
		if (!threadId.length) return;

		id threadVC = sciThreadVCForAnchor(weakAnchor);

		if (inList) {
			[SCIExcludedThreads removeThreadId:threadId];

			SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_CHAT,
				blockSelected ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded"),
				nil);

			if (blockSelected) sciMarkThreadSeenSafely(threadVC);
		} else {
			NSDictionary *entry = sciEntryFromThreadVC(threadVC);
			if (!entry) entry = @{ @"threadId": threadId, @"threadName": @"", @"isGroup": @NO, @"users": @[] };

			[SCIExcludedThreads addOrUpdateEntry:entry];

			SCINotifySuccess(blockSelected ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_CHAT,
				blockSelected ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded"),
				nil);

			if (!blockSelected) sciMarkThreadSeenSafely(threadVC);
		}

		sciRefreshNavBarItems(weakAnchor);
	}];

	if (excluded) listToggle.attributes = UIMenuElementAttributesDestructive;
	[items addObject:listToggle];

	if ([SCIUtils getBoolPref:@"unlimited_replay"] && !excluded) {
		NSString *title = dmVisualMsgsViewedButtonEnabled
			? SCILocalized(@"Visual messages: expiring")
			: SCILocalized(@"Visual messages: unlimited replay");

		NSString *icon = dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill";

		UIAction *replay = [UIAction actionWithTitle:title
											   image:[SCIIcon imageNamed:icon]
										  identifier:nil
											 handler:^(__kindof UIAction *_) {
			dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;

			SCINotifySuccess(SCI_NOTIF_SEEN_DM,
				dmVisualMsgsViewedButtonEnabled ? SCILocalized(@"Visual messages will expire") : SCILocalized(@"Unlimited replay enabled"),
				nil);

			sciRefreshNavBarItems(weakAnchor);
		}];

		replay.state = dmVisualMsgsViewedButtonEnabled ? UIMenuElementStateOff : UIMenuElementStateOn;
		[items addObject:replay];
	}

	UIAction *settings = [UIAction actionWithTitle:SCILocalized(@"Messages settings")
											image:[UIImage systemImageNamed:@"gear"]
									   identifier:nil
										  handler:^(__kindof UIAction *_) {
		sciOpenMessagesSettingsFromView(weakAnchor, window);
	}];

	[items addObject:settings];

	return [UIMenu menuWithTitle:@"" children:items];
}

static NSDictionary *sciEntryFromThreadVC(id vc) {
	if (!vc) return nil;

	NSString *tid = sciThreadIdForVC(vc);
	if (!tid.length) return nil;

	NSString *name = @"";
	NSMutableArray *users = [NSMutableArray array];

	@try {
		if ([vc respondsToSelector:@selector(navigationItem)]) {
			name = [[vc navigationItem] title] ?: @"";
		}

		id thread = [vc valueForKey:@"thread"];
		id threadUsers = thread ? [thread valueForKey:@"users"] : nil;

		if ([threadUsers isKindOfClass:NSArray.class]) {
			for (id user in threadUsers) {
				NSMutableDictionary *dict = [NSMutableDictionary dictionary];

				@try {
					id pk = [user valueForKey:@"pk"];
					id username = [user valueForKey:@"username"];
					id fullName = [user valueForKey:@"fullName"];

					if (pk) dict[@"pk"] = [NSString stringWithFormat:@"%@", pk];
					if (username) dict[@"username"] = [NSString stringWithFormat:@"%@", username];
					if (fullName) dict[@"fullName"] = [NSString stringWithFormat:@"%@", fullName];
				} @catch (__unused id e) {}

				if (dict.count) [users addObject:dict];
			}
		}
	} @catch (__unused id e) {}

	return @{
		@"threadId": tid,
		@"threadName": name ?: @"",
		@"isGroup": @NO,
		@"users": users ?: @[]
	};
}

%hook IGTallNavigationBarView

%new - (void)sciAddToListHandler:(id)sender {
	id vc = sciThreadVCForAnchor(self);
	NSDictionary *entry = sciEntryFromThreadVC(vc);
	if (!entry) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add to block list")
																   message:SCILocalized(@"Read receipts will be blocked for this chat.")
															preferredStyle:UIAlertControllerStyleAlert];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[SCIExcludedThreads addOrUpdateEntry:entry];
		SCINotifySuccess(SCI_NOTIF_BLOCK_TOGGLE, SCILocalized(@"Added to block list"), nil);
		sciRefreshNavBarItems(weakSelf);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	if ([vc respondsToSelector:@selector(presentViewController:animated:completion:)]) {
		[(UIViewController *)vc presentViewController:alert animated:YES completion:nil];
	}
}

%new - (void)sciUnexcludeButtonHandler:(id)sender {
	id vc = sciThreadVCForAnchor(self);
	NSString *tid = sciThreadIdForVC(vc);
	if (!tid.length) return;

	BOOL blockSelected = [SCIExcludedThreads isBlockSelectedMode];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:(blockSelected ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude chat"))
																   message:(blockSelected ? SCILocalized(@"Read receipts will no longer be blocked for this chat.") : SCILocalized(@"This chat will resume normal read-receipt behavior."))
															preferredStyle:UIAlertControllerStyleAlert];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Remove") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[SCIExcludedThreads removeThreadId:tid];
		SCINotifySuccess(SCI_NOTIF_EXCLUDE_CHAT, SCILocalized(@"Removed"), nil);
		sciRefreshNavBarItems(weakSelf);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	if ([vc respondsToSelector:@selector(presentViewController:animated:completion:)]) {
		[(UIViewController *)vc presentViewController:alert animated:YES completion:nil];
	}
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
	BOOL hideVoice = [SCIUtils getBoolPref:@"hide_voice_call_button"];
	BOOL hideVideo = [SCIUtils getBoolPref:@"hide_video_call_button"];
	BOOL hideBlend = [SCIUtils getBoolPref:@"hide_reels_blend"];

	NSMutableArray *newItems = [NSMutableArray array];

	for (UIBarButtonItem *item in items ?: @[]) {
		NSString *aid = item.accessibilityIdentifier;

		if ([aid isEqualToString:@"sci-seen-btn"] ||
			[aid isEqualToString:@"sci-unex-btn"] ||
			[aid isEqualToString:@"sci-visual-btn"]) {
			continue;
		}

		if (hideBlend && [aid isEqualToString:@"blend-button"]) continue;

		UIView *customView = item.customView;
		if (customView && [customView isKindOfClass:NSClassFromString(@"IGDirectCallButton")]) {
			NSString *cvAx = customView.accessibilityIdentifier;
			if (hideVoice && [cvAx isEqualToString:@"audio-call"]) continue;
			if (hideVideo && [cvAx isEqualToString:@"video-chat"]) continue;
		}

		[newItems addObject:item];
	}

	id threadVC = sciThreadVCForAnchor(self);
	NSString *threadId = sciThreadIdForVC(threadVC);
	BOOL excluded = threadId.length && [SCIExcludedThreads isThreadIdExcluded:threadId];
	BOOL inList = threadId.length && [SCIExcludedThreads isInList:threadId];

	if ([SCIUtils getBoolPref:@"remove_lastseen"] && !excluded) {
		SCIChromeButton *inner = nil;
		UIBarButtonItem *seenButton = SCIChromeBarButtonItem(@"", 22, self, @selector(seenButtonHandler:), &inner);

		[inner setIconResource:@"eye" pointSize:22];
		seenButton.accessibilityIdentifier = @"sci-seen-btn";
		inner.iconTint = (sciSeenToggleMode() && dmSeenToggleEnabled) ? SCIUtils.SCIColor_Primary : UIColor.labelColor;
		inner.menu = sciBuildThreadActionsMenu(self, threadId, self.window);

		[newItems addObject:seenButton];
	}

	BOOL blockSelected = [SCIExcludedThreads isBlockSelectedMode];
	BOOL showListButton = [SCIUtils getBoolPref:@"remove_lastseen"] && [SCIUtils getBoolPref:@"chat_quick_list_button"];
	BOOL showRemove = !blockSelected && inList && excluded;
	BOOL showAdd = blockSelected && !inList;

	if (showListButton && (showRemove || showAdd)) {
		SCIChromeButton *inner = nil;
		SEL action = showRemove ? @selector(sciUnexcludeButtonHandler:) : @selector(sciAddToListHandler:);
		NSString *icon = showRemove ? @"eye.slash.fill" : @"eye.slash";

		UIBarButtonItem *listButton = SCIChromeBarButtonItem(@"", 18, self, action, &inner);

		[inner setIconResource:icon pointSize:18];
		listButton.accessibilityIdentifier = @"sci-unex-btn";
		inner.iconTint = showRemove ? SCIUtils.SCIColor_Primary : UIColor.labelColor;
		inner.menu = sciBuildThreadActionsMenu(self, threadId, self.window);

		[newItems addObject:listButton];
	}

	if ([SCIUtils getBoolPref:@"unlimited_replay"] && !excluded && ![SCIUtils getBoolPref:@"remove_lastseen"]) {
		SCIChromeButton *inner = nil;
		NSString *icon = dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill";

		UIBarButtonItem *replayButton = SCIChromeBarButtonItem(@"", 18, self, @selector(sciReplayToggleHandler:), &inner);

		[inner setIconResource:icon pointSize:18];
		replayButton.accessibilityIdentifier = @"sci-visual-btn";
		inner.iconTint = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : SCIUtils.SCIColor_Primary;

		[newItems addObject:replayButton];
	}

	%orig([newItems copy]);
}

%new - (void)seenButtonHandler:(id)sender {
	UIBarButtonItem *barItem = [sender isKindOfClass:UIBarButtonItem.class] ? sender : nil;
	SCIChromeButton *inner = [sender isKindOfClass:SCIChromeButton.class] ? sender : SCIChromeButtonForBarItem(barItem);

	if (sciSeenToggleMode()) {
		dmSeenToggleEnabled = !dmSeenToggleEnabled;

		UIColor *tint = dmSeenToggleEnabled ? SCIUtils.SCIColor_Primary : UIColor.labelColor;
		if (inner) inner.iconTint = tint;
		else barItem.tintColor = tint;

		if (dmSeenToggleEnabled) {
			sciMarkThreadSeenSafely(sciThreadVCForAnchor(self));
			SCINotifySuccess(SCI_NOTIF_SEEN_DM, SCILocalized(@"Read receipts enabled"), nil);
		} else {
			SCINotifySuccess(SCI_NOTIF_SEEN_DM, SCILocalized(@"Read receipts disabled"), nil);
		}
	} else {
		if (sciMarkThreadSeenSafely(sciThreadVCForAnchor(self))) {
			SCINotifySuccess(SCI_NOTIF_SEEN_DM, SCILocalized(@"Marked messages as seen"), nil);
		}
	}

	NSString *tid = sciThreadIdForVC(sciThreadVCForAnchor(self));
	UIMenu *menu = sciBuildThreadActionsMenu(self, tid, self.window);

	if (inner) inner.menu = menu;
	else if (barItem) barItem.menu = menu;
}

%new - (void)sciReplayToggleHandler:(id)sender {
	UIBarButtonItem *barItem = [sender isKindOfClass:UIBarButtonItem.class] ? sender : nil;
	SCIChromeButton *inner = [sender isKindOfClass:SCIChromeButton.class] ? sender : SCIChromeButtonForBarItem(barItem);

	dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;

	NSString *icon = dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill";
	UIColor *tint = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : SCIUtils.SCIColor_Primary;

	if (inner) {
		[inner setIconResource:icon pointSize:18];
		inner.iconTint = tint;
	} else if (barItem) {
		barItem.image = [SCIIcon imageNamed:icon];
		barItem.tintColor = tint;
	}

	SCINotifySuccess(SCI_NOTIF_SEEN_DM,
		dmVisualMsgsViewedButtonEnabled ? SCILocalized(@"Visual messages will expire") : SCILocalized(@"Unlimited replay enabled"),
		nil);
}

%end

#pragma mark - Seen Blocking Logic

%hook IGDirectThreadViewListAdapterDataSource

- (BOOL)shouldUpdateLastSeenMessage {
	if (![SCIUtils getBoolPref:@"remove_lastseen"]) return %orig;

	if ([SCIExcludedThreads isActiveThreadExcluded]) return %orig;
	if (sciSeenToggleMode() && dmSeenToggleEnabled) return %orig;
	if (sciSeenAutoBypassCount > 0) return %orig;

	return NO;
}

%end

#pragma mark - Visual Messages Viewed Logic

%hook IGDirectVisualMessageViewerEventHandler

- (void)visualMessageViewerController:(id)arg1 didBeginPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 {
	if ([SCIUtils getBoolPref:@"unlimited_replay"] &&
		!dmVisualMsgsViewedButtonEnabled &&
		![SCIExcludedThreads isActiveThreadExcluded]) {
		return;
	}

	%orig;
}

- (void)visualMessageViewerController:(id)arg1 didEndPlaybackForVisualMessage:(id)arg2 atIndex:(NSInteger)arg3 mediaCurrentTime:(CGFloat)arg4 forNavType:(NSInteger)arg5 {
	if ([SCIUtils getBoolPref:@"unlimited_replay"] &&
		!dmVisualMsgsViewedButtonEnabled &&
		![SCIExcludedThreads isActiveThreadExcluded]) {
		return;
	}

	%orig;
}

%end

#pragma mark - Runtime Hooks

%ctor {
	Class managerClass = NSClassFromString(@"IGDirectThreadViewFeatureManager");
	SEL sentSel = NSSelectorFromString(@"setHasSentAMessageOrUpdate:");

	if (managerClass && class_getInstanceMethod(managerClass, sentSel)) {
		MSHookMessageEx(managerClass, sentSel, (IMP)new_setHasSent, (IMP *)&orig_setHasSent);
	}
}