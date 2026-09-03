#import "RYGLocalization.h"
#import <dlfcn.h>

NSString *const RYGLanguagePrefKey = @"ryg_language";

static NSBundle *gResourceBundle;
static NSBundle *gLanguageBundle;
static NSString *gLanguageCode;
static NSString *gResolvedLanguageCode;
static dispatch_once_t gResourceOnce;

static NSString *const kRYGMissing = @"\x01RYG_MISSING\x01";

NSString *RYGLocalizationOverridePath(void) {
	NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
	return [lib stringByAppendingPathComponent:@"RyukGram.bundle"];
}

static BOOL RYGFileExists(NSString *path) {
	return path.length && [NSFileManager.defaultManager fileExistsAtPath:path];
}

static NSBundle *RYGResolveResourceBundle(void) {
	NSString *path = [[NSBundle mainBundle] pathForResource:@"RyukGram" ofType:@"bundle"];
	if (RYGFileExists(path)) return [NSBundle bundleWithPath:path];

	for (NSString *p in @[
		@"/var/jb/Library/Application Support/RyukGram.bundle",
		@"/Library/Application Support/RyukGram.bundle",
		RYGLocalizationOverridePath()
	]) {
		if (RYGFileExists(p)) return [NSBundle bundleWithPath:p];
	}

	Dl_info info;
	if (dladdr((const void *)&RYGResolveResourceBundle, &info) && info.dli_fname) {
		NSString *dir = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];

		path = [dir stringByAppendingPathComponent:@"RyukGram.bundle"];
		if (RYGFileExists(path)) return [NSBundle bundleWithPath:path];

		// roothide: jbroot is randomized, .jbroot symlinks back to it
		path = [dir stringByAppendingPathComponent:@".jbroot/Library/Application Support/RyukGram.bundle"];
		if (RYGFileExists(path)) return [NSBundle bundleWithPath:path];
	}

	return nil;
}

NSBundle *RYGLocalizationBundle(void) {
	dispatch_once(&gResourceOnce, ^{
		gResourceBundle = RYGResolveResourceBundle();
	});
	return gResourceBundle;
}

static NSString *RYGPreferredLanguageCode(NSBundle *bundle) {
	if (gResolvedLanguageCode.length) return gResolvedLanguageCode;

	NSString *pref = [NSUserDefaults.standardUserDefaults stringForKey:RYGLanguagePrefKey];
	if (pref.length && ![pref isEqualToString:@"system"]) {
		gResolvedLanguageCode = pref.copy;
		return gResolvedLanguageCode;
	}

	NSMutableArray *localizations = [(bundle.localizations ?: @[]) mutableCopy];
	[localizations removeObject:@"Base"];

	NSArray *matches = [NSBundle preferredLocalizationsFromArray:localizations forPreferences:NSLocale.preferredLanguages];
	NSString *code = matches.firstObject;

	gResolvedLanguageCode = code.length ? code.copy : @"en";
	return gResolvedLanguageCode;
}

NSString *RYGResolvedLanguageCode(void) {
	NSBundle *bundle = RYGLocalizationBundle();
	if (!bundle) return @"en";

	@synchronized (RYGLanguagePrefKey) {
		return RYGPreferredLanguageCode(bundle);
	}
}

static NSBundle *RYGLanguageBundleForCode(NSBundle *resource, NSString *code) {
	NSString *overrideStrings = [[RYGLocalizationOverridePath() stringByAppendingPathComponent:[code stringByAppendingString:@".lproj"]] stringByAppendingPathComponent:@"Localizable.strings"];
	if (RYGFileExists(overrideStrings)) return [NSBundle bundleWithPath:overrideStrings.stringByDeletingLastPathComponent];

	NSString *lproj = [resource pathForResource:code ofType:@"lproj"];
	if (!lproj.length && ![code isEqualToString:@"en"]) lproj = [resource pathForResource:@"en" ofType:@"lproj"];

	return lproj.length ? [NSBundle bundleWithPath:lproj] : resource;
}

