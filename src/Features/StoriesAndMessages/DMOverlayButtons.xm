// DM disappearing-media overlay buttons — action / eye / audio (tags 1342–1344).
// Hooks IGDirectVisualMessageViewerController directly; reads only dm_visual_* prefs.

#import "OverlayHelpers.h"
#import "SCIDMButtonLayout.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "../../ActionButton/SCIActionIcon.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../ActionButton/SCIActionMenuConfig.h"
#import "../../ActionButton/SCIActionCatalog.h"

// Per-button weak ref to the owning DM VC so handlers skip the responder walk.
static const void *kSCIDMOwnerVCKey = &kSCIDMOwnerVCKey;
static char kDMActionDefaultKey;

static inline BOOL SCIDMActionEnabled(void) {return [SCIUtils getBoolPref:@"dm_visual_action_button"];}

static inline BOOL SCIDMEyeEnabled(void) {return [SCIUtils getBoolPref:@"dm_visual_seen_button"];}

static inline NSString *SCIDMDefaultAction(void) {
	return [SCIUtils getStringPref:@"dm_visual_action_default"];
}

static inline SCIChromeButton *SCIDMButton(NSString *symbol, CGFloat pointSize, CGFloat diameter, NSInteger tag) {
	SCIChromeButton *button = [[SCIChromeButton alloc] initWithSymbol:symbol pointSize:pointSize diameter:diameter];
	button.tag = tag;
	return button;
}

static inline void SCIDMRemoveButton(UIView *overlay, NSInteger tag) {
	[[overlay viewWithTag:tag] removeFromSuperview];
}

static NSString *sciDMIDForTag(NSInteger tag) {
	if (tag == SCI_DM_ACTION_TAG) return SCIDMBtnAction;
	if (tag == SCI_DM_EYE_TAG) return SCIDMBtnEye;
	if (tag == SCI_DM_AUDIO_TAG) return SCIDMBtnAudio;
	return nil;
}

// Hidden while a comment sheet / keyboard is up (IG shrinks the overlay safe area).
static BOOL sciDMButtonsKbHidden = NO;
static __weak UIView *sciCurrentDMOverlay = nil;

// Frame-positions each present button at its saved normalized point in the safe area.
static void sciDMLayoutButtons(UIView *overlay) {
	CGRect safe = overlay.safeAreaLayoutGuide.layoutFrame;
	if (safe.size.width <= 0 || safe.size.height <= 0) return;
	sciCurrentDMOverlay = overlay;

	UIEdgeInsets ins = [SCIDMButtonLayout placeableInsetsNormalized];
	CGRect area = CGRectMake(safe.origin.x + ins.left * safe.size.width,
							 safe.origin.y + ins.top * safe.size.height,
							 safe.size.width * (1.0 - ins.left - ins.right),
							 safe.size.height * (1.0 - ins.top - ins.bottom));

	NSInteger tags[] = { SCI_DM_ACTION_TAG, SCI_DM_EYE_TAG, SCI_DM_AUDIO_TAG };

	for (NSUInteger i = 0; i < 3; i++) {
		UIView *button = [overlay viewWithTag:tags[i]];
		if (!button) continue;

		if (sciDMButtonsKbHidden) { button.hidden = YES; continue; }
		button.hidden = NO;

		NSString *bid = sciDMIDForTag(tags[i]);
		CGFloat d = [SCIDMButtonLayout diameterForID:bid];
		CGPoint norm = [SCIDMButtonLayout positionForID:bid];

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

static void sciDMConfirmMarkViewed(UIViewController *dmVC, void (^onConfirm)(void)) {
	[SCIUtils confirmIfNeeded:[SCIUtils getBoolPref:@"confirm_mark_seen_dm_visual"]
	                    title:SCILocalized(@"Mark as viewed?")
	                  message:SCILocalized(@"This will send a view receipt for the current message.")
	             confirmTitle:SCILocalized(@"Mark as viewed")
	                     from:dmVC
	                onConfirm:onConfirm
	                 onCancel:nil];
}

static NSArray<UIMenuElement *> *sciDMActionMenuItems(UIViewController *dmVC, UIView *sourceView) {
	__weak UIView *weakSource = sourceView;
	__weak UIViewController *weakVC = dmVC;

	SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceDM];

	SCIAction *(^resolve)(NSString *) = ^SCIAction *(NSString *aid) {
		if ([aid isEqualToString:SCIAID_Expand]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Expand") icon:@"arrow.up.left.and.arrow.down.right" handler:^{
				if (weakVC) sciDMExpandMedia(weakVC);
			}];
		}
		if ([aid isEqualToString:SCIAID_DownloadShare]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Download and share") icon:@"square.and.arrow.up" handler:^{
				if (weakVC) sciDMShareMedia(weakVC);
			}];
		}
		if ([aid isEqualToString:SCIAID_DownloadSave]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Download to Photos") icon:@"square.and.arrow.down" handler:^{
				if (weakVC) sciDMDownloadMedia(weakVC);
			}];
		}
		if ([aid isEqualToString:SCIAID_DownloadGallery]) {
			if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;
			return [SCIAction actionWithTitle:SCILocalized(@"Download to Gallery") icon:@"photo.on.rectangle.angled" handler:^{
				if (weakVC) sciDMDownloadMediaToGallery(weakVC);
			}];
		}
		if ([aid isEqualToString:SCIAID_DMMarkSeen]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Mark as viewed") icon:@"eye" handler:^{
				UIViewController *strongVC = weakVC;
				sciDMConfirmMarkViewed(strongVC, ^{
					if (strongVC) sciDMMarkCurrentAsViewed(strongVC);
				});
			}];
		}
		if ([aid isEqualToString:SCIAID_Settings]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Messages settings") icon:@"gearshape" handler:^{
				sciOpenMessagesSettings(weakSource);
			}];
		}
		return nil;
	};

	NSArray<SCIAction *> *flat = [SCIActionMenu actionsForConfig:cfg dateHeader:nil resolver:resolve];
	UIMenu *built = [SCIActionMenu buildMenuWithActions:flat];
	return built.children;
}

