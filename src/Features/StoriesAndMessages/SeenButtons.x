#import "../../InstagramHeaders.h"
#import "../../Tweak.h"
#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import "RYGExcludedThreads.h"
#import "RYGDMLocalSeen.h"

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

static inline void RYGArmShareGuard(void) { sShareArmedAt = NSProcessInfo.processInfo.systemUptime; }
static inline void RYGDisarmShareGuard(void) { sShareArmedAt = 0; }

static BOOL RYGShareGuardActive(void) {
	if (sShareArmedAt <= 0) return NO;
	if (NSProcessInfo.processInfo.systemUptime - sShareArmedAt > kShareGuardWindow) { sShareArmedAt = 0; return NO; }
	return YES;
}

#pragma mark - Runtime Helpers

static inline BOOL RYGResponds(id obj, SEL sel) {
	return obj && [obj respondsToSelector:sel];
}

static inline id RYGGetIvar(id obj, const char *name) {
	return obj ? [RYGUtils getIvarForObj:obj name:name] : nil;
}

static inline id RYGObj(id obj, SEL sel) {
	return RYGResponds(obj, sel) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static inline NSString *RYGString(id obj) {
	return obj ? [NSString stringWithFormat:@"%@", obj] : nil;
}

static inline BOOL RYGSeenToggleMode(void) {
	return [[RYGUtils getStringPref:@"seen_mode"] isEqualToString:@"toggle"];
}

static inline BOOL RYGReadReceiptsOn(void) {
	return [RYGUtils getBoolPref:@"remove_lastseen"];
}

static NSString *RYGThreadId(id vc) {
	id tid = RYGObj(vc, @selector(threadId));
	return [tid isKindOfClass:NSString.class] ? tid : RYGString(tid);
}

static id RYGThreadVCForManager(id manager) {
	id vc = RYGGetIvar(manager, "_vc");
	Class cls = NSClassFromString(@"IGDirectThreadViewController");

	return (cls && [vc isKindOfClass:cls]) ? vc : nil;
}

static id RYGManagerForThreadVC(id vc) {
	return RYGGetIvar(vc, "_featureManager");
}

static id RYGThreadVCForAnchor(UIView *view) {
	id vc = [RYGUtils nearestViewControllerForView:view];
	Class cls = NSClassFromString(@"IGDirectThreadViewController");

	return (cls && [vc isKindOfClass:cls]) ? vc : nil;
}

static BOOL RYGAutoInteractEnabled(NSString *threadId) {
	return RYGReadReceiptsOn() &&
		   [RYGUtils getBoolPref:@"seen_auto_on_interact"] &&
		   threadId.length &&
		   ![RYGExcludedThreads isThreadIdExcluded:threadId];
}

BOOL rygAutoTypingEnabled(void) {
	return RYGReadReceiptsOn() &&
		   [RYGUtils getBoolPref:@"seen_auto_on_typing"] &&
		   ![RYGExcludedThreads isActiveThreadExcluded];
}

// Not gated on active/visible — a reel detaches the thread VC and leaving mid-send flips
// visible off. Only shares are filtered, via the share guard.
static BOOL RYGShouldAutoSeen(id manager) {
	id vc = RYGThreadVCForManager(manager);
	NSString *tid = RYGThreadId(vc);

	if (!vc || !RYGAutoInteractEnabled(tid)) return NO;
	if (sShareDepth > 0 || RYGShareGuardActive()) return NO;

	return YES;
}

#pragma mark - Mark Seen

static BOOL RYGMarkSeen(id vcOrManager) {
	if (!vcOrManager) return NO;

	dispatch_async(dispatch_get_main_queue(), ^{
		id target = RYGResponds(vcOrManager, @selector(markLastMessageAsSeen))
			? vcOrManager
			: RYGManagerForThreadVC(vcOrManager);

		if (!RYGResponds(target, @selector(markLastMessageAsSeen))) return;

		@try {
			((void (*)(id, SEL))objc_msgSend)(target, @selector(markLastMessageAsSeen));

			if ([RYGUtils getBoolPref:@"dm_local_seen"]) {
				id vc = (target == vcOrManager) ? RYGThreadVCForManager(target) : vcOrManager;
				NSString *tid = RYGThreadId(vc);
				if (tid.length) [RYGDMLocalSeen recordServerSeenThreadId:tid ts:NSDate.date.timeIntervalSince1970];
			}
		} @catch (__unused id e) {}
	});

	return YES;
}

void rygDoAutoSeen(id threadVC) {
	if (!threadVC) return;

	sSeenBypass++;
	RYGMarkSeen(threadVC);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (sSeenBypass > 0) sSeenBypass--;
	});
}