static NSBundle *RYGActiveLanguageBundle(void) {
	NSBundle *resource = RYGLocalizationBundle();
	if (!resource) return nil;

	@synchronized (RYGLanguagePrefKey) {
		NSString *code = RYGPreferredLanguageCode(resource);
		if (gLanguageBundle && [code isEqualToString:gLanguageCode]) return gLanguageBundle;

		gLanguageCode = code.copy;
		gLanguageBundle = RYGLanguageBundleForCode(resource, code);
		return gLanguageBundle;
	}
}

typedef NS_ENUM(uint8_t, RYGFormatArg) {
	RYGFormatArgNone = 0,
	RYGFormatArgObject,
	RYGFormatArgPointer,
	RYGFormatArgInt,
	RYGFormatArgLong,
	RYGFormatArgDouble,
};

static uint8_t RYGFormatArgForConversion(unichar conversion, BOOL wide) {
	switch (conversion) {
		case '@': return RYGFormatArgObject;
		case 's': case 'S': case 'p': return RYGFormatArgPointer;
		case 'd': case 'D': case 'i': case 'u': case 'U': case 'x': case 'X':
		case 'o': case 'O': case 'c': case 'C': return wide ? RYGFormatArgLong : RYGFormatArgInt;
		case 'f': case 'F': case 'e': case 'E':
		case 'g': case 'G': case 'a': case 'A': return RYGFormatArgDouble;
	}
	return RYGFormatArgNone;
}

enum { kRYGFormatMaxChars = 256, kRYGFormatMaxArgs = 12 };

// NO means unjudgeable, not invalid.
static BOOL RYGReadFormatArgs(NSString *format, uint8_t *kinds, NSUInteger *countOut) {
	NSUInteger length = format.length;
	if (length > kRYGFormatMaxChars) return NO;

	unichar chars[kRYGFormatMaxChars];
	[format getCharacters:chars range:NSMakeRange(0, length)];
	memset(kinds, RYGFormatArgNone, kRYGFormatMaxArgs);

	NSUInteger highest = 0, implicit = 0;
	for (NSUInteger i = 0; i < length; ) {
		if (chars[i] != '%') { i++; continue; }
		if (++i >= length) break;
		if (chars[i] == '%') { i++; continue; }

		NSUInteger position = 0, mark = i;
		while (i < length && chars[i] >= '0' && chars[i] <= '9') position = position * 10 + (chars[i++] - '0');
		if (i < length && chars[i] == '$' && position > 0) i++;
		else { position = 0; i = mark; }

		while (i < length && (chars[i] == '-' || chars[i] == '+' || chars[i] == ' '
							  || chars[i] == '#' || chars[i] == '0' || chars[i] == '\'')) i++;
		if (i < length && chars[i] == '*') return NO;
		while (i < length && chars[i] >= '0' && chars[i] <= '9') i++;
		if (i < length && chars[i] == '.') {
			i++;
			if (i < length && chars[i] == '*') return NO;
			while (i < length && chars[i] >= '0' && chars[i] <= '9') i++;
		}

		BOOL wide = NO;
		while (i < length) {
			unichar modifier = chars[i];
			if (modifier == 'l' || modifier == 'q' || modifier == 'z'
				|| modifier == 't' || modifier == 'j' || modifier == 'L') { wide = YES; i++; }
			else if (modifier == 'h') i++;
			else break;
		}
		if (i >= length) return NO;

		uint8_t kind = RYGFormatArgForConversion(chars[i++], wide);
		if (kind == RYGFormatArgNone) return NO;

		NSUInteger index = position ?: ++implicit;
		if (index > kRYGFormatMaxArgs) return NO;
		kinds[index - 1] = kind;
		highest = MAX(highest, index);
	}

	*countOut = highest;
	return YES;
}

