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

#pragma mark - Force-flip IG feature flags

%hook IGDirectNotesCreationView
- (id)initWithViewModel:(id)model
         featureSupport:(IGNotesCreationFeatureSupportModel *)support
  presentationAnimation:(id)animation
 composerUpdateListener:(id)listener
               delegate:(id)delegate
             layoutType:(long long)type
            userSession:(id)session
{
    if ([SCIUtils getBoolPref:@"enable_notes_customization"]) {
        @try { [support setValue:@(YES) forKey:@"enableAnimatedEmojisInCreation"]; }   @catch (__unused NSException *e) {}
        @try { [support setValue:@(YES) forKey:@"enableBubbleCustomization"]; }        @catch (__unused NSException *e) {}
        @try { [support setValue:@(YES) forKey:@"enableThemesEditButton"]; }           @catch (__unused NSException *e) {}
        @try { [support setValue:@(YES) forKey:@"enableThemesNavEntrypointButton"]; }  @catch (__unused NSException *e) {}
    }
    return %orig(model, support, animation, listener, delegate, type, session);
}
%end

#pragma mark - Helpers

static _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController *SCIBubbleEditorVCForView(UIView *v) {
    UIViewController *vc = [SCIUtils nearestViewControllerForView:v];
    while (vc) {
        if ([vc isKindOfClass:%c(_TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController)]) {
            return (id)vc;
        }
        vc = vc.parentViewController ?: vc.presentingViewController;
    }
    return nil;
}

static IGNotesCustomThemeCreationModel *SCICurrentThemeModel(IGDirectNotesComposerViewController *composer) {
    IGNotesCustomThemeCreationModel *model = nil;
    @try { model = [composer valueForKey:@"_selectedCustomThemeCreationModel"]; } @catch (__unused NSException *e) {}
    return model;
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

    UIColor   *bg     = nil;
    NSArray   *grad   = nil;
    UIColor   *text   = nil;
    UIColor   *sText  = nil;
    id         emoji  = nil;
    NSString  *cid    = nil;
    BOOL       usedGen = NO;
    NSInteger  actT    = 0;

    if (prev) {
        @try { bg     = [prev valueForKey:@"backgroundColor"]; }          @catch (__unused NSException *e) {}
        @try { grad   = [prev valueForKey:@"gradientBackgroundColors"]; } @catch (__unused NSException *e) {}
        @try { text   = [prev valueForKey:@"textColor"]; }                @catch (__unused NSException *e) {}
        @try { sText  = [prev valueForKey:@"secondaryTextColor"]; }       @catch (__unused NSException *e) {}
        @try { emoji  = [prev valueForKey:@"customEmoji"]; }              @catch (__unused NSException *e) {}
        @try { cid    = [prev valueForKey:@"customizationId"]; }          @catch (__unused NSException *e) {}
        @try { usedGen = [[prev valueForKey:@"usedGeneratedTheme"] boolValue]; } @catch (__unused NSException *e) {}
        @try { actT    = [[prev valueForKey:@"activationType"] integerValue]; } @catch (__unused NSException *e) {}
    }

    if (applyText) {
        text = textOverride;
        if (!sText) sText = textOverride;
    }
    if (applyBg) {
        bg = bgOverride;
        grad = nil;
    }
    if (applyEmoji) {
        emoji = emojiOverride;
    }

    if (!bg)    bg    = [UIColor systemPinkColor];
    if (!text)  text  = [UIColor whiteColor];
    if (!sText) sText = text;

    return [[K alloc] initWithBackgroundColor:bg
                     gradientBackgroundColors:grad
                                    textColor:text
                           secondaryTextColor:sText
                                  customEmoji:emoji
                              customizationId:cid
                           usedGeneratedTheme:usedGen
                               activationType:actT];
}

static IGNotesCustomThemeCreationModel *SCIThemeModelByOverridingColor(IGDirectNotesComposerViewController *composer,
                                                                       SCINoteColorMode mode,
                                                                       UIColor *newColor) {
    BOOL applyBg   = (mode == SCINoteColorModeBackground);
    BOOL applyText = (mode == SCINoteColorModeText);
    return SCIBuildThemeModel(composer,
                              applyBg ? newColor : nil,
                              applyText ? newColor : nil,
                              nil,
                              applyBg, applyText, NO);
}

static IGNotesCustomThemeCreationModel *SCIThemeModelByOverridingEmoji(IGDirectNotesComposerViewController *composer,
                                                                       NSString *emoji) {
    return SCIBuildThemeModel(composer, nil, nil, emoji, NO, NO, YES);
}

static void SCIEnableBottomButtons(UIViewController *parentVC) {
    for (UIView *v in parentVC.view.subviews) {
        if ([v isKindOfClass:%c(IGDSBottomButtonsView)]) {
            [(IGDSBottomButtonsView *)v setPrimaryButtonEnabled:YES];
            [(IGDSBottomButtonsView *)v setSecondaryButtonEnabled:YES];
        }
    }
}

