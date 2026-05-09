// In-memory capture pipeline for the deleted-messages log.
//
// KeepDeletedMessages.x already owns the single chokepoint hook on
// `IGDirectCacheUpdatesApplicator._applyThreadUpdates:completion:userAccess:`
// and is the only place we can guarantee ordering relative to the
// remove-keys neutering. Rather than fight install order, that hook calls
// these two C functions directly:
//
//   • `sciDMCaptureNoteInsert(message)` on every insert/replace, so we have a
//     full snapshot of the body BEFORE any unsend can happen.
//   • `sciDMCaptureNoteRemoveSids(sids, ownerPk, threadId)` on every reason==0
//     remove, so we know which captured snapshots became deleted records.
//
// All persistence + media downloading happens here, gated by
// `deleted_messages_log_enabled` (read fresh — never cached).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void sciDMCaptureNoteInsert(id _Nullable message);

// `keys` are the IGDirectMessageKey objects from the unsend delta. The
// capture side extracts sids itself, falls back to a sync lookup against
// `applicator.cache messageForKey:` for any sid that's no longer in the
// in-memory weak cache (scrolled-out chats), and finally writes a
// sender-only placeholder if the lookup fails.
void sciDMCaptureNoteRemoveKeys(NSArray * _Nullable keys,
                                 id _Nullable applicator,
                                 NSString * _Nullable ownerPk,
                                 NSString * _Nullable threadId);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
