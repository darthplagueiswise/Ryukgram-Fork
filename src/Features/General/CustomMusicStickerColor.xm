#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../UI/SCIColorPickerSheet.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Long-press a sticker editor color wheel → SCIColorPickerSheet → custom color.
// Music/lyric stickers get a direct apply (solid or pattern-image gradient); every
// other editor is fed through the wheel itself: the picked value is served from the
// wheel's getters and the host re-reads it on a synthesized ValueChanged.

static char kSCIMusicColorGestureKey;
static char kSCIMusicColorSuppressToggleKey;
static char kSCIOverrideKey;
static char kSCINotifyGenKey;
static char kSCINotifyTimeKey;
static char kSCIHostReadTimeKey;
static __weak id gSCIMusicColorEditor;

#pragma mark - Helpers

static inline BOOL SCIMusicColorEnabled(void) {
	return [SCIUtils getBoolPref:@"custom_music_sticker_color"];
}

static inline void SCISetColor(id obj, SEL sel, UIColor *color) {
	if (obj && color && [obj respondsToSelector:sel]) {
		((void (*)(id, SEL, id))objc_msgSend)(obj, sel, color);
	}
}

static inline id SCIGet(id obj, SEL sel) {
	return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static inline id SCIEditorMusicSticker(id editor) {
	return SCIGet(editor, @selector(musicStickerView)) ?: [SCIUtils getIvarForObj:editor name:"_musicStickerView"];
}

static inline id SCIStickerView(id sticker) {
	return SCIGet(sticker, @selector(stickerView));
}

static inline id SCIDynamicTextView(id sticker) {
	return [SCIUtils getIvarForObj:sticker name:"_dynamicTextView"];
}

static inline BOOL SCIIsClass(id obj, NSString *name) {
	return obj && [NSStringFromClass([obj class]) isEqualToString:name];
}

static inline BOOL SCIIsDynamicRevealSticker(id sticker) {
	return SCIIsClass(SCIDynamicTextView(sticker), @"IGDynamicRevealDynamicTextView");
}

static UIColor *SCIGradientColor(UIColor *start, UIColor *end, CGSize size) {
	if (!start || !end) return start ?: end;
	if (size.width < 1.0 || size.height < 1.0) size = CGSizeMake(300.0, 60.0);

	UIGraphicsBeginImageContextWithOptions(size, NO, UIScreen.mainScreen.scale);

	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	NSArray *colors = @[(__bridge id)start.CGColor, (__bridge id)end.CGColor];
	CGFloat locs[] = {0.0, 1.0};
	CGGradientRef gradient = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);

	if (ctx && gradient) {
		CGContextDrawLinearGradient(ctx, gradient, CGPointZero, CGPointMake(size.width, 0.0), 0);
	}

	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	if (gradient) CGGradientRelease(gradient);
	if (cs) CGColorSpaceRelease(cs);

	return img ? [UIColor colorWithPatternImage:img] : start;
}

static void SCIRefreshView(id view) {
	if (![view isKindOfClass:UIView.class]) return;

	[(UIView *)view setNeedsLayout];
	[(UIView *)view setNeedsDisplay];
}

static void SCIApplyColorToSticker(id sticker, UIColor *color, BOOL includeTextColor) {
	if (!sticker || !color) return;

	SCISetColor(sticker, @selector(setColor:), color);

	if (includeTextColor) {
		SCISetColor(sticker, @selector(setTextColor:), color);
	}

	id stickerView = SCIStickerView(sticker);
	SCISetColor(stickerView, @selector(setColor:), color);

	if (includeTextColor) {
		SCISetColor(stickerView, @selector(setTextColor:), color);
	}

	id dynamicTextView = SCIDynamicTextView(sticker);
	SCISetColor(dynamicTextView, @selector(setColor:), color);

	SCIRefreshView(sticker);
	SCIRefreshView(stickerView);
	SCIRefreshView(dynamicTextView);
}

static void SCIApplyEditorMusicColor(id editor, UIColor *color, BOOL includeTextColor) {
	if (!editor || !color) return;

	SCISetColor(editor, @selector(setStickerColor:), color);
	SCIApplyColorToSticker(SCIEditorMusicSticker(editor), color, includeTextColor);
}