void rygDoAutoSeenActiveThread(void) {
	rygDoAutoSeen(sActiveThreadVC);
}

static void RYGAutoSeenLater(id manager) {
	id vc = RYGThreadVCForManager(manager);
	NSString *tid = RYGThreadId(vc);
	if (!vc) return;

	// Strong-capture vc so a thread we just left still gets its receipt; defer lets the send register.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (!RYGAutoInteractEnabled(tid)) return;
		rygDoAutoSeen(vc);
	});
}

// Marks the active thread. For paths setHasSentAMessageOrUpdate: misses: voice notes and
// media send-initiation (uploads in the background, so the flag never fires on swipe-back).
void rygMarkActiveThreadSeenOnInteract(void) {
	id mgr = RYGManagerForThreadVC(sActiveThreadVC);
	if (mgr && RYGShouldAutoSeen(mgr)) RYGAutoSeenLater(mgr);
}

static void RYGConfirmMarkSeen(UIViewController *presenter, void (^block)(void)) {
	[RYGUtils confirmIfNeeded:[RYGUtils getBoolPref:@"confirm_mark_seen_dm"]
						 title:RYGLocalized(@"Mark as seen?")
					   message:RYGLocalized(@"This will send a read receipt for the latest messages.")
				  confirmTitle:RYGLocalized(@"Mark seen")
						  from:presenter
					 onConfirm:block
					  onCancel:nil];
}

#pragma mark - Send Hooks

// Send completion for things shown while the thread is open (reactions, reel quick-reacts).
static void (*orig_setHasSent)(id self, SEL _cmd, BOOL sent);
static void new_setHasSent(id self, SEL _cmd, BOOL sent) {
	BOOL should = sent && RYGShouldAutoSeen(self);
	orig_setHasSent(self, _cmd, sent);
	if (should) RYGAutoSeenLater(self);
}

// Send-initiation: fires the instant you tap send, so media marks even if you swipe back before it uploads.
%hook _TtC45IGDirectThreadMessageSenderListenerController45IGDirectThreadMessageSenderListenerController

- (void)outgoingMessagePayloadWillSend:(id)payload {
	%orig;
	rygMarkActiveThreadSeenOnInteract();
}

%end

#pragma mark - Active Thread

%hook IGDirectThreadViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig;

	sShareDepth = 0;
	RYGDisarmShareGuard();
	sActiveThreadVC = self;
	[RYGExcludedThreads setActiveThreadId:RYGThreadId(self) viewerPK:[RYGUtils currentUserPK]];
}

- (void)viewDidDisappear:(BOOL)animated {
	if (sActiveThreadVC == self) {
		sActiveThreadVC = nil;
		[RYGExcludedThreads setActiveThreadId:nil];
	}

	%orig;
}

%end

#pragma mark - Share Sheet Guard

%hook IGDirectShareSheetController

- (id)presentShareSheetWithOverlayView:(BOOL)view directRecipientConfiguration:(id)configuration config:(id)config {
	sShareDepth++;
	RYGArmShareGuard();
	return %orig;
}

