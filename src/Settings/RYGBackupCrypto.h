#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, RYGBackupContentType) {
	RYGBackupContentJSON    = 0,
	RYGBackupContentArchive = 1,
};

// Password-based container: AES-256-CBC, PBKDF2-SHA256 key stretch, encrypt-then-HMAC.
// A wrong password fails the HMAC before any decrypt, so it's reported as such.
@interface RYGBackupCrypto : NSObject

+ (BOOL)dataIsEncrypted:(NSData *)data;

+ (nullable NSData *)encrypt:(NSData *)plaintext
					password:(NSString *)password
				 contentType:(RYGBackupContentType)type
					   error:(NSError **)error;

+ (nullable NSData *)decrypt:(NSData *)blob
					password:(NSString *)password
				 contentType:(RYGBackupContentType *_Nullable)outType
					   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
