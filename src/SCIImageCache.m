#import "SCIImageCache.h"
#import <CommonCrypto/CommonDigest.h>

static NSCache *memCache(void) {
	static NSCache *c;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		c = [NSCache new];
		// Tuned for long Profile Analyzer lists — 64 was evicting visible
		// rows mid-scroll so revisits showed grey placeholders.
		c.countLimit = 512;
	});
	return c;
}

static NSString *diskDir(void) {
	static NSString *dir;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString *base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
		dir = [base stringByAppendingPathComponent:@"RyukGramImages"];
		[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	});
	return dir;
}

static NSString *hashKey(NSString *urlString) {
	const char *cstr = urlString.UTF8String;
	unsigned char hash[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(cstr, (CC_LONG)strlen(cstr), hash);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", hash[i]];
	return hex;
}

static const NSInteger kSCIMaxImageRetries = 2;

@implementation SCIImageCache

+ (void)fetchImageURL:(NSURL *)url key:(NSString *)key diskPath:(NSString *)path
			  attempt:(NSInteger)attempt deliver:(void (^)(UIImage *))deliver {
	[[[NSURLSession sharedSession] dataTaskWithURL:url
								 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
		UIImage *image = data ? [UIImage imageWithData:data] : nil;
		if (image) {
			[memCache() setObject:image forKey:key];
			[data writeToFile:path atomically:YES];
			deliver(image);
			return;
		}
		// Retry transient failures only; a 4xx means the signed URL is dead, so the
		// caller refetches a fresh one instead.
		NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
		BOOL transient = (err != nil) || status == 0 || status == 408 || status == 429 || status >= 500;
		if (transient && attempt < kSCIMaxImageRetries) {
			NSTimeInterval delay = 0.6 * (attempt + 1) * (attempt + 1);
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
						   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
				[self fetchImageURL:url key:key diskPath:path attempt:attempt + 1 deliver:deliver];
			});
			return;
		}
		deliver(nil);
	}] resume];
}

+ (void)loadImageFromURL:(NSURL *)url completion:(void (^)(UIImage *))completion {
	[self loadImageFromURL:url cacheKey:nil completion:completion];
}

+ (void)loadImageFromURL:(NSURL *)url cacheKey:(NSString *)cacheKey completion:(void (^)(UIImage *))completion {
	if (!url || !completion) return;
	NSString *key = cacheKey.length ? cacheKey : url.absoluteString;

	void (^deliver)(UIImage *) = ^(UIImage *image) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
	};

	UIImage *hit = [memCache() objectForKey:key];
	if (hit) { deliver(hit); return; }

	NSString *path = [diskDir() stringByAppendingPathComponent:hashKey(key)];
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:path]) {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			NSData *data = [NSData dataWithContentsOfFile:path];
			UIImage *image = data ? [UIImage imageWithData:data] : nil;
			if (image) [memCache() setObject:image forKey:key];
			deliver(image);
		});
		return;
	}

	[self fetchImageURL:url key:key diskPath:path attempt:0 deliver:deliver];
}

+ (void)loadDataFromURL:(NSURL *)url completion:(void (^)(NSData *))completion {
	if (!url || !completion) return;
	void (^deliver)(NSData *) = ^(NSData *data) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(data); });
	};

	NSString *path = [diskDir() stringByAppendingPathComponent:hashKey(url.absoluteString)];
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			deliver([NSData dataWithContentsOfFile:path]);
		});
		return;
	}

	[[[NSURLSession sharedSession] dataTaskWithURL:url
								 completionHandler:^(NSData *data, NSURLResponse *_r, NSError *_e) {
		if (data) [data writeToFile:path atomically:YES];
		deliver(data);
	}] resume];
}

@end
