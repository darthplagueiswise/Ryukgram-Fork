#import "RYGDeviceIdentity.h"
#import "../../Utils.h"
#import "../General/RYGCacheManager.h"
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

NSString *const RYGDeviceSpoofEnabledKey     = @"ryg_devicespoof_enabled";
NSString *const RYGDeviceSpoofDeviceIDKey    = @"ryg_devicespoof_device_id";
NSString *const RYGDeviceSpoofFDIDKey        = @"ryg_devicespoof_fdid";
NSString *const RYGDeviceSpoofMIDKey         = @"ryg_devicespoof_mid";
NSString *const RYGDeviceSpoofLoginButtonKey = @"ryg_devicespoof_login_button";
NSString *const RYGDeviceSpoofBlockDeviceCheckKey = @"ryg_devicespoof_block_devicecheck";

static NSString *const kMIDHeaderKey     = @"ryg_devicespoof_mid_header";
static NSString *const kOrigDeviceIDKey  = @"ryg_devicespoof_orig_deviceid";
static NSString *const kOrigFDIDKey      = @"ryg_devicespoof_orig_fbdeviceid";
static NSString *const kOrigMIDKey       = @"ryg_devicespoof_orig_mid";
static NSString *const kOrigMIDHeaderKey = @"ryg_devicespoof_orig_mid_header";

static NSString *const kIGAppGroup = @"group.com.burbn.instagram";

static NSString *const kKCDeviceIDService     = @"instagram.deviceid";
static NSString *const kKCFDIDService         = @"com.facebook.deviceid";
static NSString *const kKCUniqueIDService     = @"unique_id";
static NSString *const kKCUniqueIDAccount     = @"instagram";
static NSString *const kKCMIDService          = @"instagram.mid";
static NSString *const kKCMIDHeaderService    = @"com.instagram.device";
static NSString *const kKCMIDHeaderAccount    = @"com.instagram.device.midheader";
static NSString *const kKCDeviceLockedService = @"com.facebook.deviceLockedStatusFlag";
static NSString *const kKCDeviceLockedAccount = @"fb_locked_device_flag";

static NSString *const kSlotService = @"svc";
static NSString *const kSlotAccount = @"acct";
static NSString *const kSlotPref    = @"pref";
static NSString *const kSlotOrig    = @"orig";
static NSString *const kSlotMintable = @"mint";

// Our own reads must bypass the guard, or adoption echoes the pin back.
static _Thread_local int sRawDepth = 0;

static NSMutableDictionary *RYGKeychainQuery(NSString *svc, NSString *acct) {
    NSMutableDictionary *q = [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                 (__bridge id)kSecAttrService: svc } mutableCopy];
    if (acct.length) q[(__bridge id)kSecAttrAccount] = acct;
    return q;
}