- (id)presentShareSheetWithShortcutRecipients:(id)recipients showOverlayView:(BOOL)view directRecipientConfiguration:(id)configuration config:(id)config {
	sShareDepth++;
	RYGArmShareGuard();
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

static void RYGRefreshNav(UIView *view) {
	if (!RYGResponds(view, @selector(setRightBarButtonItems:))) return;

	NSArray *items = RYGObj(view, @selector(rightBarButtonItems)) ?: @[];
	((void (*)(id, SEL, id))objc_msgSend)(view, @selector(setRightBarButtonItems:), items);
}

static UIWindow *RYGWindow(UIView *view, UIWindow *fallback) {
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

static NSDictionary *RYGEntryForThreadVC(id vc) {
	NSString *tid = RYGThreadId(vc);
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

static void RYGOpenSettings(UIView *view, UIWindow *window) {
	UIWindow *win = RYGWindow(view, window);
	if (win) [RYGUtils showSettingsVC:win atTopLevelEntry:RYGLocalized(@"Messages")];
}

static UIAction *RYGAction(NSString *title, id image, void (^handler)(__kindof UIAction *action)) {
	return [UIAction actionWithTitle:title image:image identifier:nil handler:handler];
}

static UIMenu *RYGBuildMenu(UIView *anchor, NSString *threadId, UIWindow *window) {
	BOOL inList = threadId.length && [RYGExcludedThreads isInList:threadId];
	BOOL excluded = threadId.length && [RYGExcludedThreads isThreadIdExcluded:threadId];
	BOOL blockMode = [RYGExcludedThreads isBlockSelectedMode];

	NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
	__weak UIView *weakAnchor = anchor;

	if (RYGReadReceiptsOn() && !excluded) {
		if (RYGSeenToggleMode()) {
			NSString *title = dmSeenToggleEnabled ? RYGLocalized(@"Disable read receipts") : RYGLocalized(@"Enable read receipts");

			UIAction *toggle = RYGAction(title, [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"], ^(__kindof UIAction *_) {
				dmSeenToggleEnabled = !dmSeenToggleEnabled;

				if (dmSeenToggleEnabled) {
					RYGMarkSeen(RYGThreadVCForAnchor(weakAnchor));
				}

				RYGNotifySuccess(RYG_NOTIF_SEEN_DM,
					dmSeenToggleEnabled ? RYGLocalized(@"Read receipts enabled") : RYGLocalized(@"Read receipts disabled"),
					nil);

				RYGRefreshNav(weakAnchor);
			});

			toggle.state = dmSeenToggleEnabled ? UIMenuElementStateOn : UIMenuElementStateOff;
			[items addObject:toggle];
		}

		[items addObject:RYGAction(RYGLocalized(@"Mark messages as seen"), [RYGIcon imageNamed:@"eye"], ^(__kindof UIAction *_) {
			UIViewController *presenter = weakAnchor ? [RYGUtils nearestViewControllerForView:weakAnchor] : nil;

			RYGConfirmMarkSeen(presenter, ^{
				if (RYGMarkSeen(RYGThreadVCForAnchor(weakAnchor))) {
					RYGNotifySuccess(RYG_NOTIF_SEEN_DM, RYGLocalized(@"Marked messages as seen"), nil);
				}
			});
		})];
	}

	NSString *addTitle = blockMode ? RYGLocalized(@"Add to block list") : RYGLocalized(@"Exclude chat");
	NSString *removeTitle = blockMode ? RYGLocalized(@"Remove from block list") : RYGLocalized(@"Un-exclude chat");

	UIAction *list = RYGAction(inList ? removeTitle : addTitle, [RYGIcon imageNamed:(inList ? @"eye.fill" : @"eye.slash")], ^(__kindof UIAction *_) {
		if (!threadId.length) return;

		id vc = RYGThreadVCForAnchor(weakAnchor);

		if (inList) {
			[RYGExcludedThreads removeThreadId:threadId];

			RYGNotifySuccess(blockMode ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_CHAT,
				blockMode ? RYGLocalized(@"Unblocked") : RYGLocalized(@"Un-excluded"),
				nil);

			if (blockMode) RYGMarkSeen(vc);
		} else {
			[RYGExcludedThreads addOrUpdateEntry:RYGEntryForThreadVC(vc) ?: @{
				@"threadId": threadId,
				@"threadName": @"",
				@"isGroup": @NO,
				@"users": @[]
			}];

			RYGNotifySuccess(blockMode ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_CHAT,
				blockMode ? RYGLocalized(@"Blocked") : RYGLocalized(@"Excluded"),
				nil);

			if (!blockMode) RYGMarkSeen(vc);
		}

		RYGRefreshNav(weakAnchor);
	});

	if (excluded) list.attributes = UIMenuElementAttributesDestructive;
	[items addObject:list];

	if ([RYGUtils getBoolPref:@"unlimited_replay"] && !excluded) {
		NSString *title = dmVisualMsgsViewedButtonEnabled
			? RYGLocalized(@"Visual messages: expiring")
			: RYGLocalized(@"Visual messages: unlimited replay");

		NSString *icon = dmVisualMsgsViewedButtonEnabled
			? @"photo.badge.checkmark"
			: @"photo.badge.checkmark.fill";

		UIAction *replay = RYGAction(title, [RYGIcon imageNamed:icon], ^(__kindof UIAction *_) {
			dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;

			RYGNotifySuccess(RYG_NOTIF_SEEN_DM,
				dmVisualMsgsViewedButtonEnabled ? RYGLocalized(@"Visual messages will expire") : RYGLocalized(@"Unlimited replay enabled"),
				nil);

			RYGRefreshNav(weakAnchor);
		});

		replay.state = dmVisualMsgsViewedButtonEnabled ? UIMenuElementStateOff : UIMenuElementStateOn;
		[items addObject:replay];
	}

	[items addObject:RYGAction(RYGLocalized(@"Messages settings"), [UIImage systemImageNamed:@"gear"], ^(__kindof UIAction *_) {
		RYGOpenSettings(weakAnchor, window);
	})];

	return [UIMenu menuWithTitle:@"" children:items];
}

static UIBarButtonItem *RYGChromeItem(NSString *aid, NSString *icon, CGFloat size, UIColor *tint, id target, SEL action, UIMenu *menu) {
	RYGChromeButton *inner = nil;
	UIBarButtonItem *item = RYGChromeBarButtonItem(@"", size, target, action, &inner);

	item.accessibilityIdentifier = aid;
	[inner setIconResource:icon pointSize:size];
	inner.iconTint = tint ?: UIColor.labelColor;
	inner.menu = menu;

	return item;
}

#pragma mark - Server-pending Indicator

static __weak RYGChromeButton *sSeenIndicatorButton = nil;
static NSString *sSeenIndicatorThreadId = nil;

static void RYGUpdateSeenIndicator(void) {
	RYGChromeButton *btn = sSeenIndicatorButton;
	if (!btn) return;

	BOOL pending = [RYGUtils getBoolPref:@"dm_local_seen"]
		&& RYGReadReceiptsOn()
		&& sSeenIndicatorThreadId.length
		&& [RYGDMLocalSeen isServerPendingForThreadId:sSeenIndicatorThreadId];

	[btn setIconResource:@"eye" pointSize:22];
	btn.iconTint = pending
		? [UIColor colorWithRed:1.0 green:0.584 blue:0.0 alpha:1.0]
		: ((RYGSeenToggleMode() && dmSeenToggleEnabled) ? RYGUtils.RYGColor_Primary : UIColor.labelColor);
}

static void RYGAttachSeenIndicator(RYGChromeButton *inner, NSString *tid) {
	sSeenIndicatorButton = inner;
	sSeenIndicatorThreadId = [tid copy];
	dispatch_async(dispatch_get_main_queue(), ^{ RYGUpdateSeenIndicator(); });
}

static BOOL RYGShouldSkipNativeItem(UIBarButtonItem *item) {
	NSString *aid = item.accessibilityIdentifier;

	if ([aid isEqualToString:@"ryg-seen-btn"] ||
		[aid isEqualToString:@"ryg-unex-btn"] ||
		[aid isEqualToString:@"ryg-visual-btn"]) {
		return YES;
	}

	if ([RYGUtils getBoolPref:@"hide_reels_blend"] && [aid isEqualToString:@"blend-button"]) {
		return YES;
	}

	UIView *view = item.customView;
	Class callCls = NSClassFromString(@"IGDirectCallButton");

	if (view && callCls && [view isKindOfClass:callCls]) {
		NSString *cvAid = view.accessibilityIdentifier;

		if ([RYGUtils getBoolPref:@"hide_voice_call_button"] && [cvAid isEqualToString:@"audio-call"]) return YES;
		if ([RYGUtils getBoolPref:@"hide_video_call_button"] && [cvAid isEqualToString:@"video-chat"]) return YES;
	}

	return NO;
}

#pragma mark - Navigation Buttons

%hook IGTallNavigationBarView

%new - (void)rygAddToListHandler:(id)sender {
	id vc = RYGThreadVCForAnchor(self);
	NSDictionary *entry = RYGEntryForThreadVC(vc);
	if (!entry) return;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Add to block list")
																   message:RYGLocalized(@"Read receipts will be blocked for this chat.")
															preferredStyle:UIAlertControllerStyleAlert];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *_) {
		[RYGExcludedThreads addOrUpdateEntry:entry];
		RYGNotifySuccess(RYG_NOTIF_BLOCK_TOGGLE, RYGLocalized(@"Added to block list"), nil);
		RYGRefreshNav(weakSelf);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	if ([vc respondsToSelector:@selector(presentViewController:animated:completion:)]) {
		[(UIViewController *)vc presentViewController:alert animated:YES completion:nil];
	}
}

%new - (void)rygUnexcludeButtonHandler:(id)sender {
	id vc = RYGThreadVCForAnchor(self);
	NSString *tid = RYGThreadId(vc);
	if (!tid.length) return;

	BOOL blockMode = [RYGExcludedThreads isBlockSelectedMode];

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:(blockMode ? RYGLocalized(@"Remove from block list") : RYGLocalized(@"Un-exclude chat"))
																   message:(blockMode ? RYGLocalized(@"Read receipts will no longer be blocked for this chat.") : RYGLocalized(@"This chat will resume normal read-receipt behavior."))
															preferredStyle:UIAlertControllerStyleAlert];

	__weak typeof(self) weakSelf = self;

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Remove") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *_) {
		[RYGExcludedThreads removeThreadId:tid];
		RYGNotifySuccess(RYG_NOTIF_EXCLUDE_CHAT, RYGLocalized(@"Removed"), nil);
		RYGRefreshNav(weakSelf);
	}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	if ([vc respondsToSelector:@selector(presentViewController:animated:completion:)]) {
		[(UIViewController *)vc presentViewController:alert animated:YES completion:nil];
	}
}

