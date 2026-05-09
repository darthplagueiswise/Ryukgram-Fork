#import <Foundation/Foundation.h>
#import "SCIDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const SCIDeletedMessagesDidChangeNotification;

// Per-account on-disk store for deleted-message records and their captured media.
//
// Layout under Application Support/RyukGram/DeletedMessages/:
//   <ownerPk>.json      — array of message dicts (newest-first)
//   media/<ownerPk>/    — captured media blobs, named "<message_id>.<ext>"
@interface SCIDeletedMessagesStorage : NSObject

#pragma mark - Read

+ (NSArray<SCIDeletedMessage *> *)allMessagesForOwnerPK:(NSString *)ownerPK;
+ (NSArray<SCIDeletedMessageGroup *> *)groupedBySenderForOwnerPK:(NSString *)ownerPK;
+ (NSArray<SCIDeletedMessage *> *)messagesForSenderPK:(NSString *)senderPK
                                            ownerPK:(NSString *)ownerPK;

#pragma mark - Write

// Insert / replace by message_id. Newest-first ordering preserved on disk.
+ (BOOL)saveMessage:(SCIDeletedMessage *)message forOwnerPK:(NSString *)ownerPK;

// Atomic-ish bulk save when capture lands several at once.
+ (BOOL)saveMessages:(NSArray<SCIDeletedMessage *> *)messages forOwnerPK:(NSString *)ownerPK;

// Drop a single record (and its media blobs).
+ (void)deleteMessageId:(NSString *)messageId forOwnerPK:(NSString *)ownerPK;

// Patch every record from `senderPK` with whatever non-empty values are in
// `info` (keys: `username`, `full_name`, `profile_pic_url`). Used by the UI's
// missing-pfp backfill — capture only knows what the resolver has cached.
+ (BOOL)applySenderInfo:(NSDictionary *)info
            forSenderPK:(NSString *)senderPK
                ownerPK:(NSString *)ownerPK;

// Drop every record for one sender.
+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK;

// Wipe entire log + media for one account.
+ (void)resetForOwnerPK:(NSString *)ownerPK;
+ (void)resetAll;

#pragma mark - Media paths

// Absolute paths derived from relative paths stored on the model.
+ (nullable NSString *)absolutePathForRelativePath:(nullable NSString *)relativePath
                                          ownerPK:(NSString *)ownerPK;

// Reserve a relative path under media/<ownerPK>/ for a new blob. Caller writes the file.
+ (NSString *)reserveRelativeMediaPathForMessageId:(NSString *)messageId
                                         extension:(nullable NSString *)ext
                                           ownerPK:(NSString *)ownerPK;

// Total size (bytes) of stored media for one account — used by Settings.
+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK;

@end

NS_ASSUME_NONNULL_END
