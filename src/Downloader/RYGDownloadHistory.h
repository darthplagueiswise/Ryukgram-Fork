// Persists terminal downloads across launches, pruned to `dl_history_retention`.

#import <Foundation/Foundation.h>

@class RYGDownloadJob;

NS_ASSUME_NONNULL_BEGIN

@interface RYGDownloadHistory : NSObject

+ (NSString *)storageDirectory;

/// Hours to keep terminal jobs for; 0 = don't persist at all, -1 = keep forever.
+ (NSInteger)retentionHours;

/// Oldest first, already pruned.
+ (NSArray<RYGDownloadJob *> *)loadJobs;

/// Debounced; writes terminal jobs only.
+ (void)saveJobs:(NSArray<RYGDownloadJob *> *)jobs;

+ (void)resetAll;

@end

NS_ASSUME_NONNULL_END