- (void)setRightBarButtonItems:(NSArray<UIBarButtonItem *> *)items {
	NSMutableArray *out = [NSMutableArray array];

	for (UIBarButtonItem *item in items ?: @[]) {
		if (!RYGShouldSkipNativeItem(item)) [out addObject:item];
	}

	id vc = RYGThreadVCForAnchor(self);
	NSString *tid = RYGThreadId(vc);
	BOOL excluded = tid.length && [RYGExcludedThreads isThreadIdExcluded:tid];
	BOOL inList = tid.length && [RYGExcludedThreads isInList:tid];
	BOOL blockMode = [RYGExcludedThreads isBlockSelectedMode];

	UIMenu *menu = RYGBuildMenu(self, tid, self.window);

	if (RYGReadReceiptsOn() && !excluded && [RYGUtils getBoolPref:@"show_dm_seen_button"]) {
		UIColor *tint = (RYGSeenToggleMode() && dmSeenToggleEnabled) ? RYGUtils.RYGColor_Primary : UIColor.labelColor;
		UIBarButtonItem *seenItem = RYGChromeItem(@"ryg-seen-btn", @"eye", 22, tint, self, @selector(seenButtonHandler:), menu);
		[out addObject:seenItem];
		RYGAttachSeenIndicator(RYGChromeButtonForBarItem(seenItem), tid);
	}

	BOOL showListButton = RYGReadReceiptsOn() && [RYGUtils getBoolPref:@"chat_quick_list_button"];
	BOOL showRemove = !blockMode && inList && excluded;
	BOOL showAdd = blockMode && !inList;

	if (showListButton && (showRemove || showAdd)) {
		NSString *icon = showRemove ? @"eye.slash.fill" : @"eye.slash";
		UIColor *tint = showRemove ? RYGUtils.RYGColor_Primary : UIColor.labelColor;
		SEL action = showRemove ? @selector(rygUnexcludeButtonHandler:) : @selector(rygAddToListHandler:);

		[out addObject:RYGChromeItem(@"ryg-unex-btn", icon, 18, tint, self, action, menu)];
	}

	if ([RYGUtils getBoolPref:@"unlimited_replay"] && !excluded && !RYGReadReceiptsOn()) {
		NSString *icon = dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill";
		UIColor *tint = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : RYGUtils.RYGColor_Primary;

		[out addObject:RYGChromeItem(@"ryg-visual-btn", icon, 18, tint, self, @selector(rygReplayToggleHandler:), nil)];
	}

	%orig([out copy]);
}

