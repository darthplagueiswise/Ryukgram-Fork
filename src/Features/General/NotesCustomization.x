#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGColorPickerSheet.h"
#import "../Theme/RYGTheme.h"
#import <objc/message.h>
#import <objc/runtime.h>

// Notes bubble editor: inject Background / Text / Emoji buttons above the
// palette. Each opens the shared color picker (or an emoji prompt) and writes
// back through the composer's theme model.

typedef NS_ENUM(NSInteger, RYGNoteColorMode) {
	RYGNoteColorModeBackground = 0,
	RYGNoteColorModeText,
};

@interface _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController (RYGNotes)
- (void)rygOpenColorSheetMode:(RYGNoteColorMode)mode;
- (void)rygOpenEmojiPrompt;
@end

#pragma mark - Shared prefs

static inline BOOL RYGNotesFlagFlipEnabled(void) {
	return [RYGUtils getBoolPref:@"custom_note_themes"] || [RYGUtils getBoolPref:@"enable_notes_customization"];
}

static inline BOOL RYGNotesButtonsEnabled(void) {
	return [RYGUtils getBoolPref:@"custom_note_themes"];
}

#pragma mark - Force-flip IG feature flags

%hook _TtC25IGDirectNotesCreationView25IGDirectNotesCreationView

- (id)initWithViewModel:(id)model
		 featureSupport:(IGNotesCreationFeatureSupportModel *)support
  presentationAnimation:(id)animation
 composerUpdateListener:(id)listener
			   delegate:(id)delegate
			 layoutType:(long long)type
			userSession:(id)session {
	if (RYGNotesFlagFlipEnabled()) {
		@try { [support setValue:@YES forKey:@"enableAnimatedEmojisInCreation"]; } @catch (__unused NSException *e) {}
		@try { [support setValue:@YES forKey:@"enableBubbleCustomization"]; } @catch (__unused NSException *e) {}
		@try { [support setValue:@YES forKey:@"enableThemesEditButton"]; } @catch (__unused NSException *e) {}
		@try { [support setValue:@YES forKey:@"enableThemesNavEntrypointButton"]; } @catch (__unused NSException *e) {}
	}

	return %orig(model, support, animation, listener, delegate, type, session);
}

%end

#pragma mark - Helpers

static id RYGKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;

	@try {
		return [obj valueForKey:key];
	} @catch (__unused NSException *e) {
		return nil;
	}
}

static _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController *RYGBubbleEditorVCForView(UIView *view) {
	UIViewController *vc = [RYGUtils nearestViewControllerForView:view];

	while (vc) {
		if ([vc isKindOfClass:%c(_TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController)])
			return (id)vc;

		vc = vc.parentViewController ?: vc.presentingViewController;
	}

	return nil;
}

// 437: the bubble editor's delegate is the theme-editor controller, which holds and
// takes the selected model. Build the opaque model via the hex-string theme factory.
static id RYGThemeEditorForEditor(id editor) {
	id delegate = [editor respondsToSelector:@selector(delegate)] ? [(id)editor delegate] : nil;
	Class ctl = NSClassFromString(@"_TtC36IGDirectNotesCreationComposerUISwift34IGDirectNotesThemeEditorController");
	return (ctl && [delegate isKindOfClass:ctl]) ? delegate : nil;
}

static NSString *RYGCurrentNoteEmoji(id editor) {
	id model = RYGKVC(RYGThemeEditorForEditor(editor), @"selectedCustomThemeCreationModel");
	id emoji = RYGKVC(model, @"customEmoji");
	return [emoji isKindOfClass:NSString.class] ? emoji : nil;
}

static id RYGBuildCreationModel(UIColor *bg, UIColor *text, NSString *emoji) {
	Class apiCls = NSClassFromString(@"IGAPINoteCustomTheme");
	Class themeCls = NSClassFromString(@"IGDirectNotesCustomTheme");
	SEL apiFac = @selector(valueWithActivationType:backgroundColorGradientHexes:backgroundColorHex:customEmoji:customizationId:expressiveEmoji:noteThemeAttributionInfo:numUses:randomAssetIndex:secondaryTextColorHex:strokeColor:textColorHex:);
	if (!apiCls || !themeCls || ![apiCls respondsToSelector:apiFac] ||
		![themeCls respondsToSelector:@selector(fromCustomThemeFragment:)]) return nil;

	NSString *bgHex = [RYGTheme hexFromColor:bg ?: UIColor.systemPinkColor];
	NSString *textHex = [RYGTheme hexFromColor:text ?: UIColor.whiteColor];

	id api = ((id (*)(id, SEL, id, id, id, id, id, id, id, id, id, id, id, id))objc_msgSend)(
		apiCls, apiFac, @"user_led_customization", nil, bgHex, emoji.length ? emoji : nil,
		nil, nil, nil, nil, nil, textHex, nil, textHex);
	id theme = ((id (*)(id, SEL, id))objc_msgSend)(themeCls, @selector(fromCustomThemeFragment:), api);
	if (![theme respondsToSelector:@selector(intoCustomThemeCreationModel)]) return nil;
	id model = ((id (*)(id, SEL))objc_msgSend)(theme, @selector(intoCustomThemeCreationModel));

	// The theme layer stores the emoji as a nested object our string can't map to,
	// so the construction drops it — but the flattened creation model exposes
	// customEmoji as a plain KVC string we can set directly to any value.
	if (emoji.length && !RYGKVC(model, @"customEmoji"))
		@try { [model setValue:emoji forKey:@"customEmoji"]; } @catch (__unused NSException *e) {}
	return model;
}

