#import "../../InstagramHeaders.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "SCIExcludedThreads.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

#pragma mark - State

BOOL dmSeenToggleEnabled = NO;

static NSInteger sSeenBypass = 0;
static NSInteger sShareDepth = 0;
static __weak id sActiveThreadVC = nil;

// Share sends fire after the sheet dismisses, so shareDepth can't catch them. A guard
// armed on present suppresses the whole burst until you return to the thread or it expires.
static NSTimeInterval sShareArmedAt = 0;
static const NSTimeInterval kShareGuardWindow = 20.0;

static inline void SCIArmShareGuard(void) { sShareArmedAt = NSProcessInfo.processInfo.systemUptime; }
static inline void SCIDisarmShareGuard(void) { sShareArmedAt = 0; }

static BOOL SCIShareGuardActive(void) {
	if (sShareArmedAt <= 0) return NO;
	if (NSProcessInfo.processInfo.systemUptime - sShareArmedAt > kShareGuardWindow) { sShareArmedAt = 0; return NO; }
	return YES;
}

#pragma mark - Runtime Helpers

static inline BOOL SCIResponds(id obj, SEL sel) {
	return obj && [obj respondsToSelector:sel];
}

static inline id SCIGetIvar(id obj, const char *name) {
	return obj ? [SCIUtils getIvarForObj:obj name:name] : nil;
}

static inline id SCIObj(id obj, SEL sel) {
	return SCIResponds(obj, sel) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static inline NSString *SCIString(id obj) {
	return obj ? [NSString stringWithFormat:@"%@", obj] : nil;
}

static inline BOOL SCISeenToggleMode(void) {
	return [[SCIUtils getStringPref:@"seen_mode"] isEqualToString:@"toggle"];
}

static inline BOOL SCIReadReceiptsOn(void) {
	return [SCIUtils getBoolPref:@"remove_lastseen"];
}

static NSString *SCIThreadId(id vc) {
	id tid = SCIObj(vc, @selector(threadId));
	return [tid isKindOfClass:NSString.class] ? tid : SCIString(tid);
}

static id SCIThreadVCForManager(id manager) {
	id vc = SCIGetIvar(manager, "_vc");
	Class cls = NSClassFromString(@"IGDirectThreadViewController");

	return (cls && [vc isKindOfClass:cls]) ? vc : nil;
}

static id SCIManagerForThreadVC(id vc) {
	return SCIGetIvar(vc, "_featureManager");
}

static id SCIThreadVCForAnchor(UIView *view) {
	id vc = [SCIUtils nearestViewControllerForView:view];
	Class cls = NSClassFromString(@"IGDirectThreadViewController");

	return (cls && [vc isKindOfClass:cls]) ? vc : nil;
}

static BOOL SCIAutoInteractEnabled(NSString *threadId) {
	return SCIReadReceiptsOn() &&
		   [SCIUtils getBoolPref:@"seen_auto_on_interact"] &&
		   threadId.length &&
		   ![SCIExcludedThreads isThreadIdExcluded:threadId];
}

BOOL sciAutoTypingEnabled(void) {
	return SCIReadReceiptsOn() &&
		   [SCIUtils getBoolPref:@"seen_auto_on_typing"] &&
		   ![SCIExcludedThreads isActiveThreadExcluded];
}

// Not gated on active/visible — a reel detaches the thread VC and leaving mid-send flips
// visible off. Only shares are filtered, via the share guard.
static BOOL SCIShouldAutoSeen(id manager) {
	id vc = SCIThreadVCForManager(manager);
	NSString *tid = SCIThreadId(vc);

	if (!vc || !SCIAutoInteractEnabled(tid)) return NO;
	if (sShareDepth > 0 || SCIShareGuardActive()) return NO;

	return YES;
}

#pragma mark - Mark Seen

static BOOL SCIMarkSeen(id vcOrManager) {
	if (!vcOrManager) return NO;

	dispatch_async(dispatch_get_main_queue(), ^{
		id target = SCIResponds(vcOrManager, @selector(markLastMessageAsSeen))
			? vcOrManager
			: SCIManagerForThreadVC(vcOrManager);

		if (!SCIResponds(target, @selector(markLastMessageAsSeen))) return;

		@try {
			((void (*)(id, SEL))objc_msgSend)(target, @selector(markLastMessageAsSeen));
		} @catch (__unused id e) {}
	});

	return YES;
}

void sciDoAutoSeen(id threadVC) {
	if (!threadVC) return;

	sSeenBypass++;
	SCIMarkSeen(threadVC);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (sSeenBypass > 0) sSeenBypass--;
	});
}

