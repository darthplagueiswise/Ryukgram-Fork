// Keyboard appearance override (theme_keyboard: off / dark / oled). Hooks
// install at launch when mode != off; per-call gate via keyboardShouldApply*
// follows system dark/light unless theme_force is on.

#import "../../Utils.h"
#import "RYGTheme.h"

static inline void RYGApplyKeyboardOLEDView(UIView *view) {
	view.backgroundColor = UIColor.blackColor;

	for (UIView *sub in view.subviews) {
		sub.backgroundColor = UIColor.blackColor;
	}
}

%group KeyboardThemeDarkGroup

%hook UITextField

- (BOOL)becomeFirstResponder {
	if ([RYGTheme keyboardShouldApplyDark]) {
		self.keyboardAppearance = UIKeyboardAppearanceDark;
	}

	return %orig;
}

%end

%hook UITextView

- (BOOL)becomeFirstResponder {
	if ([RYGTheme keyboardShouldApplyDark]) {
		self.keyboardAppearance = UIKeyboardAppearanceDark;
	}

	return %orig;
}

%end

%hook UISearchBar

- (BOOL)becomeFirstResponder {
	if ([RYGTheme keyboardShouldApplyDark]) {
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

	if ([RYGTheme keyboardShouldApplyOLED]) {
		RYGApplyKeyboardOLEDView(self);
	}
}

- (void)setBackgroundColor:(UIColor *)color {
	if ([RYGTheme keyboardShouldApplyOLED] && ![color isEqual:UIColor.blackColor]) {
		%orig(UIColor.blackColor);
		return;
	}

	%orig;
}

- (void)didMoveToWindow {
	%orig;

	if ([RYGTheme keyboardShouldApplyOLED]) {
		RYGApplyKeyboardOLEDView(self);
	}
}

%end

%hook UIKBKeyplaneChargedView

- (void)layoutSubviews {
	%orig;

	if ([RYGTheme keyboardShouldApplyOLED]) {
		self.backgroundColor = UIColor.blackColor;
	}
}

%end

%end

%ctor {
	[RYGTheme migrateLegacyPrefs];

	NSString *mode = [RYGTheme keyboardModeKey];
	if ([mode isEqualToString:@"off"]) return;

	%init(KeyboardThemeDarkGroup);

	if ([mode isEqualToString:@"oled"]) {
		%init(KeyboardThemeOLEDGroup);
	}
}