static NSArray<UIMenuElement *> *sciDMEyeMenuItems(UIViewController *dmVC, UIView *sourceView) {
	__weak UIView *weakSource = sourceView;
	__weak UIViewController *weakDMVC = dmVC;

	return @[
		[UIAction actionWithTitle:SCILocalized(@"Mark as viewed") image:[SCIIcon imageNamed:@"eye"] identifier:nil handler:^(__unused UIAction *a) {
			UIViewController *strongDMVC = weakDMVC;
			sciDMConfirmMarkViewed(strongDMVC, ^{
				sciDMMarkCurrentAsViewed(strongDMVC);
			});
		}],
		[UIAction actionWithTitle:SCILocalized(@"Messages settings") image:[SCIIcon imageNamed:@"gearshape"] identifier:nil handler:^(__unused UIAction *a) {
			sciOpenMessagesSettings(weakSource);
		}]
	];
}

static void sciDMApplyTapMenu(UIButton *button, __weak UIViewController *weakDMVC) {
	__weak UIButton *weakButton = button;

	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
		UIViewController *dmVC = weakDMVC;
		UIButton *strongButton = weakButton;

		if (!dmVC || !strongButton) {
			completion(@[]);
			return;
		}

		completion(sciDMActionMenuItems(dmVC, strongButton));
	}];

	button.menu = [UIMenu menuWithChildren:@[deferred]];
	button.showsMenuAsPrimaryAction = YES;
}

// MARK: - Button delegate

@interface SCIDMButtonDelegate : NSObject
+ (instancetype)shared;
- (void)actionTapped:(UIButton *)sender;
- (void)eyeTapped:(UIButton *)sender;
- (void)audioTapped:(SCIChromeButton *)sender;
@end

@implementation SCIDMButtonDelegate

+ (instancetype)shared {
	static SCIDMButtonDelegate *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [SCIDMButtonDelegate new];
	});
	return shared;
}

- (UIViewController *)ownerForButton:(UIView *)button {
	return objc_getAssociatedObject(button, kSCIDMOwnerVCKey);
}

