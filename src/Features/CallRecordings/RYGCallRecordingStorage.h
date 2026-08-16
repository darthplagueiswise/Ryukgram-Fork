#import <Foundation/Foundation.h>
#import "RYGCallRecordingModels.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const RYGCallRecordingsDidChangeNotification;

// Per-account store for call recordings + their media.
// Layout under Application Support/RyukGram/CallRecordings/:
//   <ownerPk>.json    — array of recording dicts (newest-first)
//   media/<ownerPk>/  — recording blobs, named "<id>.<ext>"
@interface RYGCallRecordingStorage : NSObject

+ (NSString *)storageDirectory;
+ (void)mergeImportedStoreAtPath:(NSString *)importedDir;

+ (NSArray<RYGCallRecording *> *)allRecordingsForOwnerPK:(NSString *)ownerPK;
+ (NSArray<RYGCallRecordingGroup *> *)groupedForOwnerPK:(NSString *)ownerPK;
+ (NSArray<RYGCallRecording *> *)recordingsForIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK;

+ (BOOL)saveRecording:(RYGCallRecording *)recording forOwnerPK:(NSString *)ownerPK;
+ (void)deleteRecordingId:(NSString *)recordingId forOwnerPK:(NSString *)ownerPK;
+ (void)deleteRecordingsForIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK;
+ (void)resetForOwnerPK:(NSString *)ownerPK;
+ (void)resetAll;

+ (nullable NSString *)absolutePathForRelativePath:(nullable NSString *)relativePath ownerPK:(NSString *)ownerPK;
+ (NSString *)reserveMediaURLForRecordingId:(NSString *)recordingId
                                  extension:(NSString *)ext
                                    ownerPK:(NSString *)ownerPK
                                relativePath:(NSString * _Nullable * _Nullable)outRelative;
+ (unsigned long long)mediaSizeBytesForOwnerPK:(NSString *)ownerPK;

// Unread: a recording is unread if newer than both the global "seen all" mark and its
// group's own "seen" mark. Opening a group marks just that group; mark-all clears all.
+ (NSUInteger)unreadCountForOwnerPK:(NSString *)ownerPK;
+ (void)markAllSeenForOwnerPK:(NSString *)ownerPK;
+ (void)markGroupSeen:(NSString *)identifier ownerPK:(NSString *)ownerPK;

// 0 days = keep forever.
+ (NSUInteger)pruneOlderThanDays:(NSInteger)days forOwnerPK:(NSString *)ownerPK;

// Gallery-sync dedup: which recordings have already been mirrored into the gallery.
+ (BOOL)isGallerySynced:(NSString *)recordingId ownerPK:(NSString *)ownerPK;
+ (void)markGallerySynced:(NSString *)recordingId ownerPK:(NSString *)ownerPK;

// Custom rename: per-recording and per-group display label overrides.
+ (nullable NSString *)customNameForRecordingId:(NSString *)recordingId ownerPK:(NSString *)ownerPK;
+ (void)setCustomName:(nullable NSString *)name forRecordingId:(NSString *)recordingId ownerPK:(NSString *)ownerPK;
+ (nullable NSString *)customNameForGroupIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK;
+ (void)setCustomName:(nullable NSString *)name forGroupIdentifier:(NSString *)identifier ownerPK:(NSString *)ownerPK;

// Stable grouping identity for a recording (thread / peer / group-title / uncategorized).
+ (NSString *)identifierForRecording:(RYGCallRecording *)recording;

// Auto-record ignore list: chats excluded from auto-record, keyed by identifier.
+ (BOOL)isCallIgnored:(NSString *)identifier ownerPK:(NSString *)ownerPK;
+ (void)setCall:(NSString *)identifier ignored:(BOOL)ignored name:(nullable NSString *)name ownerPK:(NSString *)ownerPK;
+ (NSArray<NSDictionary *> *)ignoredCallsForOwnerPK:(NSString *)ownerPK;

@end

NS_ASSUME_NONNULL_END
