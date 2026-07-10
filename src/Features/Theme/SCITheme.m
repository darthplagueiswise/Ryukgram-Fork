#import "SCITheme.h"
#import <objc/runtime.h>

NSString *const SCIThemePrefMode = @"theme_mode";
NSString *const SCIThemePrefForce = @"theme_force";
NSString *const SCIThemePrefOLEDChat = @"theme_oled_chat";
NSString *const SCIThemePrefKeyboard = @"theme_keyboard";

static NSString *const SCIThemeMigrationFlag = @"theme_migrated_v1";

static NSString *sciThemeModeKey;
static NSString *sciThemeKeyboardKey;
static BOOL sciThemeForce;
static BOOL sciThemeOLEDChat;

static NSUserDefaults *SCIThemeDefaults(void) {
	return NSUserDefaults.standardUserDefaults;
}

static NSString *SCIThemeString(NSUserDefaults *d, NSString *key, NSString *fallback) {
	NSString *value = [d stringForKey:key];
	return value.length ? value : fallback;
}

static CGFloat SCIClamp01(CGFloat value) {
	return MAX(0.0, MIN(1.0, value));
}

@implementation SCITheme

+ (void)reloadPrefs {
	NSUserDefaults *d = SCIThemeDefaults();

	sciThemeModeKey = [SCIThemeString(d, SCIThemePrefMode, @"off") copy];
	sciThemeKeyboardKey = [SCIThemeString(d, SCIThemePrefKeyboard, @"off") copy];
	sciThemeForce = [d boolForKey:SCIThemePrefForce];
	sciThemeOLEDChat = [d boolForKey:SCIThemePrefOLEDChat];
}

+ (SCIThemeMode)mode {
	return [self modeForKey:[self modeKey]];
}

+ (NSString *)modeKey {
	return sciThemeModeKey ?: @"off";
}

+ (SCIThemeMode)modeForKey:(NSString *)key {
	if ([key isEqualToString:@"light"]) return SCIThemeModeLight;
	if ([key isEqualToString:@"dark"]) return SCIThemeModeDark;
	if ([key isEqualToString:@"oled"]) return SCIThemeModeOLED;
	return SCIThemeModeOff;
}

+ (BOOL)forceTheme {
	return sciThemeForce;
}

+ (BOOL)oledChat {
	return sciThemeOLEDChat;
}

+ (BOOL)isSystemDark {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			return window.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
		}
	}

	return UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

+ (BOOL)effectiveDark {
	SCIThemeMode mode = [self mode];

	if (mode == SCIThemeModeOff || !sciThemeForce) {
		return [self isSystemDark];
	}

	return mode != SCIThemeModeLight;
}

+ (BOOL)shouldOverrideAppearance {
	return [self mode] != SCIThemeModeOff && sciThemeForce;
}

+ (UIUserInterfaceStyle)overrideStyle {
	switch ([self mode]) {
		case SCIThemeModeLight:
			return UIUserInterfaceStyleLight;

		case SCIThemeModeDark:
		case SCIThemeModeOLED:
			return UIUserInterfaceStyleDark;

		default:
			return UIUserInterfaceStyleUnspecified;
	}
}

+ (BOOL)shouldRecolor {
	return [self mode] == SCIThemeModeOLED && [self effectiveDark];
}

