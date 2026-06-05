#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../UI/SCIColorPickerSheet.h"
#import <objc/runtime.h>

// Notes bubble editor: inject Background / Text / Emoji buttons above the
// palette. Each opens the shared color picker (or an emoji prompt) and writes
// back through the composer's theme model.

typedef NS_ENUM(NSInteger, SCINoteColorMode) {
	SCINoteColorModeBackground = 0,
	SCINoteColorModeText,
};

@interface _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController (SCINotes)
- (void)sciOpenColorSheetMode:(SCINoteColorMode)mode;
- (void)sciOpenEmojiPrompt;
@end

#pragma mark - Shared prefs

static inline BOOL SCINotesFlagFlipEnabled(void) {
	return [SCIUtils getBoolPref:@"custom_note_themes"] || [SCIUtils getBoolPref:@"enable_notes_customization"];
}

static inline BOOL SCINotesButtonsEnabled(void) {
	return [SCIUtils getBoolPref:@"custom_note_themes"];
}

#pragma mark - Force-flip IG feature flags

%hook IGDirectNotesCreationView

- (id)initWithViewModel:(id)model
		 featureSupport:(IGNotesCreationFeatureSupportModel *)support
  presentationAnimation:(id)animation
 composerUpdateListener:(id)listener
			   delegate:(id)delegate
			 layoutType:(long long)type
			userSession:(id)session {
	if (SCINotesFlagFlipEnabled()) {
		@try { [support setValue:@YES forKey:@"enableAnimatedEmojisInCreation"]; } @catch (__unused NSException *e) {}
		@try { [support setValue:@YES forKey:@"enableBubbleCustomization"]; } @catch (__unused NSException *e) {}
		@try { [support setValue:@YES forKey:@"enableThemesEditButton"]; } @catch (__unused NSException *e) {}
		@try { [support setValue:@YES forKey:@"enableThemesNavEntrypointButton"]; } @catch (__unused NSException *e) {}
	}

	return %orig(model, support, animation, listener, delegate, type, session);
}

%end

#pragma mark - Helpers

static id SCIKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;

	@try {
		return [obj valueForKey:key];
	} @catch (__unused NSException *e) {
		return nil;
	}
}

static _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController *SCIBubbleEditorVCForView(UIView *view) {
	UIViewController *vc = [SCIUtils nearestViewControllerForView:view];

	while (vc) {
		if ([vc isKindOfClass:%c(_TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController)])
			return (id)vc;

		vc = vc.parentViewController ?: vc.presentingViewController;
	}

	return nil;
}

static IGDirectNotesComposerViewController *SCIComposerForEditor(UIViewController *editor) {
	id delegate = [editor respondsToSelector:@selector(delegate)] ? [(id)editor delegate] : nil;
	return [delegate isKindOfClass:%c(IGDirectNotesComposerViewController)] ? delegate : nil;
}

static IGNotesCustomThemeCreationModel *SCICurrentThemeModel(IGDirectNotesComposerViewController *composer) {
	return SCIKVC(composer, @"_selectedCustomThemeCreationModel");
}

// Pando theme model is immutable — rebuild via the all-fields init, copying
// every existing field plus the override(s).
static IGNotesCustomThemeCreationModel *SCIBuildThemeModel(IGDirectNotesComposerViewController *composer,
														   UIColor *bgOverride,
														   UIColor *textOverride,
														   NSString *emojiOverride,
														   BOOL applyBg,
														   BOOL applyText,
														   BOOL applyEmoji) {
	Class K = %c(IGNotesCustomThemeCreationModel);
	if (!K) return nil;

	IGNotesCustomThemeCreationModel *prev = SCICurrentThemeModel(composer);

	UIColor *bg = SCIKVC(prev, @"backgroundColor");
	NSArray *grad = SCIKVC(prev, @"gradientBackgroundColors");
	UIColor *text = SCIKVC(prev, @"textColor");
	UIColor *secondaryText = SCIKVC(prev, @"secondaryTextColor");
	id emoji = SCIKVC(prev, @"customEmoji");
	NSString *customizationId = SCIKVC(prev, @"customizationId");
	BOOL usedGeneratedTheme = [SCIKVC(prev, @"usedGeneratedTheme") boolValue];
	NSInteger activationType = [SCIKVC(prev, @"activationType") integerValue];

	if (applyBg) {
		bg = bgOverride;
		grad = nil;
	}

	if (applyText) {
		text = textOverride;
		secondaryText = textOverride ?: secondaryText;
	}

	if (applyEmoji)
		emoji = emojiOverride;

	bg = bg ?: UIColor.systemPinkColor;
	text = text ?: UIColor.whiteColor;
	secondaryText = secondaryText ?: text;

	return [[K alloc] initWithBackgroundColor:bg
					 gradientBackgroundColors:grad
									textColor:text
						   secondaryTextColor:secondaryText
								  customEmoji:emoji
							  customizationId:customizationId
						   usedGeneratedTheme:usedGeneratedTheme
							   activationType:activationType];
}

