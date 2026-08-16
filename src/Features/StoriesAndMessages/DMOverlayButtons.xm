// DM disappearing-media overlay buttons — action / eye / audio (tags 1342–1344).
// Hooks IGDirectVisualMessageViewerController directly; reads only dm_visual_* prefs.

#import "OverlayHelpers.h"
#import "RYGDMButtonLayout.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import "../../ActionButton/RYGActionIcon.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../ActionButton/RYGActionMenu.h"
#import "../../ActionButton/RYGActionMenuConfig.h"
#import "../../ActionButton/RYGActionCatalog.h"

// Per-button weak ref to the owning DM VC so handlers skip the responder walk.
static const void *kRYGDMOwnerVCKey = &kRYGDMOwnerVCKey;
static char kDMActionDefaultKey;

static inline BOOL RYGDMActionEnabled(void) {return [RYGUtils getBoolPref:@"dm_visual_action_button"];}

static inline BOOL RYGDMEyeEnabled(void) {return [RYGUtils getBoolPref:@"dm_visual_seen_button"];}

static inline NSString *RYGDMDefaultAction(void) {
	return [RYGUtils getStringPref:@"dm_visual_action_default"];
}

static inline RYGChromeButton *RYGDMButton(NSString *symbol, CGFloat pointSize, CGFloat diameter, NSInteger tag) {
	RYGChromeButton *button = [[RYGChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:diameter];
	button.tag = tag;
	return button;
}

static inline void RYGDMRemoveButton(UIView *overlay, NSInteger tag) {
	[[overlay viewWithTag:tag] removeFromSuperview];
}

static NSString *rygDMIDForTag(NSInteger tag) {
	if (tag == RYG_DM_ACTION_TAG) return RYGDMBtnAction;
	if (tag == RYG_DM_EYE_TAG) return RYGDMBtnEye;
	if (tag == RYG_DM_AUDIO_TAG) return RYGDMBtnAudio;
	return nil;
}

// Hidden while a comment sheet / keyboard is up (IG shrinks the overlay safe area).
static BOOL rygDMButtonsKbHidden = NO;
static __weak UIView *rygCurrentDMOverlay = nil;

// Frame-positions each present button at its saved normalized point in the safe area.
static void rygDMLayoutButtons(UIView *overlay) {
	CGRect safe = overlay.safeAreaLayoutGuide.layoutFrame;
	if (safe.size.width <= 0 || safe.size.height <= 0) return;
	rygCurrentDMOverlay = overlay;

	UIEdgeInsets ins = [RYGDMButtonLayout placeableInsetsNormalized];
	CGRect area = CGRectMake(safe.origin.x + ins.left * safe.size.width,
							 safe.origin.y + ins.top * safe.size.height,
							 safe.size.width * (1.0 - ins.left - ins.right),
							 safe.size.height * (1.0 - ins.top - ins.bottom));

	NSInteger tags[] = { RYG_DM_ACTION_TAG, RYG_DM_EYE_TAG, RYG_DM_AUDIO_TAG };

	NSMutableArray<NSString *> *presentIDs = NSMutableArray.array;
	for (NSUInteger i = 0; i < 3; i++) {
		if ([overlay viewWithTag:tags[i]]) [presentIDs addObject:rygDMIDForTag(tags[i])];
	}
	NSDictionary<NSString *, NSValue *> *resolved = [RYGDMButtonLayout resolvedPositionsForIDs:presentIDs inSize:safe.size];

	for (NSUInteger i = 0; i < 3; i++) {
		UIView *button = [overlay viewWithTag:tags[i]];
		if (!button) continue;

		if (rygDMButtonsKbHidden) { button.hidden = YES; continue; }
		button.hidden = NO;

		NSString *bid = rygDMIDForTag(tags[i]);
		CGFloat d = [RYGDMButtonLayout diameterForID:bid];
		CGPoint norm = resolved[bid] ? resolved[bid].CGPointValue : [RYGDMButtonLayout positionForID:bid];

		CGFloat half = d / 2.0;
		CGFloat cx = safe.origin.x + norm.x * safe.size.width;
		CGFloat cy = safe.origin.y + norm.y * safe.size.height;
		cx = MIN(MAX(cx, CGRectGetMinX(area) + half), CGRectGetMaxX(area) - half);
		cy = MIN(MAX(cy, CGRectGetMinY(area) + half), CGRectGetMaxY(area) - half);

		button.bounds = CGRectMake(0, 0, d, d);
		button.center = CGPointMake(cx, cy);
	}
}

// MARK: - Menu item builders

static void rygDMConfirmMarkViewed(UIViewController *dmVC, void (^onConfirm)(void)) {
	[RYGUtils confirmIfNeeded:[RYGUtils getBoolPref:@"confirm_mark_seen_dm_visual"]
	                    title:RYGLocalized(@"Mark as viewed?")
	                  message:RYGLocalized(@"This will send a view receipt for the current message.")
	             confirmTitle:RYGLocalized(@"Mark as viewed")
	                     from:dmVC
	                onConfirm:onConfirm
	                 onCancel:nil];
}

static NSArray<UIMenuElement *> *rygDMActionMenuItems(UIViewController *dmVC, UIView *sourceView) {
	__weak UIView *weakSource = sourceView;
	__weak UIViewController *weakVC = dmVC;

	RYGActionMenuConfig *cfg = [RYGActionMenuConfig configForSource:RYGActionSourceDM];

	RYGAction *(^resolve)(NSString *) = ^RYGAction *(NSString *aid) {
		if ([aid isEqualToString:RYGAID_Expand]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Expand") icon:@"bcn_arrow-expand_outline_24" handler:^{
				if (weakVC) rygDMExpandMedia(weakVC);
			}];
		}
		if ([aid isEqualToString:RYGAID_DownloadShare]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Download and share") icon:@"square.and.arrow.up" handler:^{
				if (weakVC) rygDMShareMedia(weakVC);
			}];
		}
		if ([aid isEqualToString:RYGAID_DownloadSave]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Download to Photos") icon:@"square.and.arrow.down" handler:^{
				if (weakVC) rygDMDownloadMedia(weakVC);
			}];
		}
		if ([aid isEqualToString:RYGAID_DownloadGallery]) {
			if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;
			return [RYGAction actionWithTitle:RYGLocalized(@"Download to Gallery") icon:@"ig_icon_photo_gallery_prism_outline_24" handler:^{
				if (weakVC) rygDMDownloadMediaToGallery(weakVC);
			}];
		}
		if ([aid isEqualToString:RYGAID_DMMarkSeen]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Mark as viewed") icon:@"ig_icon_eye_filled_24" handler:^{
				UIViewController *strongVC = weakVC;
				rygDMConfirmMarkViewed(strongVC, ^{
					if (strongVC) rygDMMarkCurrentAsViewed(strongVC);
				});
			}];
		}
		if ([aid isEqualToString:RYGAID_Settings]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Messages settings") icon:@"ig_icon_settings_outline_24" handler:^{
				rygOpenMessagesSettings(weakSource);
			}];
		}
		return nil;
	};

	NSArray<RYGAction *> *flat = [RYGActionMenu actionsForConfig:cfg dateHeader:nil resolver:resolve];
	UIMenu *built = [RYGActionMenu buildMenuWithActions:flat];
	return built.children;
}