static void SCIPresentMusicColorPicker(UIView *wheel, SCIColorPickerSheetMode mode, id editor, UIViewController *presenter) {
	__weak id weakEditor = editor;

	SCIColorPickerSheet *vc = [SCIColorPickerSheet sheetWithMode:mode
													  startColor:nil
														endColor:nil
													applyHandler:^(SCIColorPickerSheetMode m, UIColor *primary, UIColor *secondary) {
		id strongEditor = weakEditor;
		if (!strongEditor || !primary) return;

		id sticker = SCIEditorMusicSticker(strongEditor);
		BOOL isGradient = (m == SCIColorPickerSheetModeGradient && secondary);

		if (isGradient && SCIIsDynamicRevealSticker(sticker)) {
			SCIApplyEditorMusicColor(strongEditor, primary, YES);
			return;
		}

		CGSize size = [sticker isKindOfClass:UIView.class] ? ((UIView *)sticker).bounds.size : CGSizeMake(300.0, 60.0);
		UIColor *color = isGradient ? SCIGradientColor(primary, secondary, size) : primary;
		BOOL includeTextColor = !isGradient || SCIDynamicTextView(sticker) != nil;

		SCIApplyEditorMusicColor(strongEditor, color, includeTextColor);
	}];

	[vc presentFromViewController:presenter];
}

#pragma mark - Wheel injection

// Some editors (poll v2, countdown) never read the wheel — they derive colors from
// their own tables and just count taps, so the picker can't reach them.
static NSMutableSet *gSCIWheelIgnoringHosts(void) {
	static NSMutableSet *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		set = [NSMutableSet setWithArray:@[
			@"IGPollStickerV2CreationViewController",
			@"IGPostCaptureCountdownSticker.IGCountdownStickerCreationViewController",
		]];
	});
	return set;
}

static BOOL SCIIsWheelStateIgnoringHost(UIViewController *host) {
	return host && [gSCIWheelIgnoringHosts() containsObject:NSStringFromClass([host class])];
}

static BOOL SCIRecentlyNotified(id wheel) {
	NSNumber *t = objc_getAssociatedObject(wheel, &kSCINotifyTimeKey);
	return t && (CACurrentMediaTime() - t.doubleValue) < 3.0;
}

static void SCIMarkHostRead(id wheel) {
	objc_setAssociatedObject(wheel, &kSCIHostReadTimeKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The picker sheet fires per drag tick and hosts animate per ValueChanged — notify
// only once the color rests. A host that doesn't read the wheel back during the
// event gets auto-added to the ignore list so it can't cycle randomly.
static void SCIDebouncedWheelNotify(UIControl *wheel) {
	NSInteger gen = [objc_getAssociatedObject(wheel, &kSCINotifyGenKey) integerValue] + 1;
	objc_setAssociatedObject(wheel, &kSCINotifyGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	__weak UIControl *weakWheel = wheel;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UIControl *w = weakWheel;
		if (!w || [objc_getAssociatedObject(w, &kSCINotifyGenKey) integerValue] != gen) return;

		double sentAt = CACurrentMediaTime();
		objc_setAssociatedObject(w, &kSCINotifyTimeKey, @(sentAt), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[w sendActionsForControlEvents:UIControlEventValueChanged];

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			UIControl *w2 = weakWheel;
			if (!w2) return;

			NSNumber *readAt = objc_getAssociatedObject(w2, &kSCIHostReadTimeKey);
			if (readAt && readAt.doubleValue >= sentAt) return;

			UIViewController *host = [SCIUtils nearestViewControllerForView:w2];
			if (!host) return;

			[gSCIWheelIgnoringHosts() addObject:NSStringFromClass([host class])];
			objc_setAssociatedObject(w2, &kSCIOverrideKey, nil, OBJC_ASSOCIATION_ASSIGN);
		});
	});
}

