// Compute and clear Instagram's local caches (Library/Caches, Application
// Support, tmp, NSURLCache).

#import <Foundation/Foundation.h>

extern NSString *const RYGCacheSizeDidUpdateNotification;

@interface RYGCacheManager : NSObject

+ (void)getCacheSizeWithCompletion:(void(^)(uint64_t bytes))completion;

+ (void)getCacheSizeTransientWithCompletion:(void(^)(uint64_t bytes))completion;

+ (uint64_t)cachedSize;

+ (void)refreshSizeInBackground;

+ (void)refreshSizeInBackgroundIfEnabled;

+ (void)clearCacheWithCompletion:(void(^)(uint64_t bytesCleared))completion;

// Clears when the interval elapsed, or when the last run was cut short or failed.
+ (void)runAutoClearIfDue;

+ (void)recoverInterruptedAutoClear;

+ (NSString *)formattedSize:(uint64_t)bytes;

@end