static NSArray<UIMenuElement *> *rygDMEyeMenuItems(UIViewController *dmVC, UIView *sourceView) {
	__weak UIView *weakSource = sourceView;
	__weak UIViewController *weakDMVC = dmVC;

	return @[
		[UIAction actionWithTitle:RYGLocalized(@"Mark as viewed") image:[RYGIcon menuImageNamed:@"ig_icon_eye_filled_24" pointSize:18] identifier:nil handler:^(__unused UIAction *a) {
			UIViewController *strongDMVC = weakDMVC;
			rygDMConfirmMarkViewed(strongDMVC, ^{
				rygDMMarkCurrentAsViewed(strongDMVC);
			});
		}],
		[UIAction actionWithTitle:RYGLocalized(@"Messages settings") image:[RYGIcon menuImageNamed:@"ig_icon_settings_outline_24" pointSize:18] identifier:nil handler:^(__unused UIAction *a) {
			rygOpenMessagesSettings(weakSource);
		}]
	];
}

static void rygDMApplyTapMenu(UIButton *button, __weak UIViewController *weakDMVC) {
	__weak UIButton *weakButton = button;

	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
		UIViewController *dmVC = weakDMVC;
		UIButton *strongButton = weakButton;

		if (!dmVC || !strongButton) {
			completion(@[]);
			return;
		}

		completion(rygDMActionMenuItems(dmVC, strongButton));
	}];

	button.menu = [UIMenu menuWithChildren:@[deferred]];
	button.showsMenuAsPrimaryAction = YES;
}

