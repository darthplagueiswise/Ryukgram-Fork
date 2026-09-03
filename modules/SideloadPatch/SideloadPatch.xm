// Sideload compat: keychain, app groups, CloudKit and container access for dup
// builds signed under an app-id that never matches the CFBundleIdentifier.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../modules/fishhook/fishhook.h"

// IG keys keychain/app-group state off the main bundle id; present the original
// so the login token round-trips across a cold launch under any install id.
static NSString *const kRYGOriginalBundleId = @"com.burbn.instagram";

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *) = NULL;
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef) = NULL;
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef) = NULL;

static IMP orig_CKEntitlements_initWithEntitlementsDict __attribute__((unused)) = NULL;
static IMP orig_CKContainer_setupWithContainerID __attribute__((unused)) = NULL;
static IMP orig_CKContainer_initWithContainerIdentifier __attribute__((unused)) = NULL;
static IMP orig_NSFileManager_containerURL __attribute__((unused)) = NULL;
static IMP orig_NSBundle_bundleIdentifier __attribute__((unused)) = NULL;
static IMP orig_NSBundle_bundleWithIdentifier __attribute__((unused)) = NULL;

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
        if (url) _appGroupPath = [url path];
    });
    return _appGroupPath;
}

static BOOL createDirectoryIfNotExists(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) return YES;
    return [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

// -- keychain access group resolution --
// Add a group-less sentinel item and read back the OS-assigned group — the only
// one that round-trips across a cold launch. Resolved lazily (keychain isn't
// ready in %ctor) and retried so an early miss doesn't poison later calls.

static NSString *ryg_accessGroupFromEntitlements(void) {
    Class LSBundleProxy = objc_getClass("LSBundleProxy");
    if (!LSBundleProxy) return nil;
    id proxy = ((id(*)(id, SEL))objc_msgSend)((id)LSBundleProxy, sel_registerName("bundleProxyForCurrentProcess"));
    if (!proxy) return nil;
    NSDictionary *ents = ((NSDictionary *(*)(id, SEL))objc_msgSend)(proxy, sel_registerName("entitlements"));
    if (![ents isKindOfClass:[NSDictionary class]]) return nil;

    id kg = ents[@"keychain-access-groups"];
    if ([kg isKindOfClass:[NSString class]] && [kg length] > 0) return kg;
    if ([kg isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)kg)
            if ([e isKindOfClass:[NSString class]] && [e length] > 0) return e;
    }
    id appId = ents[@"application-identifier"];
    return ([appId isKindOfClass:[NSString class]] && [appId length] > 0) ? appId : nil;
}

static NSString *ryg_accessGroupFromSentinel(void) {
    OSStatus (*copyFn)(CFDictionaryRef, CFTypeRef *) = orig_SecItemCopyMatching ?: SecItemCopyMatching;
    OSStatus (*addFn)(CFDictionaryRef, CFTypeRef *) = orig_SecItemAdd ?: SecItemAdd;

    NSDictionary *query = @{
        (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount:      @"RyukGramSideloadSentinel",
        (__bridge id)kSecAttrService:      @"RyukGramSideloadPatch",
        (__bridge id)kSecReturnAttributes: (__bridge id)kCFBooleanTrue,
    };
    NSMutableDictionary *attrs = [query mutableCopy];
    attrs[(__bridge id)kSecValueData] = [NSData data];

    CFTypeRef result = NULL;
    OSStatus status = copyFn((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound)
        status = addFn((__bridge CFDictionaryRef)attrs, &result);
    if (status != errSecSuccess || !result) {
        if (result) CFRelease(result);
        return nil;
    }

    id obj = (__bridge id)result;
    NSString *group = [obj isKindOfClass:[NSDictionary class]]
        ? [[obj objectForKey:(__bridge id)kSecAttrAccessGroup] copy] : nil;
    CFRelease(result);
    return group.length > 0 ? group : nil;
}

static NSString *ryg_resolveAccessGroup(void) {
    static NSString *cached = nil;
    static NSObject *lock = nil;
    static dispatch_once_t lockOnce = 0;
    dispatch_once(&lockOnce, ^{ lock = [NSObject new]; });

    @synchronized (lock) {
        if (cached.length > 0) return cached;
        NSString *g = ryg_accessGroupFromSentinel();
        if (g.length == 0) g = ryg_accessGroupFromEntitlements();
        if (g.length > 0) cached = [g copy];
        return cached;
    }
}

// -- per-bundle-id keychain namespace --
// Tag kSecAttrService per app so each dup keeps a private login slot inside the
// shared group. From the real bundle id, captured before the NSBundle spoof.
static NSString *gRYGServiceTag = nil;

static void ryg_buildServiceTag(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if (bid.length == 0) return;
    NSMutableString *san = [NSMutableString stringWithCapacity:bid.length];
    NSCharacterSet *alnum = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < bid.length; i++) {
        unichar c = [bid characterAtIndex:i];
        [san appendString:[alnum characterIsMember:c] ? [NSString stringWithCharacters:&c length:1] : @"_"];
    }
    gRYGServiceTag = [[@"__ryg_" stringByAppendingString:san] copy];
}

static BOOL ryg_shouldTagService(NSString *svc) {
    if (gRYGServiceTag.length == 0) return NO;
    if (![svc isKindOfClass:[NSString class]] || svc.length == 0) return NO;
    if ([svc hasPrefix:@"com.apple."]) return NO;
    if ([svc hasSuffix:gRYGServiceTag]) return NO;
    return YES;
}

// -- SecItem replacements: force the shared group + per-app service tag --

static CFDictionaryRef ryg_patchDict(CFDictionaryRef dict, BOOL injectGroupWhenMissing, BOOL tagService) {
    NSDictionary *src = (__bridge NSDictionary *)dict;
    if (![src isKindOfClass:[NSDictionary class]]) return NULL;

    NSMutableDictionary *m = nil;

    BOOL hasGroup = src[(__bridge id)kSecAttrAccessGroup] != nil;
    NSString *group = ryg_resolveAccessGroup();
    if (group.length > 0 && (hasGroup || injectGroupWhenMissing)) {
        m = m ?: [src mutableCopy];
        m[(__bridge id)kSecAttrAccessGroup] = group;
    }

    if (tagService) {
        NSString *svc = src[(__bridge id)kSecAttrService];
        if (ryg_shouldTagService(svc)) {
            m = m ?: [src mutableCopy];
            m[(__bridge id)kSecAttrService] = [svc stringByAppendingString:gRYGServiceTag];
        }
    }

    if (!m) return NULL;
    return (CFDictionaryRef)CFBridgingRetain(m);
}

static OSStatus replaced_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    CFDictionaryRef p = ryg_patchDict(attributes, YES, YES);
    OSStatus s = orig_SecItemAdd(p ?: attributes, result);
    if (p) CFRelease(p);
    return s;
}

