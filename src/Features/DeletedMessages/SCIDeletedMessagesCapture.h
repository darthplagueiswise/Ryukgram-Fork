// In-memory capture pipeline for the deleted-messages log. Driven by
// KeepDeletedMessages.x's cache hook. Gated by deleted_messages_log_enabled.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void sciDMCaptureNoteInsert(id _Nullable message);

void sciDMCaptureNoteEdit(NSString * _Nullable messageId,
                          id _Nullable contentMutation,
                          NSString * _Nullable ownerPk,
                          NSString * _Nullable threadId);

void sciDMCaptureNoteRemoveKeys(NSArray * _Nullable keys,
                                 id _Nullable applicator,
                                 NSString * _Nullable ownerPk,
                                 NSString * _Nullable threadId);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