// MARK: - Button delegate

@interface RYGDMButtonDelegate : NSObject
+ (instancetype)shared;
- (void)actionTapped:(UIButton *)sender;
- (void)eyeTapped:(UIButton *)sender;
- (void)audioTapped:(RYGChromeButton *)sender;
@end

@implementation RYGDMButtonDelegate

+ (instancetype)shared {
	static RYGDMButtonDelegate *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [RYGDMButtonDelegate new];
	});
	return shared;
}

- (UIViewController *)ownerForButton:(UIView *)button {
	return objc_getAssociatedObject(button, kRYGDMOwnerVCKey);
}

// Default-tap path when pref is not "menu".
- (void)actionTapped:(UIButton *)sender {
	UIViewController *dmVC = [self ownerForButton:sender];
	if (!dmVC) return;

	NSString *tap = RYGDMDefaultAction();

	// Legacy values from older builds — translate before dispatch.
	if ([tap isEqualToString:@"download_photos"]) tap = RYGAID_DownloadSave;
	if ([tap isEqualToString:@"copy_link"])       tap = RYGAID_CopyURL;

	if ([tap isEqualToString:RYGAID_Expand]) {
		rygDMExpandMedia(dmVC);
	} else if ([tap isEqualToString:RYGAID_DownloadShare]) {
		rygDMShareMedia(dmVC);
	} else if ([tap isEqualToString:RYGAID_DownloadSave]) {
		rygDMDownloadMedia(dmVC);
	} else if ([tap isEqualToString:RYGAID_DownloadGallery]) {
		rygDMDownloadMediaToGallery(dmVC);
	} else if ([tap isEqualToString:RYGAID_DMMarkSeen]) {
		rygDMConfirmMarkViewed(dmVC, ^{
			rygDMMarkCurrentAsViewed(dmVC);
		});
	}
}

- (void)eyeTapped:(UIButton *)sender {
	UIViewController *dmVC = [self ownerForButton:sender];
	if (!dmVC) return;

	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[haptic impactOccurred];

	[UIView animateWithDuration:0.1 animations:^{
		sender.transform = CGAffineTransformMakeScale(0.8, 0.8);
		sender.alpha = 0.6;
	} completion:^(__unused BOOL finished) {
		[UIView animateWithDuration:0.15 animations:^{
			sender.transform = CGAffineTransformIdentity;
			sender.alpha = 1.0;
		}];
	}];

	rygDMConfirmMarkViewed(dmVC, ^{
		rygDMMarkCurrentAsViewed(dmVC);
	});
}

- (void)audioTapped:(RYGChromeButton *)sender {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	rygToggleStoryAudio();
	sender.symbolName = rygIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
}

@end

// MARK: - Long-press menu builder

