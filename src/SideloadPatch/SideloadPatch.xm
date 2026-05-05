// Sideload compatibility patch for Instagram.
// Fixes app groups and CloudKit when sideloaded.
// Keychain rewriting is intentionally opt-in: forcing SecItem access groups on
// every call can make Instagram auth tokens inaccessible after reinstall/resign.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../modules/fishhook/fishhook.h"

static NSString *bundleId = nil;
static NSString *accessGroupId = nil;

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef) = NULL;

static IMP orig_CKEntitlements_initWithEntitlementsDict __attribute__((unused)) = NULL;
static IMP orig_CKContainer_setupWithContainerID __attribute__((unused)) = NULL;
static IMP orig_CKContainer_initWithContainerIdentifier __attribute__((unused)) = NULL;
static IMP orig_NSFileManager_containerURL __attribute__((unused)) = NULL;

static NSString * const kSCISideloadKeychainRewriteEnabledKey = @"sci_sideload_keychain_rewrite_enabled";

static BOOL sideloadKeychainRewriteEnabled(void) {
    // Default is OFF. This preserves Instagram's own keychain behavior and avoids
    // logouts when the IPA is installed over itself with the same signing identity.
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSCISideloadKeychainRewriteEnabledKey];
}

// -- app group path --

static NSString *_appGroupPath = nil;
static dispatch_once_t _appGroupOnce = 0;

static NSString *getAppGroupPathIfExists(void) {
    dispatch_once(&_appGroupOnce, ^{
        Class LSBundleProxy = objc_getClass("LSBundleProxy");
        if (!LSBundleProxy) return;

        id proxy = ((id(*)(id, SEL))objc_msgSend)(
            (id)LSBundleProxy, sel_registerName("bundleProxyForCurrentProcess"));
        if (!proxy) return;

        NSDictionary *ents = ((NSDictionary *(*)(id, SEL))objc_msgSend)(
            proxy, sel_registerName("entitlements"));
        if (!ents || ![ents isKindOfClass:[NSDictionary class]]) return;

        NSArray *groups = ents[@"com.apple.security.application-groups"];
        if (!groups || groups.count == 0) return;

        NSDictionary *urls = ((NSDictionary *(*)(id, SEL))objc_msgSend)(
            proxy, sel_registerName("groupContainerURLs"));
        if (!urls || ![urls isKindOfClass:[NSDictionary class]]) return;

        NSURL *url = urls[groups.firstObject];
        if (url) _appGroupPath = [[url path] copy];
    });
    return _appGroupPath;
}

static BOOL createDirectoryIfNotExists(NSString *path) {
    if (!path.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDir]) return isDir;
    return [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

// -- SecItem replacements: opt-in and non-destructive --

static NSMutableDictionary *queryByAddingAccessGroupIfMissing(CFDictionaryRef input) {
    if (!input || !accessGroupId.length || !sideloadKeychainRewriteEnabled()) return nil;

    NSDictionary *dict = (__bridge NSDictionary *)input;
    id existing = dict[(__bridge id)kSecAttrAccessGroup];
    if (existing) return nil;

    NSMutableDictionary *q = [dict mutableCopy];
    q[(__bridge id)kSecAttrAccessGroup] = accessGroupId;
    return q;
}

static OSStatus replaced_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSMutableDictionary *q = queryByAddingAccessGroupIfMissing(attributes);
    if (q) return orig_SecItemAdd((__bridge CFDictionaryRef)q, result);
    return orig_SecItemAdd(attributes, result);
}

static OSStatus replaced_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSMutableDictionary *q = queryByAddingAccessGroupIfMissing(query);
    if (q) return orig_SecItemCopyMatching((__bridge CFDictionaryRef)q, result);
    return orig_SecItemCopyMatching(query, result);
}

static OSStatus replaced_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attrs) {
    NSMutableDictionary *q = queryByAddingAccessGroupIfMissing(query);
    if (q) return orig_SecItemUpdate((__bridge CFDictionaryRef)q, attrs);
    return orig_SecItemUpdate(query, attrs);
}

static OSStatus replaced_SecItemDelete(CFDictionaryRef query) {
    // Do not rewrite destructive deletes. Rewriting broad IG deletes to a forced
    // access group is the risky path that can wipe/invalidate auth material.
    return orig_SecItemDelete(query);
}

// -- CloudKit patches: strip iCloud entitlements, disable container init --

