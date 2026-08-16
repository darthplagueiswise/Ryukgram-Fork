// Sideload compatibility is part of RyukGram.dylib. Do not inject a second
// zxPluginsInject/SideloadPatch dylib: double-hooking NSFileManager and SecItem
// is both unnecessary and a launch-crash risk.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>

#import "../../modules/fishhook/fishhook.h"
#import "../RYGFileLog.h"

static NSString *const kRYGFallbackGroup = @"group.ryukgram.default";

static OSStatus (*rygOrigSecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*rygOrigSecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*rygOrigSecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*rygOrigSecItemDelete)(CFDictionaryRef);
static NSURL *(*rygOrigContainerURL)(id, SEL, id);
static IMP rygOrigCKEntitlementsInit;
static IMP rygOrigCKContainerSetup;
static IMP rygOrigCKContainerInit;
static NSMutableSet<NSString *> *gRYGInstalledCompatibilityHooks;
static BOOL gRYGCompatibilityInstallScheduled;

static NSObject *RYGCompatibilityLock(void) {
	static NSObject *lock;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ lock = [NSObject new]; });
	return lock;
}

static const char *RYGUnqualifiedObjCType(const char *type) {
	while (type && strchr("rnNoORV", *type)) type++;
	return type;
}

static BOOL RYGObjectMethodMatches(Method method, NSUInteger explicitArguments) {
	if (!method || method_getNumberOfArguments(method) != explicitArguments + 2) return NO;
	char type[64] = {0};
	method_getReturnType(method, type, sizeof(type));
	if (*RYGUnqualifiedObjCType(type) != '@') return NO;
	for (NSUInteger index = 0; index < explicitArguments; index++) {
		memset(type, 0, sizeof(type));
		method_getArgumentType(method, (unsigned int)index + 2, type, sizeof(type));
		if (*RYGUnqualifiedObjCType(type) != '@') return NO;
	}
	return YES;
}

static BOOL RYGSelectorReturnsObjectWithoutArguments(id object, SEL selector) {
	if (!object || !selector || ![object respondsToSelector:selector]) return NO;
	return RYGObjectMethodMatches(class_getInstanceMethod(object_getClass(object), selector), 0);
}

static void RYGSideloadLogOnce(NSString *key, NSString *message) {
	static NSMutableSet<NSString *> *seen;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
	if (!key.length || !message.length) return;
	@synchronized (seen) {
		if ([seen containsObject:key]) return;
		[seen addObject:key];
	}
	RYGFileLogWrite(@"sideload", message);
}

static NSDictionary *RYGProcessEntitlements(void) {
	Class proxyClass = objc_getClass("LSBundleProxy");
	SEL currentSelector = sel_registerName("bundleProxyForCurrentProcess");
	SEL entitlementsSelector = sel_registerName("entitlements");
	if (!proxyClass || ![proxyClass respondsToSelector:currentSelector]) return nil;
	if (!RYGObjectMethodMatches(class_getClassMethod(proxyClass, currentSelector), 0)) return nil;
	id proxy = ((id (*)(id, SEL))objc_msgSend)((id)proxyClass, currentSelector);
	if (!RYGSelectorReturnsObjectWithoutArguments(proxy, entitlementsSelector)) return nil;
	id value = ((id (*)(id, SEL))objc_msgSend)(proxy, entitlementsSelector);
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray<NSString *> *RYGStringsFromEntitlement(id value) {
	NSMutableArray<NSString *> *strings = [NSMutableArray array];
	if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) {
		[strings addObject:value];
	} else if ([value isKindOfClass:NSArray.class]) {
		for (id candidate in (NSArray *)value) {
			if ([candidate isKindOfClass:NSString.class] && [(NSString *)candidate length]) {
				[strings addObject:candidate];
			}
		}
	}
	return strings.copy;
}

static NSString *RYGSafeGroupIdentifier(id value) {
	if (![value isKindOfClass:NSString.class]) return kRYGFallbackGroup;
	NSString *identifier = [(NSString *)value stringByTrimmingCharactersInSet:
		NSCharacterSet.whitespaceAndNewlineCharacterSet];
	static NSCharacterSet *invalidCharacters;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
		[allowed addCharactersInString:@"._-"];
		invalidCharacters = allowed.invertedSet;
	});
	if (!identifier.length || [identifier isEqualToString:@"."] ||
		identifier.length > 255 || [identifier isEqualToString:@".."] ||
		[identifier rangeOfCharacterFromSet:invalidCharacters].location != NSNotFound) {
		return kRYGFallbackGroup;
	}
	return identifier;
}