// Native scheme object for gradient-wheel hosts. Solid pick = two identical stops.
static id SCIMakeColorScheme(UIColor *start, UIColor *end) {
	Class gradientCls = NSClassFromString(@"IGGradient");
	Class schemeCls = NSClassFromString(@"IGGradientColorScheme");
	if (!gradientCls || !schemeCls || !start) return nil;

	UIColor *second = end ?: start;
	IGGradient *gradient = [(IGGradient *)[gradientCls alloc] initWithColors:@[start, second]];
	if (!gradient) return nil;

	CGFloat r = 0, g = 0, b = 0, a = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
	BOOL gotRGB = [start getRed:&r green:&g blue:&b alpha:&a] && [second getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
	CGFloat lum = gotRGB ? (0.2126 * (r + r2) + 0.7152 * (g + g2) + 0.0722 * (b + b2)) / 2.0 : 0.0;
	UIColor *text = lum > 0.6 ? UIColor.blackColor : UIColor.whiteColor;

	return [(IGGradientColorScheme *)[schemeCls alloc] initWithGradient:gradient
													compatibleTextColor:text
										   compatibleSecondaryTextColor:[text colorWithAlphaComponent:0.6]
															accentColor:start];
}

static void SCIPresentSchemeWheelPicker(UIControl *wheel, SCIColorPickerSheetMode mode, UIViewController *presenter) {
	__weak UIControl *weakWheel = wheel;

	SCIColorPickerSheet *vc = [SCIColorPickerSheet sheetWithMode:mode
													  startColor:nil
														endColor:nil
													applyHandler:^(SCIColorPickerSheetMode m, UIColor *primary, UIColor *secondary) {
		UIControl *w = weakWheel;
		if (!w || !primary) return;

		id scheme = SCIMakeColorScheme(primary, (m == SCIColorPickerSheetModeGradient) ? secondary : nil);
		if (!scheme) return;

		objc_setAssociatedObject(w, &kSCIOverrideKey, scheme, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		SCIDebouncedWheelNotify(w);
	}];

	[vc presentFromViewController:presenter];
}

static void SCIPresentGenericWheelPicker(UIControl *wheel, UIViewController *presenter) {
	__weak UIControl *weakWheel = wheel;

	SCIColorPickerSheet *vc = [SCIColorPickerSheet sheetWithMode:SCIColorPickerSheetModeSolid
													  startColor:SCIGet(wheel, @selector(currentColor))
														endColor:nil
													applyHandler:^(__unused SCIColorPickerSheetMode m, UIColor *primary, __unused UIColor *secondary) {
		UIControl *w = weakWheel;
		if (!w || !primary) return;

		objc_setAssociatedObject(w, &kSCIOverrideKey, primary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		SCIDebouncedWheelNotify(w);
	}];

	[vc presentFromViewController:presenter];
}

// Eat the single tap that fires on touch-up after the long-press. Self-clears so a
// missed toggle can't swallow a later legitimate tap.
static void SCIArmToggleSuppression(UIView *wheel) {
	objc_setAssociatedObject(wheel, &kSCIMusicColorSuppressToggleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	__weak UIView *weakWheel = wheel;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UIView *w = weakWheel;
		if (w) objc_setAssociatedObject(w, &kSCIMusicColorSuppressToggleKey, nil, OBJC_ASSOCIATION_ASSIGN);
	});
}

static void SCIPresentSolidGradientSheet(UIView *wheel, UIViewController *presenter, BOOL allowGradient, void (^pick)(SCIColorPickerSheetMode mode)) {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Custom sticker colors")
																   message:nil
															preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Solid color")
											  style:UIAlertActionStyleDefault
											handler:^(__unused UIAlertAction *a) { pick(SCIColorPickerSheetModeSolid); }]];

	if (allowGradient) {
		[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Gradient color")
												  style:UIAlertActionStyleDefault
												handler:^(__unused UIAlertAction *a) { pick(SCIColorPickerSheetModeGradient); }]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel")
											  style:UIAlertActionStyleCancel
											handler:nil]];

	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.sourceView = wheel;
		sheet.popoverPresentationController.sourceRect = wheel.bounds;
	}

	[presenter presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Hooks

%hook IGMusicStickerEditor

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	gSCIMusicColorEditor = self;
}

- (void)viewWillDisappear:(BOOL)animated {
	if (gSCIMusicColorEditor == self) gSCIMusicColorEditor = nil;
	%orig;
}

%end

@interface IGStoryColorPaletteWheel (SCIMusicColor)
- (void)sciMusicColorLongPress:(UILongPressGestureRecognizer *)sender;
@end

%hook IGStoryColorPaletteWheel

// No backing ivar for currentColor — the setter snaps to a palette index, so an
// arbitrary color can't be stored. Serve the custom color from the getter instead.
- (id)currentColor {
	id override = objc_getAssociatedObject(self, &kSCIOverrideKey);
	if (SCIRecentlyNotified(self)) SCIMarkHostRead(self);
	return override ?: %orig;
}