void sciDoAutoSeenActiveThread(void) {
	sciDoAutoSeen(sActiveThreadVC);
}

static void SCIAutoSeenLater(id manager) {
	id vc = SCIThreadVCForManager(manager);
	NSString *tid = SCIThreadId(vc);
	if (!vc) return;

	// Strong-capture vc so a thread we just left still gets its receipt; defer lets the send register.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (!SCIAutoInteractEnabled(tid)) return;
		sciDoAutoSeen(vc);
	});
}

// Marks the active thread. For paths setHasSentAMessageOrUpdate: misses: voice notes and
// media send-initiation (uploads in the background, so the flag never fires on swipe-back).
void sciMarkActiveThreadSeenOnInteract(void) {
	id mgr = SCIManagerForThreadVC(sActiveThreadVC);
	if (mgr && SCIShouldAutoSeen(mgr)) SCIAutoSeenLater(mgr);
}

static void SCIConfirmMarkSeen(UIViewController *presenter, void (^block)(void)) {
	[SCIUtils confirmIfNeeded:[SCIUtils getBoolPref:@"confirm_mark_seen_dm"]
						 title:SCILocalized(@"Mark as seen?")
					   message:SCILocalized(@"This will send a read receipt for the latest messages.")
				  confirmTitle:SCILocalized(@"Mark seen")
						  from:presenter
					 onConfirm:block
					  onCancel:nil];
}

#pragma mark - Send Hooks

// Send completion for things shown while the thread is open (reactions, reel quick-reacts).
static void (*orig_setHasSent)(id self, SEL _cmd, BOOL sent);
static void new_setHasSent(id self, SEL _cmd, BOOL sent) {
	BOOL should = sent && SCIShouldAutoSeen(self);
	orig_setHasSent(self, _cmd, sent);
	if (should) SCIAutoSeenLater(self);
}

// Send-initiation: fires the instant you tap send, so media marks even if you swipe back before it uploads.
%hook _TtC45IGDirectThreadMessageSenderListenerController45IGDirectThreadMessageSenderListenerController

- (void)outgoingMessagePayloadWillSend:(id)payload {
	%orig;
	sciMarkActiveThreadSeenOnInteract();
}

%end

#pragma mark - Active Thread

%hook IGDirectThreadViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	sShareDepth = 0;
	SCIDisarmShareGuard();
	sActiveThreadVC = self;
	[SCIExcludedThreads setActiveThreadId:SCIThreadId(self)];
}

- (void)viewDidDisappear:(BOOL)animated {
	if (sActiveThreadVC == self) {
		sActiveThreadVC = nil;
		[SCIExcludedThreads setActiveThreadId:nil];
	}

	%orig;
}

%end

#pragma mark - Share Sheet Guard

%hook IGDirectShareSheetController

- (id)presentShareSheetWithOverlayView:(BOOL)view directRecipientConfiguration:(id)configuration config:(id)config {
	sShareDepth++;
	SCIArmShareGuard();
	return %orig;
}

- (id)presentShareSheetWithShortcutRecipients:(id)recipients showOverlayView:(BOOL)view directRecipientConfiguration:(id)configuration config:(id)config {
	sShareDepth++;
	SCIArmShareGuard();
	return %orig;
}

- (void)dismissShareSheetAnimated:(BOOL)animated logCancellation:(BOOL)cancellation completion:(id)completion {
	%orig;
	if (sShareDepth > 0) sShareDepth--;
}

- (void)dismissShareSheetWithAnimationDuration:(double)duration logCancellation:(BOOL)cancellation {
	%orig;
	if (sShareDepth > 0) sShareDepth--;
}

