// Masks IG's device identifiers (device-id, family device id, vendor id, machine
// id), pinning each so it survives IG rewrites and relaunches, with optional
// Apple-attestation blocking and a full reset.

#import <Foundation/Foundation.h>

extern NSString *const RYGDeviceSpoofEnabledKey;
extern NSString *const RYGDeviceSpoofDeviceIDKey;
extern NSString *const RYGDeviceSpoofFDIDKey;
extern NSString *const RYGDeviceSpoofMIDKey;
extern NSString *const RYGDeviceSpoofLoginButtonKey;
extern NSString *const RYGDeviceSpoofBlockDeviceCheckKey;

@interface RYGDeviceIdentity : NSObject

+ (BOOL)spoofingEnabled;

+ (NSString *)spoofedDeviceID;
+ (NSString *)spoofedFDID;
+ (NSString *)nativeDeviceID;
+ (NSString *)nativeFDID;
+ (NSString *)effectiveDeviceID;

// Adopted from IG, never minted — the server format-checks it.
+ (NSString *)pinnedMachineID;

// Rolls every id, blocks attestation, clears logins, then terminates.
+ (void)maskEverythingAndTerminate;

+ (void)generateNewIdentity;
+ (void)setCustomDeviceID:(NSString *)deviceID;
+ (void)setCustomMachineID:(NSString *)machineID;
+ (void)disableSpoofing;
+ (void)clearMachineID;

// Adopts anything unpinned, then rewrites every slot. Safe to repeat.
+ (void)enforcePinnedIdentity;

// nil unless the query is a plain data read for a slot we have pinned.
+ (NSString *)pinnedValueForKeychainQuery:(NSDictionary *)query;
+ (BOOL)rawKeychainAccessInProgress;

// Clears keychain, cookies, caches and IG Documents, then terminates so IG
// regenerates a clean identity. Logs out all accounts.
+ (void)wipeDeviceDataAndTerminate;

// Like the wipe, but keeps spoofing on with a fresh masked identity.
+ (void)freshSpoofedDeviceAndTerminate;

@end