// Mismatched placeholders crash -stringWithFormat: at the call site.
static BOOL RYGFormatMatchesSource(NSString *source, NSString *value) {
	uint8_t expected[kRYGFormatMaxArgs], actual[kRYGFormatMaxArgs];
	NSUInteger expectedCount = 0, actualCount = 0;
	if (!RYGReadFormatArgs(source, expected, &expectedCount)) return YES;
	if (!RYGReadFormatArgs(value, actual, &actualCount)) return NO;
	return expectedCount == actualCount && memcmp(expected, actual, expectedCount) == 0;
}

// Skips the user override on purpose: shipped English is what call sites pass args for.
static NSString *RYGShippedEnglishValue(NSString *key) {
	static NSBundle *english;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSBundle *resource = RYGLocalizationBundle();
		NSString *lproj = [resource pathForResource:@"en" ofType:@"lproj"];
		english = lproj.length ? [NSBundle bundleWithPath:lproj] : resource;
	});
	if (!english) return nil;

	NSString *value = [english localizedStringForKey:key value:kRYGMissing table:nil];
	return [value isEqualToString:kRYGMissing] ? nil : value;
}

NSString *RYGLocalizedString(NSString *key, NSString *fallback) {
	if (!key.length) return fallback ?: @"";

	NSBundle *bundle = RYGActiveLanguageBundle();
	if (!bundle) return fallback ?: key;

	NSString *value = [bundle localizedStringForKey:key value:kRYGMissing table:nil];
	if ([value isEqualToString:kRYGMissing]) return fallback ?: key;

	if ([key rangeOfString:@"%"].location != NSNotFound)
		return RYGFormatMatchesSource(key, value) ? value : key;

	// settings.* keys are identifiers, so their format lives in the English value.
	if ([value rangeOfString:@"%"].location == NSNotFound) return value;
	NSString *source = RYGShippedEnglishValue(key);
	if (!source) return value;
	return RYGFormatMatchesSource(source, value) ? value : source;
}

static NSString *RYGNativeLanguageName(NSString *code) {
	NSLocale *locale = [NSLocale localeWithLocaleIdentifier:code];
	NSString *name = [locale localizedStringForLocaleIdentifier:code] ?: [locale localizedStringForLanguageCode:code] ?: code;
	if (!name.length) return code;
	return [[name substringToIndex:1].uppercaseString stringByAppendingString:[name substringFromIndex:1]];
}

static void RYGAppendLanguagesFromPath(NSString *base, NSMutableArray *result, NSMutableSet *seen) {
	if (!RYGFileExists(base)) return;

	NSArray *items = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:nil] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *item in items) {
		if (![item hasSuffix:@".lproj"]) continue;

		NSString *code = item.stringByDeletingPathExtension;
		if (!code.length || [code isEqualToString:@"Base"] || [seen containsObject:code]) continue;

		NSString *strings = [[base stringByAppendingPathComponent:item] stringByAppendingPathComponent:@"Localizable.strings"];
		if (!RYGFileExists(strings)) continue;

		[seen addObject:code];
		[result addObject:@{@"code": code, @"native": RYGNativeLanguageName(code)}];
	}
}

NSArray<NSDictionary<NSString *, NSString *> *> *RYGAvailableLanguages(void) {
	NSMutableArray *result = [@[
		@{@"code": @"system", @"native": @"System"},
		@{@"code": @"en", @"native": @"English"}
	] mutableCopy];

	NSMutableSet *seen = [NSMutableSet setWithObject:@"en"];

	NSBundle *resource = RYGLocalizationBundle();
	if (resource.bundlePath.length) RYGAppendLanguagesFromPath(resource.bundlePath, result, seen);
	RYGAppendLanguagesFromPath(RYGLocalizationOverridePath(), result, seen);

	return result;
}

void RYGLocalizationReset(void) {
	@synchronized (RYGLanguagePrefKey) {
		gLanguageBundle = nil;
		gLanguageCode = nil;
		gResolvedLanguageCode = nil;
	}
}