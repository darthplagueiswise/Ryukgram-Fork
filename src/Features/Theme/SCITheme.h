// Single source of truth for the theme stack — read by every theme hook so
// the mode/force matrix lives in one place.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIThemeMode) {
	SCIThemeModeOff = 0,
	SCIThemeModeLight,
	SCIThemeModeDark,
	SCIThemeModeOLED,
};

extern NSString *const SCIThemePrefMode;     // string: off/light/dark/oled
extern NSString *const SCIThemePrefForce;    // bool
extern NSString *const SCIThemePrefOLEDChat; // bool
extern NSString *const SCIThemePrefKeyboard; // string: off/dark/oled

@interface SCITheme : NSObject

// Reads NSUserDefaults once and refreshes the cached theme values.
// Call after saving theme prefs if you want live changes without restart.
+ (void)reloadPrefs;

+ (SCIThemeMode)mode;
+ (BOOL)forceTheme;
+ (BOOL)oledChat;

+ (NSString *)modeKey;
+ (SCIThemeMode)modeForKey:(NSString *)key;

// `effectiveDark` answers "is IG currently in a dark appearance?" — trusts
// the system trait collection unless force is on.
+ (BOOL)isSystemDark;
+ (BOOL)effectiveDark;

+ (BOOL)shouldOverrideAppearance;
+ (UIUserInterfaceStyle)overrideStyle;
+ (BOOL)shouldRecolor;

// YES when the responder chain contains a RyukGram (SCI-prefixed) object.
// The theme only applies to Instagram — RyukGram UIs stay stock.
+ (BOOL)isTweakSurface:(nullable UIResponder *)responder;

// Keyboard theme resolved against current state: returns NO when
// `theme_keyboard` is off, YES when force is on, else mirrors system dark.
+ (NSString *)keyboardModeKey;
+ (BOOL)keyboardShouldApplyDark;
+ (BOOL)keyboardShouldApplyOLED;

+ (UIColor *)backgroundColor;
+ (UIColor *)surfaceColor;

+ (BOOL)colorIsNearBlack:(nullable UIColor *)color;
+ (BOOL)cgColorIsNearBlack:(nullable CGColorRef)cg;
// Looser than near-black: catches IG's neutral dark-grey surface tiers for OLED flattening.
+ (BOOL)colorIsDarkSurface:(nullable UIColor *)color;

// Hex helpers (#RRGGBB / #RRGGBBAA).
+ (nullable UIColor *)colorFromHex:(nullable NSString *)hex;
+ (NSString *)hexFromColor:(UIColor *)color;

// Folds the legacy `theme_force_dark` / `theme_full_oled` prefs onto the new
// keys. Idempotent.
+ (void)migrateLegacyPrefs;

+ (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
