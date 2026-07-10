// Forces Instagram's own UI language: leads the fbt locale inputs (preferredLocalizations /
// preferredLanguages) with the chosen code and installs a bundled fbt pack for its translations.

#import "../../Utils.h"
#import "../../Localization/SCILocalization.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSString *sCode;

static NSArray *sciLead(NSArray *orig) {
	if (!orig) return @[sCode];
	NSMutableArray *out = [NSMutableArray arrayWithObject:sCode];
	for (NSString *c in orig) if (![c isEqualToString:sCode]) [out addObject:c];
	return out;
}

static NSArray *(*orig_prefLoc)(id, SEL);
static NSArray *new_prefLoc(id self, SEL _cmd) {
	NSArray *o = orig_prefLoc(self, _cmd);
	return (self == [NSBundle mainBundle]) ? sciLead(o) : o;
}

static NSArray *(*orig_prefLocArr)(Class, SEL, NSArray *);
static NSArray *new_prefLocArr(Class self, SEL _cmd, NSArray *loc) {
	return sciLead(orig_prefLocArr(self, _cmd, loc));
}

static NSArray *(*orig_prefLangs)(Class, SEL);
static NSArray *new_prefLangs(Class self, SEL _cmd) {
	return sciLead(orig_prefLangs(self, _cmd));
}

static void sciInstallPackForCode(NSString *code) {
	NSString *src = [SCILocalizationBundle() pathForResource:[NSString stringWithFormat:@"fbt_language_pack_%@", code] ofType:@"bin"];
	if (!src) return;

	NSFileManager *fm = NSFileManager.defaultManager;
	NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/locales"];
	NSString *ver = nil;
	NSDate *newest = nil;
	for (NSString *v in [fm contentsOfDirectoryAtPath:root error:nil]) {
		NSDate *m = [fm attributesOfItemAtPath:[root stringByAppendingPathComponent:v] error:nil][NSFileModificationDate];
		if (!newest || [m compare:newest] == NSOrderedDescending) { newest = m; ver = v; }
	}
	if (!ver) return;

	NSString *dest = [NSString stringWithFormat:@"%@/%@/%@.lproj/fbt_language_pack.bin", root, ver, code];
	if ([fm fileExistsAtPath:dest]) return;
	[fm createDirectoryAtPath:[dest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
	[fm copyItemAtPath:src toPath:dest error:nil];
}

%ctor {
	NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
	NSString *code = [SCIUtils allTweakOptionsDisabled] ? @"system" : [SCIUtils getStringPref:@"ig_force_language"];

	// Clearing IG's locale memo forces an immediate re-resolve, else the change lags a launch.
	if (!code.length || [code isEqualToString:@"system"]) {
		if ([d objectForKey:@"AppleLanguages"]) {
			[d removeObjectForKey:@"AppleLanguages"];
			[d removeObjectForKey:@"METAI18NContext.prev.pref.langid"];
		}
		return;
	}

	sCode = code;
	[d setObject:@[code] forKey:@"AppleLanguages"];
	[d removeObjectForKey:@"METAI18NContext.prev.pref.langid"];
	sciInstallPackForCode(code);

	MSHookMessageEx(NSBundle.class, @selector(preferredLocalizations),
					(IMP)new_prefLoc, (IMP *)&orig_prefLoc);
	MSHookMessageEx(object_getClass(NSBundle.class), @selector(preferredLocalizationsFromArray:),
					(IMP)new_prefLocArr, (IMP *)&orig_prefLocArr);
	MSHookMessageEx(object_getClass(NSLocale.class), @selector(preferredLanguages),
					(IMP)new_prefLangs, (IMP *)&orig_prefLangs);
}