static BOOL RYGCreateDirectory(NSString *path) {
	if (!path.length) return NO;
	BOOL directory = NO;
	NSFileManager *manager = NSFileManager.defaultManager;
	if ([manager fileExistsAtPath:path isDirectory:&directory]) return directory;
	NSError *error = nil;
	BOOL ok = [manager createDirectoryAtPath:path
					withIntermediateDirectories:YES
							 attributes:nil
								  error:&error];
	if (!ok) {
		RYGSideloadLogOnce([@"mkdir:" stringByAppendingString:path],
			[NSString stringWithFormat:@"container mkdir failed: %@", error.localizedDescription ?: @"unknown"]);
	}
	return ok;
}

static NSURL *RYGEntitledContainerURL(NSString *identifier) {
	Class proxyClass = objc_getClass("LSBundleProxy");
	SEL currentSelector = sel_registerName("bundleProxyForCurrentProcess");
	SEL urlsSelector = sel_registerName("groupContainerURLs");
	if (!proxyClass || ![proxyClass respondsToSelector:currentSelector]) return nil;
	if (!RYGObjectMethodMatches(class_getClassMethod(proxyClass, currentSelector), 0)) return nil;
	id proxy = ((id (*)(id, SEL))objc_msgSend)((id)proxyClass, currentSelector);
	if (!RYGSelectorReturnsObjectWithoutArguments(proxy, urlsSelector)) return nil;
	id raw = ((id (*)(id, SEL))objc_msgSend)(proxy, urlsSelector);
	if (![raw isKindOfClass:NSDictionary.class]) return nil;
	NSDictionary *urls = raw;
	id exact = urls[identifier];
	if ([exact isKindOfClass:NSURL.class] && [(NSURL *)exact path].length) return exact;
	if (urls.count == 1) {
		id only = urls.allValues.firstObject;
		if ([only isKindOfClass:NSURL.class] && [(NSURL *)only path].length) return only;
	}
	return nil;
}

static NSURL *RYGFallbackContainerURL(NSString *identifier) {
	NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
		NSUserDomainMask, YES).firstObject;
	if (!base.length) {
		NSString *home = NSHomeDirectory();
		base = home.length ? [home stringByAppendingPathComponent:@"Library/Application Support"]
			: NSTemporaryDirectory();
	}
	NSString *root = [[base stringByAppendingPathComponent:@"RyukGram"]
		stringByAppendingPathComponent:@"AppGroups"];
	NSString *path = [root stringByAppendingPathComponent:identifier];
	RYGCreateDirectory(path);
	return [NSURL fileURLWithPath:path isDirectory:YES];
}

static NSURL *RYGGuardedContainerURL(id self, SEL selector, id rawIdentifier) {
	NSString *identifier = RYGSafeGroupIdentifier(rawIdentifier);
	@try {
		NSURL *original = rygOrigContainerURL ?
			rygOrigContainerURL(self, selector, identifier) : nil;
		if ([original isKindOfClass:NSURL.class] && original.path.length) return original;
	} @catch (NSException *exception) {
		RYGSideloadLogOnce([@"container-exception:" stringByAppendingString:identifier],
			[NSString stringWithFormat:@"recovered %@ (%@), input=%@",
				exception.name ?: @"NSException", exception.reason ?: @"no reason",
				NSStringFromClass([rawIdentifier class]) ?: @"nil"]);
	}

	NSURL *entitled = RYGEntitledContainerURL(identifier);
	if (entitled) return entitled;
	NSURL *fallback = RYGFallbackContainerURL(identifier);
	RYGSideloadLogOnce([@"container-fallback:" stringByAppendingString:identifier],
		[NSString stringWithFormat:@"%@ -> %@", identifier, fallback.path]);
	return fallback;
}

static NSString *RYGAccessGroupFromEntitlements(void) {
	NSDictionary *entitlements = RYGProcessEntitlements();
	if (!entitlements) return nil;
	NSArray<NSString *> *groups = RYGStringsFromEntitlement(entitlements[@"keychain-access-groups"]);
	if (groups.count) return groups.firstObject;
	id applicationIdentifier = entitlements[@"application-identifier"];
	return [applicationIdentifier isKindOfClass:NSString.class] &&
		[(NSString *)applicationIdentifier length] ? applicationIdentifier : nil;
}

