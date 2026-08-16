#import "RYGDeviceIdentity.h"
#import "../../Utils.h"
#import "../General/RYGCacheManager.h"
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

NSString *const RYGDeviceSpoofEnabledKey     = @"ryg_devicespoof_enabled";
NSString *const RYGDeviceSpoofDeviceIDKey    = @"ryg_devicespoof_device_id";
NSString *const RYGDeviceSpoofFDIDKey        = @"ryg_devicespoof_fdid";
NSString *const RYGDeviceSpoofLoginButtonKey = @"ryg_devicespoof_login_button";
NSString *const RYGDeviceSpoofBlockDeviceCheckKey = @"ryg_devicespoof_block_devicecheck";

static NSString *const kOrigDeviceIDKey = @"ryg_devicespoof_orig_deviceid";
static NSString *const kOrigFDIDKey      = @"ryg_devicespoof_orig_fbdeviceid";

static NSString *const kIGAppGroup = @"group.com.burbn.instagram";

// IG reads these at launch; the getter hooks don't cover direct keychain reads,
// so the spoof is written here too.
static NSString *const kKCDeviceIDService = @"instagram.deviceid";
static NSString *const kKCFDIDService      = @"com.facebook.deviceid";
static NSString *const kKCUniqueIDService  = @"unique_id";   // device-id mirror
static NSString *const kKCUniqueIDAccount  = @"instagram";
static NSString *const kKCMIDService        = @"instagram.mid";
static NSString *const kKCMIDHeaderService  = @"com.instagram.device";
static NSString *const kKCMIDHeaderAccount  = @"com.instagram.device.midheader";
static NSString *const kKCDeviceLockedService = @"com.facebook.deviceLockedStatusFlag";
static NSString *const kKCDeviceLockedAccount = @"fb_locked_device_flag";

static NSString *RYGKeychainRead(NSString *svc) {
    NSDictionary *q = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                         (__bridge id)kSecAttrService: svc,
                         (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
                         (__bridge id)kSecReturnData: @YES };
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess || !out) return nil;
    NSData *data = (__bridge_transfer NSData *)out;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static BOOL RYGKeychainWrite(NSString *svc, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *q = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                         (__bridge id)kSecAttrService: svc };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q,
                                (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
    return st == errSecSuccess;
}

static BOOL RYGKeychainWriteAccount(NSString *svc, NSString *acct, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *q = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                         (__bridge id)kSecAttrService: svc,
                         (__bridge id)kSecAttrAccount: acct };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q,
                                (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
    return st == errSecSuccess;
}

static void RYGKeychainDeleteService(NSString *svc) {
    SecItemDelete((__bridge CFDictionaryRef)@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: svc });
}

static NSString *RYGNewUUID(void) {
    return [[NSUUID UUID] UUIDString];
}

@implementation RYGDeviceIdentity

+ (BOOL)spoofingEnabled {
    return [RYGUtils getBoolPref:RYGDeviceSpoofEnabledKey];
}

+ (NSString *)spoofedDeviceID {
    NSString *v = [RYGUtils getStringPref:RYGDeviceSpoofDeviceIDKey];
    if (v.length == 0) {
        v = RYGNewUUID();
        [RYGUtils setPref:v forKey:RYGDeviceSpoofDeviceIDKey];
    }
    return v;
}

+ (NSString *)spoofedFDID {
    NSString *v = [RYGUtils getStringPref:RYGDeviceSpoofFDIDKey];
    if (v.length == 0) {
        v = RYGNewUUID();
        [RYGUtils setPref:v forKey:RYGDeviceSpoofFDIDKey];
    }
    return v;
}

+ (NSString *)nativeDeviceID {
    Class foa = NSClassFromString(@"_TtC23FOATokenRegistrationKit23FOATokenRegistrationKit");
    if (foa && [foa respondsToSelector:@selector(getDeviceId)]) {
        @try {
            NSString *v = ((id(*)(id, SEL))objc_msgSend)(foa, @selector(getDeviceId));
            if ([v isKindOfClass:[NSString class]]) return v;
        } @catch (__unused id e) {}
    }
    return nil;
}

