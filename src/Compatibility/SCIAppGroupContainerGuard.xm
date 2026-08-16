// Protect Instagram startup from sideload helpers that append a nil or
// non-string App Group identifier. Some pre-patched IPAs ship a separate
// `pluginsinject.dylib`; its NSFileManager hook can throw before Instagram has
// finished constructing its shared storage. Install outside that helper so a
// RyukGram DEB also protects already-patched IPAs.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#import "../SCIFileLog.h"

static NSURL *(*sciOrigContainerURL)(id, SEL, id);

static NSString *sciSafeAppGroupIdentifier(id value) {
	if (![value isKindOfClass:NSString.class]) return @"group.ryukgram.default";

	NSString *identifier = (NSString *)value;
	if (!identifier.length) return @"group.ryukgram.default";

	// App Group identifiers are one component. Reject paths instead of letting
	// an injector redirect the fallback outside Documents.
	if ([identifier containsString:@"/"] || [identifier isEqualToString:@"."] ||
		[identifier isEqualToString:@".."]) return @"group.ryukgram.default";
	return identifier;
}

static NSURL *sciFallbackContainerURL(id fileManager, NSString *identifier) {
	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
													 NSUserDomainMask, YES).lastObject;
	if (!documents.length) {
		NSString *home = NSHomeDirectory();
		documents = home.length ? [home stringByAppendingPathComponent:@"Documents"] : NSTemporaryDirectory();
	}

	NSString *path = [documents stringByAppendingPathComponent:identifier];
	NSError *error = nil;
	[(NSFileManager *)fileManager createDirectoryAtPath:path
							 withIntermediateDirectories:YES
										  attributes:nil
											   error:&error];
	return [NSURL fileURLWithPath:path isDirectory:YES];
}

static NSURL *sciGuardedContainerURL(id self, SEL _cmd, id groupIdentifier) {
	NSString *safeIdentifier = sciSafeAppGroupIdentifier(groupIdentifier);

	@try {
		NSURL *url = sciOrigContainerURL ? sciOrigContainerURL(self, _cmd, safeIdentifier) : nil;
		if ([url isKindOfClass:NSURL.class] && url.path.length) return url;
	} @catch (NSException *exception) {
		SCIFileLogWrite(@"appgroup-guard",
			[NSString stringWithFormat:@"recovered %@ from %@ (%@)",
				exception.name ?: @"NSException",
				NSStringFromClass([groupIdentifier class]) ?: @"nil",
				exception.reason ?: @"no reason"]);
	}

	return sciFallbackContainerURL(self, safeIdentifier);
}

__attribute__((constructor)) static void sciInstallAppGroupContainerGuard(void) {
	@autoreleasepool {
		Class fileManager = objc_getClass("NSFileManager");
		SEL selector = sel_registerName("containerURLForSecurityApplicationGroupIdentifier:");
		if (!fileManager || !class_getInstanceMethod(fileManager, selector)) return;

		MSHookMessageEx(fileManager, selector, (IMP)sciGuardedContainerURL,
						(IMP *)&sciOrigContainerURL);
	}
}