%new - (void)seenButtonHandler:(id)sender {
	UIBarButtonItem *item = [sender isKindOfClass:UIBarButtonItem.class] ? sender : nil;
	RYGChromeButton *inner = [sender isKindOfClass:RYGChromeButton.class] ? sender : RYGChromeButtonForBarItem(item);

	if (RYGSeenToggleMode()) {
		dmSeenToggleEnabled = !dmSeenToggleEnabled;

		UIColor *tint = dmSeenToggleEnabled ? RYGUtils.RYGColor_Primary : UIColor.labelColor;
		if (inner) inner.iconTint = tint;
		else item.tintColor = tint;

		if (dmSeenToggleEnabled) {
			RYGMarkSeen(RYGThreadVCForAnchor(self));
		}

		RYGNotifySuccess(RYG_NOTIF_SEEN_DM,
			dmSeenToggleEnabled ? RYGLocalized(@"Read receipts enabled") : RYGLocalized(@"Read receipts disabled"),
			nil);
	} else {
		__weak UIView *weakSelf = self;

		RYGConfirmMarkSeen([RYGUtils nearestViewControllerForView:self], ^{
			if (RYGMarkSeen(RYGThreadVCForAnchor(weakSelf))) {
				RYGNotifySuccess(RYG_NOTIF_SEEN_DM, RYGLocalized(@"Marked messages as seen"), nil);
			}
		});
	}

	NSString *tid = RYGThreadId(RYGThreadVCForAnchor(self));
	UIMenu *menu = RYGBuildMenu(self, tid, self.window);

	if (inner) inner.menu = menu;
	else item.menu = menu;
}