static id replaced_CKEntitlements_init(id self, SEL _cmd, NSDictionary *dict) {
    NSMutableDictionary *d = [dict mutableCopy];
    [d removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
    [d removeObjectForKey:@"com.apple.developer.icloud-services"];
    return ((id(*)(id, SEL, NSDictionary *))orig_CKEntitlements_initWithEntitlementsDict)(self, _cmd, [d copy]);
}

static id replaced_CKContainer_setup(id self, SEL _cmd, id containerID, id options) {
    return nil;
}

static id replaced_CKContainer_init(id self, SEL _cmd, id identifier) {
    return nil;
}

// -- NSFileManager: redirect app group container to a local fallback --

static NSURL *replaced_containerURL(id self, SEL _cmd, NSString *groupId) {
    NSString *groupPath = getAppGroupPathIfExists();
    if (groupPath.length) {
        createDirectoryIfNotExists(groupPath);
        return [NSURL fileURLWithPath:groupPath];
    }

    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).lastObject;
    NSString *base = appSupport.length ? appSupport : NSTemporaryDirectory();
    NSString *safeGroup = groupId.length ? groupId : @"unknown-group";
    NSString *fallback = [[base stringByAppendingPathComponent:@"RyukGramAppGroups"] stringByAppendingPathComponent:safeGroup];
    createDirectoryIfNotExists(fallback);
    return [NSURL fileURLWithPath:fallback];
}

// -- swizzle helper: walks class hierarchy, handles inherited methods --

static void swizzleMethod(Class cls, SEL sel, IMP newIMP, IMP *outOrig) {
    if (!cls) return;
    Class cur = cls;
    while (cur) {
        unsigned int count = 0;
        Method *list = class_copyMethodList(cur, &count);
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(list[i]) == sel) {
                if (cur == cls) {
                    *outOrig = method_setImplementation(list[i], newIMP);
                } else {
                    *outOrig = method_getImplementation(list[i]);
                    class_addMethod(cls, sel, newIMP, method_getTypeEncoding(list[i]));
                }
                free(list);
                return;
            }
        }
        free(list);
        cur = class_getSuperclass(cur);
    }
}

// -- keychain bootstrap: discover the access group assigned to this app --

static void bootstrapKeychainAccessGroup(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount:      @"RyukGramSideloadPatch",
        (__bridge id)kSecAttrService:      @"RyukGram",
        (__bridge id)kSecReturnAttributes: @YES,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = [@"1" dataUsingEncoding:NSUTF8StringEncoding];
        status = SecItemAdd((__bridge CFDictionaryRef)add, &result);
    }

    if (status == errSecSuccess && result) {
        bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSDictionary *attrs = (__bridge NSDictionary *)result;
        NSString *group = attrs[(__bridge id)kSecAttrAccessGroup];
        if (group) accessGroupId = [group copy];
        CFRelease(result);
    }
}

static void installKeychainRebindingsIfNeeded(void) {
    if (!sideloadKeychainRewriteEnabled()) return;

    bootstrapKeychainAccessGroup();
    if (!accessGroupId.length) return;

    struct rebinding rebindings[] = {
        {"SecItemAdd",          (void *)replaced_SecItemAdd,          (void **)&orig_SecItemAdd},
        {"SecItemCopyMatching", (void *)replaced_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
        {"SecItemUpdate",       (void *)replaced_SecItemUpdate,       (void **)&orig_SecItemUpdate},
        {"SecItemDelete",       (void *)replaced_SecItemDelete,       (void **)&orig_SecItemDelete},
    };
    rebind_symbols(rebindings, 4);
}

// -- init --

%ctor {
    @autoreleasepool {
        installKeychainRebindingsIfNeeded();

        // patch NSFileManager for app group container fallback
        Class fm = objc_getClass("NSFileManager");
        if (fm) swizzleMethod(fm, sel_registerName("containerURLForSecurityApplicationGroupIdentifier:"),
                              (IMP)replaced_containerURL, &orig_NSFileManager_containerURL);

        // patch CloudKit to prevent crashes from missing entitlements
        Class ckEnt = objc_getClass("CKEntitlements");
        if (ckEnt) swizzleMethod(ckEnt, sel_registerName("initWithEntitlementsDict:"),
                                 (IMP)replaced_CKEntitlements_init, &orig_CKEntitlements_initWithEntitlementsDict);

        Class ckCon = objc_getClass("CKContainer");
        if (ckCon) {
            swizzleMethod(ckCon, sel_registerName("_setupWithContainerID:options:"),
                          (IMP)replaced_CKContainer_setup, &orig_CKContainer_setupWithContainerID);
            swizzleMethod(ckCon, sel_registerName("_initWithContainerIdentifier:"),
                          (IMP)replaced_CKContainer_init, &orig_CKContainer_initWithContainerIdentifier);
        }

        // NSUserDefaults _initWithSuiteName:container: intentionally not patched —
        // crashes on current IG versions. the NSFileManager patch covers the
        // group container redirect which is what actually matters.
    }
}
