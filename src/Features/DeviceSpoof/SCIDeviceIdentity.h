// Masks IG's device identifiers (device-id, family device id, vendor id, machine
// id), writing the spoof into the keychain IG reads at launch, with optional
// Apple-attestation blocking and a full reset.

#import <Foundation/Foundation.h>

extern NSString *const SCIDeviceSpoofEnabledKey;
extern NSString *const SCIDeviceSpoofDeviceIDKey;
extern NSString *const SCIDeviceSpoofFDIDKey;
extern NSString *const SCIDeviceSpoofLoginButtonKey;
extern NSString *const SCIDeviceSpoofBlockDeviceCheckKey;

@interface SCIDeviceIdentity : NSObject

+ (BOOL)spoofingEnabled;

+ (NSString *)spoofedDeviceID;
+ (NSString *)spoofedFDID;
+ (NSString *)nativeDeviceID;
+ (NSString *)nativeFDID;
+ (NSString *)effectiveDeviceID;

+ (void)generateNewIdentity;
+ (void)setCustomDeviceID:(NSString *)deviceID;
+ (void)disableSpoofing;
+ (void)clearMachineID;

// Clears keychain, cookies, caches and IG Documents, then terminates so IG
// regenerates a clean identity. Logs out all accounts.
+ (void)wipeDeviceDataAndTerminate;

// Like the wipe, but keeps spoofing on with a fresh masked identity.
+ (void)freshSpoofedDeviceAndTerminate;

@end