- (void)shareSheetContainerDidDismiss:(id)dismiss {
	%orig;
	if (sShareDepth > 0) sShareDepth--;
}

%end

#pragma mark - Nav Helpers

static void SCIRefreshNav(UIView *view) {
	if (!SCIResponds(view, @selector(setRightBarButtonItems:))) return;

	NSArray *items = SCIObj(view, @selector(rightBarButtonItems)) ?: @[];
	((void (*)(id, SEL, id))objc_msgSend)(view, @selector(setRightBarButtonItems:), items);
}

static UIWindow *SCIWindow(UIView *view, UIWindow *fallback) {
	if (fallback) return fallback;
	if (view.window) return view.window;

	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *win in ((UIWindowScene *)scene).windows) {
			if (win.isKeyWindow) return win;
		}
	}

	return nil;
}

static NSDictionary *SCIEntryForThreadVC(id vc) {
	NSString *tid = SCIThreadId(vc);
	if (!tid.length) return nil;

	NSString *name = @"";

	@try {
		if ([vc respondsToSelector:@selector(navigationItem)]) {
			name = [[vc navigationItem] title] ?: @"";
		}
	} @catch (__unused id e) {}

	return @{
		@"threadId": tid,
		@"threadName": name,
		@"isGroup": @NO,
		@"users": @[]
	};
}

static void SCIOpenSettings(UIView *view, UIWindow *window) {
	UIWindow *win = SCIWindow(view, window);
	if (win) [SCIUtils showSettingsVC:win atTopLevelEntry:SCILocalized(@"Messages")];
}

static UIAction *SCIAction(NSString *title, id image, void (^handler)(__kindof UIAction *action)) {
	return [UIAction actionWithTitle:title image:image identifier:nil handler:handler];
}

static UIMenu *SCIBuildMenu(UIView *anchor, NSString *threadId, UIWindow *window) {
	BOOL inList = threadId.length && [SCIExcludedThreads isInList:threadId];
	BOOL excluded = threadId.length && [SCIExcludedThreads isThreadIdExcluded:threadId];
	BOOL blockMode = [SCIExcludedThreads isBlockSelectedMode];

	NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
	__weak UIView *weakAnchor = anchor;

	if (SCIReadReceiptsOn() && !excluded) {
		if (SCISeenToggleMode()) {
			NSString *title = dmSeenToggleEnabled ? SCILocalized(@"Disable read receipts") : SCILocalized(@"Enable read receipts");

			UIAction *toggle = SCIAction(title, [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"], ^(__kindof UIAction *_) {
				dmSeenToggleEnabled = !dmSeenToggleEnabled;

				if (dmSeenToggleEnabled) {
					SCIMarkSeen(SCIThreadVCForAnchor(weakAnchor));
				}

				SCINotifySuccess(SCI_NOTIF_SEEN_DM,
					dmSeenToggleEnabled ? SCILocalized(@"Read receipts enabled") : SCILocalized(@"Read receipts disabled"),
					nil);

				SCIRefreshNav(weakAnchor);
			});

			toggle.state = dmSeenToggleEnabled ? UIMenuElementStateOn : UIMenuElementStateOff;
			[items addObject:toggle];
		}

		[items addObject:SCIAction(SCILocalized(@"Mark messages as seen"), [SCIIcon imageNamed:@"eye"], ^(__kindof UIAction *_) {
			UIViewController *presenter = weakAnchor ? [SCIUtils nearestViewControllerForView:weakAnchor] : nil;

			SCIConfirmMarkSeen(presenter, ^{
				if (SCIMarkSeen(SCIThreadVCForAnchor(weakAnchor))) {
					SCINotifySuccess(SCI_NOTIF_SEEN_DM, SCILocalized(@"Marked messages as seen"), nil);
				}
			});
		})];
	}

	NSString *addTitle = blockMode ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude chat");
	NSString *removeTitle = blockMode ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude chat");

	UIAction *list = SCIAction(inList ? removeTitle : addTitle, [SCIIcon imageNamed:(inList ? @"eye.fill" : @"eye.slash")], ^(__kindof UIAction *_) {
		if (!threadId.length) return;

		id vc = SCIThreadVCForAnchor(weakAnchor);

		if (inList) {
			[SCIExcludedThreads removeThreadId:threadId];

			SCINotifySuccess(blockMode ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_CHAT,
				blockMode ? SCILocalized(@"Unblocked") : SCILocalized(@"Un-excluded"),
				nil);

			if (blockMode) SCIMarkSeen(vc);
		} else {
			[SCIExcludedThreads addOrUpdateEntry:SCIEntryForThreadVC(vc) ?: @{
				@"threadId": threadId,
				@"threadName": @"",
				@"isGroup": @NO,
				@"users": @[]
			}];

			SCINotifySuccess(blockMode ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_CHAT,
				blockMode ? SCILocalized(@"Blocked") : SCILocalized(@"Excluded"),
				nil);

			if (!blockMode) SCIMarkSeen(vc);
		}

		SCIRefreshNav(weakAnchor);
	});

	if (excluded) list.attributes = UIMenuElementAttributesDestructive;
	[items addObject:list];

	if ([SCIUtils getBoolPref:@"unlimited_replay"] && !excluded) {
		NSString *title = dmVisualMsgsViewedButtonEnabled
			? SCILocalized(@"Visual messages: expiring")
			: SCILocalized(@"Visual messages: unlimited replay");

		NSString *icon = dmVisualMsgsViewedButtonEnabled
			? @"photo.badge.checkmark"
			: @"photo.badge.checkmark.fill";

		UIAction *replay = SCIAction(title, [SCIIcon imageNamed:icon], ^(__kindof UIAction *_) {
			dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;

			SCINotifySuccess(SCI_NOTIF_SEEN_DM,
				dmVisualMsgsViewedButtonEnabled ? SCILocalized(@"Visual messages will expire") : SCILocalized(@"Unlimited replay enabled"),
				nil);

			SCIRefreshNav(weakAnchor);
		});

		replay.state = dmVisualMsgsViewedButtonEnabled ? UIMenuElementStateOff : UIMenuElementStateOn;
		[items addObject:replay];
	}

	[items addObject:SCIAction(SCILocalized(@"Messages settings"), [UIImage systemImageNamed:@"gear"], ^(__kindof UIAction *_) {
		SCIOpenSettings(weakAnchor, window);
	})];

	return [UIMenu menuWithTitle:@"" children:items];
}