// Default-tap path when pref is not "menu".
- (void)actionTapped:(UIButton *)sender {
	UIViewController *dmVC = [self ownerForButton:sender];
	if (!dmVC) return;

	NSString *tap = SCIDMDefaultAction();

	// Legacy values from older builds — translate before dispatch.
	if ([tap isEqualToString:@"download_photos"]) tap = SCIAID_DownloadSave;
	if ([tap isEqualToString:@"copy_link"])       tap = SCIAID_CopyURL;

	if ([tap isEqualToString:SCIAID_Expand]) {
		sciDMExpandMedia(dmVC);
	} else if ([tap isEqualToString:SCIAID_DownloadShare]) {
		sciDMShareMedia(dmVC);
	} else if ([tap isEqualToString:SCIAID_DownloadSave]) {
		sciDMDownloadMedia(dmVC);
	} else if ([tap isEqualToString:SCIAID_DownloadGallery]) {
		sciDMDownloadMediaToGallery(dmVC);
	} else if ([tap isEqualToString:SCIAID_DMMarkSeen]) {
		sciDMConfirmMarkViewed(dmVC, ^{
			sciDMMarkCurrentAsViewed(dmVC);
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

	sciDMConfirmMarkViewed(dmVC, ^{
		sciDMMarkCurrentAsViewed(dmVC);
	});
}

- (void)audioTapped:(SCIChromeButton *)sender {
	UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[haptic impactOccurred];

	sciToggleStoryAudio();
	sender.symbolName = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
}

@end

// MARK: - Long-press menu builder

// UIButton.menu + showsMenuAsPrimaryAction=NO means:
// tap fires default action, long-press shows menu.
static void sciDMAttachLongPressMenu(SCIChromeButton *button, NSInteger tag) {
	__weak SCIChromeButton *weakButton = button;

	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
		SCIChromeButton *strongButton = weakButton;
		UIViewController *dmVC = strongButton ? objc_getAssociatedObject(strongButton, kSCIDMOwnerVCKey) : nil;

		if (!dmVC) {
			completion(@[]);
			return;
		}

		completion(tag == SCI_DM_ACTION_TAG ? sciDMActionMenuItems(dmVC, strongButton) : sciDMEyeMenuItems(dmVC, strongButton));
	}];

	button.menu = [UIMenu menuWithChildren:@[deferred]];
	button.showsMenuAsPrimaryAction = NO;
}

static void sciDMConfigureActionButton(SCIChromeButton *button, UIViewController *dmVC) {
	if (!button || !dmVC) return;

	SCIDMButtonDelegate *delegate = SCIDMButtonDelegate.shared;
	NSString *action = SCIDMDefaultAction();

	button.menu = nil;
	button.showsMenuAsPrimaryAction = NO;

	[button removeTarget:delegate action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];

	if ([action isEqualToString:@"menu"]) {
		sciDMApplyTapMenu(button, dmVC);
	} else {
		// Tap = default action, long-press = full menu.
		[button addTarget:delegate action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
		sciDMAttachLongPressMenu(button, SCI_DM_ACTION_TAG);
	}

	objc_setAssociatedObject(button, &kDMActionDefaultKey, action, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void sciDMRefreshActionIcon(UIViewController *dmVC) {
	if (!dmVC || !dmVC.isViewLoaded) return;

	UIView *overlay = sciFindOverlayInView(dmVC.view);
	SCIChromeButton *button = (SCIChromeButton *)[overlay viewWithTag:SCI_DM_ACTION_TAG];

	if (![button isKindOfClass:SCIChromeButton.class]) return;

	NSString *action = SCIDMDefaultAction();
	NSString *oldAction = objc_getAssociatedObject(button, &kDMActionDefaultKey);

	if (!oldAction || ![oldAction isEqualToString:action]) {
		sciDMConfigureActionButton(button, dmVC);
		return;
	}
}

// MARK: - Overlay injection

static void sciDMInstallButtons(UIViewController *dmVC) {
	if (!dmVC || !dmVC.isViewLoaded) return;

	UIView *overlay = sciFindOverlayInView(dmVC.view);
	if (!overlay) return;

	// Kill any story-tag injections from the shared story overlay hook.
	SCIDMRemoveButton(overlay, SCI_STORY_ACTION_TAG);
	SCIDMRemoveButton(overlay, SCI_STORY_EYE_TAG);
	SCIDMRemoveButton(overlay, SCI_STORY_AUDIO_TAG);

	SCIDMButtonDelegate *delegate = SCIDMButtonDelegate.shared;

	// --- Action button (tag 1342) ---
	SCIDMRemoveButton(overlay, SCI_DM_ACTION_TAG);

	if (SCIDMActionEnabled()) {
		SCIChromeButton *button = SCIDMButton(@"", 18.0, 36.0, SCI_DM_ACTION_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;
		objc_setAssociatedObject(button, kSCIDMOwnerVCKey, dmVC, OBJC_ASSOCIATION_ASSIGN);

		[overlay addSubview:button];
		[SCIActionIcon attachAutoUpdate:button source:SCIActionSourceDM pointSize:18.0 style:SCIActionIconStylePlain];
		sciDMConfigureActionButton(button, dmVC);
	}

	// --- Eye / mark-as-viewed (tag 1343) ---
	SCIDMRemoveButton(overlay, SCI_DM_EYE_TAG);

	if (SCIDMEyeEnabled()) {
		SCIChromeButton *button = SCIDMButton(@"", 18.0, 36.0, SCI_DM_EYE_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;
		[button setIconResource:@"eye" pointSize:18.0]; // IG-styled eye glyph
		objc_setAssociatedObject(button, kSCIDMOwnerVCKey, dmVC, OBJC_ASSOCIATION_ASSIGN);

		[button addTarget:delegate action:@selector(eyeTapped:) forControlEvents:UIControlEventTouchUpInside];
		sciDMAttachLongPressMenu(button, SCI_DM_EYE_TAG);

		[overlay addSubview:button];
	}

	// --- Audio toggle (tag 1344) ---
	SCIDMRemoveButton(overlay, SCI_DM_AUDIO_TAG);

	sciInitStoryAudioState();

	if ([SCIUtils getBoolPref:@"dm_visual_audio_toggle"]) {
		NSString *symbol = sciIsStoryAudioEnabled() ? @"speaker.wave.2" : @"speaker.slash";
		SCIChromeButton *button = SCIDMButton(symbol, 14.0, 28.0, SCI_DM_AUDIO_TAG);
		button.translatesAutoresizingMaskIntoConstraints = YES;

		[button addTarget:delegate action:@selector(audioTapped:) forControlEvents:UIControlEventTouchUpInside];
		[overlay addSubview:button];
	}

	sciDMLayoutButtons(overlay);
}

// Rebuild only when an enabled button is missing.
// Action default only refreshes the action icon/behavior.
static void sciDMEnsureButtons(UIViewController *dmVC) {
	if (!dmVC || !dmVC.isViewLoaded) return;

	UIView *overlay = sciFindOverlayInView(dmVC.view);
	if (!overlay) return;

	SCIDMRemoveButton(overlay, SCI_STORY_ACTION_TAG);
	SCIDMRemoveButton(overlay, SCI_STORY_EYE_TAG);
	SCIDMRemoveButton(overlay, SCI_STORY_AUDIO_TAG);

	BOOL needAction = SCIDMActionEnabled() && ![overlay viewWithTag:SCI_DM_ACTION_TAG];
	BOOL needEye = SCIDMEyeEnabled() && ![overlay viewWithTag:SCI_DM_EYE_TAG];
	BOOL needAudio = [SCIUtils getBoolPref:@"dm_visual_audio_toggle"] && ![overlay viewWithTag:SCI_DM_AUDIO_TAG];

	if (needAction || needEye || needAudio) {
		sciDMInstallButtons(dmVC);
		return;
	}

	sciDMRefreshActionIcon(dmVC);
	sciDMLayoutButtons(overlay);
}

// MARK: - VC hook

%group DMOverlayGroup

%hook IGDirectVisualMessageViewerController

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	sciDMInstallButtons(self);
}

- (void)viewDidLayoutSubviews {
	%orig;
	sciDMEnsureButtons(self);
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;

	if (!self.isViewLoaded) return;

	UIView *overlay = sciFindOverlayInView(self.view);
	if (!overlay) return;

	SCIDMRemoveButton(overlay, SCI_DM_ACTION_TAG);
	SCIDMRemoveButton(overlay, SCI_DM_EYE_TAG);
	SCIDMRemoveButton(overlay, SCI_DM_AUDIO_TAG);
}

%end

%end // DMOverlayGroup

static void sciSetDMButtonsKbHidden(BOOL hidden) {
	if (sciDMButtonsKbHidden == hidden) return;
	sciDMButtonsKbHidden = hidden;
	__weak UIView *ov = sciCurrentDMOverlay;
	if (ov) sciDMLayoutButtons(ov);
	// On unhide the safe area is still keyboard-shrunk for a beat — relayout again
	// once it settles so the buttons return to their saved spots, not the middle.
	if (!hidden) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{ if (ov && !sciDMButtonsKbHidden) sciDMLayoutButtons(ov); });
	}
}

%ctor {
	if (SCIDMActionEnabled() ||
		SCIDMEyeEnabled() ||
		[SCIUtils getBoolPref:@"dm_visual_audio_toggle"]) {
		%init(DMOverlayGroup);
		[[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillShowNotification
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
				sciSetDMButtonsKbHidden(YES);
			}];
		[[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardDidHideNotification
			object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
				sciSetDMButtonsKbHidden(NO);
			}];
	}
}