static IGNotesCustomThemeCreationModel *SCIThemeModelByOverridingColor(IGDirectNotesComposerViewController *composer,
																	   SCINoteColorMode mode,
																	   UIColor *newColor) {
	BOOL applyBg = mode == SCINoteColorModeBackground;
	BOOL applyText = mode == SCINoteColorModeText;

	return SCIBuildThemeModel(composer,
							  applyBg ? newColor : nil,
							  applyText ? newColor : nil,
							  nil,
							  applyBg,
							  applyText,
							  NO);
}

static IGNotesCustomThemeCreationModel *SCIThemeModelByOverridingEmoji(IGDirectNotesComposerViewController *composer,
																	   NSString *emoji) {
	return SCIBuildThemeModel(composer, nil, nil, emoji, NO, NO, YES);
}

static void SCIWalkSubviews(UIView *view, void (^block)(UIView *subview)) {
	if (!view || !block) return;

	for (UIView *sub in view.subviews) {
		block(sub);
		SCIWalkSubviews(sub, block);
	}
}

static void SCIEnableBottomButtons(UIViewController *parentVC) {
	if (!parentVC.view) return;

	Class bottomButtonsClass = %c(IGDSBottomButtonsView);
	if (!bottomButtonsClass) return;

	SCIWalkSubviews(parentVC.view, ^(UIView *subview) {
		if (![subview isKindOfClass:bottomButtonsClass]) return;

		IGDSBottomButtonsView *buttons = (id)subview;
		[buttons setPrimaryButtonEnabled:YES];
		[buttons setSecondaryButtonEnabled:YES];
	});
}

static UIButton *SCIMakeNoteButton(NSString *title) {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = [SCIUtils SCIColor_Primary];

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

static char kSCINoteBgColorKey;
static char kSCINoteTextColorKey;
static char kSCINoteEmojiKey;
static char kSCINoteStackKey;

#pragma mark - Bubble editor VC handlers

%hook _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController

%new
- (void)sciOpenColorSheetMode:(SCINoteColorMode)mode {
	UIColor *saved = objc_getAssociatedObject(self, mode == SCINoteColorModeText ? &kSCINoteTextColorKey : &kSCINoteBgColorKey);
	UIColor *initial = saved ?: (mode == SCINoteColorModeText ? UIColor.whiteColor : UIColor.systemPinkColor);

	__weak typeof(self) weakSelf = self;
	SCIColorPickerSheet *picker = [SCIColorPickerSheet sheetWithMode:SCIColorPickerSheetModeSolid
														  startColor:initial
															endColor:nil
														applyHandler:^(__unused SCIColorPickerSheetMode pickerMode, UIColor *primary, __unused UIColor *secondary) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || !primary) return;

		IGDirectNotesComposerViewController *composer = SCIComposerForEditor((UIViewController *)self);
		if (!composer) return;

		IGNotesCustomThemeCreationModel *model = SCIThemeModelByOverridingColor(composer, mode, primary);
		if (!model) return;

		objc_setAssociatedObject(self,
								 mode == SCINoteColorModeText ? &kSCINoteTextColorKey : &kSCINoteBgColorKey,
								 primary,
								 OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[composer notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:model];
		SCIEnableBottomButtons((UIViewController *)self);
	}];

	[picker presentFromViewController:(UIViewController *)self];
}