static void RYGApplyNoteModel(id editor, id model) {
	id ctl = RYGThemeEditorForEditor(editor);
	if (!ctl || !model) return;
	if ([ctl respondsToSelector:@selector(setSelectedCustomThemeCreationModel:)])
		((void (*)(id, SEL, id))objc_msgSend)(ctl, @selector(setSelectedCustomThemeCreationModel:), model);
	if ([ctl respondsToSelector:@selector(notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:)])
		((void (*)(id, SEL, id))objc_msgSend)(ctl, @selector(notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:), model);
}

static void RYGWalkSubviews(UIView *view, void (^block)(UIView *subview)) {
	if (!view || !block) return;

	for (UIView *sub in view.subviews) {
		block(sub);
		RYGWalkSubviews(sub, block);
	}
}

static void RYGEnableBottomButtons(UIViewController *parentVC) {
	if (!parentVC.view) return;

	Class bottomButtonsClass = %c(IGDSBottomButtonsView);
	if (!bottomButtonsClass) return;

	RYGWalkSubviews(parentVC.view, ^(UIView *subview) {
		if (![subview isKindOfClass:bottomButtonsClass]) return;

		IGDSBottomButtonsView *buttons = (id)subview;
		[buttons setPrimaryButtonEnabled:YES];
		[buttons setSecondaryButtonEnabled:YES];
	});
}

static UIButton *RYGMakeNoteButton(NSString *title) {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = [RYGUtils RYGColor_Primary];

	UIButtonConfiguration *config = UIButtonConfiguration.tintedButtonConfiguration;
	config.cornerStyle = UIButtonConfigurationCornerStyleFixed;
	config.background.cornerRadius = 12.0;
	config.contentInsets = NSDirectionalEdgeInsetsMake(12.0, 10.0, 12.0, 10.0);

	NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title ?: @""];
	[attr addAttribute:NSFontAttributeName
				 value:[UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold]
				 range:NSMakeRange(0, attr.length)];

	[button setAttributedTitle:attr forState:UIControlStateNormal];
	button.configuration = config;

	return button;
}

