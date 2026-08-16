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

NSString *RYGLocalizedString(NSString *key, NSString *fallback) {
	if (!key.length) return fallback ?: @"";

	NSBundle *bundle = RYGActiveLanguageBundle();
	if (!bundle) return fallback ?: key;

	NSString *value = [bundle localizedStringForKey:key value:kRYGMissing table:nil];
	return [value isEqualToString:kRYGMissing] ? (fallback ?: key) : value;
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