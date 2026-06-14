#import "SCILockManager.h"
#import "SCILockGroups.h"
#import "../Utils.h"
#import "../SCIAccountScopedDefaults.h"
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonCryptoError.h>

NSString *const SCILockSessionDidChangeNotification  = @"SCILockSessionDidChange";
NSString *const SCILockChatListDidChangeNotification = @"SCILockChatListDidChange";

// Sideload keychain access is flaky across re-signs; we store the
// PBKDF2-SHA256 hash in NSUserDefaults as raw NSData (salt || hash).
static NSString *const kPrefPasscodeBlob     = @"lock_passcode_blob";
static NSString *const kPrefMasterEnabled    = @"lock_master_enabled";
static NSString *const kPrefBiometricEnabled = @"lock_biometric_enabled";
static NSString *const kPrefPasscodeLength   = @"lock_passcode_length";
static NSString *const kPrefLockedChats      = @"lock_chats_locked_entries";

static const NSUInteger kSaltLen   = 16;
static const NSUInteger kDerivLen  = 32;
static const NSUInteger kPBKDFIter = 60000;

@interface SCILockManager () {
    NSMutableDictionary<NSString *, NSDate *> *_sessions;
    NSString *_lastSeenUserPK;
}
@end

@implementation SCILockManager

+ (instancetype)shared {
    static SCILockManager *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _sessions = [NSMutableDictionary new];
    }
    return self;
}

#pragma mark - Notifications

- (void)postSessionDidChange:(NSString * _Nullable)gid {
    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCILockSessionDidChangeNotification object:gid];
    };
    if ([NSThread isMainThread]) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

- (void)postChatListDidChange {
    void (^post)(void) = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCILockChatListDidChangeNotification object:nil];
    };
    if ([NSThread isMainThread]) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

#pragma mark - Master

- (BOOL)isMasterEnabled {
    return [SCIUtils getBoolPref:kPrefMasterEnabled] && [self hasPasscode];
}

- (NSInteger)passcodeLength {
    NSInteger n = (NSInteger)[SCIUtils getDoublePref:kPrefPasscodeLength];
    return (n == 4 || n == 6) ? n : 4;
}

#pragma mark - Passcode storage

- (NSData *)passcodeBlob {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefPasscodeBlob];
    return [v isKindOfClass:[NSData class]] ? v : nil;
}

- (BOOL)hasPasscode {
    return [self passcodeBlob].length == (kSaltLen + kDerivLen);
}

- (NSData *)derive:(NSString *)passcode salt:(NSData *)salt {
    NSData *pwd = [passcode dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *out = [NSMutableData dataWithLength:kDerivLen];
    int r = CCKeyDerivationPBKDF(kCCPBKDF2,
                                 pwd.bytes, pwd.length,
                                 salt.bytes, salt.length,
                                 kCCPRFHmacAlgSHA256,
                                 (unsigned)kPBKDFIter,
                                 out.mutableBytes, out.length);
    return (r == kCCSuccess) ? out : nil;
}

- (NSData *)randomBytes:(NSUInteger)n {
    NSMutableData *d = [NSMutableData dataWithLength:n];
    if (SecRandomCopyBytes(kSecRandomDefault, n, d.mutableBytes) != errSecSuccess) return nil;
    return d;
}

- (BOOL)setPasscode:(NSString *)passcode error:(NSError **)error {
    if (passcode.length < 4) {
        if (error) *error = [NSError errorWithDomain:@"SCILock" code:1 userInfo:@{ NSLocalizedDescriptionKey: SCILocalized(@"Passcode too short") }];
        return NO;
    }
    NSData *salt = [self randomBytes:kSaltLen];
    NSData *hash = [self derive:passcode salt:salt];
    if (salt.length != kSaltLen || hash.length != kDerivLen) {
        if (error) *error = [NSError errorWithDomain:@"SCILock" code:2 userInfo:@{ NSLocalizedDescriptionKey: SCILocalized(@"Derivation failed") }];
        return NO;
    }
    NSMutableData *blob = [NSMutableData dataWithCapacity:kSaltLen + kDerivLen];
    [blob appendData:salt];
    [blob appendData:hash];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:[blob copy] forKey:kPrefPasscodeBlob];
    [d setObject:@(passcode.length) forKey:kPrefPasscodeLength];
    [d synchronize];
    return YES;
}

