#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import "../fishhook/fishhook.h"

@interface LSBundleProxy : NSObject
+ (instancetype)bundleProxyForCurrentProcess;
@property (nonatomic, readonly) NSDictionary *entitlements;
@property (nonatomic, readonly) NSDictionary *groupContainerURLs;
@end

static NSString *accessGroupId;
static NSURL *groupBaseURL;

static NSURL *baseGroupURL(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		LSBundleProxy *proxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
		NSArray *groups = proxy.entitlements[@"com.apple.security.application-groups"];
		NSURL *url = proxy.groupContainerURLs[groups.firstObject];
		groupBaseURL = [url isKindOfClass:NSURL.class] ? url : [NSURL fileURLWithPath:NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject isDirectory:YES];
	});
	return groupBaseURL;
}

static NSURL *fakeGroupURL(NSString *identifier) {
	if (!identifier.length) return nil;
	NSURL *url = [baseGroupURL() URLByAppendingPathComponent:identifier isDirectory:YES];
	[NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
	return url;
}

static BOOL isAppExtension(void) {
	static BOOL value;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		value = NSBundle.mainBundle.infoDictionary[@"NSExtension"] != nil;
	});
	return value;
}

%hook CKContainer
- (id)_setupWithContainerID:(id)a options:(id)b { return nil; }
- (id)_initWithContainerIdentifier:(id)a { return nil; }
%end

%hook CKEntitlements
- (id)initWithEntitlementsDict:(NSDictionary *)entitlements {
	NSMutableDictionary *dict = entitlements.mutableCopy;
	[dict removeObjectsForKeys:@[@"com.apple.developer.icloud-container-environment", @"com.apple.developer.icloud-services"]];
	return %orig(dict.copy);
}
%end

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
	return fakeGroupURL(groupIdentifier) ?: %orig(groupIdentifier);
}
%end

%hook NSUserDefaults
- (id)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container {
	return %orig(suiteName, isAppExtension() && [suiteName hasPrefix:@"group"] ? fakeGroupURL(suiteName) : container);
}
%end

static OSStatus (*origSecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*origSecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*origSecItemDelete)(CFDictionaryRef);

static CFDictionaryRef fixedQuery(CFDictionaryRef query) {
	if (!query || !accessGroupId.length) return NULL;
	CFMutableDictionaryRef dict = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
	if (dict) CFDictionarySetValue(dict, kSecAttrAccessGroup, (__bridge const void *)accessGroupId);
	return dict;
}

static OSStatus zxSecItemAdd(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = fixedQuery(q);
	OSStatus s = origSecItemAdd(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemCopyMatching(CFDictionaryRef q, CFTypeRef *r) {
	CFDictionaryRef d = fixedQuery(q);
	OSStatus s = origSecItemCopyMatching(d ?: q, r);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemUpdate(CFDictionaryRef q, CFDictionaryRef u) {
	CFDictionaryRef d = fixedQuery(q);
	OSStatus s = origSecItemUpdate(d ?: q, u);
	if (d) CFRelease(d);
	return s;
}

static OSStatus zxSecItemDelete(CFDictionaryRef q) {
	CFDictionaryRef d = fixedQuery(q);
	OSStatus s = origSecItemDelete(d ?: q);
	if (d) CFRelease(d);
	return s;
}

static BOOL loadAccessGroup(void) {
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrAccount: @"zxPluginsInjectGenericEntry",
		(__bridge id)kSecAttrService: @"",
		(__bridge id)kSecReturnAttributes: @YES
	};
	
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) status = SecItemAdd((__bridge CFDictionaryRef)query, &result);
	if (status != errSecSuccess || !result) return NO;
	
	NSDictionary *attrs = CFBridgingRelease(result);
	accessGroupId = [[attrs objectForKey:(__bridge id)kSecAttrAccessGroup] copy];
	return accessGroupId.length > 0;
}

__attribute__((constructor))
static void zxInit(void) {
	if (!loadAccessGroup()) return;
	
	struct rebinding binds[] = {
		{"SecItemAdd", (void *)zxSecItemAdd, (void **)&origSecItemAdd},
		{"SecItemCopyMatching", (void *)zxSecItemCopyMatching, (void **)&origSecItemCopyMatching},
		{"SecItemUpdate", (void *)zxSecItemUpdate, (void **)&origSecItemUpdate},
		{"SecItemDelete", (void *)zxSecItemDelete, (void **)&origSecItemDelete}
	};
	
	rebind_symbols(binds, sizeof(binds) / sizeof(binds[0]));
}