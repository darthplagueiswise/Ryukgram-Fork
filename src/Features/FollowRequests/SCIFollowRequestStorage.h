#import <Foundation/Foundation.h>
#import "SCIFollowRequestModels.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SCIFollowRequestsDidChangeNotification;

@interface SCIFollowRequestStorage : NSObject

+ (NSString *)storageDirectory;

// All records for an account, newest sort-date first.
+ (NSArray<SCIFollowRequest *> *)allForOwnerPK:(NSString *)ownerPK;

// PKs of outgoing requests still pending (Sent) — the checker polls these.
+ (NSArray<NSString *> *)pendingTargetPKsForOwnerPK:(NSString *)ownerPK;
+ (nullable SCIFollowRequest *)latestPendingForTargetPK:(NSString *)targetPK ownerPK:(NSString *)ownerPK;

// Insert a fresh pending record (type must be Sent or Received).
+ (void)recordRequest:(SCIFollowRequest *)request forOwnerPK:(NSString *)ownerPK;

// Flip the latest `fromType` record for a target to `toType`; nil if none.
+ (nullable SCIFollowRequest *)resolveTargetPK:(NSString *)targetPK
                                        fromType:(SCIFollowRequestType)fromType
                                          toType:(SCIFollowRequestType)toType
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
