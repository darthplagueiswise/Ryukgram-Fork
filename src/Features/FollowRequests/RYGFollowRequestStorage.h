#import <Foundation/Foundation.h>
#import "RYGFollowRequestModels.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const RYGFollowRequestsDidChangeNotification;

@interface RYGFollowRequestStorage : NSObject

+ (NSString *)storageDirectory;

// All records for an account, newest sort-date first.
+ (NSArray<RYGFollowRequest *> *)allForOwnerPK:(NSString *)ownerPK;

// PKs of outgoing requests still pending (Sent) — the checker polls these.
+ (NSArray<NSString *> *)pendingTargetPKsForOwnerPK:(NSString *)ownerPK;
+ (nullable RYGFollowRequest *)latestPendingForTargetPK:(NSString *)targetPK ownerPK:(NSString *)ownerPK;

// A resolved incoming record (mis-classified Withdrawn or a re-request) back in the live inbox → Received.
+ (BOOL)restoreIncomingToReceivedForTargetPK:(NSString *)targetPK ownerPK:(NSString *)ownerPK;

// Insert a fresh pending record (type must be Sent or Received).
+ (void)recordRequest:(RYGFollowRequest *)request forOwnerPK:(NSString *)ownerPK;

// Flip the latest `fromType` record for a target to `toType`; nil if none.
+ (nullable RYGFollowRequest *)resolveTargetPK:(NSString *)targetPK
                                        fromType:(RYGFollowRequestType)fromType
                                          toType:(RYGFollowRequestType)toType
                                         ownerPK:(NSString *)ownerPK;

// PKs currently in your pending inbox (pk → firstSeen unix) — diffed each poll.
+ (NSDictionary<NSString *, NSNumber *> *)incomingSnapshotForOwnerPK:(NSString *)ownerPK;
+ (void)setIncomingSnapshot:(NSDictionary<NSString *, NSNumber *> *)snapshot forOwnerPK:(NSString *)ownerPK;

// First poll seeds existing requests silently; only later arrivals notify.
+ (BOOL)incomingSeededForOwnerPK:(NSString *)ownerPK;
+ (void)setIncomingSeededForOwnerPK:(NSString *)ownerPK;

// Marks set when you delete a request in-app, so a vanished PK reads Ignored not Withdrawn.
+ (void)markIgnoredPK:(NSString *)pk ownerPK:(NSString *)ownerPK;
+ (BOOL)consumeIgnoredPK:(NSString *)pk ownerPK:(NSString *)ownerPK;

// Records updated since the list was last opened — badges the settings entry.
+ (NSUInteger)unreadCountForOwnerPK:(NSString *)ownerPK;
+ (void)markAllSeenForOwnerPK:(NSString *)ownerPK;

+ (void)deleteRecordID:(NSString *)recordID ownerPK:(NSString *)ownerPK;
+ (void)resetForOwnerPK:(NSString *)ownerPK;
+ (void)resetAll;

// Backup import — union records by recordID.
+ (void)mergeImportedStoreAtPath:(NSString *)importedDir;

@end

NS_ASSUME_NONNULL_END
