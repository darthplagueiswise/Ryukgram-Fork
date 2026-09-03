// Sideload compatibility shim for IG. Upstream: github.com/asdfzxcvbn/zxPluginsInject.
//
// Four pieces:
//   1. SecItem* rebind — IG hard-codes `group.com.facebook.family` as its
//      keychain access group; sideload doesn't have it. Every query is
//      rewritten to the entitled group.
//   2. NSUserDefaults init redirect (appex-only) — appex reads what the
//      main app wrote so rich-notification previews fill in. Applying it
//      in the main process breaks NUX dismiss flags on IG 423+.
//   3. Main-app fan-out — cfprefsd caches group.* writes per-process; the
//      appex sees stale data until flush. Mirror writes through an explicit
//      shared-container `_initWithSuiteName:container:`. Skipped without
//      a real app-groups entitlement.
//   4. `containerURLForSecurityApplicationGroupIdentifier:` never returns
//      nil — IG's IGProductSaveStatusStore crashes inside `hasPrefix:nil`
//      otherwise. Real URL when entitled, Documents-dir sandbox path when not.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "../fishhook/fishhook.h"
#import "../../src/RYGFileLog.h"

@interface LSBundleProxy: NSObject
@property(nonatomic, assign, readonly) NSDictionary *entitlements;
@property(nonatomic, assign, readonly) NSDictionary *groupContainerURLs;
+ (instancetype)bundleProxyForCurrentProcess;
@end

@interface NSUserDefaults (Sideload)
- (id)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

static NSString *accessGroupId;

// Marker on the fan-out NSUserDefaults so its own writes don't recurse here.
static const void *kRYGFanoutTagKey = &kRYGFanoutTagKey;

// Dedup so the hot-path hooks below log each distinct event only once.
static void rygLogOnce(NSString *key, NSString *message) {
	static NSMutableSet *seen;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ seen = [NSMutableSet new]; });

	@synchronized(seen) {
		if ([seen containsObject:key]) return;
		[seen addObject:key];
	}

	RYGFileLogWrite(@"zxpi", message);
}

static BOOL createDirectoryIfNotExists(NSString *path) {
	if (!path.length) return NO;

	NSFileManager *fm = NSFileManager.defaultManager;
	if ([fm fileExistsAtPath:path]) return YES;

	NSError *error = nil;
	[fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
	return error == nil;
}

static NSURL *getAppGroupPathIfExists(void) {
	static NSURL *cached = nil;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		LSBundleProxy *proxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
		if (!proxy) { RYGFileLogWrite(@"zxpi", @"appGroup nil — no LSBundleProxy"); return; }

		NSDictionary *entitlements = proxy.entitlements;
		if (![entitlements isKindOfClass:NSDictionary.class]) { RYGFileLogWrite(@"zxpi", @"appGroup nil — no entitlements dict"); return; }

		NSArray *appGroups = entitlements[@"com.apple.security.application-groups"];
		if (![appGroups isKindOfClass:NSArray.class] || !appGroups.count) { RYGFileLogWrite(@"zxpi", @"appGroup nil — no application-groups entitlement"); return; }

		NSDictionary *paths = proxy.groupContainerURLs;
		if (![paths isKindOfClass:NSDictionary.class]) { RYGFileLogWrite(@"zxpi", @"appGroup nil — no groupContainerURLs"); return; }

		NSURL *url = paths[appGroups.firstObject];
		if ([url isKindOfClass:NSURL.class]) {
			cached = url;
			RYGFileLogWrite(@"zxpi", [NSString stringWithFormat:@"appGroup resolved %@ -> %@", appGroups.firstObject, url.path]);
		} else {
			RYGFileLogWrite(@"zxpi", [NSString stringWithFormat:@"appGroup nil — no container URL for %@", appGroups.firstObject]);
		}
	});

	return cached;
}

static BOOL rygIsAppExtensionProcess(void) {
	static BOOL cached = NO;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		cached = NSBundle.mainBundle.infoDictionary[@"NSExtension"] != nil;
	});

	return cached;
}