+ (NSString *)nativeFDID {
    id fdid = nil;
    Class cls = NSClassFromString(@"FBFamilyDeviceID");
    if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
        @try {
            id shared = ((id(*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance));
            SEL sel = NSSelectorFromString(@"cachedFamilyDeviceIDWithConfiguration:SourceFile:SourceLine:");
            if ([shared respondsToSelector:sel])
                fdid = ((id(*)(id, SEL, id, id, id))objc_msgSend)(shared, sel, nil, @"RyukGram", @0);
        } @catch (__unused id e) {}
    }
    return [fdid isKindOfClass:[NSString class]] ? fdid : nil;
}

+ (NSString *)effectiveDeviceID {
    if ([self spoofingEnabled]) return [self spoofedDeviceID];
    return [self nativeDeviceID] ?: [self spoofedDeviceID];
}

// Capture IG's real ids once, before the first overwrite, so revert is exact.
+ (void)backupOriginalsIfNeeded {
    if ([RYGUtils getStringPref:kOrigDeviceIDKey].length == 0) {
        NSString *real = RYGKeychainRead(kKCDeviceIDService);
        if (real.length) [RYGUtils setPref:real forKey:kOrigDeviceIDKey];
    }
    if ([RYGUtils getStringPref:kOrigFDIDKey].length == 0) {
        NSString *real = RYGKeychainRead(kKCFDIDService);
        if (real.length) [RYGUtils setPref:real forKey:kOrigFDIDKey];
    }
}

+ (void)applySpoofToKeychain {
    [self backupOriginalsIfNeeded];
    RYGKeychainWrite(kKCDeviceIDService, [self spoofedDeviceID]);
    RYGKeychainWrite(kKCFDIDService, [self spoofedFDID]);
    RYGKeychainWriteAccount(kKCUniqueIDService, kKCUniqueIDAccount, [self spoofedDeviceID]);
}

// Clear (not forge) the mid so the server re-mints a fresh one; a forged mid
// fails its format check.
+ (void)clearMachineID {
    RYGKeychainDeleteService(kKCMIDService);
    SecItemDelete((__bridge CFDictionaryRef)@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKCMIDHeaderService,
        (__bridge id)kSecAttrAccount: kKCMIDHeaderAccount });
}

+ (void)generateNewIdentity {
    [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofDeviceIDKey];
    [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofFDIDKey];
    [RYGUtils setPref:@(YES) forKey:RYGDeviceSpoofEnabledKey];
    [self applySpoofToKeychain];
    [self clearMachineID];
    RYGKeychainWriteAccount(kKCDeviceLockedService, kKCDeviceLockedAccount, RYGNewUUID());
    [self wipeCookies];
}