%new
- (void)sciOpenEmojiPrompt {
	NSString *saved = objc_getAssociatedObject(self, &kSCINoteEmojiKey);

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Enter emoji")
																   message:SCILocalized(@"Type an emoji to use as the note bubble icon.")
															preferredStyle:UIAlertControllerStyleAlert];

	[alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = SCILocalized(@"Emoji");
		tf.text = saved ?: @"";
	}];

	__weak typeof(self) weakSelf = self;
	UIAlertAction *apply = [UIAlertAction actionWithTitle:SCILocalized(@"Apply")
													style:UIAlertActionStyleDefault
												  handler:^(__unused UIAlertAction *action) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;

		NSString *text = alert.textFields.firstObject.text ?: @"";
		IGDirectNotesComposerViewController *composer = SCIComposerForEditor((UIViewController *)self);
		if (!composer) return;

		IGNotesCustomThemeCreationModel *model = SCIThemeModelByOverridingEmoji(composer, text);
		if (!model) return;

		objc_setAssociatedObject(self, &kSCINoteEmojiKey, text, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[composer notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:model];
		SCIEnableBottomButtons((UIViewController *)self);
	}];

	[alert addAction:apply];
	[alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

	[self presentViewController:alert animated:YES completion:nil];
}

%end

#pragma mark - Palette injection

static UIStackView *SCINotesButtonStackForPalette(UIView *palette) {
	return objc_getAssociatedObject(palette, &kSCINoteStackKey);
}

static void SCIPositionNotesButtonStack(UIView *palette) {
	UIStackView *stack = SCINotesButtonStackForPalette(palette);
	UIView *container = stack.superview;
	if (!palette.window || !stack || !container) return;

	CGRect paletteFrame = [palette convertRect:palette.bounds toView:container];

	CGFloat margin = 15.0;
	CGFloat height = 44.0;
	CGFloat width = MAX(0.0, container.bounds.size.width - margin * 2.0);
	CGFloat y = CGRectGetMinY(paletteFrame) - height - margin;

	stack.frame = CGRectMake(margin, y, width, height);
}

static void SCIInjectNotesButtonsIfNeeded(UIView *palette) {
	if (!SCINotesButtonsEnabled() || !palette.window) return;
	if (SCINotesButtonStackForPalette(palette)) {
		SCIPositionNotesButtonStack(palette);
		return;
	}

	UIView *container = palette.superview ?: palette.window;
	if (!container) return;

	UIButton *bgButton = SCIMakeNoteButton(SCILocalized(@"Background"));
	UIButton *textButton = SCIMakeNoteButton(SCILocalized(@"Text"));
	UIButton *emojiButton = SCIMakeNoteButton(SCILocalized(@"Emoji"));

	__weak UIView *weakPalette = palette;

	[bgButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIView *strongPalette = weakPalette;
		[SCIBubbleEditorVCForView(strongPalette) sciOpenColorSheetMode:SCINoteColorModeBackground];
	}] forControlEvents:UIControlEventTouchUpInside];

	[textButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIView *strongPalette = weakPalette;
		[SCIBubbleEditorVCForView(strongPalette) sciOpenColorSheetMode:SCINoteColorModeText];
	}] forControlEvents:UIControlEventTouchUpInside];

	[emojiButton addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
		UIView *strongPalette = weakPalette;
		[SCIBubbleEditorVCForView(strongPalette) sciOpenEmojiPrompt];
	}] forControlEvents:UIControlEventTouchUpInside];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
		bgButton,
		textButton,
		emojiButton
	]];

	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.spacing = 10.0;
	stack.alignment = UIStackViewAlignmentFill;
	stack.distribution = UIStackViewDistributionFillEqually;
	stack.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;

	[container addSubview:stack];
	objc_setAssociatedObject(palette, &kSCINoteStackKey, stack, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	SCIPositionNotesButtonStack(palette);
}

#pragma mark - Palette: inject 3-button row

%hook _TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView

- (void)didMoveToWindow {
	%orig;

	if (!SCINotesButtonsEnabled()) {
		[SCINotesButtonStackForPalette(self) removeFromSuperview];
		objc_setAssociatedObject(self, &kSCINoteStackKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (!self.window) return;

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		__strong typeof(weakSelf) self = weakSelf;
		if (self) SCIInjectNotesButtonsIfNeeded(self);
	});
}

- (void)layoutSubviews {
	%orig;
	if (SCINotesButtonsEnabled())
		SCIPositionNotesButtonStack(self);
}

%end