static NSString *RYGAccessGroupFromSentinel(void) {
	if (!rygOrigSecItemCopyMatching || !rygOrigSecItemAdd) return nil;
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrAccount: @"RyukGramSideloadSentinel",
		(__bridge id)kSecAttrService: @"RyukGramSideloadCompatibility",
		(__bridge id)kSecReturnAttributes: @YES,
	};
	CFTypeRef result = NULL;
	OSStatus status = rygOrigSecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) {
		NSMutableDictionary *add = query.mutableCopy;
		add[(__bridge id)kSecValueData] = [NSData data];
		add[(__bridge id)kSecAttrAccessible] =
			(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
		status = rygOrigSecItemAdd((__bridge CFDictionaryRef)add, &result);
		if (status == errSecDuplicateItem) {
			if (result) { CFRelease(result); result = NULL; }
			status = rygOrigSecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
		}
	}
	NSString *group = nil;
	if (status == errSecSuccess && result) {
		id object = (__bridge id)result;
		id value = [object isKindOfClass:NSDictionary.class] ?
			object[(__bridge id)kSecAttrAccessGroup] : nil;
		if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) group = [value copy];
	}
	if (result) CFRelease(result);
	return group;
}

static NSString *RYGResolvedAccessGroup(void) {
	static NSString *cached;
	static NSObject *lock;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ lock = [NSObject new]; });
	@synchronized (lock) {
		if (cached.length) return cached;
		cached = [RYGAccessGroupFromEntitlements() copy];
		if (!cached.length) cached = [RYGAccessGroupFromSentinel() copy];
		return cached;
	}
}

static CFDictionaryRef RYGPatchKeychainDictionary(CFDictionaryRef dictionary) {
	if (!dictionary) return NULL;
	id object = (__bridge id)dictionary;
	if (![object isKindOfClass:NSDictionary.class]) return NULL;
	NSDictionary *source = object;
	id requested = source[(__bridge id)kSecAttrAccessGroup];
	if (!requested) return NULL;

	NSArray<NSString *> *entitled = RYGStringsFromEntitlement(
		RYGProcessEntitlements()[@"keychain-access-groups"]);
	if ([requested isKindOfClass:NSString.class] && [entitled containsObject:requested]) return NULL;
	NSString *replacement = RYGResolvedAccessGroup();
	if (!replacement.length || [requested isEqual:replacement]) return NULL;

	NSMutableDictionary *patched = source.mutableCopy;
	patched[(__bridge id)kSecAttrAccessGroup] = replacement;
	return (__bridge_retained CFDictionaryRef)patched;
}

static OSStatus RYGSecItemAdd(CFDictionaryRef query, CFTypeRef *result) {
	CFDictionaryRef patched = RYGPatchKeychainDictionary(query);
	OSStatus status = rygOrigSecItemAdd(patched ?: query, result);
	if (patched) CFRelease(patched);
	return status;
}

static OSStatus RYGSecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
	CFDictionaryRef patched = RYGPatchKeychainDictionary(query);
	OSStatus status = rygOrigSecItemCopyMatching(patched ?: query, result);
	if (patched) CFRelease(patched);
	return status;
}

static OSStatus RYGSecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
	CFDictionaryRef patched = RYGPatchKeychainDictionary(query);
	OSStatus status = rygOrigSecItemUpdate(patched ?: query, attributes);
	if (patched) CFRelease(patched);
	return status;
}

static OSStatus RYGSecItemDelete(CFDictionaryRef query) {
	CFDictionaryRef patched = RYGPatchKeychainDictionary(query);
	OSStatus status = rygOrigSecItemDelete(patched ?: query);
	if (patched) CFRelease(patched);
	return status;
}

static BOOL RYGHasICloudEntitlements(void) {
	NSDictionary *entitlements = RYGProcessEntitlements();
	// If LaunchServices is not ready yet, preserve native CloudKit behavior.
	if (!entitlements) return YES;
	return RYGStringsFromEntitlement(entitlements[@"com.apple.developer.icloud-services"]).count > 0 ||
		RYGStringsFromEntitlement(entitlements[@"com.apple.developer.ubiquity-container-identifiers"]).count > 0;
}

