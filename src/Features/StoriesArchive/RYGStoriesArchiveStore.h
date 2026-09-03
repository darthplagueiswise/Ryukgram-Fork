#import <CoreData/CoreData.h>
#import "RYGArchivedStory.h"
#import "RYGArchivedStoryViewer.h"

NS_ASSUME_NONNULL_BEGIN

// One CoreData stack per IG account, keyed by user PK. Instances are cached and
// coexist, so an account switch is a dictionary hit — no teardown/reload.
@interface RYGStoriesArchiveStore : NSObject

+ (nullable instancetype)storeForPK:(NSString *)pk;
+ (nullable instancetype)storeForCurrentUser;

+ (NSString *)storageDirectory;

// Backup hooks. Row-level merge never swaps a live sqlite; reset/resetPK unload
// the affected stacks first so the generic replace path can copy files safely.
+ (void)checkpointAllForExport;
+ (void)resetAll;
+ (void)resetForPK:(NSString *)pk;
+ (void)mergeImportedStoreAtPath:(NSString *)extractedDir;

@property (nonatomic, copy, readonly) NSString *accountPK;
@property (nonatomic, strong, readonly) NSManagedObjectContext *viewContext;

- (void)performBackground:(void (^)(NSManagedObjectContext *ctx))block;

// Insert if absent (dedup on story pk); media paths land later via -markStoryPK:…
- (RYGArchivedStory *)upsertStoryWithPK:(NSString *)pk
                                mediaID:(NSString *)mediaID
                              mediaType:(int16_t)mediaType
                                takenAt:(nullable NSDate *)takenAt
                              expiresAt:(nullable NSDate *)expiresAt
                              inContext:(NSManagedObjectContext *)ctx;

- (nullable RYGArchivedStory *)storyWithPK:(NSString *)pk inContext:(NSManagedObjectContext *)ctx;
- (nullable RYGArchivedStory *)storyWithMediaID:(NSString *)mediaID inContext:(NSManagedObjectContext *)ctx;

// Fresh viewer fetch by story pk, ordered by view order. Avoids a stale
// to-many relationship on a long-lived story object.
- (NSArray<RYGArchivedStoryViewer *> *)sortedViewersForStoryPK:(NSString *)pk;

// Fresh identity keyed by user pk, in IG's own field names. Applied to every
// story row for that user.
- (void)applyViewerIdentities:(NSDictionary<NSString *, NSDictionary *> *)byPK;

// Every story this user appeared in, newest first.
- (NSArray<RYGArchivedStoryViewer *> *)viewerRowsForUserPK:(NSString *)pk;

- (void)markStoryPK:(NSString *)pk downloadedMediaRel:(nullable NSString *)mediaRel thumbRel:(nullable NSString *)thumbRel;

// Stops further viewer polling for a story IG no longer serves.
- (void)markViewersFinalForMediaID:(NSString *)mediaID;

// Stories still within the 48h fetchable window whose viewers haven't been
// refreshed since `cutoff` (nil lastFetch always qualifies), excluding ones marked
// final. Keeps live stories current and grabs the final post-expiry snapshot.
- (NSArray<NSString *> *)mediaIDsNeedingViewerRefreshBefore:(NSDate *)cutoff;

// Upsert viewers/likers onto the story; flags new ones via addedInLatestFetch.
- (void)saveViewers:(NSArray<NSDictionary *> *)viewers
          totalCount:(NSInteger)totalCount
          forMediaID:(NSString *)mediaID;

- (NSArray<RYGArchivedStory *> *)allStoriesSortedByDateDescending;
- (NSArray<RYGArchivedStory *> *)storiesSortedByDateDescendingInContext:(NSManagedObjectContext *)ctx;

// Every viewer row across every story. Run on a background context.
- (NSArray<RYGArchivedStoryViewer *> *)allViewersInContext:(NSManagedObjectContext *)ctx;

- (nullable NSString *)absoluteMediaPathForStory:(RYGArchivedStory *)story;
- (nullable NSString *)absoluteThumbPathForStory:(RYGArchivedStory *)story;

- (void)deleteStory:(RYGArchivedStory *)story;
- (void)deleteAllStories;

// Folds WAL into the main file so an export archives a complete store.
- (void)checkpointForExport;
- (void)unload;

@end

NS_ASSUME_NONNULL_END
