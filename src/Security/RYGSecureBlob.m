#import "RYGSecureBlob.h"
#import "../Localization/RYGLocalization.h"
#import <CommonCrypto/CommonCrypto.h>
#import <compression.h>

static const uint8_t kMagic[4]  = { 'R', 'G', 'S', 'B' };
static const uint8_t kVersion   = 1;
static const uint32_t kIters    = 20000;
#define kHdrLen   26
#define kMacLen   CC_SHA256_DIGEST_LENGTH
#define kFlagDeflate 0x01

static void rygWipe(void *p, size_t n) {
	volatile uint8_t *v = (volatile uint8_t *)p;
	while (n--) *v++ = 0;
}

static inline uint64_t rygXs(uint64_t x) {
	x ^= x << 13; x ^= x >> 7; x ^= x << 17;
	return x;
}

static void rygFillSecret(uint8_t out[48]) {
	volatile uint64_t s0 = 0x64ECA42D62DC6C78ULL, s1 = 0x72226F81A8CF5D9EULL,
	                  s2 = 0xF2C6CF91F7D0D235ULL, s3 = 0xB3C74F3E7A9AB07BULL,
	                  s4 = 0xFFFBE9CD98EAA363ULL, s5 = 0x71B25E1436CCCB56ULL;
	uint64_t st[6] = { s0, s1, s2, s3, s4, s5 };
	uint64_t x = 0x5B5486090AA25EE3ULL;
	for (int i = 0; i < 6; i++) {
		x = rygXs(x);
		uint64_t w = st[i] ^ x;
		memcpy(out + i * 8, &w, sizeof(w));
	}
	rygWipe(st, sizeof(st));
}

static BOOL rygDeriveKey(uint8_t derived[64]) {
	uint8_t secret[48];
	rygFillSecret(secret);
	int ok = CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)secret, 32,
	                              secret + 32, 16,
	                              kCCPRFHmacAlgSHA256, kIters, derived, 64);
	rygWipe(secret, sizeof(secret));
	return ok == kCCSuccess;
}

@implementation RYGSecureBlob

+ (NSData *)decryptContainer:(NSData *)blob {
	if (blob.length < kHdrLen + kMacLen) return nil;
	const uint8_t *b = blob.bytes;
	if (memcmp(b, kMagic, sizeof(kMagic)) != 0) return nil;
	if (b[4] != kVersion) return nil;
	uint8_t flags = b[5];
	uint32_t origLen; memcpy(&origLen, b + 6, 4);
	origLen = CFSwapInt32LittleToHost(origLen);
	const uint8_t *iv = b + 10;
	const uint8_t *mac = b + kHdrLen;
	const uint8_t *cipher = b + kHdrLen + kMacLen;
	size_t cipherLen = blob.length - kHdrLen - kMacLen;

	uint8_t key[64];
	if (!rygDeriveKey(key)) return nil;

	uint8_t expected[kMacLen];
	CCHmacContext hctx;
	CCHmacInit(&hctx, kCCHmacAlgSHA256, key + 32, 32);
	CCHmacUpdate(&hctx, b, kHdrLen);
	CCHmacUpdate(&hctx, cipher, cipherLen);
	CCHmacFinal(&hctx, expected);
	if (timingsafe_bcmp(expected, mac, kMacLen) != 0) { rygWipe(key, sizeof(key)); return nil; }

	NSMutableData *inflated = nil;
	NSMutableData *packed = [NSMutableData dataWithLength:cipherLen + kCCBlockSizeAES128];
	size_t moved = 0;
	CCCryptorStatus s = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
	                            key, kCCKeySizeAES256, iv,
	                            cipher, cipherLen,
	                            packed.mutableBytes, packed.length, &moved);
	rygWipe(key, sizeof(key));
	if (s != kCCSuccess) return nil;
	packed.length = moved;

	if (flags & kFlagDeflate) {
		if (origLen == 0 || origLen > (64u * 1024 * 1024)) return nil;
		inflated = [NSMutableData dataWithLength:origLen];
		size_t got = compression_decode_buffer(inflated.mutableBytes, origLen,
		                                        packed.bytes, packed.length,
		                                        NULL, COMPRESSION_ZLIB);
		rygWipe(packed.mutableBytes, packed.length);
		if (got != origLen) return nil;
		return inflated;
	}
	return packed;
}

+ (NSData *)decryptBundleResource:(NSString *)name ofType:(NSString *)type {
	NSString *path = [RYGLocalizationBundle() pathForResource:name ofType:type];
	if (!path) return nil;
	NSData *blob = [NSData dataWithContentsOfFile:path];
	return blob.length ? [self decryptContainer:blob] : nil;
}

@end
