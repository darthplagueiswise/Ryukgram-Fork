// Lock state, passcode storage, biometric evaluation, per-group session pool.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGBiometricKind) {
    RYGBiometricKindNone   = 0,
    RYGBiometricKindTouchID,
    RYGBiometricKindFaceID,
    RYGBiometricKindOpticID,
};

extern NSString *const RYGLockSessionDidChangeNotification;
extern NSString *const RYGLockChatListDidChangeNotification;

@interface RYGLockManager : NSObject

+ (instancetype)shared;

// Master
- (BOOL)isMasterEnabled;
- (BOOL)hasPasscode;
- (NSInteger)passcodeLength;

// Passcode storage
- (BOOL)setPasscode:(NSString *)passcode error:(NSError **)error;
- (BOOL)verifyPasscode:(NSString *)passcode;
- (void)clearPasscodeAndState;

// Biometric
+ (RYGBiometricKind)availableBiometricKind;
+ (NSString *)biometricKindDisplayName;
+ (NSString * _Nullable)biometricSymbolName;
- (BOOL)isBiometricEnabledByUser;
// Returns the LAContext so the caller can -invalidate it when the user starts typing.
- (id)evaluateBiometricWithReason:(NSString *)reason
                        completion:(void(^)(BOOL success, NSError * _Nullable error))completion;
- (void)evaluateRecoveryWithReason:(NSString *)reason
                         completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

// Session pool
- (BOOL)isGroupLocked:(NSString *)groupID;
- (BOOL)isGroupUnlocked:(NSString *)groupID;
- (void)markGroupUnlocked:(NSString *)groupID;
- (void)markGroupLocked:(NSString *)groupID;
- (void)lockAll;
- (void)applyBackgroundInvalidation;

// Locked chats — entries are { threadId, threadName, users[], isGroup, lockedAt }.
- (NSArray<NSDictionary *> *)lockedChatEntries;
- (NSArray<NSString *> *)lockedChatIDs;
- (BOOL)isChatLocked:(NSString *)threadID;
- (void)setChat:(NSString *)threadID locked:(BOOL)locked;
- (void)lockChatEntry:(NSDictionary *)entry;
- (void)setLockedChatEntries:(NSArray<NSDictionary *> *)entries;

@end

NS_ASSUME_NONNULL_END