static UIBarButtonItem *SCIChromeItem(NSString *aid, NSString *icon, CGFloat size, UIColor *tint, id target, SEL action, UIMenu *menu) {
	SCIChromeButton *inner = nil;
	UIBarButtonItem *item = SCIChromeBarButtonItem(@"", size, target, action, &inner);

	item.accessibilityIdentifier = aid;
	[inner setIconResource:icon pointSize:size];
	inner.iconTint = tint ?: UIColor.labelColor;
	inner.menu = menu;

	return item;
}

static BOOL SCIShouldSkipNativeItem(UIBarButtonItem *item) {
	NSString *aid = item.accessibilityIdentifier;

	if ([aid isEqualToString:@"sci-seen-btn"] ||
		[aid isEqualToString:@"sci-unex-btn"] ||
		[aid isEqualToString:@"sci-visual-btn"]) {
		return YES;
	}

	if ([SCIUtils getBoolPref:@"hide_reels_blend"] && [aid isEqualToString:@"blend-button"]) {
		return YES;
	}

	UIView *view = item.customView;
	Class callCls = NSClassFromString(@"IGDirectCallButton");

	if (view && callCls && [view isKindOfClass:callCls]) {
		NSString *cvAid = view.accessibilityIdentifier;

		if ([SCIUtils getBoolPref:@"hide_voice_call_button"] && [cvAid isEqualToString:@"audio-call"]) return YES;
		if ([SCIUtils getBoolPref:@"hide_video_call_button"] && [cvAid isEqualToString:@"video-chat"]) return YES;
	}

	return NO;
}

#pragma mark - Navigation Buttons

%hook IGTallNavigationBarView

