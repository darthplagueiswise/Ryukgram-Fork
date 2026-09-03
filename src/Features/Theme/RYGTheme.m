#import "RYGTheme.h"
#import <objc/runtime.h>

NSString *const RYGThemePrefMode = @"theme_mode";
NSString *const RYGThemePrefForce = @"theme_force";
NSString *const RYGThemePrefOLEDChat = @"theme_oled_chat";
NSString *const RYGThemePrefKeyboard = @"theme_keyboard";

static NSString *const RYGThemeMigrationFlag = @"theme_migrated_v1";

static NSString *rygThemeModeKey;
static NSString *rygThemeKeyboardKey;
static BOOL rygThemeForce;
static BOOL rygThemeOLEDChat;

static NSUserDefaults *RYGThemeDefaults(void) {
	return NSUserDefaults.standardUserDefaults;
}

static NSString *RYGThemeString(NSUserDefaults *d, NSString *key, NSString *fallback) {
	NSString *value = [d stringForKey:key];
	return value.length ? value : fallback;
}

static CGFloat RYGClamp01(CGFloat value) {
	return MAX(0.0, MIN(1.0, value));
}

@implementation RYGTheme

+ (void)reloadPrefs {
	NSUserDefaults *d = RYGThemeDefaults();

	rygThemeModeKey = [RYGThemeString(d, RYGThemePrefMode, @"off") copy];
	rygThemeKeyboardKey = [RYGThemeString(d, RYGThemePrefKeyboard, @"off") copy];
	rygThemeForce = [d boolForKey:RYGThemePrefForce];
	rygThemeOLEDChat = [d boolForKey:RYGThemePrefOLEDChat];
}

+ (RYGThemeMode)mode {
	return [self modeForKey:[self modeKey]];
}

+ (NSString *)modeKey {
	return rygThemeModeKey ?: @"off";
}

+ (RYGThemeMode)modeForKey:(NSString *)key {
	if ([key isEqualToString:@"light"]) return RYGThemeModeLight;
	if ([key isEqualToString:@"dark"]) return RYGThemeModeDark;
	if ([key isEqualToString:@"oled"]) return RYGThemeModeOLED;
	return RYGThemeModeOff;
}

+ (BOOL)forceTheme {
	return rygThemeForce;
}

+ (BOOL)oledChat {
	return rygThemeOLEDChat;
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
	RYGThemeMode mode = [self mode];

	if (mode == RYGThemeModeOff || !rygThemeForce) {
		return [self isSystemDark];
	}

	return mode != RYGThemeModeLight;
}

+ (BOOL)shouldOverrideAppearance {
	return [self mode] != RYGThemeModeOff && rygThemeForce;
}

+ (UIUserInterfaceStyle)overrideStyle {
	switch ([self mode]) {
		case RYGThemeModeLight:
			return UIUserInterfaceStyleLight;

		case RYGThemeModeDark:
		case RYGThemeModeOLED:
			return UIUserInterfaceStyleDark;

		default:
			return UIUserInterfaceStyleUnspecified;
	}
}

+ (BOOL)shouldRecolor {
	return [self mode] == RYGThemeModeOLED && [self effectiveDark];
}

+ (BOOL)isTweakSurface:(UIResponder *)responder {
	// Class names are obfuscated at build (RYG* -> _xxx); match ownership by defining
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
	return rygThemeKeyboardKey ?: @"off";
}

+ (BOOL)keyboardShouldApplyDark {
	NSString *mode = [self keyboardModeKey];
	return ![mode isEqualToString:@"off"] && (rygThemeForce || [self isSystemDark]);
}

+ (BOOL)keyboardShouldApplyOLED {
	return [[self keyboardModeKey] isEqualToString:@"oled"] && (rygThemeForce || [self isSystemDark]);
}

+ (UIColor *)backgroundColor {
	return UIColor.blackColor;
}

+ (UIColor *)surfaceColor {
	// Alpha 0.89 dodges the >= 0.9 near-black gate so RYG-owned cells stay visible.
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
		(int)round(RYGClamp01(r) * 255.0),
		(int)round(RYGClamp01(g) * 255.0),
		(int)round(RYGClamp01(b) * 255.0)
	];
}

+ (void)resetToDefaults {
	NSUserDefaults *d = RYGThemeDefaults();

	[d setObject:@"off" forKey:RYGThemePrefMode];
	[d setBool:NO forKey:RYGThemePrefForce];
	[d setBool:NO forKey:RYGThemePrefOLEDChat];
	[d setObject:@"off" forKey:RYGThemePrefKeyboard];

	[self reloadPrefs];
}

+ (void)migrateLegacyPrefs {
	NSUserDefaults *d = RYGThemeDefaults();
	if ([d boolForKey:RYGThemeMigrationFlag]) {
		[self reloadPrefs];
		return;
	}

	if (![d stringForKey:RYGThemePrefMode]) {
		if ([d boolForKey:@"theme_full_oled"]) {
			[d setObject:@"oled" forKey:RYGThemePrefMode];
			[d setBool:YES forKey:RYGThemePrefForce];
		} else if ([d boolForKey:@"theme_force_dark"]) {
			[d setObject:@"dark" forKey:RYGThemePrefMode];
			[d setBool:YES forKey:RYGThemePrefForce];
		} else {
			[d setObject:@"off" forKey:RYGThemePrefMode];
		}
	}

	[d setBool:YES forKey:RYGThemeMigrationFlag];
	[self reloadPrefs];
}

@end