static UIButton *SCIMakeNoteButton(NSString *title) {
    UIButtonConfiguration *config = [UIButtonConfiguration tintedButtonConfiguration];
    config.background.cornerRadius = 12.0;
    config.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    config.contentInsets = NSDirectionalEdgeInsetsMake(13.7, 10, 13.7, 10);

    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.configuration = config;
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.tintColor = [SCIUtils SCIColor_Primary];

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title];
    [attr addAttribute:NSFontAttributeName
                 value:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]
                 range:NSMakeRange(0, attr.length)];
    [b setAttributedTitle:attr forState:UIControlStateNormal];
    return b;
}

static char kSCINoteBgColorKey;
static char kSCINoteTextColorKey;
static char kSCINoteEmojiKey;

#pragma mark - Bubble editor VC (handlers)

%hook _TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController

%new
- (void)sciOpenColorSheetMode:(SCINoteColorMode)mode {
    UIColor *saved = objc_getAssociatedObject(self,
        (mode == SCINoteColorModeText) ? &kSCINoteTextColorKey : &kSCINoteBgColorKey);
    UIColor *initial = saved ?: ((mode == SCINoteColorModeText) ? [UIColor whiteColor] : [UIColor systemPinkColor]);

    __weak typeof(self) weakSelf = self;
    SCIColorPickerSheet *picker = [SCIColorPickerSheet
        sheetWithMode:SCIColorPickerSheetModeSolid
           startColor:initial
             endColor:nil
         applyHandler:^(SCIColorPickerSheetMode m, UIColor *primary, UIColor *secondary) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !primary) return;

        IGDirectNotesComposerViewController *composer = [(id)self delegate];
        if (!composer) return;

        IGNotesCustomThemeCreationModel *model = SCIThemeModelByOverridingColor(composer, mode, primary);
        if (!model) return;

        char *assocKey = (mode == SCINoteColorModeText) ? &kSCINoteTextColorKey : &kSCINoteBgColorKey;
        objc_setAssociatedObject(self, assocKey, primary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [composer notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:model];
        SCIEnableBottomButtons(self);
    }];
    [picker presentFromViewController:self];
}

%new
- (void)sciOpenEmojiPrompt {
    NSString *saved = objc_getAssociatedObject(self, &kSCINoteEmojiKey);

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:SCILocalized(@"Enter emoji")
                         message:SCILocalized(@"Type an emoji to use as the note bubble icon.")
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = SCILocalized(@"Emoji");
        tf.text = saved ?: @"";
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Apply")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *_a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *text = alert.textFields.firstObject.text ?: @"";

        IGDirectNotesComposerViewController *composer = [(id)self delegate];
        if (!composer) return;

        IGNotesCustomThemeCreationModel *model = SCIThemeModelByOverridingEmoji(composer, text);
        if (!model) return;

        objc_setAssociatedObject(self, &kSCINoteEmojiKey, text, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [composer notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:model];
        SCIEnableBottomButtons(self);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
                                              style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
%end

#pragma mark - Palette: inject 3-button row

%hook _TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView

- (void)didMoveToWindow {
    %orig;
    if (![SCIUtils getBoolPref:@"custom_note_themes"]) return;
    if (!self.window) return;

    static char didInjectKey;
    if (objc_getAssociatedObject(self, &didInjectKey)) return;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.window) return;
        if (objc_getAssociatedObject(self, &didInjectKey)) return;

        UIView *container = self.superview ?: self.window;
        if (!container) return;

        UIButton *bgBtn    = SCIMakeNoteButton(SCILocalized(@"Background"));
        UIButton *textBtn  = SCIMakeNoteButton(SCILocalized(@"Text"));
        UIButton *emojiBtn = SCIMakeNoteButton(SCILocalized(@"Emoji"));

        [bgBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction *_a) {
            [SCIBubbleEditorVCForView(self) sciOpenColorSheetMode:SCINoteColorModeBackground];
        }] forControlEvents:UIControlEventTouchUpInside];

        [textBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction *_a) {
            [SCIBubbleEditorVCForView(self) sciOpenColorSheetMode:SCINoteColorModeText];
        }] forControlEvents:UIControlEventTouchUpInside];

        [emojiBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction *_a) {
            [SCIBubbleEditorVCForView(self) sciOpenEmojiPrompt];
        }] forControlEvents:UIControlEventTouchUpInside];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[bgBtn, textBtn, emojiBtn]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 15.0;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.distribution = UIStackViewDistributionFillEqually;

        [bgBtn sizeToFit];
        [textBtn sizeToFit];
        [emojiBtn sizeToFit];
        CGFloat maxH = 0;
        for (UIView *sv in stack.arrangedSubviews) maxH = MAX(maxH, sv.bounds.size.height);

        CGFloat bottomMargin = 15.0;
        CGRect paletteFrame = [self convertRect:self.bounds toView:container];
        CGFloat y = CGRectGetMinY(paletteFrame) - maxH - bottomMargin;
        CGFloat width = container.bounds.size.width - stack.spacing * 2;
        stack.frame = CGRectMake(stack.spacing, y, width, maxH);

        [container addSubview:stack];
        [stack layoutIfNeeded];

        objc_setAssociatedObject(self, &didInjectKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}
%end