- (BOOL)verifyPasscode:(NSString *)passcode {
    NSData *blob = [self passcodeBlob];
    if (blob.length != kSaltLen + kDerivLen) return NO;
    NSData *salt = [blob subdataWithRange:NSMakeRange(0, kSaltLen)];
    NSData *stored = [blob subdataWithRange:NSMakeRange(kSaltLen, kDerivLen)];
    NSData *attempt = [self derive:passcode salt:salt];
    if (attempt.length != stored.length) return NO;

    // Constant-time compare.
    const uint8_t *a = stored.bytes;
    const uint8_t *b = attempt.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < stored.length; i++) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

- (void)clearPasscodeAndState {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:kPrefPasscodeBlob];
    [d setBool:NO forKey:kPrefMasterEnabled];
    [d setBool:NO forKey:kPrefBiometricEnabled];
    for (SCILockGroupInfo *g in SCILockAllGroups()) {
        [d setBool:NO forKey:SCILockPrefEnabled(g.identifier)];
    }
    [SCIAccountScopedDefaults setObject:@[] forKey:kPrefLockedChats];
    [d synchronize];
    [self lockAll];
}

#pragma mark - Biometric

+ (SCIBiometricKind)availableBiometricKind {
    LAContext *ctx = [LAContext new];
    NSError *err = nil;
    if (![ctx canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&err]) return SCIBiometricKindNone;
    switch ((NSInteger)ctx.biometryType) {
        case LABiometryTypeFaceID:  return SCIBiometricKindFaceID;
        case LABiometryTypeTouchID: return SCIBiometricKindTouchID;
        case 4:                     return SCIBiometricKindOpticID;
        default:                    return SCIBiometricKindNone;
    }
}

+ (NSString *)biometricKindDisplayName {
    switch ([self availableBiometricKind]) {
        case SCIBiometricKindFaceID:  return @"Face ID";
        case SCIBiometricKindTouchID: return @"Touch ID";
        case SCIBiometricKindOpticID: return @"Optic ID";
        default: return nil;
    }
}

+ (NSString *)biometricSymbolName {
    switch ([self availableBiometricKind]) {
        case SCIBiometricKindFaceID:  return @"faceid";
        case SCIBiometricKindTouchID: return @"touchid";
        case SCIBiometricKindOpticID: return @"opticid";
        default: return nil;
    }
}

- (BOOL)isBiometricEnabledByUser {
    return [SCIUtils getBoolPref:kPrefBiometricEnabled] && [[self class] availableBiometricKind] != SCIBiometricKindNone;
}

- (id)evaluateBiometricWithReason:(NSString *)reason
                       completion:(void(^)(BOOL, NSError *))completion {
    LAContext *ctx = [LAContext new];
    [ctx evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
        localizedReason:reason
                  reply:^(BOOL ok, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, err); });
    }];
    return ctx;
}

- (void)evaluateRecoveryWithReason:(NSString *)reason
                         completion:(void(^)(BOOL, NSError *))completion {
    LAContext *ctx = [LAContext new];
    [ctx evaluatePolicy:LAPolicyDeviceOwnerAuthentication
        localizedReason:reason
                  reply:^(BOOL ok, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(ok, err); });
    }];
}

#pragma mark - Session pool

- (void)resetIfAccountSwitched {
    NSString *pk = [SCIUtils currentUserPK];
    if (!pk.length) return;
    @synchronized (_sessions) {
        if (_lastSeenUserPK && ![_lastSeenUserPK isEqualToString:pk]) {
            [_sessions removeAllObjects];
        }
        _lastSeenUserPK = [pk copy];
    }
}

- (BOOL)isGroupLocked:(NSString *)gid {
    if (!gid.length) return NO;
    if (![self isMasterEnabled]) return NO;
    if (![SCIUtils getBoolPref:SCILockPrefEnabled(gid)]) return NO;
    [self resetIfAccountSwitched];
    NSDate *expiry;
    @synchronized (_sessions) { expiry = _sessions[gid]; }
    if (!expiry) return YES;
    return [expiry timeIntervalSinceNow] <= 0;
}

- (BOOL)isGroupUnlocked:(NSString *)gid { return ![self isGroupLocked:gid]; }

- (NSDate *)expiryForGroup:(NSString *)gid {
    double timeout = [SCIUtils getDoublePref:SCILockPrefIdleTimeout(gid)];
    if (timeout <= 0) return [NSDate distantFuture];
    return [NSDate dateWithTimeIntervalSinceNow:timeout];
}