%new - (void)rygReplayToggleHandler:(id)sender {
	UIBarButtonItem *item = [sender isKindOfClass:UIBarButtonItem.class] ? sender : nil;
	RYGChromeButton *inner = [sender isKindOfClass:RYGChromeButton.class] ? sender : RYGChromeButtonForBarItem(item);

	dmVisualMsgsViewedButtonEnabled = !dmVisualMsgsViewedButtonEnabled;

	NSString *icon = dmVisualMsgsViewedButtonEnabled ? @"photo.badge.checkmark" : @"photo.badge.checkmark.fill";
	UIColor *tint = dmVisualMsgsViewedButtonEnabled ? UIColor.labelColor : RYGUtils.RYGColor_Primary;

	if (inner) {
		[inner setIconResource:icon pointSize:18];
		inner.iconTint = tint;
	} else {
		item.image = [RYGIcon imageNamed:icon];
		item.tintColor = tint;
	}

	RYGNotifySuccess(RYG_NOTIF_SEEN_DM,
		dmVisualMsgsViewedButtonEnabled ? RYGLocalized(@"Visual messages will expire") : RYGLocalized(@"Unlimited replay enabled"),
		nil);
}

%end

#pragma mark - Seen Blocking

%hook IGDirectThreadViewListAdapterDataSource

- (BOOL)shouldUpdateLastSeenMessage {
	BOOL allowed = !RYGReadReceiptsOn()
		|| [RYGExcludedThreads isActiveThreadExcluded]
		|| (RYGSeenToggleMode() && dmSeenToggleEnabled)
		|| sSeenBypass > 0;
	if (!allowed) return NO;

	BOOL r = %orig;
	if (r && [RYGUtils getBoolPref:@"dm_local_seen"]) {
		NSString *tid = [RYGExcludedThreads activeThreadId];
		if (tid.length) [RYGDMLocalSeen recordServerSeenThreadId:tid ts:NSDate.date.timeIntervalSince1970];
	}
	return r;
}

%end

#pragma mark - Visual Messages

static inline BOOL RYGBlockVisualSeen(void) {
	return [RYGUtils getBoolPref:@"unlimited_replay"] &&
		   !dmVisualMsgsViewedButtonEnabled &&
		   ![RYGExcludedThreads isActiveThreadExcluded];
}

%hook IGDirectVisualMessageViewerEventHandler

- (void)visualMessageViewerController:(id)controller didBeginPlaybackForVisualMessage:(id)message atIndex:(long long)index {
	if (RYGBlockVisualSeen()) return;
	%orig;
}

- (void)visualMessageViewerController:(id)controller didEndPlaybackForVisualMessage:(id)message atIndex:(long long)index mediaCurrentTime:(double)time forNavType:(long long)type {
	if (RYGBlockVisualSeen()) return;
	%orig;
}

%end

#pragma mark - Runtime Hooks

%ctor {
	[NSNotificationCenter.defaultCenter addObserverForName:RYGDMSeenStateDidChangeNotification
													object:nil
													 queue:NSOperationQueue.mainQueue
												usingBlock:^(__unused NSNotification *note) { RYGUpdateSeenIndicator(); }];

	Class cls = NSClassFromString(@"IGDirectThreadViewFeatureManager");
	if (!cls) return;

	SEL sent = @selector(setHasSentAMessageOrUpdate:);
	if (class_getInstanceMethod(cls, sent)) {
		MSHookMessageEx(cls, sent, (IMP)new_setHasSent, (IMP *)&orig_setHasSent);
	}
}