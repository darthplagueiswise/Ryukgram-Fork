#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Canonical action keys. Each maps to a row in Settings → Notifications.
// Add a new ID here, in RYGNotificationActions.m's DEF list, and in
// RYGNotificationActionsAll() — that's the entire registration.

// ───── Downloads & saving ─────
extern NSString *const RYG_NOTIF_DOWNLOAD;
extern NSString *const RYG_NOTIF_DOWNLOAD_BULK;
extern NSString *const RYG_NOTIF_GALLERY_SAVE;
extern NSString *const RYG_NOTIF_REPOST;

// ───── Copy to clipboard ─────
extern NSString *const RYG_NOTIF_COPY_URL;
extern NSString *const RYG_NOTIF_COPY_CAPTION;
extern NSString *const RYG_NOTIF_COPY_COMMENT;
extern NSString *const RYG_NOTIF_COPY_NOTE;
extern NSString *const RYG_NOTIF_COPY_PROFILE;
extern NSString *const RYG_NOTIF_COPY_GIF;
extern NSString *const RYG_NOTIF_COPY_AUDIO_URL;
extern NSString *const RYG_NOTIF_COPY_QUALITY_URL;
extern NSString *const RYG_NOTIF_COPY_PASSWORD;
extern NSString *const RYG_NOTIF_COPY_DESCRIPTION;

// ───── Read receipts & seen ─────
extern NSString *const RYG_NOTIF_SEEN_DM;
extern NSString *const RYG_NOTIF_SEEN_STORY;
extern NSString *const RYG_NOTIF_READ_RECEIPT;   // someone read a message YOU sent
extern NSString *const RYG_NOTIF_ACTIVITY_ONLINE;  // someone came online
extern NSString *const RYG_NOTIF_ACTIVITY_OFFLINE; // someone went offline
extern NSString *const RYG_NOTIF_ACTIVITY_TYPING;  // someone started typing to you
extern NSString *const RYG_NOTIF_CHAT_FONT;        // chat font set (reopen to apply)

// ───── Block, exclude & pin ─────
extern NSString *const RYG_NOTIF_BLOCK_TOGGLE;
extern NSString *const RYG_NOTIF_EXCLUDE_CHAT;
extern NSString *const RYG_NOTIF_EXCLUDE_STORY;
extern NSString *const RYG_NOTIF_PIN_THREAD;
extern NSString *const RYG_NOTIF_PIN_STORY_VIEWER;
extern NSString *const RYG_NOTIF_PINNED_VIEWER_ACTIVITY;

// ───── Stories & messages ─────
extern NSString *const RYG_NOTIF_UNSENT_MESSAGE;
extern NSString *const RYG_NOTIF_REACTION_REMOVED;
extern NSString *const RYG_NOTIF_LIVE_TOGGLE;
extern NSString *const RYG_NOTIF_ACTIVITY_TOGGLE;    // "Show activity status" flipped from the inbox
extern NSString *const RYG_NOTIF_GIF_SENT;
extern NSString *const RYG_NOTIF_GIF_FAVORITE;

// ───── Voice & audio ─────
extern NSString *const RYG_NOTIF_VOICE_SEND;
extern NSString *const RYG_NOTIF_AUDIO_EXTRACT;
extern NSString *const RYG_NOTIF_CALL_RECORDING;

// ───── Profile ─────
extern NSString *const RYG_NOTIF_ANALYZER_DONE;
extern NSString *const RYG_NOTIF_ANALYZER_RUN;       // progress: profile-analyzer scan
extern NSString *const RYG_NOTIF_FOLLOW_REQ_ACCEPTED; // a sent follow request was accepted
extern NSString *const RYG_NOTIF_FOLLOW_REQ_REJECTED; // a sent follow request is no longer pending
extern NSString *const RYG_NOTIF_FOLLOW_REQ_RECEIVED;  // someone requested to follow you
extern NSString *const RYG_NOTIF_FOLLOW_REQ_WITHDRAWN; // someone cancelled their request to follow you

// ───── Errors ─────
extern NSString *const RYG_NOTIF_MEDIA_ERROR;
extern NSString *const RYG_NOTIF_PERMISSION_ERROR;
extern NSString *const RYG_NOTIF_VALIDATION_ERROR;
extern NSString *const RYG_NOTIF_NETWORK_ERROR;
extern NSString *const RYG_NOTIF_ACTION_ERROR;       // generic per-action error fallback

// ───── Security & Privacy ─────
extern NSString *const RYG_NOTIF_LOCK_SETUP;
extern NSString *const RYG_NOTIF_LOCK_CHANGED;
extern NSString *const RYG_NOTIF_LOCK_RESET;
extern NSString *const RYG_NOTIF_LOCK_FAILED;
extern NSString *const RYG_NOTIF_LOCK_CHAT_TOGGLE;

// ───── Other ─────
extern NSString *const RYG_NOTIF_PASTE_LINK_INVALID;
extern NSString *const RYG_NOTIF_EXPERIMENTAL_WARN;
extern NSString *const RYG_NOTIF_SETTINGS_ACTION;
extern NSString *const RYG_NOTIF_CACHE_CLEAR;        // progress: clearing cache
extern NSString *const RYG_NOTIF_BACKUP;             // loading: export / import / restore
extern NSString *const RYG_NOTIF_GENERIC;            // fallback for un-categorised callers

typedef NS_OPTIONS(NSUInteger, RYGNotificationActionCaps) {
    RYGNotificationActionCapsNone               = 0,
    RYGNotificationActionCapsAllowOff           = 1 << 0,  // user can mute the action
    RYGNotificationActionCapsAllowIG            = 1 << 1,  // can route to IG-native toast
    RYGNotificationActionCapsProgress           = 1 << 2,  // emits progress (forces pill)
    RYGNotificationActionCapsMirrorOffByDefault = 1 << 3,  // background mirror ships off
    RYGNotificationActionCapsCoalesce           = 1 << 4,  // foreground bursts merge into one summary pill
};

@interface RYGNotificationActionInfo : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *category;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) RYGNotificationActionCaps caps;

+ (instancetype)infoWithID:(NSString *)identifier
                  category:(NSString *)category
                      name:(NSString *)displayName
                      caps:(RYGNotificationActionCaps)caps;
@end

FOUNDATION_EXPORT NSArray<RYGNotificationActionInfo *> *RYGNotificationActionsAll(void);
FOUNDATION_EXPORT RYGNotificationActionInfo * _Nullable RYGNotificationActionInfoForID(NSString *identifier);
FOUNDATION_EXPORT NSArray<NSString *> *RYGNotificationCategoriesAll(void);

NS_ASSUME_NONNULL_END
