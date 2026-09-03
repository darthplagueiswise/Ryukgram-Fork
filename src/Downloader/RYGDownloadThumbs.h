// Disk-backed square previews for download rows, keyed by job ID.

#import <UIKit/UIKit.h>

@class RYGDownloadJob;

NS_ASSUME_NONNULL_BEGIN

/// Posted on main with the job ID in `object`.
extern NSString *const RYGDownloadThumbDidLoadNotification;

@interface RYGDownloadThumbs : NSObject

+ (NSString *)storageDirectory;

/// Snapshots the job's file now (the caller may move it) and renders off-main.
+ (void)captureForJob:(RYGDownloadJob *)job;

/// Memory cache, then disk.
+ (nullable UIImage *)thumbForJobID:(NSString *)jobID;

+ (void)pruneKeepingJobIDs:(NSSet<NSString *> *)jobIDs;
+ (void)removeAll;

@end

NS_ASSUME_NONNULL_END
