// Keyboard appearance override (theme_keyboard: off / dark / oled). Hooks
// install at launch when mode != off; per-call gate via keyboardShouldApply*
// follows system dark/light unless theme_force is on.

#import "../../Utils.h"
#import "SCITheme.h"

static inline void SCIApplyKeyboardOLEDView(UIView *view) {
	view.backgroundColor = UIColor.blackColor;

	for (UIView *sub in view.subviews) {
		sub.backgroundColor = UIColor.blackColor;
	}
}

%group KeyboardThemeDarkGroup

%hook UITextField

- (BOOL)becomeFirstResponder {
	if ([SCITheme keyboardShouldApplyDark]) {
		self.keyboardAppearance = UIKeyboardAppearanceDark;
	}

	return %orig;
}

%end

%hook UITextView

- (BOOL)becomeFirstResponder {
	if ([SCITheme keyboardShouldApplyDark]) {
		self.keyboardAppearance = UIKeyboardAppearanceDark;
	}

	return %orig;
}

%end

%hook UISearchBar

- (BOOL)becomeFirstResponder {
	if ([SCITheme keyboardShouldApplyDark]) {
		self.keyboardAppearance = UIKeyboardAppearanceDark;
	}

	return %orig;
}

%end

%end

%group KeyboardThemeOLEDGroup

%hook UIKBBackdropView

- (void)layoutSubviews {
	%orig;

	if ([SCITheme keyboardShouldApplyOLED]) {
		SCIApplyKeyboardOLEDView(self);
	}
}

- (void)setBackgroundColor:(UIColor *)color {
	if ([SCITheme keyboardShouldApplyOLED] && ![color isEqual:UIColor.blackColor]) {
		%orig(UIColor.blackColor);
		return;
	}

	%orig;
}

- (void)didMoveToWindow {
	%orig;

	if ([SCITheme keyboardShouldApplyOLED]) {
		SCIApplyKeyboardOLEDView(self);
	}
}

%end

%hook UIKBKeyplaneChargedView

- (void)layoutSubviews {
	%orig;

	if ([SCITheme keyboardShouldApplyOLED]) {
		self.backgroundColor = UIColor.blackColor;
	}
}

%end

%end

%ctor {
	[SCITheme migrateLegacyPrefs];

	NSString *mode = [SCITheme keyboardModeKey];
	if ([mode isEqualToString:@"off"]) return;

	%init(KeyboardThemeDarkGroup);

	if ([mode isEqualToString:@"oled"]) {
		%init(KeyboardThemeOLEDGroup);
	}
}