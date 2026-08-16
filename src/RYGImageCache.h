#import <UIKit/UIKit.h>

// Memory + disk image cache for remote URLs. Completion runs on main queue.
// Disk cache lives under Library/Caches/RyukGramImages and survives reinstall
// so long as Caches isn't wiped.
@interface RYGImageCache : NSObject

+ (void)loadImageFromURL:(NSURL *)url completion:(void (^)(UIImage *_Nullable image))completion;

// Caches under an explicit key instead of the URL — for signed/expiring CDN URLs
// (profile pics) where the signature rotates but the asset is stable.
+ (void)loadImageFromURL:(NSURL *)url
				cacheKey:(nullable NSString *)cacheKey
			  completion:(void (^)(UIImage *_Nullable image))completion;

// Downsampled thumbnail keyed by a stable key (survives URL expiry). Decodes to
// maxPixel off-main and caches the small bitmap — fast scrolling, low memory. Disk
// keeps the original bytes so different sizes can be re-derived.
+ (void)loadThumbnailFromURL:(NSURL *)url
					cacheKey:(nullable NSString *)cacheKey
					maxPixel:(CGFloat)maxPixel
				  completion:(void (^)(UIImage *_Nullable image))completion;

// Raw bytes variant — shares the same disk cache. Completion on main queue.
+ (void)loadDataFromURL:(NSURL *)url completion:(void (^)(NSData *_Nullable data))completion;

// YES if an image for this key is already in memory or on disk (renders without network).
+ (BOOL)hasImageForKey:(nullable NSString *)key;

@end
