#import <Foundation/Foundation.h>

// The NSE stages captured media per account. These promote a staged item into the
// log only once its sender unsends it; never-unsent captures stay staged and are cleaned.
@interface RYGNSEImport : NSObject

// Promote staged captures flagged unsent into the deleted-messages log.
+ (void)promoteDeleted;

// Enforce the size/age caps over the not-yet-unsent staging cache, oldest first.
+ (void)runCleanup;

// Drop the whole not-yet-unsent staging cache (used by "clean up on open").
+ (void)cleanStagingCache;

// Total bytes held by the staging cache across all accounts.
+ (unsigned long long)stagingCacheSize;

// Wipe the entire staging cache (all accounts).
+ (void)clearAllStaging;

@end