static NSURL *rygSharedContainerURLForSuite(NSString *suiteName) {
	NSURL *appGroup = getAppGroupPathIfExists();
	if (!appGroup || !suiteName.length) return nil;

	NSURL *container = [appGroup URLByAppendingPathComponent:suiteName isDirectory:YES];
	NSURL *prefs = [[container URLByAppendingPathComponent:@"Library" isDirectory:YES] URLByAppendingPathComponent:@"Preferences" isDirectory:YES];
	createDirectoryIfNotExists(prefs.path);

	return container;
}

static NSUserDefaults *rygFanoutDefaultsForSuite(NSString *suiteName) {
	if (!suiteName.length) return nil;

	static NSMutableDictionary<NSString *, NSUserDefaults *> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = NSMutableDictionary.dictionary;
	});

	@synchronized(cache) {
		NSUserDefaults *hit = cache[suiteName];
		if (hit) return hit;

		NSURL *container = rygSharedContainerURLForSuite(suiteName);
		if (!container) {
			rygLogOnce([@"fanout:" stringByAppendingString:suiteName],
					   [NSString stringWithFormat:@"fanout FAILED suite=%@ — no shared container", suiteName]);
			return nil;
		}

		NSUserDefaults *fanout = [[NSUserDefaults alloc] _initWithSuiteName:suiteName container:container];
		if (!fanout) {
			rygLogOnce([@"fanout:" stringByAppendingString:suiteName],
					   [NSString stringWithFormat:@"fanout FAILED suite=%@ — _initWithSuiteName:container: returned nil", suiteName]);
			return nil;
		}

		objc_setAssociatedObject(fanout, kRYGFanoutTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		cache[suiteName] = fanout;
		rygLogOnce([@"fanout:" stringByAppendingString:suiteName],
				   [NSString stringWithFormat:@"fanout active suite=%@ -> %@", suiteName, container.path]);
		return fanout;
	}
}

static NSString *rygSuiteNameForDefaults(NSUserDefaults *defaults) {
	if (![defaults respondsToSelector:@selector(_identifier)]) return nil;
	return ((NSString *(*)(id, SEL))objc_msgSend)(defaults, @selector(_identifier));
}

static BOOL rygShouldFanout(NSUserDefaults *defaults) {
	if (rygIsAppExtensionProcess()) return NO;
	if (!getAppGroupPathIfExists()) return NO;
	if (objc_getAssociatedObject(defaults, kRYGFanoutTagKey)) return NO;

	NSString *suite = rygSuiteNameForDefaults(defaults);
	return [suite hasPrefix:@"group"];
}

static NSUserDefaults *rygFanoutForDefaults(NSUserDefaults *defaults) {
	return rygFanoutDefaultsForSuite(rygSuiteNameForDefaults(defaults));
}

// === keychain access-group rebind ==========================================

static OSStatus (*origSecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*origSecItemDelete)(CFDictionaryRef);

static CFDictionaryRef rygFixedQuery(CFDictionaryRef query) {
	if (!query || !accessGroupId.length) return NULL;

	CFMutableDictionaryRef dict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
	if (dict) CFDictionarySetValue(dict, kSecAttrAccessGroup, (__bridge const void *)accessGroupId);

	return dict;
}

