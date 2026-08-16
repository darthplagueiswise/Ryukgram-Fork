#import <Foundation/Foundation.h>
#import "RYGProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

// Posted on every save/update/reset. userInfo carries @"user_pk".
extern NSNotificationName const RYGProfileAnalyzerDataDidChangeNotification;

// Sentinel compare selection: each new scan diffs against the rolling last scan.
extern NSString *const RYGProfileAnalyzerCompareSelectionPrevious;

// Lightweight metadata for one archived snapshot — listed without loading the
// full follower/following arrays off disk.
@interface RYGProfileAnalyzerSnapshotMeta : NSObject
@property (nonatomic, copy) NSString *snapshotID;
@property (nonatomic, strong) NSDate *scanDate;
@property (nonatomic, assign) NSInteger followerCount;
@property (nonatomic, assign) NSInteger followingCount;
@property (nonatomic, assign) NSInteger mediaCount;
@property (nonatomic, assign) unsigned long long byteSize;
@end

// Per-account on-disk store: rolling snapshots + recorded archive + header cache + visit log.
@interface RYGProfileAnalyzerStorage : NSObject

+ (NSString *)storageDirectory;

#pragma mark - Snapshots

+ (nullable RYGProfileAnalyzerSnapshot *)currentSnapshotForUserPK:(NSString *)userPK;
+ (nullable RYGProfileAnalyzerSnapshot *)previousSnapshotForUserPK:(NSString *)userPK;

// Rotates current → previous, then writes the new current.
+ (BOOL)saveSnapshot:(RYGProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;
// Overwrites current without rotating — used for in-app follow/unfollow mutations.
+ (BOOL)updateCurrentSnapshot:(RYGProfileAnalyzerSnapshot *)snapshot forUserPK:(NSString *)userPK;

+ (void)resetForUserPK:(NSString *)userPK;
+ (void)resetAll;

#pragma mark - Snapshot history (recorded archive)

// Newest-first. Cheap — reads the manifest, not the snapshot bodies.
+ (NSArray<RYGProfileAnalyzerSnapshotMeta *> *)snapshotHistoryForUserPK:(NSString *)userPK;
// Writes the full snapshot to its own file + prepends a manifest entry. When
// capacity > 0, oldest entries beyond it are pruned (files deleted). Returns the new id.
+ (nullable NSString *)appendSnapshotToHistory:(RYGProfileAnalyzerSnapshot *)snapshot
                                     forUserPK:(NSString *)userPK
                                      capacity:(NSInteger)capacity;
+ (nullable RYGProfileAnalyzerSnapshot *)historySnapshotWithID:(NSString *)snapshotID forUserPK:(NSString *)userPK;
+ (void)deleteHistorySnapshotIDs:(NSArray<NSString *> *)ids forUserPK:(NSString *)userPK;
+ (void)clearHistoryForUserPK:(NSString *)userPK;
+ (unsigned long long)historyByteSizeForUserPK:(NSString *)userPK;

// What the next scan diffs against: RYGProfileAnalyzerCompareSelectionPrevious,
// a history snapshot id, or nil (caller falls back to its own default).
+ (nullable NSString *)compareSelectionForUserPK:(NSString *)userPK;
+ (void)setCompareSelection:(nullable NSString *)selection forUserPK:(NSString *)userPK;

#pragma mark - Unread tracking

// Per-category "last seen" item-id sets, used to badge lists with new entries.
// Returns nil when no record exists yet (caller should seed, not badge).
+ (nullable NSArray<NSString *> *)seenIDsForUserPK:(NSString *)userPK categoryKey:(NSString *)key;
+ (void)markSeenIDs:(NSArray<NSString *> *)ids forUserPK:(NSString *)userPK categoryKey:(NSString *)key;

#pragma mark - Header cache

+ (nullable NSDictionary *)headerInfoForUserPK:(NSString *)userPK;
+ (void)saveHeaderInfo:(NSDictionary *)info forUserPK:(NSString *)userPK;

#pragma mark - Backup / restore

+ (NSDictionary *)exportedDict;
+ (BOOL)importFromDict:(NSDictionary *)dict;

#pragma mark - Visited profiles

+ (NSArray<RYGProfileAnalyzerVisit *> *)visitedProfilesForUserPK:(NSString *)userPK;
+ (void)recordVisitForUser:(RYGProfileAnalyzerUser *)user forUserPK:(NSString *)userPK;
+ (void)removeVisitForUserPK:(NSString *)userPK visitedPK:(NSString *)visitedPK;
+ (void)clearVisitsForUserPK:(NSString *)userPK;
// Refresh metadata for an existing visit without bumping last_seen / visit_count.
+ (void)refreshVisitedUser:(RYGProfileAnalyzerUser *)user forUserPK:(NSString *)userPK;

@end

NS_ASSUME_NONNULL_END
