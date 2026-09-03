#import "RYGBackupCrypto.h"
#import <CommonCrypto/CommonCrypto.h>

#define kSaltLen   16
#define kIVLen     16
#define kMacLen    CC_SHA256_DIGEST_LENGTH
#define kHeaderLen (sizeof(kMagic) + 1 /*ver*/ + 1 /*type*/ + 4 /*iters*/ + kSaltLen + kIVLen)

static const uint8_t kMagic[7] = { 'R', 'G', 'B', 'K', 'E', 'N', 'C' };
static const uint8_t kFormatVersion = 1;
static const uint32_t kIterations = 200000;

static NSError *rygCryptoError(NSInteger code, NSString *msg) {
	return [NSError errorWithDomain:@"RYGBackupCrypto" code:code userInfo:@{ NSLocalizedDescriptionKey: msg }];
}

@implementation RYGBackupCrypto

+ (BOOL)dataIsEncrypted:(NSData *)data {
	return data.length >= kHeaderLen + kMacLen &&
		   memcmp(data.bytes, kMagic, sizeof(kMagic)) == 0;
}

// derived: encKey = [0..32), macKey = [32..64)
+ (BOOL)deriveKey:(uint8_t[64])derived password:(NSString *)password salt:(const uint8_t *)salt iters:(uint32_t)iters {
	NSData *pw = [password dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
	return CCKeyDerivationPBKDF(kCCPBKDF2, pw.bytes, pw.length, salt, kSaltLen,
							   kCCPRFHmacAlgSHA256, iters, derived, 64) == kCCSuccess;
}

+ (NSData *)encrypt:(NSData *)plaintext password:(NSString *)password contentType:(RYGBackupContentType)type error:(NSError **)error {
	if (!plaintext) { if (error) *error = rygCryptoError(2, @"Nothing to encrypt."); return nil; }
	if (!password.length) { if (error) *error = rygCryptoError(3, @"Empty password."); return nil; }

	uint8_t salt[kSaltLen], iv[kIVLen];
	arc4random_buf(salt, kSaltLen);
	arc4random_buf(iv, kIVLen);

	uint8_t key[64];
	if (![self deriveKey:key password:password salt:salt iters:kIterations]) {
		if (error) *error = rygCryptoError(4, @"Key derivation failed.");
		return nil;
	}

	NSMutableData *cipher = [NSMutableData dataWithLength:plaintext.length + kCCBlockSizeAES128];
	size_t moved = 0;
	CCCryptorStatus s = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
								key, kCCKeySizeAES256, iv,
								plaintext.bytes, plaintext.length,
								cipher.mutableBytes, cipher.length, &moved);
	if (s != kCCSuccess) { if (error) *error = rygCryptoError(5, @"Encryption failed."); return nil; }
	cipher.length = moved;

	NSMutableData *out = [NSMutableData dataWithCapacity:kHeaderLen + cipher.length + kMacLen];
	[out appendBytes:kMagic length:sizeof(kMagic)];
	[out appendBytes:&kFormatVersion length:1];
	uint8_t t = (uint8_t)type;
	[out appendBytes:&t length:1];
	uint32_t itersBE = CFSwapInt32HostToBig(kIterations);
	[out appendBytes:&itersBE length:4];
	[out appendBytes:salt length:kSaltLen];
	[out appendBytes:iv length:kIVLen];
	[out appendData:cipher];

	uint8_t mac[kMacLen];
	CCHmac(kCCHmacAlgSHA256, key + 32, 32, out.bytes, out.length, mac);
	[out appendBytes:mac length:kMacLen];

	return out;
}

+ (NSData *)decrypt:(NSData *)blob password:(NSString *)password contentType:(RYGBackupContentType *)outType error:(NSError **)error {
	if (![self dataIsEncrypted:blob]) { if (error) *error = rygCryptoError(6, @"Not an encrypted backup."); return nil; }
	if (!password.length) { if (error) *error = rygCryptoError(3, @"Empty password."); return nil; }

	const uint8_t *b = blob.bytes;
	size_t off = sizeof(kMagic);
	uint8_t ver = b[off++];
	if (ver != kFormatVersion) { if (error) *error = rygCryptoError(7, @"Unsupported backup format."); return nil; }
	uint8_t type = b[off++];
	uint32_t itersBE; memcpy(&itersBE, b + off, 4); off += 4;
	uint32_t iters = CFSwapInt32BigToHost(itersBE);
	if (iters == 0 || iters > 5000000) { if (error) *error = rygCryptoError(7, @"Unsupported backup format."); return nil; }
	const uint8_t *salt = b + off; off += kSaltLen;
	const uint8_t *iv = b + off; off += kIVLen;

	size_t cipherLen = blob.length - kHeaderLen - kMacLen;
	const uint8_t *cipher = b + kHeaderLen;
	const uint8_t *mac = b + blob.length - kMacLen;

	uint8_t key[64];
	if (![self deriveKey:key password:password salt:salt iters:iters]) {
		if (error) *error = rygCryptoError(4, @"Key derivation failed.");
		return nil;
	}

	uint8_t expected[kMacLen];
	CCHmac(kCCHmacAlgSHA256, key + 32, 32, b, blob.length - kMacLen, expected);
	if (timingsafe_bcmp(expected, mac, kMacLen) != 0) {
		if (error) *error = rygCryptoError(1, @"Wrong password.");
		return nil;
	}

	NSMutableData *plain = [NSMutableData dataWithLength:cipherLen + kCCBlockSizeAES128];
	size_t moved = 0;
	CCCryptorStatus s = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
								key, kCCKeySizeAES256, iv,
								cipher, cipherLen,
								plain.mutableBytes, plain.length, &moved);
	if (s != kCCSuccess) { if (error) *error = rygCryptoError(1, @"Wrong password."); return nil; }
	plain.length = moved;

	if (outType) *outType = (RYGBackupContentType)type;
	return plain;
}

@end
