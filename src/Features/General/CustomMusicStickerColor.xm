#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../UI/RYGColorPickerSheet.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Long-press a sticker editor color wheel → RYGColorPickerSheet → custom color.
// Music/lyric stickers get a direct apply (solid or pattern-image gradient); every
// other editor is fed through the wheel itself: the picked value is served from the
// wheel's getters and the host re-reads it on a synthesized ValueChanged.

static char kRYGMusicColorGestureKey;
static char kRYGMusicColorSuppressToggleKey;
static char kRYGOverrideKey;
static char kRYGNotifyGenKey;
static char kRYGNotifyTimeKey;
static char kRYGHostReadTimeKey;
static __weak id gRYGMusicColorEditor;

#pragma mark - Helpers

static inline BOOL RYGMusicColorEnabled(void) {
	return [RYGUtils getBoolPref:@"custom_music_sticker_color"];
}

static inline void RYGSetColor(id obj, SEL sel, UIColor *color) {
	if (obj && color && [obj respondsToSelector:sel]) {
		((void (*)(id, SEL, id))objc_msgSend)(obj, sel, color);
	}
}

static inline id RYGGet(id obj, SEL sel) {
	return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static inline id RYGEditorMusicSticker(id editor) {
	return RYGGet(editor, @selector(musicStickerView)) ?: [RYGUtils getIvarForObj:editor name:"_musicStickerView"];
}

static inline id RYGStickerView(id sticker) {
	return RYGGet(sticker, @selector(stickerView));
}

static inline id RYGDynamicTextView(id sticker) {
	return [RYGUtils getIvarForObj:sticker name:"_dynamicTextView"];
}

static inline BOOL RYGIsClass(id obj, NSString *name) {
	return obj && [NSStringFromClass([obj class]) isEqualToString:name];
}

static inline BOOL RYGIsDynamicRevealSticker(id sticker) {
	return RYGIsClass(RYGDynamicTextView(sticker), @"IGDynamicRevealDynamicTextView");
}

static UIColor *RYGGradientColor(UIColor *start, UIColor *end, CGSize size) {
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

static void RYGRefreshView(id view) {
	if (![view isKindOfClass:UIView.class]) return;

	[(UIView *)view setNeedsLayout];
	[(UIView *)view setNeedsDisplay];
}

static void RYGApplyColorToSticker(id sticker, UIColor *color, BOOL includeTextColor) {
	if (!sticker || !color) return;

	RYGSetColor(sticker, @selector(setColor:), color);

	if (includeTextColor) {
		RYGSetColor(sticker, @selector(setTextColor:), color);
	}

	id stickerView = RYGStickerView(sticker);
	RYGSetColor(stickerView, @selector(setColor:), color);

	if (includeTextColor) {
		RYGSetColor(stickerView, @selector(setTextColor:), color);
	}

	id dynamicTextView = RYGDynamicTextView(sticker);
	RYGSetColor(dynamicTextView, @selector(setColor:), color);

	RYGRefreshView(sticker);
	RYGRefreshView(stickerView);
	RYGRefreshView(dynamicTextView);
}

static void RYGApplyEditorMusicColor(id editor, UIColor *color, BOOL includeTextColor) {
	if (!editor || !color) return;

	RYGSetColor(editor, @selector(setStickerColor:), color);
	RYGApplyColorToSticker(RYGEditorMusicSticker(editor), color, includeTextColor);
}

static void RYGPresentMusicColorPicker(UIView *wheel, RYGColorPickerSheetMode mode, id editor, UIViewController *presenter) {
	__weak id weakEditor = editor;

	RYGColorPickerSheet *vc = [RYGColorPickerSheet sheetWithMode:mode
													  startColor:nil
														endColor:nil
													applyHandler:^(RYGColorPickerSheetMode m, UIColor *primary, UIColor *secondary) {
		id strongEditor = weakEditor;
		if (!strongEditor || !primary) return;

		id sticker = RYGEditorMusicSticker(strongEditor);
		BOOL isGradient = (m == RYGColorPickerSheetModeGradient && secondary);

		if (isGradient && RYGIsDynamicRevealSticker(sticker)) {
			RYGApplyEditorMusicColor(strongEditor, primary, YES);
			return;
		}

		CGSize size = [sticker isKindOfClass:UIView.class] ? ((UIView *)sticker).bounds.size : CGSizeMake(300.0, 60.0);
		UIColor *color = isGradient ? RYGGradientColor(primary, secondary, size) : primary;
		BOOL includeTextColor = !isGradient || RYGDynamicTextView(sticker) != nil;

		RYGApplyEditorMusicColor(strongEditor, color, includeTextColor);
	}];

	[vc presentFromViewController:presenter];
}

#pragma mark - Wheel injection

// Some editors (poll v2, countdown) never read the wheel — they derive colors from
// their own tables and just count taps, so the picker can't reach them.
static NSMutableSet *gRYGWheelIgnoringHosts(void) {
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

static BOOL RYGIsWheelStateIgnoringHost(UIViewController *host) {
	return host && [gRYGWheelIgnoringHosts() containsObject:NSStringFromClass([host class])];
}

static BOOL RYGRecentlyNotified(id wheel) {
	NSNumber *t = objc_getAssociatedObject(wheel, &kRYGNotifyTimeKey);
	return t && (CACurrentMediaTime() - t.doubleValue) < 3.0;
}

static void RYGMarkHostRead(id wheel) {
	objc_setAssociatedObject(wheel, &kRYGHostReadTimeKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The picker sheet fires per drag tick and hosts animate per ValueChanged — notify
// only once the color rests. A host that doesn't read the wheel back during the
// event gets auto-added to the ignore list so it can't cycle randomly.
static void RYGDebouncedWheelNotify(UIControl *wheel) {
	NSInteger gen = [objc_getAssociatedObject(wheel, &kRYGNotifyGenKey) integerValue] + 1;
	objc_setAssociatedObject(wheel, &kRYGNotifyGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	__weak UIControl *weakWheel = wheel;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UIControl *w = weakWheel;
		if (!w || [objc_getAssociatedObject(w, &kRYGNotifyGenKey) integerValue] != gen) return;

		double sentAt = CACurrentMediaTime();
		objc_setAssociatedObject(w, &kRYGNotifyTimeKey, @(sentAt), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		[w sendActionsForControlEvents:UIControlEventValueChanged];

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			UIControl *w2 = weakWheel;
			if (!w2) return;

			NSNumber *readAt = objc_getAssociatedObject(w2, &kRYGHostReadTimeKey);
			if (readAt && readAt.doubleValue >= sentAt) return;

			UIViewController *host = [RYGUtils nearestViewControllerForView:w2];
			if (!host) return;

			[gRYGWheelIgnoringHosts() addObject:NSStringFromClass([host class])];
			objc_setAssociatedObject(w2, &kRYGOverrideKey, nil, OBJC_ASSOCIATION_ASSIGN);
		});
	});
}

// Native scheme object for gradient-wheel hosts. Solid pick = two identical stops.
static id RYGMakeColorScheme(UIColor *start, UIColor *end) {
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

static void RYGPresentSchemeWheelPicker(UIControl *wheel, RYGColorPickerSheetMode mode, UIViewController *presenter) {
	__weak UIControl *weakWheel = wheel;

	RYGColorPickerSheet *vc = [RYGColorPickerSheet sheetWithMode:mode
													  startColor:nil
														endColor:nil
													applyHandler:^(RYGColorPickerSheetMode m, UIColor *primary, UIColor *secondary) {
		UIControl *w = weakWheel;
		if (!w || !primary) return;

		id scheme = RYGMakeColorScheme(primary, (m == RYGColorPickerSheetModeGradient) ? secondary : nil);
		if (!scheme) return;

		objc_setAssociatedObject(w, &kRYGOverrideKey, scheme, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		RYGDebouncedWheelNotify(w);
	}];

	[vc presentFromViewController:presenter];
}

static void RYGPresentGenericWheelPicker(UIControl *wheel, UIViewController *presenter) {
	__weak UIControl *weakWheel = wheel;

	RYGColorPickerSheet *vc = [RYGColorPickerSheet sheetWithMode:RYGColorPickerSheetModeSolid
													  startColor:RYGGet(wheel, @selector(currentColor))
														endColor:nil
													applyHandler:^(__unused RYGColorPickerSheetMode m, UIColor *primary, __unused UIColor *secondary) {
		UIControl *w = weakWheel;
		if (!w || !primary) return;

		objc_setAssociatedObject(w, &kRYGOverrideKey, primary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		RYGDebouncedWheelNotify(w);
	}];

	[vc presentFromViewController:presenter];
}

// Eat the single tap that fires on touch-up after the long-press. Self-clears so a
// missed toggle can't swallow a later legitimate tap.
static void RYGArmToggleSuppression(UIView *wheel) {
	objc_setAssociatedObject(wheel, &kRYGMusicColorSuppressToggleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	__weak UIView *weakWheel = wheel;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UIView *w = weakWheel;
		if (w) objc_setAssociatedObject(w, &kRYGMusicColorSuppressToggleKey, nil, OBJC_ASSOCIATION_ASSIGN);
	});
}

static void RYGPresentSolidGradientSheet(UIView *wheel, UIViewController *presenter, BOOL allowGradient, void (^pick)(RYGColorPickerSheetMode mode)) {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Custom sticker colors")
																   message:nil
															preferredStyle:UIAlertControllerStyleActionSheet];

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Solid color")
											  style:UIAlertActionStyleDefault
											handler:^(__unused UIAlertAction *a) { pick(RYGColorPickerSheetModeSolid); }]];

	if (allowGradient) {
		[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Gradient color")
												  style:UIAlertActionStyleDefault
												handler:^(__unused UIAlertAction *a) { pick(RYGColorPickerSheetModeGradient); }]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
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
	gRYGMusicColorEditor = self;
}

- (void)viewWillDisappear:(BOOL)animated {
	if (gRYGMusicColorEditor == self) gRYGMusicColorEditor = nil;
	%orig;
}

%end

@interface IGStoryColorPaletteWheel (RYGMusicColor)
- (void)rygMusicColorLongPress:(UILongPressGestureRecognizer *)sender;
@end

%hook IGStoryColorPaletteWheel

// No backing ivar for currentColor — the setter snaps to a palette index, so an
// arbitrary color can't be stored. Serve the custom color from the getter instead.
- (id)currentColor {
	id override = objc_getAssociatedObject(self, &kRYGOverrideKey);
	if (RYGRecentlyNotified(self)) RYGMarkHostRead(self);
	return override ?: %orig;
}

- (void)_toggleToNextColor {
	if ([objc_getAssociatedObject(self, &kRYGMusicColorSuppressToggleKey) boolValue]) {
		objc_setAssociatedObject(self, &kRYGMusicColorSuppressToggleKey, nil, OBJC_ASSOCIATION_ASSIGN);
		return;
	}

	// Normal tap resumes IG's palette cycle.
	objc_setAssociatedObject(self, &kRYGOverrideKey, nil, OBJC_ASSOCIATION_ASSIGN);
	%orig;
}

- (void)didMoveToWindow {
	%orig;

	if (objc_getAssociatedObject(self, &kRYGMusicColorGestureKey)) return;

	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rygMusicColorLongPress:)];
	lp.minimumPressDuration = 0.25;
	lp.cancelsTouchesInView = YES;

	[(UIView *)self addGestureRecognizer:lp];
	objc_setAssociatedObject(self, &kRYGMusicColorGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)rygMusicColorLongPress:(UILongPressGestureRecognizer *)sender {
	if (sender.state != UIGestureRecognizerStateBegan) return;
	if (!RYGMusicColorEnabled()) return;

	RYGArmToggleSuppression((UIView *)self);

	UIViewController *presenter = [RYGUtils nearestViewControllerForView:(UIView *)self];
	if (!presenter) return;

	id editor = gRYGMusicColorEditor;
	id sticker = RYGEditorMusicSticker(editor);

	if (!editor || !sticker) {
		if (RYGIsWheelStateIgnoringHost(presenter)) {
			RYGNotifyInfo(RYG_NOTIF_GENERIC, RYGLocalized(@"Custom colors aren't supported for this sticker"), nil);
			return;
		}

		RYGPresentGenericWheelPicker((UIControl *)self, presenter);
		return;
	}

	BOOL allowGradient = !RYGIsDynamicRevealSticker(sticker);

	RYGPresentSolidGradientSheet((UIView *)self, presenter, allowGradient, ^(RYGColorPickerSheetMode mode) {
		RYGPresentMusicColorPicker((UIView *)self, mode, editor, presenter);
	});
}

%end

@interface IGStoryColorPaletteGradientWheel (RYGStickerColor)
- (void)rygGradientWheelLongPress:(UILongPressGestureRecognizer *)sender;
@end

%hook IGStoryColorPaletteGradientWheel

- (void)didMoveToWindow {
	%orig;

	if (objc_getAssociatedObject(self, &kRYGMusicColorGestureKey)) return;

	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rygGradientWheelLongPress:)];
	lp.minimumPressDuration = 0.25;
	lp.cancelsTouchesInView = YES;

	[(UIView *)self addGestureRecognizer:lp];
	objc_setAssociatedObject(self, &kRYGMusicColorGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)currentColorScheme {
	id override = objc_getAssociatedObject(self, &kRYGOverrideKey);
	if (RYGRecentlyNotified(self)) RYGMarkHostRead(self);
	return override ?: %orig;
}

- (void)_toggleToNextColor {
	if ([objc_getAssociatedObject(self, &kRYGMusicColorSuppressToggleKey) boolValue]) {
		objc_setAssociatedObject(self, &kRYGMusicColorSuppressToggleKey, nil, OBJC_ASSOCIATION_ASSIGN);
		return;
	}

	// Normal tap resumes IG's palette cycle.
	objc_setAssociatedObject(self, &kRYGOverrideKey, nil, OBJC_ASSOCIATION_ASSIGN);
	%orig;
}

%new
- (void)rygGradientWheelLongPress:(UILongPressGestureRecognizer *)sender {
	if (sender.state != UIGestureRecognizerStateBegan) return;
	if (!RYGMusicColorEnabled()) return;

	RYGArmToggleSuppression((UIView *)self);

	UIViewController *presenter = [RYGUtils nearestViewControllerForView:(UIView *)self];
	if (!presenter) return;

	if (RYGIsWheelStateIgnoringHost(presenter)) {
		RYGNotifyInfo(RYG_NOTIF_GENERIC, RYGLocalized(@"Custom colors aren't supported for this sticker"), nil);
		return;
	}

	RYGPresentSolidGradientSheet((UIView *)self, presenter, YES, ^(RYGColorPickerSheetMode mode) {
		RYGPresentSchemeWheelPicker((UIControl *)self, mode, presenter);
	});
}

%end
