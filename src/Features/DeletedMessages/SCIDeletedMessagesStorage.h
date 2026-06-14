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

// Root store dir, created on demand. Exposed so backup can archive/restore/clear it.
+ (NSString *)storageDirectory;

// Merge another store's files into this one (backup import). Dedup by message_id,
// local wins; exclude lists union; media copied when missing.
+ (void)mergeImportedStoreAtPath:(NSString *)importedDir;

#pragma mark - Read

+ (NSArray<SCIDeletedMessage *> *)allMessagesForOwnerPK:(NSString *)ownerPK;
+ (NSArray<SCIDeletedMessageGroup *> *)groupedBySenderForOwnerPK:(NSString *)ownerPK;
+ (NSArray<SCIDeletedMessage *> *)messagesForSenderPK:(NSString *)senderPK
                                            ownerPK:(NSString *)ownerPK;

// One entry per DM thread; threadless legacy records fall back to a per-sender bucket.
+ (NSArray<SCIDeletedMessageGroup *> *)groupedByThreadForOwnerPK:(NSString *)ownerPK;
+ (NSArray<SCIDeletedMessage *> *)messagesForThreadId:(NSString *)threadId
                                              ownerPK:(NSString *)ownerPK;

#pragma mark - Write

// Insert / replace by message_id. Newest-first ordering preserved on disk.
+ (BOOL)saveMessage:(SCIDeletedMessage *)message forOwnerPK:(NSString *)ownerPK;

// Atomic-ish bulk save when capture lands several at once.
+ (BOOL)saveMessages:(NSArray<SCIDeletedMessage *> *)messages forOwnerPK:(NSString *)ownerPK;

// RMW under the storage queue — closes the thumb-vs-media race; return NO from the mutator to skip the write.
+ (BOOL)updateMessageWithId:(NSString *)messageId
                    ownerPK:(NSString *)ownerPK
                    mutator:(BOOL (^)(SCIDeletedMessage *m))mutator;

// Drop a single record (and its media blobs).
+ (void)deleteMessageId:(NSString *)messageId forOwnerPK:(NSString *)ownerPK;

// Patch every record from `senderPK` with whatever non-empty values are in
// `info` (keys: `username`, `full_name`, `profile_pic_url`). Used by the UI's
// missing-pfp backfill — capture only knows what the resolver has cached.
+ (BOOL)applySenderInfo:(NSDictionary *)info
            forSenderPK:(NSString *)senderPK
                ownerPK:(NSString *)ownerPK;

// overwrite:YES replaces existing values (renames); NO only fills blanks.
+ (BOOL)applySenderInfo:(NSDictionary *)info
            forSenderPK:(NSString *)senderPK
                ownerPK:(NSString *)ownerPK
              overwrite:(BOOL)overwrite;

// Drop every record for one sender. threadlessOnly:YES limits to the legacy no-threadId bucket.
+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK;
+ (void)deleteMessagesForSenderPK:(NSString *)senderPK ownerPK:(NSString *)ownerPK threadlessOnly:(BOOL)threadlessOnly;

// Drop every record in one thread.
+ (void)deleteMessagesForThreadId:(NSString *)threadId ownerPK:(NSString *)ownerPK;

// Stamp thread metadata (is_group, thread_title, thread_avatar_url) onto every record in `threadId`.
+ (BOOL)applyThreadInfo:(NSDictionary *)info
            forThreadId:(NSString *)threadId
                ownerPK:(NSString *)ownerPK;

// Wipe entire log + media for one account.
+ (void)resetForOwnerPK:(NSString *)ownerPK;
+ (void)resetAll;

#pragma mark - Exclude (skip logging)

// Excluded chats/senders never get captured. Identifier matches
// SCIDeletedMessageGroup.identifier: threadId, else "s:<senderPk>".
+ (NSArray<NSString *> *)excludedIdentifiersForOwnerPK:(NSString *)ownerPK;
+ (BOOL)isExcludedIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK;
+ (BOOL)isExcludedThreadId:(nullable NSString *)threadId
                  senderPk:(nullable NSString *)senderPk
                   ownerPK:(NSString *)ownerPK;
+ (void)setExcludedIdentifier:(NSString *)identifier
                     excluded:(BOOL)excluded
                      ownerPK:(NSString *)ownerPK;

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