static OSStatus zxSecItemAdd(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = rygFixedQuery(q);
	OSStatus s = origSecItemAdd(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemCopyMatching(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = rygFixedQuery(q);
	OSStatus s = origSecItemCopyMatching(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemUpdate(CFDictionaryRef q, CFDictionaryRef u) {
	CFDictionaryRef d = rygFixedQuery(q);
	OSStatus s = origSecItemUpdate(d ?: q, u);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemDelete(CFDictionaryRef q) {
	CFDictionaryRef d = rygFixedQuery(q);
	OSStatus s = origSecItemDelete(d ?: q);
	if (d) CFRelease(d);
	return s;
}

static void rebindSecFuncs(void) {
	struct rebinding rebinds[] = {
		{"SecItemAdd", (void *)zxSecItemAdd, (void **)&origSecItemAdd},
		{"SecItemCopyMatching", (void *)zxSecItemCopyMatching, (void **)&origSecItemCopyMatching},
		{"SecItemUpdate", (void *)zxSecItemUpdate, (void **)&origSecItemUpdate},
		{"SecItemDelete", (void *)zxSecItemDelete, (void **)&origSecItemDelete},
	};

	rebind_symbols(rebinds, sizeof(rebinds) / sizeof(rebinds[0]));
}

// === CloudKit disable ======================================================

%hook CKContainer
- (id)_setupWithContainerID:(id)a options:(id)b { return nil; }
- (id)_initWithContainerIdentifier:(id)a { return nil; }
%end

%hook CKEntitlements
- (id)initWithEntitlementsDict:(NSDictionary *)entitlements {
	if (![entitlements isKindOfClass:NSDictionary.class]) return %orig(entitlements);

	NSMutableDictionary *m = entitlements.mutableCopy;
	[m removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
	[m removeObjectForKey:@"com.apple.developer.icloud-services"];
	return %orig(m.copy);
}

%end

// === NSFileManager group container URL =====================================

%hook NSFileManager

- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
	NSString *group = groupIdentifier.length ? groupIdentifier : @"group";

	if (NSURL *appGroupURL = getAppGroupPathIfExists()) {
		NSURL *url = [appGroupURL URLByAppendingPathComponent:group isDirectory:YES];
		createDirectoryIfNotExists(url.path);
		rygLogOnce([@"grp:" stringByAppendingString:group],
				   [NSString stringWithFormat:@"groupContainer %@ -> %@ (entitled)", group, url.path]);
		return url;
	}

	// No entitlement → sandbox path so the caller never sees nil.
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
	NSString *path = [docs stringByAppendingPathComponent:group];
	createDirectoryIfNotExists(path);

	rygLogOnce([@"grp:" stringByAppendingString:group],
			   [NSString stringWithFormat:@"groupContainer %@ -> %@ (sandbox fallback)", group, path]);

	return [NSURL fileURLWithPath:path isDirectory:YES];
}

%end

// === NSUserDefaults: appex redirect + main-app fan-out =====================

%hook NSUserDefaults

- (id)initWithSuiteName:(NSString *)suiteName {
	if (!rygIsAppExtensionProcess() || ![suiteName hasPrefix:@"group"]) return %orig;

	NSURL *container = rygSharedContainerURLForSuite(suiteName);
	if (!container) {
		rygLogOnce([@"suite:" stringByAppendingString:suiteName],
				   [NSString stringWithFormat:@"appex suite redirect FAILED %@ — no shared container, reading local store", suiteName]);
		return %orig;
	}

	rygLogOnce([@"suite:" stringByAppendingString:suiteName],
			   [NSString stringWithFormat:@"appex suite redirect %@ -> %@", suiteName, container.path]);

	return [self _initWithSuiteName:suiteName container:container];
}

- (id)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container {
	if (!rygIsAppExtensionProcess() || ![suiteName hasPrefix:@"group"]) {
		return %orig(suiteName, container);
	}

	NSURL *redirect = rygSharedContainerURLForSuite(suiteName);
	if (!redirect) {
		rygLogOnce([@"suite2:" stringByAppendingString:suiteName],
				   [NSString stringWithFormat:@"appex suite redirect FAILED (_init) %@ — no shared container", suiteName]);
		return %orig(suiteName, container);
	}

	return %orig(suiteName, redirect);
}

// Group-suite keys the appex reads as nil — the usual cause of a blank
// notification preview after the app was killed.
- (id)objectForKey:(NSString *)key {
	id value = %orig;

	if (!value && key.length && rygIsAppExtensionProcess()) {
		NSString *suite = rygSuiteNameForDefaults(self);
		if ([suite hasPrefix:@"group"]) {
			rygLogOnce([NSString stringWithFormat:@"miss:%@:%@", suite, key],
					   [NSString stringWithFormat:@"appex read MISS suite=%@ key=%@", suite, key]);
		}
	}

	return value;
}

- (void)setObject:(id)value forKey:(NSString *)key {
	%orig;

	if (!value || !key.length || !rygShouldFanout(self)) return;
	[rygFanoutForDefaults(self) setObject:value forKey:key];
	rygLogOnce([NSString stringWithFormat:@"fkey:%@:%@", rygSuiteNameForDefaults(self), key],
			   [NSString stringWithFormat:@"fanout mirror key=%@", key]);
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
	%orig;

	if (!key.length || !rygShouldFanout(self)) return;
	[rygFanoutForDefaults(self) setBool:value forKey:key];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
	%orig;

	if (!key.length || !rygShouldFanout(self)) return;
	[rygFanoutForDefaults(self) setInteger:value forKey:key];
}

- (void)setDouble:(double)value forKey:(NSString *)key {
	%orig;

	if (!key.length || !rygShouldFanout(self)) return;
	[rygFanoutForDefaults(self) setDouble:value forKey:key];
}

- (void)setFloat:(float)value forKey:(NSString *)key {
	%orig;

	if (!key.length || !rygShouldFanout(self)) return;
	[rygFanoutForDefaults(self) setFloat:value forKey:key];
}

- (void)setURL:(NSURL *)url forKey:(NSString *)key {
	%orig;

	if (!url || !key.length || !rygShouldFanout(self)) return;
	[rygFanoutForDefaults(self) setURL:url forKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
	%orig;

	if (!key.length || !rygShouldFanout(self)) return;

	NSUserDefaults *fanout = rygFanoutForDefaults(self);
	value ? [fanout setValue:value forKey:key] : [fanout removeObjectForKey:key];
	rygLogOnce([NSString stringWithFormat:@"fkey:%@:%@", rygSuiteNameForDefaults(self), key],
			   [NSString stringWithFormat:@"fanout mirror(value) key=%@", key]);
}

- (void)removeObjectForKey:(NSString *)key {
	%orig;

	if (!key.length || !rygShouldFanout(self)) return;
	[rygFanoutForDefaults(self) removeObjectForKey:key];
}

- (BOOL)synchronize {
	BOOL ok = %orig;

	if (rygShouldFanout(self)) {
		[rygFanoutForDefaults(self) synchronize];
	}

	return ok;
}

%end

// === keychain access-group bootstrap =======================================

static void setRequiredIDs(void) {
	NSDictionary *query = @{
		(__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
		(__bridge NSString *)kSecAttrAccount: @"zxPluginsInjectGenericEntry",
		(__bridge NSString *)kSecAttrService: @"",
		(__bridge id)kSecReturnAttributes: (id)kCFBooleanTrue,
	};

	CFDictionaryRef result = nil;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);

	if (status == errSecItemNotFound) {
		// AfterFirstUnlock is mandatory: the NSE is spawned for pushes while the device
		// is still locked, and the default WhenUnlocked class makes this item unreadable
		// then (-25308), leaving accessGroupId nil → SecItem rebind inactive → no preview.
		NSMutableDictionary *add = [query mutableCopy];
		add[(__bridge NSString *)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
		status = SecItemAdd((__bridge CFDictionaryRef)add, (CFTypeRef *)&result);
	} else if (status == errSecSuccess) {
		// Migrate items left by older builds (created WhenUnlocked) so locked launches stop failing.
		// Update query must not carry return-type keys.
		SecItemUpdate((__bridge CFDictionaryRef)@{
			(__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
			(__bridge NSString *)kSecAttrAccount: @"zxPluginsInjectGenericEntry",
			(__bridge NSString *)kSecAttrService: @"",
		}, (__bridge CFDictionaryRef)@{
			(__bridge NSString *)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
		});
	}

	if (status == errSecSuccess && result) {
		accessGroupId = [[(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup] copy];
	}

	if (!accessGroupId.length) {
		RYGFileLogWrite(@"zxpi", [NSString stringWithFormat:@"keychain bootstrap FAILED status=%d — SecItem rebind inactive", (int)status]);
	}

	if (result) CFRelease(result);
}

__attribute__((constructor)) static void init(void) {
	setRequiredIDs();
	rebindSecFuncs();

	RYGFLog(@"zxpi", @"loaded — appex=%@ accessGroup=%@ appGroup=%@",
			rygIsAppExtensionProcess() ? @"YES" : @"NO",
			accessGroupId ?: @"(none)",
			getAppGroupPathIfExists().path ?: @"(none)");
}