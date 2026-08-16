// In-memory capture pipeline for the deleted-messages log.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void rygDMCaptureNoteInsert(id _Nullable message);

void rygDMCaptureNoteEdit(NSString * _Nullable messageId,
                          id _Nullable contentMutation,
                          NSString * _Nullable ownerPk,
                          NSString * _Nullable threadId);

void rygDMCaptureNoteReaction(NSString * _Nullable messageId,
                              id _Nullable contentMutation,
                              NSString * _Nullable ownerPk,
                              NSString * _Nullable threadId);

void rygDMCaptureNoteRemoveKeys(NSArray * _Nullable keys,
                                 id _Nullable applicator,
                                 NSString * _Nullable ownerPk,
                                 NSString * _Nullable threadId);

// Off-thread unsends only become reachable on thread open.
void rygDMCaptureNotePreservedMessage(id _Nullable message, NSString * _Nullable ownerPk, NSString * _Nullable threadId);

// De-duped per session; only fills blank fields.
void rygDMResolveThreadInfo(NSString * _Nullable threadId, NSString * _Nullable ownerPk);

void rygDMRefreshThreadInfo(NSString * _Nullable threadId, NSString * _Nullable ownerPk);

// `visualMessage` = IGDirectVisualMessage, `contextMetadata` = IGDirectUIMessageMetadata. Capture while the URL is still live.
void rygDMCaptureVisualMessageOnOpen(id _Nullable visualMessage, id _Nullable contextMetadata, NSString * _Nullable ownerPk);

void rygDMUpdateKeepAlive(void);

// Re-attempt a record's media: replays its candidate chain, then refetch-by-PK. No-op once on disk.
void rygDMRetryMediaDownload(NSString * _Nullable messageId, NSString * _Nullable ownerPk);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