+ (BOOL)isTweakSurface:(UIResponder *)responder {
	// Class names are obfuscated at build (SCI* -> _xxx); match ownership by defining
	// image instead — every RyukGram class lives in our dylib.
	static const char *ownImage;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ ownImage = class_getImageName([self class]); });
	if (!ownImage) return NO;

	// Verdict memoized on the Class — stable, so the responder walk drops to assoc lookups.
	static const void *cacheKey = &cacheKey;
	for (UIResponder *r = responder; r; r = r.nextResponder) {
		Class cls = [r class];
		NSNumber *cached = objc_getAssociatedObject(cls, cacheKey);
		BOOL owned;
		if (cached) {
			owned = cached.boolValue;
		} else {
			const char *img = class_getImageName(cls);
			owned = img == ownImage || (img && strcmp(img, ownImage) == 0);
			objc_setAssociatedObject(cls, cacheKey, @(owned), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		if (owned) return YES;
	}

	return NO;
}

+ (NSString *)keyboardModeKey {
	return sciThemeKeyboardKey ?: @"off";
}

+ (BOOL)keyboardShouldApplyDark {
	NSString *mode = [self keyboardModeKey];
	return ![mode isEqualToString:@"off"] && (sciThemeForce || [self isSystemDark]);
}

+ (BOOL)keyboardShouldApplyOLED {
	return [[self keyboardModeKey] isEqualToString:@"oled"] && (sciThemeForce || [self isSystemDark]);
}

+ (UIColor *)backgroundColor {
	return UIColor.blackColor;
}

+ (UIColor *)surfaceColor {
	// Alpha 0.89 dodges the >= 0.9 near-black gate so SCI-owned cells stay visible.
	return [UIColor colorWithWhite:0.08 alpha:0.89];
}

+ (BOOL)colorIsNearBlack:(UIColor *)color {
	if (!color) return NO;

	CGFloat r = 0, g = 0, b = 0, a = 0;

	if ([color getRed:&r green:&g blue:&b alpha:&a]) {
		return a >= 0.9 && r < 0.13 && g < 0.13 && b < 0.13;
	}

	CGFloat w = 0;
	return [color getWhite:&w alpha:&a] && a >= 0.9 && w < 0.13;
}

+ (BOOL)cgColorIsNearBlack:(CGColorRef)cg {
	if (!cg || CGColorGetAlpha(cg) < 0.9) return NO;

	size_t n = CGColorGetNumberOfComponents(cg);
	const CGFloat *c = CGColorGetComponents(cg);
	if (!c) return NO;

	if (n == 4) return c[0] < 0.13 && c[1] < 0.13 && c[2] < 0.13;
	if (n == 2) return c[0] < 0.13;

	return [self colorIsNearBlack:[UIColor colorWithCGColor:cg]];
}

+ (BOOL)colorIsDarkSurface:(UIColor *)color {
	if (!color) return NO;

	CGFloat r = 0, g = 0, b = 0, a = 0;
	if ([color getRed:&r green:&g blue:&b alpha:&a]) {
		if (a < 0.9) return NO;
		CGFloat mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
		// Low chroma so we only flatten IG's neutral grey surface tiers, not dark colored UI.
		return mx < 0.25 && (mx - mn) < 0.08;
	}

	CGFloat w = 0;
	return [color getWhite:&w alpha:&a] && a >= 0.9 && w < 0.25;
}

+ (UIColor *)colorFromHex:(NSString *)hex {
	NSString *s = [hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

	if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
	if (s.length != 6 && s.length != 8) return nil;

	unsigned int value = 0;
	if (![[NSScanner scannerWithString:s] scanHexInt:&value]) return nil;

	CGFloat r = 0, g = 0, b = 0, a = 1.0;

	if (s.length == 6) {
		r = ((value >> 16) & 0xFF) / 255.0;
		g = ((value >> 8) & 0xFF) / 255.0;
		b = (value & 0xFF) / 255.0;
	} else {
		r = ((value >> 24) & 0xFF) / 255.0;
		g = ((value >> 16) & 0xFF) / 255.0;
		b = ((value >> 8) & 0xFF) / 255.0;
		a = (value & 0xFF) / 255.0;
	}

	return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

+ (NSString *)hexFromColor:(UIColor *)color {
	CGFloat r = 0, g = 0, b = 0, a = 0;

	if (![color getRed:&r green:&g blue:&b alpha:&a]) {
		CGFloat w = 0;
		if ([color getWhite:&w alpha:&a]) r = g = b = w;
	}

	return [NSString stringWithFormat:@"#%02X%02X%02X",
		(int)round(SCIClamp01(r) * 255.0),
		(int)round(SCIClamp01(g) * 255.0),
		(int)round(SCIClamp01(b) * 255.0)
	];
}

+ (void)resetToDefaults {
	NSUserDefaults *d = SCIThemeDefaults();

	[d setObject:@"off" forKey:SCIThemePrefMode];
	[d setBool:NO forKey:SCIThemePrefForce];
	[d setBool:NO forKey:SCIThemePrefOLEDChat];
	[d setObject:@"off" forKey:SCIThemePrefKeyboard];

	[self reloadPrefs];
}

+ (void)migrateLegacyPrefs {
	NSUserDefaults *d = SCIThemeDefaults();
	if ([d boolForKey:SCIThemeMigrationFlag]) {
		[self reloadPrefs];
		return;
	}

	if (![d stringForKey:SCIThemePrefMode]) {
		if ([d boolForKey:@"theme_full_oled"]) {
			[d setObject:@"oled" forKey:SCIThemePrefMode];
			[d setBool:YES forKey:SCIThemePrefForce];
		} else if ([d boolForKey:@"theme_force_dark"]) {
			[d setObject:@"dark" forKey:SCIThemePrefMode];
			[d setBool:YES forKey:SCIThemePrefForce];
		} else {
			[d setObject:@"off" forKey:SCIThemePrefMode];
		}
	}

	[d setBool:YES forKey:SCIThemeMigrationFlag];
	[self reloadPrefs];
}

@end