static NSString *RYGKeychainRead(NSString *svc, NSString *acct) {
    NSMutableDictionary *q = RYGKeychainQuery(svc, acct);
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    q[(__bridge id)kSecReturnData] = @YES;

    sRawDepth++;
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    sRawDepth--;

    if (st != errSecSuccess || !out) return nil;
    NSData *data = (__bridge_transfer NSData *)out;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// SecItemUpdate alone no-ops when the item doesn't exist yet.
static OSStatus RYGKeychainSet(NSString *svc, NSString *acct, NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *q = RYGKeychainQuery(svc, acct);

    sRawDepth++;
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q,
                                (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
    if (st == errSecItemNotFound) {
        NSMutableDictionary *add = [q mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    sRawDepth--;
    return st;
}

static void RYGKeychainDelete(NSString *svc, NSString *acct) {
    sRawDepth++;
    SecItemDelete((__bridge CFDictionaryRef)RYGKeychainQuery(svc, acct));
    sRawDepth--;
}

static NSString *RYGNewUUID(void) {
    return [[NSUUID UUID] UUIDString];
}

static BOOL RYGPlausibleServerID(NSString *v) {
    return v.length >= 8;
}

// A suite-backed NSUserDefaults merges our app domain in, so an unfiltered
// name match would rewrite our own prefs.
static BOOL RYGKeyIsIGIdentifier(NSString *key) {
    if ([key hasPrefix:@"ryg_"]) return NO;
    NSString *k = key.lowercaseString;
    return [k containsString:@"device_id"] || [k containsString:@"deviceid"] ||
           [k containsString:@"fdid"] || [k containsString:@"family_device"];
}

@implementation RYGDeviceIdentity

// Every identifier IG can read. Apply, adopt, revert, wipe and the guard walk this.
+ (NSArray<NSDictionary *> *)identitySlots {
    static NSArray *slots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        slots = @[
            @{ kSlotService: kKCDeviceIDService,
               kSlotPref: RYGDeviceSpoofDeviceIDKey, kSlotOrig: kOrigDeviceIDKey, kSlotMintable: @YES },
            @{ kSlotService: kKCUniqueIDService, kSlotAccount: kKCUniqueIDAccount,
               kSlotPref: RYGDeviceSpoofDeviceIDKey, kSlotOrig: kOrigDeviceIDKey, kSlotMintable: @YES },
            @{ kSlotService: kKCFDIDService,
               kSlotPref: RYGDeviceSpoofFDIDKey, kSlotOrig: kOrigFDIDKey, kSlotMintable: @YES },
            @{ kSlotService: kKCMIDService,
               kSlotPref: RYGDeviceSpoofMIDKey, kSlotOrig: kOrigMIDKey, kSlotMintable: @NO },
            @{ kSlotService: kKCMIDHeaderService, kSlotAccount: kKCMIDHeaderAccount,
               kSlotPref: kMIDHeaderKey, kSlotOrig: kOrigMIDHeaderKey, kSlotMintable: @NO },
        ];
    });
    return slots;
}

+ (BOOL)rawKeychainAccessInProgress { return sRawDepth > 0; }

+ (BOOL)spoofingEnabled {
    return [RYGUtils getBoolPref:RYGDeviceSpoofEnabledKey];
}

+ (NSString *)mintedPrefValue:(NSString *)key {
    NSString *v = [RYGUtils getStringPref:key];
    if (v.length == 0) {
        v = RYGNewUUID();
        [RYGUtils setPref:v forKey:key];
    }
    return v;
}

+ (NSString *)spoofedDeviceID { return [self mintedPrefValue:RYGDeviceSpoofDeviceIDKey]; }
+ (NSString *)spoofedFDID     { return [self mintedPrefValue:RYGDeviceSpoofFDIDKey]; }

+ (NSString *)pinnedMachineID {
    NSString *v = [RYGUtils getStringPref:RYGDeviceSpoofMIDKey];
    return v.length ? v : nil;
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

#pragma mark - Pinning

+ (void)enforcePinnedIdentity {
    if (![self spoofingEnabled]) return;

    for (NSDictionary *slot in [self identitySlots]) {
        NSString *svc  = slot[kSlotService];
        NSString *acct = slot[kSlotAccount];
        NSString *live = RYGKeychainRead(svc, acct);

        NSString *origKey = slot[kSlotOrig];
        if (origKey.length && live.length && [RYGUtils getStringPref:origKey].length == 0 &&
            ![live isEqualToString:[RYGUtils getStringPref:slot[kSlotPref]]])
            [RYGUtils setPref:live forKey:origKey];

        NSString *prefKey = slot[kSlotPref];
        BOOL mintable = [slot[kSlotMintable] boolValue];
        NSString *pinned = [RYGUtils getStringPref:prefKey];

        if (!mintable && pinned.length && !RYGPlausibleServerID(pinned)) {
            [RYGUtils setPref:@"" forKey:prefKey];
            pinned = nil;
        }

        if (pinned.length == 0) {
            if (mintable) {
                pinned = RYGNewUUID();
                [RYGUtils setPref:pinned forKey:prefKey];
            } else if (RYGPlausibleServerID(live)) {
                pinned = live;
                [RYGUtils setPref:pinned forKey:prefKey];
            } else {
                continue;
            }
        }

        // Adopt-only slots are mirrored where IG has one, never created.
        if ([live isEqualToString:pinned]) continue;
        if (!mintable && !live.length) continue;
        RYGKeychainSet(svc, acct, pinned);
    }

    [self pinGroupDefaults];
}

+ (void)pinGroupDefaults {
    NSUserDefaults *grp = [[NSUserDefaults alloc] initWithSuiteName:kIGAppGroup];
    NSUserDefaults *std = NSUserDefaults.standardUserDefaults;
    NSString *deviceID = [self spoofedDeviceID];
    NSString *fdid = [self spoofedFDID];

    for (NSString *key in [[grp dictionaryRepresentation] allKeys]) {
        if (!RYGKeyIsIGIdentifier(key)) continue;

        id current = [grp objectForKey:key];
        if (![current isKindOfClass:[NSString class]]) continue;

        NSString *k = key.lowercaseString;
        BOOL isFDID = [k containsString:@"fdid"] || [k containsString:@"family_device"];
        NSString *want = isFDID ? fdid : deviceID;
        if ([current isEqualToString:want]) continue;

        // The merged dictionary doesn't say which domain IG reads, so pin both.
        [grp setObject:want forKey:key];
        if ([std objectForKey:key]) [std setObject:want forKey:key];
    }
    [grp synchronize];
}

+ (NSString *)pinnedValueForKeychainQuery:(NSDictionary *)query {
    if (![query isKindOfClass:[NSDictionary class]]) return nil;
    if (![query[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassGenericPassword]) return nil;
    if (![query[(__bridge id)kSecReturnData] boolValue]) return nil;
    if ([query[(__bridge id)kSecReturnAttributes] boolValue]) return nil;
    if ([query[(__bridge id)kSecMatchLimit] isEqual:(__bridge id)kSecMatchLimitAll]) return nil;

    id svc = query[(__bridge id)kSecAttrService];
    if (![svc isKindOfClass:[NSString class]]) return nil;
    id acct = query[(__bridge id)kSecAttrAccount];
    NSString *acctStr = [acct isKindOfClass:[NSString class]] ? acct : nil;

    for (NSDictionary *slot in [self identitySlots]) {
        if (![slot[kSlotService] isEqualToString:svc]) continue;
        NSString *slotAcct = slot[kSlotAccount];
        if (slotAcct.length && ![slotAcct isEqualToString:acctStr]) continue;

        NSString *pinned = [RYGUtils getStringPref:slot[kSlotPref]];
        return pinned.length ? pinned : nil;
    }
    return nil;
}

#pragma mark - Mutations

+ (void)generateNewIdentity {
    [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofDeviceIDKey];
    [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofFDIDKey];
    [RYGUtils setPref:@(YES) forKey:RYGDeviceSpoofEnabledKey];
    [self clearMachineID];
    [self enforcePinnedIdentity];
    RYGKeychainSet(kKCDeviceLockedService, kKCDeviceLockedAccount, RYGNewUUID());
    [self wipeCookies];
}

+ (void)setCustomDeviceID:(NSString *)deviceID {
    NSString *trimmed = [deviceID stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    [RYGUtils setPref:trimmed forKey:RYGDeviceSpoofDeviceIDKey];
    [RYGUtils setPref:@(YES) forKey:RYGDeviceSpoofEnabledKey];
    [self enforcePinnedIdentity];
}

+ (void)setCustomMachineID:(NSString *)machineID {
    NSString *trimmed = [machineID stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    [RYGUtils setPref:trimmed forKey:RYGDeviceSpoofMIDKey];
    [RYGUtils setPref:@(YES) forKey:RYGDeviceSpoofEnabledKey];
    [self enforcePinnedIdentity];
}

// A forged mid fails its format check, so drop ours and re-pin what IG is issued.
+ (void)clearMachineID {
    [RYGUtils setPref:@"" forKey:RYGDeviceSpoofMIDKey];
    [RYGUtils setPref:@"" forKey:kMIDHeaderKey];
    RYGKeychainDelete(kKCMIDService, nil);
    RYGKeychainDelete(kKCMIDHeaderService, kKCMIDHeaderAccount);
}

+ (void)disableSpoofing {
    for (NSDictionary *slot in [self identitySlots]) {
        NSString *origKey = slot[kSlotOrig];
        NSString *orig = origKey.length ? [RYGUtils getStringPref:origKey] : nil;
        // An "original" equal to the mask is a corrupted backup, not a real id.
        if (!orig.length || [orig isEqualToString:[RYGUtils getStringPref:slot[kSlotPref]]]) continue;
        RYGKeychainSet(slot[kSlotService], slot[kSlotAccount], orig);
    }
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
    sRawDepth++;
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    sRawDepth--;
    if (st != errSecSuccess || !out) return;

    NSArray *items = (__bridge_transfer NSArray *)out;
    for (NSDictionary *it in items) {
        NSString *svc = it[(__bridge id)kSecAttrService] ?: @"";
        id acctVal = it[(__bridge id)kSecAttrAccount];
        NSString *acct = [acctVal isKindOfClass:[NSString class]] ? acctVal : @"";
        if (!RYGServiceIsMeta(svc, acct)) continue;
        RYGKeychainDelete(svc, acct.length ? acct : nil);
    }
}

+ (void)wipeFDIDDefaults {
    NSUserDefaults *grp = [[NSUserDefaults alloc] initWithSuiteName:kIGAppGroup];
    for (NSString *key in [[grp dictionaryRepresentation] allKeys])
        if (RYGKeyIsIGIdentifier(key)) [grp removeObjectForKey:key];
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

+ (void)clearAllPins {
    for (NSDictionary *slot in [self identitySlots]) {
        [RYGUtils setPref:@"" forKey:slot[kSlotPref]];
        NSString *origKey = slot[kSlotOrig];
        if (origKey.length) [RYGUtils setPref:@"" forKey:origKey];
    }
}

+ (void)clearAndTerminateKeepingSpoof:(BOOL)keepSpoof {
    [self wipeKeychain];
    [self wipeFDIDDefaults];
    [self wipeCookies];
    [self wipeDocuments];
    [self clearAllPins];
    [RYGUtils setPref:@(keepSpoof) forKey:RYGDeviceSpoofEnabledKey];
    if (keepSpoof) {
        [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofDeviceIDKey];
        [RYGUtils setPref:RYGNewUUID() forKey:RYGDeviceSpoofFDIDKey];
    }

    void (^finish)(void) = ^{ exit(0); };
    [RYGCacheManager clearCacheWithCompletion:^(__unused uint64_t cleared) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), finish);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), finish);
}

+ (void)maskEverythingAndTerminate {
    [RYGUtils setPref:@(YES) forKey:RYGDeviceSpoofBlockDeviceCheckKey];
    [self clearAndTerminateKeepingSpoof:YES];
}

+ (void)wipeDeviceDataAndTerminate     { [self clearAndTerminateKeepingSpoof:NO]; }
+ (void)freshSpoofedDeviceAndTerminate { [self clearAndTerminateKeepingSpoof:YES]; }

@end