- (void)_toggleToNextColor {
	if ([objc_getAssociatedObject(self, &kSCIMusicColorSuppressToggleKey) boolValue]) {
		objc_setAssociatedObject(self, &kSCIMusicColorSuppressToggleKey, nil, OBJC_ASSOCIATION_ASSIGN);
		return;
	}

	// Normal tap resumes IG's palette cycle.
	objc_setAssociatedObject(self, &kSCIOverrideKey, nil, OBJC_ASSOCIATION_ASSIGN);
	%orig;
}

- (void)didMoveToWindow {
	%orig;

	if (objc_getAssociatedObject(self, &kSCIMusicColorGestureKey)) return;

	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sciMusicColorLongPress:)];
	lp.minimumPressDuration = 0.25;
	lp.cancelsTouchesInView = YES;

	[(UIView *)self addGestureRecognizer:lp];
	objc_setAssociatedObject(self, &kSCIMusicColorGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)sciMusicColorLongPress:(UILongPressGestureRecognizer *)sender {
	if (sender.state != UIGestureRecognizerStateBegan) return;
	if (!SCIMusicColorEnabled()) return;

	SCIArmToggleSuppression((UIView *)self);

	UIViewController *presenter = [SCIUtils nearestViewControllerForView:(UIView *)self];
	if (!presenter) return;

	id editor = gSCIMusicColorEditor;
	id sticker = SCIEditorMusicSticker(editor);

	if (!editor || !sticker) {
		if (SCIIsWheelStateIgnoringHost(presenter)) {
			SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Custom colors aren't supported for this sticker"), nil);
			return;
		}

		SCIPresentGenericWheelPicker((UIControl *)self, presenter);
		return;
	}

	BOOL allowGradient = !SCIIsDynamicRevealSticker(sticker);

	SCIPresentSolidGradientSheet((UIView *)self, presenter, allowGradient, ^(SCIColorPickerSheetMode mode) {
		SCIPresentMusicColorPicker((UIView *)self, mode, editor, presenter);
	});
}

%end

@interface IGStoryColorPaletteGradientWheel (SCIStickerColor)
- (void)sciGradientWheelLongPress:(UILongPressGestureRecognizer *)sender;
@end

%hook IGStoryColorPaletteGradientWheel

- (void)didMoveToWindow {
	%orig;

	if (objc_getAssociatedObject(self, &kSCIMusicColorGestureKey)) return;

	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sciGradientWheelLongPress:)];
	lp.minimumPressDuration = 0.25;
	lp.cancelsTouchesInView = YES;

	[(UIView *)self addGestureRecognizer:lp];
	objc_setAssociatedObject(self, &kSCIMusicColorGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)currentColorScheme {
	id override = objc_getAssociatedObject(self, &kSCIOverrideKey);
	if (SCIRecentlyNotified(self)) SCIMarkHostRead(self);
	return override ?: %orig;
}

- (void)_toggleToNextColor {
	if ([objc_getAssociatedObject(self, &kSCIMusicColorSuppressToggleKey) boolValue]) {
		objc_setAssociatedObject(self, &kSCIMusicColorSuppressToggleKey, nil, OBJC_ASSOCIATION_ASSIGN);
		return;
	}

	// Normal tap resumes IG's palette cycle.
	objc_setAssociatedObject(self, &kSCIOverrideKey, nil, OBJC_ASSOCIATION_ASSIGN);
	%orig;
}

%new
- (void)sciGradientWheelLongPress:(UILongPressGestureRecognizer *)sender {
	if (sender.state != UIGestureRecognizerStateBegan) return;
	if (!SCIMusicColorEnabled()) return;

	SCIArmToggleSuppression((UIView *)self);

	UIViewController *presenter = [SCIUtils nearestViewControllerForView:(UIView *)self];
	if (!presenter) return;

	if (SCIIsWheelStateIgnoringHost(presenter)) {
		SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"Custom colors aren't supported for this sticker"), nil);
		return;
	}

	SCIPresentSolidGradientSheet((UIView *)self, presenter, YES, ^(SCIColorPickerSheetMode mode) {
		SCIPresentSchemeWheelPicker((UIControl *)self, mode, presenter);
	});
}

%end