static id RYGCKEntitlementsInit(id self, SEL selector, id rawEntitlements) {
	if (RYGHasICloudEntitlements() || ![rawEntitlements isKindOfClass:NSDictionary.class]) {
		return rygOrigCKEntitlementsInit ?
			((id (*)(id, SEL, id))rygOrigCKEntitlementsInit)(self, selector, rawEntitlements) : nil;
	}
	NSMutableDictionary *sanitized = [(NSDictionary *)rawEntitlements mutableCopy];
	[sanitized removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
	[sanitized removeObjectForKey:@"com.apple.developer.icloud-services"];
	return rygOrigCKEntitlementsInit ?
		((id (*)(id, SEL, id))rygOrigCKEntitlementsInit)(self, selector, sanitized.copy) : nil;
}

static id RYGCKContainerSetup(id self, SEL selector, id containerID, id options) {
	if (!RYGHasICloudEntitlements()) return nil;
	return rygOrigCKContainerSetup ?
		((id (*)(id, SEL, id, id))rygOrigCKContainerSetup)(self, selector, containerID, options) : nil;
}

static id RYGCKContainerInit(id self, SEL selector, id identifier) {
	if (!RYGHasICloudEntitlements()) return nil;
	return rygOrigCKContainerInit ?
		((id (*)(id, SEL, id))rygOrigCKContainerInit)(self, selector, identifier) : nil;
}

static void RYGInstallMethodHook(Class cls, SEL selector, NSUInteger argumentCount,
								 IMP replacement, IMP *original) {
	Method method = (cls && selector) ? class_getInstanceMethod(cls, selector) : NULL;
	if (!RYGObjectMethodMatches(method, argumentCount)) return;
	NSString *key = [NSString stringWithFormat:@"%@#%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
	@synchronized(RYGCompatibilityLock()) {
		if (!gRYGInstalledCompatibilityHooks) gRYGInstalledCompatibilityHooks = [NSMutableSet set];
		if ([gRYGInstalledCompatibilityHooks containsObject:key]) return;
		[gRYGInstalledCompatibilityHooks addObject:key];
	}
	MSHookMessageEx(cls, selector, replacement, original);
}

static void RYGInstallObjCCompatibilityHooks(void) {
	RYGInstallMethodHook(objc_getClass("NSFileManager"),
		sel_registerName("containerURLForSecurityApplicationGroupIdentifier:"),
		1, (IMP)RYGGuardedContainerURL, (IMP *)&rygOrigContainerURL);
	RYGInstallMethodHook(objc_getClass("CKEntitlements"),
		sel_registerName("initWithEntitlementsDict:"),
		1, (IMP)RYGCKEntitlementsInit, &rygOrigCKEntitlementsInit);
	Class cloudContainer = objc_getClass("CKContainer");
	RYGInstallMethodHook(cloudContainer, sel_registerName("_setupWithContainerID:options:"),
		2, (IMP)RYGCKContainerSetup, &rygOrigCKContainerSetup);
	RYGInstallMethodHook(cloudContainer, sel_registerName("_initWithContainerIdentifier:"),
		1, (IMP)RYGCKContainerInit, &rygOrigCKContainerInit);
}

static void RYGScheduleObjCCompatibilityInstall(void) {
	@synchronized(RYGCompatibilityLock()) {
		if (gRYGCompatibilityInstallScheduled) return;
		gRYGCompatibilityInstallScheduled = YES;
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			@synchronized(RYGCompatibilityLock()) { gRYGCompatibilityInstallScheduled = NO; }
			RYGInstallObjCCompatibilityHooks();
		});
}

static void RYGCompatibilityImageDidLoad(const struct mach_header *header, intptr_t slide) {
	(void)header;
	(void)slide;
	RYGScheduleObjCCompatibilityInstall();
}

__attribute__((constructor)) static void RYGInstallSideloadCompatibility(void) {
	@autoreleasepool {
		rygOrigSecItemAdd = SecItemAdd;
		rygOrigSecItemCopyMatching = SecItemCopyMatching;
		rygOrigSecItemUpdate = SecItemUpdate;
		rygOrigSecItemDelete = SecItemDelete;
		struct rebinding keychain[] = {
			{"SecItemAdd", (void *)RYGSecItemAdd, (void **)&rygOrigSecItemAdd},
			{"SecItemCopyMatching", (void *)RYGSecItemCopyMatching, (void **)&rygOrigSecItemCopyMatching},
			{"SecItemUpdate", (void *)RYGSecItemUpdate, (void **)&rygOrigSecItemUpdate},
			{"SecItemDelete", (void *)RYGSecItemDelete, (void **)&rygOrigSecItemDelete},
		};
		rebind_symbols(keychain, sizeof(keychain) / sizeof(keychain[0]));

		RYGInstallObjCCompatibilityHooks();
		_dyld_register_func_for_add_image(RYGCompatibilityImageDidLoad);

		RYGSideloadLogOnce(@"installed", @"integrated compatibility installed in RyukGram.dylib");
	}
}