%new - (void)sciAddToListHandler:(id)sender {
	id vc = SCIThreadVCForAnchor(self);
	NSDictionary *entry = SCIEntryForThreadVC(vc);
	if (!entry) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Add to block list")
																   message:SCILocalized(@"Read receipts will be blocked for this chat.")
															preferredStyle:UIAlertControllerStyleAlert];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[SCIExcludedThreads addOrUpdateEntry:entry];
		SCINotifySuccess(SCI_NOTIF_BLOCK_TOGGLE, SCILocalized(@"Added to block list"), nil);
		SCIRefreshNav(weakSelf);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	if ([vc respondsToSelector:@selector(presentViewController:animated:completion:)]) {
		[(UIViewController *)vc presentViewController:alert animated:YES completion:nil];
	}
}

%new - (void)sciUnexcludeButtonHandler:(id)sender {
	id vc = SCIThreadVCForAnchor(self);
	NSString *tid = SCIThreadId(vc);
	if (!tid.length) return;

	BOOL blockMode = [SCIExcludedThreads isBlockSelectedMode];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:(blockMode ? SCILocalized(@"Remove from block list") : SCILocalized(@"Un-exclude chat"))
																   message:(blockMode ? SCILocalized(@"Read receipts will no longer be blocked for this chat.") : SCILocalized(@"This chat will resume normal read-receipt behavior."))
															preferredStyle:UIAlertControllerStyleAlert];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Remove") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[SCIExcludedThreads removeThreadId:tid];
		SCINotifySuccess(SCI_NOTIF_EXCLUDE_CHAT, SCILocalized(@"Removed"), nil);
		SCIRefreshNav(weakSelf);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	if ([vc respondsToSelector:@selector(presentViewController:animated:completion:)]) {
		[(UIViewController *)vc presentViewController:alert animated:YES completion:nil];
	}
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
	NSMutableArray *out = [NSMutableArray array];

	for (UIBarButtonItem *item in items ?: @[]) {
		if (!SCIShouldSkipNativeItem(item)) [out addObject:item];
	}

	id vc = SCIThreadVCForAnchor(self);
	NSString *tid = SCIThreadId(vc);
	BOOL excluded = tid.length && [SCIExcludedThreads isThreadIdExcluded:tid];
	BOOL inList = tid.length && [SCIExcludedThreads isInList:tid];
	BOOL blockMode = [SCIExcludedThreads isBlockSelectedMode];

	UIMenu *menu = SCIBuildMenu(self, tid, self.window);

	if (SCIReadReceiptsOn() && !excluded && [SCIUtils getBoolPref:@"show_dm_seen_button"]) {
		UIColor *tint = (SCISeenToggleMode() && dmSeenToggleEnabled) ? SCIUtils.SCIColor_Primary : UIColor.labelColor;
		[out addObject:SCIChromeItem(@"sci-seen-btn", @"eye", 22, tint, self, @selector(seenButtonHandler:), menu)];
	}

	BOOL showListButton = SCIReadReceiptsOn() && [SCIUtils getBoolPref:@"chat_quick_list_button"];
	BOOL showRemove = !blockMode && inList && excluded;
	BOOL showAdd = blockMode && !inList;

	if (showListButton && (showRemove || showAdd)) {
		NSString *icon = showRemove ? @"eye.slash.fill" : @"eye.slash";
		UIColor *tint = showRemove ? SCIUtils.SCIColor_Primary : UIColor.labelColor;
		SEL action = showRemove ? @selector(sciUnexcludeButtonHandler:) : @selector(sciAddToListHandler:);

		[out addObject:SCIChromeItem(@"sci-unex-btn", icon, 18, tint, self, action, menu)];
	}

	if ([SCIUtils getBoolPref:@"unlimited_replay"] && !excluded && !SCIReadReceiptsOn()) {
		NSString *icon = dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill";
		UIColor *tint = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : SCIUtils.SCIColor_Primary;

		[out addObject:SCIChromeItem(@"sci-visual-btn", icon, 18, tint, self, @selector(sciReplayToggleHandler:), nil)];
	}

	%orig([out copy]);
}

