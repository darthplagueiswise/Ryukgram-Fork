#import "SCILocalization.h"
#import <dlfcn.h>

NSString *const SCILanguagePrefKey = @"sci_language";

static NSBundle *gResourceBundle;
static NSBundle *gLanguageBundle;
static NSString *gLanguageCode;
static NSString *gResolvedLanguageCode;
static dispatch_once_t gResourceOnce;

static NSString *const kSCIMissing = @"\x01SCI_MISSING\x01";

NSString *SCILocalizationOverridePath(void) {
	NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
	return [lib stringByAppendingPathComponent:@"RyukGram.bundle"];
}

static BOOL SCIFileExists(NSString *path) {
	return path.length && [NSFileManager.defaultManager fileExistsAtPath:path];
}

static NSBundle *SCIResolveResourceBundle(void) {
	NSString *path = [[NSBundle mainBundle] pathForResource:@"RyukGram" ofType:@"bundle"];
	if (SCIFileExists(path)) return [NSBundle bundleWithPath:path];

	for (NSString *p in @[
		@"/var/jb/Library/Application Support/RyukGram.bundle",
		@"/Library/Application Support/RyukGram.bundle",
		SCILocalizationOverridePath()
	]) {
		if (SCIFileExists(p)) return [NSBundle bundleWithPath:p];
	}

	Dl_info info;
	if (dladdr((const void *)&SCIResolveResourceBundle, &info) && info.dli_fname) {
		NSString *dylib = [NSString stringWithUTF8String:info.dli_fname];
		path = [[dylib stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"RyukGram.bundle"];
		if (SCIFileExists(path)) return [NSBundle bundleWithPath:path];
	}

	return nil;
}

NSBundle *SCILocalizationBundle(void) {
	dispatch_once(&gResourceOnce, ^{
		gResourceBundle = SCIResolveResourceBundle();
	});
	return gResourceBundle;
}

static NSString *SCIPreferredLanguageCode(NSBundle *bundle) {
	if (gResolvedLanguageCode.length) return gResolvedLanguageCode;

	NSString *pref = [NSUserDefaults.standardUserDefaults stringForKey:SCILanguagePrefKey];
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

NSString *SCIResolvedLanguageCode(void) {
	NSBundle *bundle = SCILocalizationBundle();
	if (!bundle) return @"en";

	@synchronized (SCILanguagePrefKey) {
		return SCIPreferredLanguageCode(bundle);
	}
}

static NSBundle *SCILanguageBundleForCode(NSBundle *resource, NSString *code) {
	NSString *overrideStrings = [[SCILocalizationOverridePath() stringByAppendingPathComponent:[code stringByAppendingString:@".lproj"]] stringByAppendingPathComponent:@"Localizable.strings"];
	if (SCIFileExists(overrideStrings)) return [NSBundle bundleWithPath:overrideStrings.stringByDeletingLastPathComponent];

	NSString *lproj = [resource pathForResource:code ofType:@"lproj"];
	if (!lproj.length && ![code isEqualToString:@"en"]) lproj = [resource pathForResource:@"en" ofType:@"lproj"];

	return lproj.length ? [NSBundle bundleWithPath:lproj] : resource;
}

static NSBundle *SCIActiveLanguageBundle(void) {
	NSBundle *resource = SCILocalizationBundle();
	if (!resource) return nil;

	@synchronized (SCILanguagePrefKey) {
		NSString *code = SCIPreferredLanguageCode(resource);
		if (gLanguageBundle && [code isEqualToString:gLanguageCode]) return gLanguageBundle;

		gLanguageCode = code.copy;
		gLanguageBundle = SCILanguageBundleForCode(resource, code);
		return gLanguageBundle;
	}
}

NSString *SCILocalizedString(NSString *key, NSString *fallback) {
	if (!key.length) return fallback ?: @"";

	NSBundle *bundle = SCIActiveLanguageBundle();
	if (!bundle) return fallback ?: key;

	NSString *value = [bundle localizedStringForKey:key value:kSCIMissing table:nil];
	return [value isEqualToString:kSCIMissing] ? (fallback ?: key) : value;
}

static NSString *SCINativeLanguageName(NSString *code) {
	NSLocale *locale = [NSLocale localeWithLocaleIdentifier:code];
	NSString *name = [locale localizedStringForLocaleIdentifier:code] ?: [locale localizedStringForLanguageCode:code] ?: code;
	if (!name.length) return code;
	return [[name substringToIndex:1].uppercaseString stringByAppendingString:[name substringFromIndex:1]];
}

static void SCIAppendLanguagesFromPath(NSString *base, NSMutableArray *result, NSMutableSet *seen) {
	if (!SCIFileExists(base)) return;

	NSArray *items = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:nil] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *item in items) {
		if (![item hasSuffix:@".lproj"]) continue;

		NSString *code = item.stringByDeletingPathExtension;
		if (!code.length || [code isEqualToString:@"Base"] || [seen containsObject:code]) continue;

		NSString *strings = [[base stringByAppendingPathComponent:item] stringByAppendingPathComponent:@"Localizable.strings"];
		if (!SCIFileExists(strings)) continue;

		[seen addObject:code];
		[result addObject:@{@"code": code, @"native": SCINativeLanguageName(code)}];
	}
}

NSArray<NSDictionary<NSString *, NSString *> *> *SCIAvailableLanguages(void) {
	NSMutableArray *result = [@[
		@{@"code": @"system", @"native": @"System"},
		@{@"code": @"en", @"native": @"English"}
	] mutableCopy];

	NSMutableSet *seen = [NSMutableSet setWithObject:@"en"];

	NSBundle *resource = SCILocalizationBundle();
	if (resource.bundlePath.length) SCIAppendLanguagesFromPath(resource.bundlePath, result, seen);
	SCIAppendLanguagesFromPath(SCILocalizationOverridePath(), result, seen);

	return result;
}

void SCILocalizationReset(void) {
	@synchronized (SCILanguagePrefKey) {
		gLanguageBundle = nil;
		gLanguageCode = nil;
		gResolvedLanguageCode = nil;
	}
}
