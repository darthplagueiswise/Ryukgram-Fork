#import "RYGImageCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>

static UIImage *rygDownsample(NSData *data, CGFloat maxPixel) {
	if (!data.length) return nil;
	CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
	if (!src) return [UIImage imageWithData:data];
	NSDictionary *opts = @{
		(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
		(id)kCGImageSourceShouldCacheImmediately: @YES,
		(id)kCGImageSourceCreateThumbnailWithTransform: @YES,
		(id)kCGImageSourceThumbnailMaxPixelSize: @(maxPixel),
	};
	CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
	CFRelease(src);
	if (!thumb) return [UIImage imageWithData:data];
	UIImage *img = [UIImage imageWithCGImage:thumb];
	CGImageRelease(thumb);
	return img;
}

// Capped by decoded bytes — grid thumbs (~600KB) dwarf avatars (~50KB), so a count-only
// cap let deep scrolling balloon to hundreds of MB. Count stays as a backstop.
static NSUInteger rygImageCost(UIImage *img) {
	CGImageRef cg = img.CGImage;
	if (!cg) return 1;
	return CGImageGetBytesPerRow(cg) * CGImageGetHeight(cg);
}

static NSCache *memCache(void) {
	static NSCache *c;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		c = [NSCache new];
		c.countLimit = 512;
		c.totalCostLimit = 64 * 1024 * 1024;
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

static const NSInteger kRYGMaxImageRetries = 2;

// Own session: more parallel connections, and no HTTP cache since we disk-cache the bytes.
static NSURLSession *imgSession(void) {
	static NSURLSession *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
		cfg.HTTPMaximumConnectionsPerHost = 8;
		cfg.URLCache = nil;
		cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
		s = [NSURLSession sessionWithConfiguration:cfg];
	});
	return s;
}

// Coalesce concurrent fetches for the same key so prefetch + cell don't double-download.
static NSMutableDictionary<NSString *, NSMutableArray *> *inflightMap(void) {
	static NSMutableDictionary *m;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ m = [NSMutableDictionary dictionary]; });
	return m;
}
static dispatch_queue_t inflightQ(void) {
	static dispatch_queue_t q;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryuk.imgcache.inflight", DISPATCH_QUEUE_SERIAL); });
	return q;
}
static BOOL rygJoinInflight(NSString *key, void (^deliver)(UIImage *)) {
	__block BOOL owner = NO;
	dispatch_sync(inflightQ(), ^{
		NSMutableArray *a = inflightMap()[key];
		if (!a) { a = [NSMutableArray array]; inflightMap()[key] = a; owner = YES; }
		[a addObject:[deliver copy]];
	});
	return owner;
}
static void rygFinishInflight(NSString *key, UIImage *img) {
	__block NSArray *blocks = nil;
	dispatch_sync(inflightQ(), ^{ blocks = inflightMap()[key]; [inflightMap() removeObjectForKey:key]; });
	for (void (^b)(UIImage *) in blocks) b(img);
}

@implementation RYGImageCache

+ (void)fetchImageURL:(NSURL *)url key:(NSString *)key diskPath:(NSString *)path
			  attempt:(NSInteger)attempt deliver:(void (^)(UIImage *))deliver {
	[[imgSession() dataTaskWithURL:url
								 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
		UIImage *image = data ? [UIImage imageWithData:data] : nil;
		if (image) {
			[memCache() setObject:image forKey:key cost:rygImageCost(image)];
			[data writeToFile:path atomically:YES];
			deliver(image);
			return;
		}
		// Retry transient failures only; a 4xx means the signed URL is dead, so the
		// caller refetches a fresh one instead.
		NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
		BOOL transient = (err != nil) || status == 0 || status == 408 || status == 429 || status >= 500;
		if (transient && attempt < kRYGMaxImageRetries) {
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
			if (image) [memCache() setObject:image forKey:key cost:rygImageCost(image)];
			deliver(image);
		});
		return;
	}

	if (!rygJoinInflight(key, deliver)) return;
	[self fetchImageURL:url key:key diskPath:path attempt:0 deliver:^(UIImage *img){ rygFinishInflight(key, img); }];
}

+ (void)fetchThumbURL:(NSURL *)url memKey:(NSString *)memKey diskPath:(NSString *)path
			 maxPixel:(CGFloat)maxPixel attempt:(NSInteger)attempt finish:(void (^)(UIImage *))finish {
	[[imgSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
		if (data.length) {
			[data writeToFile:path atomically:YES];
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
				UIImage *img = rygDownsample(data, maxPixel);
				if (img) [memCache() setObject:img forKey:memKey cost:rygImageCost(img)];
				finish(img);
			});
			return;
		}
		NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
		BOOL transient = (err != nil) || status == 0 || status == 408 || status == 429 || status >= 500;
		if (transient && attempt < kRYGMaxImageRetries) {
			NSTimeInterval delay = 0.6 * (attempt + 1) * (attempt + 1);
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
						   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
				[self fetchThumbURL:url memKey:memKey diskPath:path maxPixel:maxPixel attempt:attempt + 1 finish:finish];
			});
			return;
		}
		finish(nil);
	}] resume];
}

+ (void)loadThumbnailFromURL:(NSURL *)url cacheKey:(NSString *)cacheKey maxPixel:(CGFloat)maxPixel completion:(void (^)(UIImage *))completion {
	if (!url || !completion) return;
	NSString *baseKey = cacheKey.length ? cacheKey : url.absoluteString;
	NSString *memKey = [NSString stringWithFormat:@"%@#%.0f", baseKey, maxPixel];

	void (^deliver)(UIImage *) = ^(UIImage *image) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
	};

	UIImage *hit = [memCache() objectForKey:memKey];
	if (hit) { deliver(hit); return; }

	NSString *path = [diskDir() stringByAppendingPathComponent:hashKey(baseKey)];
	NSFileManager *fm = [NSFileManager defaultManager];
	if ([fm fileExistsAtPath:path]) {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			UIImage *img = rygDownsample([NSData dataWithContentsOfFile:path], maxPixel);
			if (img) [memCache() setObject:img forKey:memKey cost:rygImageCost(img)];
			deliver(img);
		});
		return;
	}

	if (!rygJoinInflight(memKey, deliver)) return;
	[self fetchThumbURL:url memKey:memKey diskPath:path maxPixel:maxPixel attempt:0 finish:^(UIImage *img){ rygFinishInflight(memKey, img); }];
}

+ (BOOL)hasImageForKey:(NSString *)key {
	if (!key.length) return NO;
	if ([memCache() objectForKey:key]) return YES;
	NSString *path = [diskDir() stringByAppendingPathComponent:hashKey(key)];
	return [[NSFileManager defaultManager] fileExistsAtPath:path];
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

	[[imgSession() dataTaskWithURL:url
								 completionHandler:^(NSData *data, NSURLResponse *_r, NSError *_e) {
		if (data) [data writeToFile:path atomically:YES];
		deliver(data);
	}] resume];
}

@end