+ (void)setCustomDeviceID:(NSString *)deviceID {
    NSString *trimmed = [deviceID stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    [RYGUtils setPref:trimmed forKey:RYGDeviceSpoofDeviceIDKey];
    [RYGUtils setPref:@(YES) forKey:RYGDeviceSpoofEnabledKey];
    [self applySpoofToKeychain];
}

+ (void)disableSpoofing {
    NSString *od = [RYGUtils getStringPref:kOrigDeviceIDKey];
    NSString *of = [RYGUtils getStringPref:kOrigFDIDKey];
    if (od.length) RYGKeychainWrite(kKCDeviceIDService, od);
    if (of.length) RYGKeychainWrite(kKCFDIDService, of);
    [RYGUtils setPref:@(NO) forKey:RYGDeviceSpoofEnabledKey];
}

#pragma mark - Wipe

// Sideloaded apps share one keychain access group, so match Meta items by
// service name only — allowlist, never touch other apps.
static BOOL RYGServiceIsMeta(NSString *svc, NSString *acct) {
    if (svc.length == 0) return NO;
    NSArray *prefixes = @[ @"com.instagram.", @"instagram.", @"com.facebook.instagram.",
                           @"com.facebook.deviceid", @"com.facebook.lockbox",
                           @"com.facebook.deviceLockedStatus", @"com.meta." ];
    for (NSString *p in prefixes) if ([svc hasPrefix:p]) return YES;
    if ([svc isEqualToString:@"device_based_login.growth"] ||
        [svc isEqualToString:@"persistent_accounts.growth"]) return YES;
    if ([svc containsString:@".e2ee.apt.meta.com"]) return YES;
    if ([svc isEqualToString:@"unique_id"] && [acct.lowercaseString containsString:@"instagram"]) return YES;
    return NO;
}

+ (void)wipeKeychain {
    NSDictionary *q = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                         (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
                         (__bridge id)kSecReturnAttributes: @YES };
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess || !out) return;
    NSArray *items = (__bridge_transfer NSArray *)out;
    for (NSDictionary *it in items) {
        NSString *svc = it[(__bridge id)kSecAttrService] ?: @"";
        id acctVal = it[(__bridge id)kSecAttrAccount];
        NSString *acct = [acctVal isKindOfClass:[NSString class]] ? acctVal : @"";
        if (!RYGServiceIsMeta(svc, acct)) continue;

        NSMutableDictionary *del = [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                       (__bridge id)kSecAttrService: svc } mutableCopy];
        if ([acctVal isKindOfClass:[NSString class]] && [acctVal length])
            del[(__bridge id)kSecAttrAccount] = acctVal;
        SecItemDelete((__bridge CFDictionaryRef)del);
    }
}

+ (void)wipeFDIDDefaults {
    NSUserDefaults *grp = [[NSUserDefaults alloc] initWithSuiteName:kIGAppGroup];
    for (NSString *key in [[grp dictionaryRepresentation] allKeys]) {
        NSString *k = key.lowercaseString;
        if ([k containsString:@"device_id"] || [k containsString:@"deviceid"] ||
            [k containsString:@"fdid"] || [k containsString:@"family_device"])
            [grp removeObjectForKey:key];
    }
    [grp synchronize];
}

+ (void)wipeCookies {
    NSHTTPCookieStorage *store = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *c in [store.cookies copy]) [store deleteCookie:c];
}

+ (void)wipeDocuments {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docs.length) return;
    for (NSString *name in [fm contentsOfDirectoryAtPath:docs error:nil]) {
        NSString *lo = name.lowercaseString;
        if ([lo containsString:@"ryukgram"]) continue;
        [fm removeItemAtPath:[docs stringByAppendingPathComponent:name] error:nil];
    }
}

+ (void)wipeDeviceDataAndTerminate {
    for (NSString *k in @[ RYGDeviceSpoofEnabledKey, RYGDeviceSpoofDeviceIDKey,
                           RYGDeviceSpoofFDIDKey, kOrigDeviceIDKey, kOrigFDIDKey ])
        [RYGUtils setPref:([k isEqualToString:RYGDeviceSpoofEnabledKey] ? (id)@(NO) : (id)@"") forKey:k];

    [self wipeKeychain];
    [self wipeFDIDDefaults];
    [self wipeCookies];
    [self wipeDocuments];

    void (^finish)(void) = ^{ exit(0); };
    [RYGCacheManager clearCacheWithCompletion:^(__unused uint64_t cleared) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), finish);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), finish);
}

// Same clear as the wipe, but keeps spoofing on with a fresh identity.
+ (void)freshSpoofedDeviceAndTerminate {
    [self wipeKeychain];
    [self wipeFDIDDefaults];
    [self wipeCookies];
    [self wipeDocuments];
    [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofDeviceIDKey];
    [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofFDIDKey];
    [RYGUtils setPref:@(YES) forKey:RYGDeviceSpoofEnabledKey];
    [RYGUtils setPref:@"" forKey:kOrigDeviceIDKey];
    [RYGUtils setPref:@"" forKey:kOrigFDIDKey];

    void (^finish)(void) = ^{ exit(0); };
    [RYGCacheManager clearCacheWithCompletion:^(__unused uint64_t cleared) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), finish);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), finish);
}

@end
