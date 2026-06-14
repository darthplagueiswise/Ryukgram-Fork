#import <UIKit/UIKit.h>

// Memory + disk image cache for remote URLs. Completion runs on main queue.
// Disk cache lives under Library/Caches/RyukGramImages and survives reinstall
// so long as Caches isn't wiped.
@interface SCIImageCache : NSObject

+ (void)loadImageFromURL:(NSURL *)url completion:(void (^)(UIImage *_Nullable image))completion;

// Caches under an explicit key instead of the URL — for signed/expiring CDN URLs
// (profile pics) where the signature rotates but the asset is stable.
+ (void)loadImageFromURL:(NSURL *)url
				cacheKey:(nullable NSString *)cacheKey
			  completion:(void (^)(UIImage *_Nullable image))completion;

// Raw bytes variant — shares the same disk cache. Completion on main queue.
+ (void)loadDataFromURL:(NSURL *)url completion:(void (^)(NSData *_Nullable data))completion;

@end