// Wrap the button in a chrome canvas so Hide UI on Capture redacts it; taps
// still reach the button.
static UIView *RYGWrapNoteButtonInChrome(UIButton *button) {
	RYGChromeCanvas *canvas = [RYGChromeCanvas new];
	canvas.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *host = canvas.contentContainer;
	button.translatesAutoresizingMaskIntoConstraints = NO;
	[host addSubview:button];

	[NSLayoutConstraint activateConstraints:@[
		[button.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
		[button.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
		[button.topAnchor constraintEqualToAnchor:host.topAnchor],
		[button.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
	]];

	return canvas;
}

static char kRYGNoteBgColorKey;
static char kRYGNoteTextColorKey;
static char kRYGNoteEmojiKey;
static char kRYGNoteStackKey;

#pragma mark - Bubble editor VC handlers

%hook _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController

%new
- (void)rygOpenColorSheetMode:(RYGNoteColorMode)mode {
	UIColor *saved = objc_getAssociatedObject(self, mode == RYGNoteColorModeText ? &kRYGNoteTextColorKey : &kRYGNoteBgColorKey);
	UIColor *initial = saved ?: (mode == RYGNoteColorModeText ? UIColor.whiteColor : UIColor.systemPinkColor);

	__weak typeof(self) weakSelf = self;
	RYGColorPickerSheet *picker = [RYGColorPickerSheet sheetWithMode:RYGColorPickerSheetModeSolid
														  startColor:initial
															endColor:nil
														applyHandler:^(__unused RYGColorPickerSheetMode pickerMode, UIColor *primary, __unused UIColor *secondary) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !primary) return;

		objc_setAssociatedObject(self,
								 mode == RYGNoteColorModeText ? &kRYGNoteTextColorKey : &kRYGNoteBgColorKey,
								 primary,
								 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		UIColor *bg = objc_getAssociatedObject(self, &kRYGNoteBgColorKey);
		UIColor *text = objc_getAssociatedObject(self, &kRYGNoteTextColorKey);
		NSString *emoji = objc_getAssociatedObject(self, &kRYGNoteEmojiKey) ?: RYGCurrentNoteEmoji(self);

		id model = RYGBuildCreationModel(bg, text, emoji);
		if (!model) return;

		RYGApplyNoteModel(self, model);
		RYGEnableBottomButtons((UIViewController *)self);
	}];

	[picker presentFromViewController:(UIViewController *)self];
}

%new
- (void)rygOpenEmojiPrompt {
	NSString *saved = objc_getAssociatedObject(self, &kRYGNoteEmojiKey);
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Enter emoji")
																   message:RYGLocalized(@"Type an emoji to use as the note bubble icon.")
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = RYGLocalized(@"Emoji");
		tf.text = saved ?: @"";
	}];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Apply") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		NSString *emoji = alert.textFields.firstObject.text ?: @"";
		objc_setAssociatedObject(self, &kRYGNoteEmojiKey, emoji, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		UIColor *bg = objc_getAssociatedObject(self, &kRYGNoteBgColorKey);
		UIColor *textColor = objc_getAssociatedObject(self, &kRYGNoteTextColorKey);
		id model = RYGBuildCreationModel(bg, textColor, emoji);
		if (!model) return;
		RYGApplyNoteModel(self, model);
		RYGEnableBottomButtons((UIViewController *)self);
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

%end

#pragma mark - Palette injection

static UIStackView *RYGNotesButtonStackForPalette(UIView *palette) {
	return objc_getAssociatedObject(palette, &kRYGNoteStackKey);
}

static void RYGPositionNotesButtonStack(UIView *palette) {
	UIStackView *stack = RYGNotesButtonStackForPalette(palette);
	UIView *container = stack.superview;
	if (!palette.window || !stack || !container) return;

	CGRect paletteFrame = [palette convertRect:palette.bounds toView:container];

	CGFloat margin = 15.0;
	CGFloat height = 44.0;
	CGFloat width = MAX(0.0, container.bounds.size.width - margin * 2.0);
	CGFloat y = CGRectGetMinY(paletteFrame) - height - margin;

	stack.frame = CGRectMake(margin, y, width, height);
}

static void RYGInjectNotesButtonsIfNeeded(UIView *palette) {
	if (!RYGNotesButtonsEnabled() || !palette.window) return;
	if (RYGNotesButtonStackForPalette(palette)) {
		RYGPositionNotesButtonStack(palette);
		return;
	}

	UIView *container = palette.superview ?: palette.window;
	if (!container) return;

	UIButton *bgButton = RYGMakeNoteButton(RYGLocalized(@"Background"));
	UIButton *textButton = RYGMakeNoteButton(RYGLocalized(@"Text"));
	UIButton *emojiButton = RYGMakeNoteButton(RYGLocalized(@"Emoji"));

	__weak UIView *weakPalette = palette;

	[bgButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIView *strongPalette = weakPalette;
		[RYGBubbleEditorVCForView(strongPalette) rygOpenColorSheetMode:RYGNoteColorModeBackground];
	}] forControlEvents:UIControlEventTouchUpInside];

	[textButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIView *strongPalette = weakPalette;
		[RYGBubbleEditorVCForView(strongPalette) rygOpenColorSheetMode:RYGNoteColorModeText];
	}] forControlEvents:UIControlEventTouchUpInside];

	[emojiButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIView *strongPalette = weakPalette;
		[RYGBubbleEditorVCForView(strongPalette) rygOpenEmojiPrompt];
	}] forControlEvents:UIControlEventTouchUpInside];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
		RYGWrapNoteButtonInChrome(bgButton),
		RYGWrapNoteButtonInChrome(textButton),
		RYGWrapNoteButtonInChrome(emojiButton)
	]];

	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.spacing = 10.0;
	stack.alignment = UIStackViewAlignmentFill;
	stack.distribution = UIStackViewDistributionFillEqually;
	stack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

	[container addSubview:stack];
	objc_setAssociatedObject(palette, &kRYGNoteStackKey, stack, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	RYGPositionNotesButtonStack(palette);
}

#pragma mark - Palette: inject 3-button row

%hook _TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView

- (void)didMoveToWindow {
	%orig;

	if (!RYGNotesButtonsEnabled()) {
		[RYGNotesButtonStackForPalette(self) removeFromSuperview];
		objc_setAssociatedObject(self, &kRYGNoteStackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (!self.window) return;

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		__strong typeof(weakSelf) self = weakSelf;
		if (self) RYGInjectNotesButtonsIfNeeded(self);
	});
}

- (void)layoutSubviews {
	%orig;
	if (RYGNotesButtonsEnabled())
		RYGPositionNotesButtonStack(self);
}

%end