- (void)markGroupUnlocked:(NSString *)gid {
    if (!gid.length) return;
    NSDate *expiry = [self expiryForGroup:gid];
    BOOL independent = [SCIUtils getBoolPref:SCILockPrefIndependentSession(gid)];
    @synchronized (_sessions) {
        _sessions[gid] = expiry;
        if (!independent) {
            for (SCILockGroupInfo *g in SCILockAllGroups()) {
                if ([g.identifier isEqualToString:gid]) continue;
                if ([SCIUtils getBoolPref:SCILockPrefIndependentSession(g.identifier)]) continue;
                _sessions[g.identifier] = [self expiryForGroup:g.identifier];
            }
        }
    }
    [self postSessionDidChange:gid];
}

- (void)markGroupLocked:(NSString *)gid {
    if (!gid.length) return;
    @synchronized (_sessions) { [_sessions removeObjectForKey:gid]; }
    [self postSessionDidChange:gid];
}

- (void)lockAll {
    @synchronized (_sessions) { [_sessions removeAllObjects]; }
    [self postSessionDidChange:nil];
}

- (void)applyBackgroundInvalidation {
    BOOL touched = NO;
    @synchronized (_sessions) {
        for (SCILockGroupInfo *g in SCILockAllGroups()) {
            if (![SCIUtils getBoolPref:SCILockPrefRelockOnBackground(g.identifier)]) continue;
            if (_sessions[g.identifier]) touched = YES;
            [_sessions removeObjectForKey:g.identifier];
        }
    }
    if (!touched) return;
    [self postSessionDidChange:nil];
}

#pragma mark - Locked chats

- (NSArray<NSDictionary *> *)lockedChatEntries {
    NSArray *raw = [SCIAccountScopedDefaults arrayForKey:kPrefLockedChats];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:raw.count];
    for (id e in raw) {
        if (![e isKindOfClass:[NSDictionary class]]) continue;
        NSString *tid = e[@"threadId"];
        if ([tid isKindOfClass:[NSString class]] && tid.length) [out addObject:e];
    }
    return out;
}

- (NSArray<NSString *> *)lockedChatIDs {
    NSMutableArray *out = [NSMutableArray new];
    for (NSDictionary *e in [self lockedChatEntries]) [out addObject:e[@"threadId"]];
    return out;
}

- (BOOL)isChatLocked:(NSString *)threadID {
    if (!threadID.length) return NO;
    if (![self isGroupLocked:SCILockGroupChats]) return NO;
    return [[self lockedChatIDs] containsObject:threadID];
}

- (NSInteger)indexOfEntryWithThreadID:(NSString *)tid inArray:(NSArray *)arr {
    for (NSInteger i = 0; i < (NSInteger)arr.count; i++) {
        if ([arr[i][@"threadId"] isEqualToString:tid]) return i;
    }
    return NSNotFound;
}

- (void)setChat:(NSString *)threadID locked:(BOOL)locked {
    if (!threadID.length) return;
    if (locked) {
        [self lockChatEntry:@{ @"threadId": threadID, @"lockedAt": @([NSDate date].timeIntervalSince1970) }];
        return;
    }
    NSMutableArray *list = [[self lockedChatEntries] mutableCopy];
    NSInteger idx = [self indexOfEntryWithThreadID:threadID inArray:list];
    if (idx == NSNotFound) return;
    [list removeObjectAtIndex:idx];
    [SCIAccountScopedDefaults setObject:list forKey:kPrefLockedChats];
    [self postChatListDidChange];
}

- (void)lockChatEntry:(NSDictionary *)entry {
    NSString *tid = entry[@"threadId"];
    if (![tid isKindOfClass:[NSString class]] || !tid.length) return;
    NSMutableDictionary *merged = [entry mutableCopy];
    if (!merged[@"lockedAt"]) merged[@"lockedAt"] = @([NSDate date].timeIntervalSince1970);
    NSMutableArray *list = [[self lockedChatEntries] mutableCopy];
    NSInteger idx = [self indexOfEntryWithThreadID:tid inArray:list];
    if (idx == NSNotFound) [list addObject:merged];
    else                   list[idx] = merged;
    [SCIAccountScopedDefaults setObject:list forKey:kPrefLockedChats];
    [self postChatListDidChange];
}

- (void)setLockedChatEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:entries.count];
    for (id e in entries) if ([e isKindOfClass:[NSDictionary class]] && [e[@"threadId"] length]) [out addObject:e];
    [SCIAccountScopedDefaults setObject:out forKey:kPrefLockedChats];
    [self postChatListDidChange];
}

@end