static OSStatus replaced_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CFDictionaryRef p = ryg_patchDict(query, YES, YES);
    OSStatus s = orig_SecItemCopyMatching(p ?: query, result);
    if (p) CFRelease(p);
    return s;
}

static OSStatus replaced_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attrs) {
    CFDictionaryRef pq = ryg_patchDict(query, YES, YES);
    // Never tag the update payload's service — it would rename the item mid-update.
    CFDictionaryRef pa = ryg_patchDict(attrs, NO, NO);
    OSStatus s = orig_SecItemUpdate(pq ?: query, pa ?: attrs);
    if (pq) CFRelease(pq);
    if (pa) CFRelease(pa);
    return s;
}

static OSStatus replaced_SecItemDelete(CFDictionaryRef query) {
    CFDictionaryRef p = ryg_patchDict(query, YES, YES);
    OSStatus s = orig_SecItemDelete(p ?: query);
    if (p) CFRelease(p);
    return s;
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
    // --dup installs ask for a nil group; appending nil throws and crashes launch.
    if (!groupId.length) groupId = @"group.ryukgram.default";
    NSString *groupPath = getAppGroupPathIfExists();
    if (!groupPath) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
        NSString *fallback = [docs stringByAppendingPathComponent:groupId];
        createDirectoryIfNotExists(fallback);
        return [NSURL fileURLWithPath:fallback];
    }
    NSURL *url = [[NSURL fileURLWithPath:groupPath] URLByAppendingPathComponent:groupId];
    createDirectoryIfNotExists([url path]);
    return url;
}

// -- NSBundle: present Instagram's original id for the main bundle only --

static NSString *replaced_bundleIdentifier(id self, SEL _cmd) {
    NSString *orig = ((NSString *(*)(id, SEL))orig_NSBundle_bundleIdentifier)(self, _cmd);
    if (self == [NSBundle mainBundle] && ![orig isEqualToString:kRYGOriginalBundleId])
        return kRYGOriginalBundleId;
    return orig;
}

// Round-trip: code that looks the bundle back up by the spoofed id (IG's plugin
// asset provider, e.g. the reels repost icon) must get the real main bundle.
static id replaced_bundleWithIdentifier(id self, SEL _cmd, NSString *ident) {
    if ([ident isKindOfClass:[NSString class]] && [ident isEqualToString:kRYGOriginalBundleId])
        return [NSBundle mainBundle];
    return ((id(*)(id, SEL, NSString *))orig_NSBundle_bundleWithIdentifier)(self, _cmd, ident);
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

// -- init --

%ctor {
    @autoreleasepool {
        // Must run before the NSBundle spoof starts returning com.burbn.instagram.
        ryg_buildServiceTag();

        struct rebinding rebindings[] = {
            {"SecItemAdd",          (void *)replaced_SecItemAdd,          (void **)&orig_SecItemAdd},
            {"SecItemCopyMatching", (void *)replaced_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching},
            {"SecItemUpdate",       (void *)replaced_SecItemUpdate,       (void **)&orig_SecItemUpdate},
            {"SecItemDelete",       (void *)replaced_SecItemDelete,       (void **)&orig_SecItemDelete},
        };
        rebind_symbols(rebindings, 4);

        Class nsb = objc_getClass("NSBundle");
        if (nsb) {
            swizzleMethod(nsb, sel_registerName("bundleIdentifier"),
                          (IMP)replaced_bundleIdentifier, &orig_NSBundle_bundleIdentifier);
            // class method — swizzle on the metaclass
            swizzleMethod(object_getClass(nsb), sel_registerName("bundleWithIdentifier:"),
                          (IMP)replaced_bundleWithIdentifier, &orig_NSBundle_bundleWithIdentifier);
        }

        Class fm = objc_getClass("NSFileManager");
        if (fm) swizzleMethod(fm, sel_registerName("containerURLForSecurityApplicationGroupIdentifier:"),
                              (IMP)replaced_containerURL, &orig_NSFileManager_containerURL);

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
    }
}
