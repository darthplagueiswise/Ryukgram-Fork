#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Canonical action keys. Each maps to a row in Settings → Notifications.
// Add a new ID here, in SCINotificationActions.m's DEF list, and in
// SCINotificationActionsAll() — that's the entire registration.

// ───── Downloads & saving ─────
extern NSString *const SCI_NOTIF_DOWNLOAD;
extern NSString *const SCI_NOTIF_DOWNLOAD_BULK;
extern NSString *const SCI_NOTIF_GALLERY_SAVE;

// ───── Copy to clipboard ─────
extern NSString *const SCI_NOTIF_COPY_URL;
extern NSString *const SCI_NOTIF_COPY_CAPTION;
extern NSString *const SCI_NOTIF_COPY_COMMENT;
extern NSString *const SCI_NOTIF_COPY_NOTE;
extern NSString *const SCI_NOTIF_COPY_PROFILE;
extern NSString *const SCI_NOTIF_COPY_GIF;
extern NSString *const SCI_NOTIF_COPY_AUDIO_URL;
extern NSString *const SCI_NOTIF_COPY_QUALITY_URL;
extern NSString *const SCI_NOTIF_COPY_PASSWORD;
extern NSString *const SCI_NOTIF_COPY_DESCRIPTION;

// ───── Read receipts & seen ─────
extern NSString *const SCI_NOTIF_SEEN_DM;
extern NSString *const SCI_NOTIF_SEEN_STORY;

// ───── Block, exclude & pin ─────
extern NSString *const SCI_NOTIF_BLOCK_TOGGLE;
extern NSString *const SCI_NOTIF_EXCLUDE_CHAT;
extern NSString *const SCI_NOTIF_EXCLUDE_STORY;
extern NSString *const SCI_NOTIF_PIN_THREAD;

// ───── Stories & messages ─────
extern NSString *const SCI_NOTIF_UNSENT_MESSAGE;
extern NSString *const SCI_NOTIF_LIVE_TOGGLE;
extern NSString *const SCI_NOTIF_GIF_SENT;

// ───── Voice & audio ─────
extern NSString *const SCI_NOTIF_VOICE_SEND;
extern NSString *const SCI_NOTIF_AUDIO_EXTRACT;

// ───── Profile ─────
extern NSString *const SCI_NOTIF_ANALYZER_DONE;

// ───── Errors ─────
extern NSString *const SCI_NOTIF_MEDIA_ERROR;
extern NSString *const SCI_NOTIF_PERMISSION_ERROR;
extern NSString *const SCI_NOTIF_VALIDATION_ERROR;
extern NSString *const SCI_NOTIF_NETWORK_ERROR;
extern NSString *const SCI_NOTIF_ACTION_ERROR;       // generic per-action error fallback

// ───── Other ─────
extern NSString *const SCI_NOTIF_PASTE_LINK_INVALID;
extern NSString *const SCI_NOTIF_EXPERIMENTAL_WARN;
extern NSString *const SCI_NOTIF_SETTINGS_ACTION;
extern NSString *const SCI_NOTIF_CACHE_CLEAR;        // progress: clearing cache
extern NSString *const SCI_NOTIF_GENERIC;            // fallback for un-categorised callers

typedef NS_OPTIONS(NSUInteger, SCINotificationActionCaps) {
    SCINotificationActionCapsNone     = 0,
    SCINotificationActionCapsAllowOff = 1 << 0,  // user can mute the action
    SCINotificationActionCapsAllowIG  = 1 << 1,  // can route to IG-native toast
    SCINotificationActionCapsProgress = 1 << 2,  // emits progress (forces pill)
};

@interface SCINotificationActionInfo : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *category;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) SCINotificationActionCaps caps;

+ (instancetype)infoWithID:(NSString *)identifier
                  category:(NSString *)category
                      name:(NSString *)displayName
                      caps:(SCINotificationActionCaps)caps;
@end

FOUNDATION_EXPORT NSArray<SCINotificationActionInfo *> *SCINotificationActionsAll(void);
FOUNDATION_EXPORT SCINotificationActionInfo * _Nullable SCINotificationActionInfoForID(NSString *identifier);
FOUNDATION_EXPORT NSArray<NSString *> *SCINotificationCategoriesAll(void);

NS_ASSUME_NONNULL_END