// UIButton.menu + showsMenuAsPrimaryAction=NO means:
// tap fires default action, long-press shows menu.
static void rygDMAttachLongPressMenu(RYGChromeButton *button, NSInteger tag) {
	__weak RYGChromeButton *weakButton = button;

	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
		RYGChromeButton *strongButton = weakButton;
		UIViewController *dmVC = strongButton ? objc_getAssociatedObject(strongButton, kRYGDMOwnerVCKey) : nil;

		if (!dmVC) {
			completion(@[]);
			return;
		}

		completion(tag == RYG_DM_ACTION_TAG ? rygDMActionMenuItems(dmVC, strongButton) : rygDMEyeMenuItems(dmVC, strongButton));
	}];

	button.menu = [UIMenu menuWithChildren:@[deferred]];
	button.showsMenuAsPrimaryAction = NO;
}

static void rygDMConfigureActionButton(RYGChromeButton *button, UIViewController *dmVC) {
	if (!button || !dmVC) return;

	RYGDMButtonDelegate *delegate = RYGDMButtonDelegate.shared;
	NSString *action = RYGDMDefaultAction();

	button.menu = nil;
	button.showsMenuAsPrimaryAction = NO;

	[button removeTarget:delegate action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];

	if ([action isEqualToString:@"menu"]) {
		rygDMApplyTapMenu(button, dmVC);
	} else {
		// Tap = default action, long-press = full menu.
		[button addTarget:delegate action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
		rygDMAttachLongPressMenu(button, RYG_DM_ACTION_TAG);
	}

	objc_setAssociatedObject(button, &kDMActionDefaultKey, action, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void rygDMRefreshActionIcon(UIViewController *dmVC) {
	if (!dmVC || !dmVC.isViewLoaded) return;

	UIView *overlay = rygFindOverlayInView(dmVC.view);
	RYGChromeButton *button = (RYGChromeButton *)[overlay viewWithTag:RYG_DM_ACTION_TAG];

	if (![button isKindOfClass:RYGChromeButton.class]) return;

	NSString *action = RYGDMDefaultAction();
	NSString *oldAction = objc_getAssociatedObject(button, &kDMActionDefaultKey);

	if (!oldAction || ![oldAction isEqualToString:action]) {
		rygDMConfigureActionButton(button, dmVC);
		return;
	}
}

// MARK: - Overlay injection

static void rygDMInstallButtons(UIViewController *dmVC) {
	if (!dmVC || !dmVC.isViewLoaded) return;

	UIView *overlay = rygFindOverlayInView(dmVC.view);
	if (!overlay) return;

	// Kill any story-tag injections from the shared story overlay hook.
	RYGDMRemoveButton(overlay, RYG_STORY_ACTION_TAG);
	RYGDMRemoveButton(overlay, RYG_STORY_EYE_TAG);
	RYGDMRemoveButton(overlay, RYG_STORY_AUDIO_TAG);

	RYGDMButtonDelegate *delegate = RYGDMButtonDelegate.shared;

	// --- Action button (tag 1342) ---
	RYGDMRemoveButton(overlay, RYG_DM_ACTION_TAG);

	if (RYGDMActionEnabled()) {
		RYGChromeButton *button = RYGDMButton(@"", 18.0, 36.0, RYG_DM_ACTION_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;
		objc_setAssociatedObject(button, kRYGDMOwnerVCKey, dmVC, OBJC_ASSOCIATION_ASSIGN);

		[overlay addSubview:button];
		[RYGActionIcon attachAutoUpdate:button source:RYGActionSourceDM pointSize:18.0 style:RYGActionIconStylePlain];
		rygDMConfigureActionButton(button, dmVC);
	}

	// --- Eye / mark-as-viewed (tag 1343) ---
	RYGDMRemoveButton(overlay, RYG_DM_EYE_TAG);

	if (RYGDMEyeEnabled()) {
		RYGChromeButton *button = RYGDMButton(@"", 18.0, 36.0, RYG_DM_EYE_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;
		[button setIconResource:@"eye" pointSize:18.0]; // IG-styled eye glyph
		objc_setAssociatedObject(button, kRYGDMOwnerVCKey, dmVC, OBJC_ASSOCIATION_ASSIGN);

		[button addTarget:delegate action:@selector(eyeTapped:) forControlEvents:UIControlEventTouchUpInside];
		rygDMAttachLongPressMenu(button, RYG_DM_EYE_TAG);

		[overlay addSubview:button];
	}

	// --- Audio toggle (tag 1344) ---
	RYGDMRemoveButton(overlay, RYG_DM_AUDIO_TAG);

	rygInitStoryAudioState();

	if ([RYGUtils getBoolPref:@"dm_visual_audio_toggle"]) {
		NSString *symbol = rygIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
		RYGChromeButton *button = RYGDMButton(symbol, 14.0, 28.0, RYG_DM_AUDIO_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;

		[button addTarget:delegate action:@selector(audioTapped:) forControlEvents:UIControlEventTouchUpInside];
		[overlay addSubview:button];
	}

	rygDMLayoutButtons(overlay);
}

// Rebuild only when an enabled button is missing.
// Action default only refreshes the action icon/behavior.
static void rygDMEnsureButtons(UIViewController *dmVC) {
	if (!dmVC || !dmVC.isViewLoaded) return;

	UIView *overlay = rygFindOverlayInView(dmVC.view);
	if (!overlay) return;

	RYGDMRemoveButton(overlay, RYG_STORY_ACTION_TAG);
	RYGDMRemoveButton(overlay, RYG_STORY_EYE_TAG);
	RYGDMRemoveButton(overlay, RYG_STORY_AUDIO_TAG);

	BOOL needAction = RYGDMActionEnabled() && ![overlay viewWithTag:RYG_DM_ACTION_TAG];
	BOOL needEye = RYGDMEyeEnabled() && ![overlay viewWithTag:RYG_DM_EYE_TAG];
	BOOL needAudio = [RYGUtils getBoolPref:@"dm_visual_audio_toggle"] && ![overlay viewWithTag:RYG_DM_AUDIO_TAG];

	if (needAction || needEye || needAudio) {
		rygDMInstallButtons(dmVC);
		return;
	}

	rygDMRefreshActionIcon(dmVC);
	rygDMLayoutButtons(overlay);
}

// MARK: - VC hook

%group DMOverlayGroup

%hook IGDirectVisualMessageViewerController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygDMInstallButtons(self);
}

- (void)viewDidLayoutSubviews {
	%orig;
	rygDMEnsureButtons(self);
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;

	if (!self.isViewLoaded) return;

	UIView *overlay = rygFindOverlayInView(self.view);
	if (!overlay) return;

	RYGDMRemoveButton(overlay, RYG_DM_ACTION_TAG);
	RYGDMRemoveButton(overlay, RYG_DM_EYE_TAG);
	RYGDMRemoveButton(overlay, RYG_DM_AUDIO_TAG);
}

%end

%end // DMOverlayGroup

static void rygSetDMButtonsKbHidden(BOOL hidden) {
	if (rygDMButtonsKbHidden == hidden) return;
	rygDMButtonsKbHidden = hidden;
	__weak UIView *ov = rygCurrentDMOverlay;
	if (ov) rygDMLayoutButtons(ov);
	// On unhide the safe area is still keyboard-shrunk for a beat — relayout again
	// once it settles so the buttons return to their saved spots, not the middle.
	if (!hidden) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ if (ov && !rygDMButtonsKbHidden) rygDMLayoutButtons(ov); });
	}
}

%ctor {
	if (RYGDMActionEnabled() ||
		RYGDMEyeEnabled() ||
		[RYGUtils getBoolPref:@"dm_visual_audio_toggle"]) {
		%init(DMOverlayGroup);
		[[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillShowNotification
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
				rygSetDMButtonsKbHidden(YES);
			}];
		[[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardDidHideNotification
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
				rygSetDMButtonsKbHidden(NO);
			}];
	}
}