%new - (void)seenButtonHandler:(id)sender {
	UIBarButtonItem *item = [sender isKindOfClass:UIBarButtonItem.class] ? sender : nil;
	SCIChromeButton *inner = [sender isKindOfClass:SCIChromeButton.class] ? sender : SCIChromeButtonForBarItem(item);

	if (SCISeenToggleMode()) {
		dmSeenToggleEnabled = !dmSeenToggleEnabled;

		UIColor *tint = dmSeenToggleEnabled ? SCIUtils.SCIColor_Primary : UIColor.labelColor;
		if (inner) inner.iconTint = tint;
		else item.tintColor = tint;

		if (dmSeenToggleEnabled) {
			SCIMarkSeen(SCIThreadVCForAnchor(self));
		}

		SCINotifySuccess(SCI_NOTIF_SEEN_DM,
			dmSeenToggleEnabled ? SCILocalized(@"Read receipts enabled") : SCILocalized(@"Read receipts disabled"),
			nil);
	} else {
		__weak UIView *weakSelf = self;

		SCIConfirmMarkSeen([SCIUtils nearestViewControllerForView:self], ^{
			if (SCIMarkSeen(SCIThreadVCForAnchor(weakSelf))) {
				SCINotifySuccess(SCI_NOTIF_SEEN_DM, SCILocalized(@"Marked messages as seen"), nil);
			}
		});
	}

	NSString *tid = SCIThreadId(SCIThreadVCForAnchor(self));
	UIMenu *menu = SCIBuildMenu(self, tid, self.window);

	if (inner) inner.menu = menu;
	else item.menu = menu;
}

%new - (void)sciReplayToggleHandler:(id)sender {
	UIBarButtonItem *item = [sender isKindOfClass:UIBarButtonItem.class] ? sender : nil;
	SCIChromeButton *inner = [sender isKindOfClass:SCIChromeButton.class] ? sender : SCIChromeButtonForBarItem(item);

	dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;

	NSString *icon = dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill";
	UIColor *tint = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : SCIUtils.SCIColor_Primary;

	if (inner) {
		[inner setIconResource:icon pointSize:18];
		inner.iconTint = tint;
	} else {
		item.image = [SCIIcon imageNamed:icon];
		item.tintColor = tint;
	}

	SCINotifySuccess(SCI_NOTIF_SEEN_DM,
		dmVisualMsgsViewedButtonEnabled ? SCILocalized(@"Visual messages will expire") : SCILocalized(@"Unlimited replay enabled"),
		nil);
}

%end

#pragma mark - Seen Blocking

%hook IGDirectThreadViewListAdapterDataSource

- (BOOL)shouldUpdateLastSeenMessage {
	if (!SCIReadReceiptsOn()) return %orig;
	if ([SCIExcludedThreads isActiveThreadExcluded]) return %orig;
	if (SCISeenToggleMode() && dmSeenToggleEnabled) return %orig;
	if (sSeenBypass > 0) return %orig;

	return NO;
}

%end

#pragma mark - Visual Messages

static inline BOOL SCIBlockVisualSeen(void) {
	return [SCIUtils getBoolPref:@"unlimited_replay"] &&
		   !dmVisualMsgsViewedButtonEnabled &&
		   ![SCIExcludedThreads isActiveThreadExcluded];
}

%hook IGDirectVisualMessageViewerEventHandler

- (void)visualMessageViewerController:(id)controller didBeginPlaybackForVisualMessage:(id)message atIndex:(long long)index {
	if (SCIBlockVisualSeen()) return;
	%orig;
}

- (void)visualMessageViewerController:(id)controller didEndPlaybackForVisualMessage:(id)message atIndex:(long long)index mediaCurrentTime:(double)time forNavType:(long long)type {
	if (SCIBlockVisualSeen()) return;
	%orig;
}

%end

#pragma mark - Runtime Hooks

%ctor {
	Class cls = NSClassFromString(@"IGDirectThreadViewFeatureManager");
	if (!cls) return;

	SEL sent = @selector(setHasSentAMessageOrUpdate:);
	if (class_getInstanceMethod(cls, sent)) {
		MSHookMessageEx(cls, sent, (IMP)new_setHasSent, (IMP *)&orig_setHasSent);
	}
}