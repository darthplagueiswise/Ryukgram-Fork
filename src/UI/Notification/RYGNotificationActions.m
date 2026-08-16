#import "RYGNotificationActions.h"

#define DEF(name, value) NSString *const name = @value
DEF(RYG_NOTIF_DOWNLOAD,             "download");
DEF(RYG_NOTIF_DOWNLOAD_BULK,        "download_bulk");
DEF(RYG_NOTIF_GALLERY_SAVE,         "gallery_save");
DEF(RYG_NOTIF_REPOST,               "repost");

DEF(RYG_NOTIF_COPY_URL,             "copy_url");
DEF(RYG_NOTIF_COPY_CAPTION,         "copy_caption");
DEF(RYG_NOTIF_COPY_COMMENT,         "copy_comment");
DEF(RYG_NOTIF_COPY_NOTE,            "copy_note");
DEF(RYG_NOTIF_COPY_PROFILE,         "copy_profile");
DEF(RYG_NOTIF_COPY_GIF,             "copy_gif");
DEF(RYG_NOTIF_COPY_AUDIO_URL,       "copy_audio_url");
DEF(RYG_NOTIF_COPY_QUALITY_URL,     "copy_quality_url");
DEF(RYG_NOTIF_COPY_PASSWORD,        "copy_password");
DEF(RYG_NOTIF_COPY_DESCRIPTION,     "copy_description");

DEF(RYG_NOTIF_CHAT_FONT,            "chat_font");
DEF(RYG_NOTIF_BLOCK_TOGGLE,         "block_toggle");
DEF(RYG_NOTIF_EXCLUDE_CHAT,         "exclude_chat");
DEF(RYG_NOTIF_EXCLUDE_STORY,        "exclude_story");
DEF(RYG_NOTIF_PIN_THREAD,           "pin_thread");
DEF(RYG_NOTIF_PIN_STORY_VIEWER,     "pin_story_viewer");
DEF(RYG_NOTIF_PINNED_VIEWER_ACTIVITY, "pinned_viewer_activity");

DEF(RYG_NOTIF_SEEN_DM,              "seen_dm");
DEF(RYG_NOTIF_SEEN_STORY,           "seen_story");
DEF(RYG_NOTIF_READ_RECEIPT,         "read_receipt");
DEF(RYG_NOTIF_ACTIVITY_ONLINE,      "activity_online");
DEF(RYG_NOTIF_ACTIVITY_OFFLINE,     "activity_offline");
DEF(RYG_NOTIF_ACTIVITY_TYPING,      "activity_typing");

DEF(RYG_NOTIF_VOICE_SEND,           "voice_send");
DEF(RYG_NOTIF_AUDIO_EXTRACT,        "audio_extract");
DEF(RYG_NOTIF_CALL_RECORDING,       "call_recording");

DEF(RYG_NOTIF_UNSENT_MESSAGE,       "unsent_message");
DEF(RYG_NOTIF_REACTION_REMOVED,     "reaction_removed");
DEF(RYG_NOTIF_LIVE_TOGGLE,          "live_toggle");
DEF(RYG_NOTIF_ACTIVITY_TOGGLE,      "activity_toggle");
DEF(RYG_NOTIF_GIF_SENT,             "gif_sent");
DEF(RYG_NOTIF_GIF_FAVORITE,         "gif_favorite");

DEF(RYG_NOTIF_ANALYZER_DONE,        "analyzer_done");
DEF(RYG_NOTIF_ANALYZER_RUN,         "analyzer_run");
DEF(RYG_NOTIF_FOLLOW_REQ_ACCEPTED,  "follow_req_accepted");
DEF(RYG_NOTIF_FOLLOW_REQ_REJECTED,  "follow_req_rejected");
DEF(RYG_NOTIF_FOLLOW_REQ_RECEIVED,  "follow_req_received");
DEF(RYG_NOTIF_FOLLOW_REQ_WITHDRAWN, "follow_req_withdrawn");

DEF(RYG_NOTIF_MEDIA_ERROR,          "media_error");
DEF(RYG_NOTIF_PERMISSION_ERROR,     "permission_error");
DEF(RYG_NOTIF_VALIDATION_ERROR,     "validation_error");
DEF(RYG_NOTIF_NETWORK_ERROR,        "network_error");
DEF(RYG_NOTIF_ACTION_ERROR,         "action_error");

DEF(RYG_NOTIF_LOCK_SETUP,           "lock_setup");
DEF(RYG_NOTIF_LOCK_CHANGED,         "lock_changed");
DEF(RYG_NOTIF_LOCK_RESET,           "lock_reset");
DEF(RYG_NOTIF_LOCK_FAILED,          "lock_failed");
DEF(RYG_NOTIF_LOCK_CHAT_TOGGLE,     "lock_chat_toggle");

DEF(RYG_NOTIF_PASTE_LINK_INVALID,   "paste_link_invalid");
DEF(RYG_NOTIF_EXPERIMENTAL_WARN,    "experimental_warn");
DEF(RYG_NOTIF_SETTINGS_ACTION,      "settings_action");
DEF(RYG_NOTIF_CACHE_CLEAR,          "cache_clear");
DEF(RYG_NOTIF_BACKUP,               "backup");
DEF(RYG_NOTIF_GENERIC,              "generic");
#undef DEF

static NSString *const kCatDownloads   = @"Downloads & saving";
static NSString *const kCatCopy        = @"Copy to clipboard";
static NSString *const kCatSeen        = @"Read receipts & seen";
static NSString *const kCatRelations   = @"Block, exclude & pin";
static NSString *const kCatStories     = @"Stories & messages";
static NSString *const kCatAudio       = @"Voice & audio";
static NSString *const kCatProfile     = @"Profile";
static NSString *const kCatErrors      = @"Errors";
static NSString *const kCatSecurity    = @"Security & Privacy";
static NSString *const kCatMisc        = @"Other";

@implementation RYGNotificationActionInfo

+ (instancetype)infoWithID:(NSString *)identifier
                  category:(NSString *)category
                      name:(NSString *)displayName
                      caps:(RYGNotificationActionCaps)caps {
    RYGNotificationActionInfo *info = [self new];
    info->_identifier = [identifier copy];
    info->_category = [category copy];
    info->_displayName = [displayName copy];
    info->_caps = caps;
    return info;
}

@end

#define A(_id, _cat, _name, _caps) [RYGNotificationActionInfo infoWithID:(_id) category:RYGLocalized(_cat) name:RYGLocalized(_name) caps:(_caps)]

NSArray<RYGNotificationActionInfo *> *RYGNotificationActionsAll(void) {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        RYGNotificationActionCaps tog  = RYGNotificationActionCapsAllowOff | RYGNotificationActionCapsAllowIG;
        RYGNotificationActionCaps prog = RYGNotificationActionCapsAllowOff | RYGNotificationActionCapsProgress;
        RYGNotificationActionCaps togC = tog | RYGNotificationActionCapsCoalesce;  // backlog-bursty

        all = @[
            // Downloads & saving
            A(RYG_NOTIF_DOWNLOAD,           kCatDownloads, @"Download progress",         prog),
            A(RYG_NOTIF_DOWNLOAD_BULK,      kCatDownloads, @"Bulk download progress",    prog),
            A(RYG_NOTIF_GALLERY_SAVE,       kCatDownloads, @"Saved to Gallery",          tog),
            A(RYG_NOTIF_REPOST,             kCatDownloads, @"Repost progress",           prog),

            // Copy to clipboard
            A(RYG_NOTIF_COPY_URL,           kCatCopy,      @"Copied post / reel URL",    tog),
            A(RYG_NOTIF_COPY_CAPTION,       kCatCopy,      @"Copied caption",            tog),
            A(RYG_NOTIF_COPY_COMMENT,       kCatCopy,      @"Copied comment text",       tog),
            A(RYG_NOTIF_COPY_GIF,           kCatCopy,      @"Copied GIF link",           tog),
            A(RYG_NOTIF_COPY_NOTE,          kCatCopy,      @"Copied note text",          tog),
            A(RYG_NOTIF_COPY_PROFILE,       kCatCopy,      @"Copied profile info",       tog),
            A(RYG_NOTIF_COPY_AUDIO_URL,     kCatCopy,      @"Copied audio URL",          tog),
            A(RYG_NOTIF_COPY_QUALITY_URL,   kCatCopy,      @"Copied quality picker URL", tog),
            A(RYG_NOTIF_COPY_PASSWORD,      kCatCopy,      @"Copied unlocked password",  tog),
            A(RYG_NOTIF_COPY_DESCRIPTION,   kCatCopy,      @"Copied description text",   tog),

            // Read receipts & seen
            A(RYG_NOTIF_SEEN_DM,            kCatSeen,      @"DM seen / read receipts",    togC),
            A(RYG_NOTIF_SEEN_STORY,         kCatSeen,      @"Story seen / read receipts", togC),
            A(RYG_NOTIF_READ_RECEIPT,       kCatSeen,      @"Someone read your message",  togC),
            A(RYG_NOTIF_ACTIVITY_ONLINE,    kCatSeen,      @"Someone came online",        togC),
            A(RYG_NOTIF_ACTIVITY_OFFLINE,   kCatSeen,      @"Someone went offline",       togC),
            A(RYG_NOTIF_ACTIVITY_TYPING,    kCatSeen,      @"Someone is typing to you",   togC),

            // Block, exclude & pin
            A(RYG_NOTIF_BLOCK_TOGGLE,       kCatRelations, @"User blocked / unblocked",   tog),
            A(RYG_NOTIF_EXCLUDE_CHAT,       kCatRelations, @"Chat added / removed from exclude", tog),
            A(RYG_NOTIF_EXCLUDE_STORY,      kCatRelations, @"Story user added / removed from exclude", tog),
            A(RYG_NOTIF_PIN_THREAD,         kCatRelations, @"Share-sheet recipient pinned", tog),
            A(RYG_NOTIF_PIN_STORY_VIEWER,   kCatRelations, @"Story viewer pinned", tog),
            A(RYG_NOTIF_PINNED_VIEWER_ACTIVITY, kCatRelations, @"Pinned viewer saw / liked your story", tog),

            // Stories & messages
            A(RYG_NOTIF_CHAT_FONT,          kCatStories,   @"Chat font set",             tog),
            A(RYG_NOTIF_UNSENT_MESSAGE,     kCatStories,   @"Unsent message detected",   togC),
            A(RYG_NOTIF_REACTION_REMOVED,   kCatStories,   @"Reaction removed detected",  togC),
            A(RYG_NOTIF_LIVE_TOGGLE,        kCatStories,   @"Live comments toggled",     tog),
            A(RYG_NOTIF_ACTIVITY_TOGGLE,    kCatStories,   @"Activity status toggled",   tog),
            A(RYG_NOTIF_GIF_SENT,           kCatStories,   @"Custom GIF sent",           tog),
            A(RYG_NOTIF_GIF_FAVORITE,       kCatStories,   @"GIF favorited / unfavorited", tog),

            // Voice & audio
            A(RYG_NOTIF_VOICE_SEND,         kCatAudio,     @"Voice DM sent",             tog),
            A(RYG_NOTIF_AUDIO_EXTRACT,      kCatAudio,     @"Audio extraction status",   tog),
            A(RYG_NOTIF_CALL_RECORDING,     kCatAudio,     @"Call recording status",     tog),

            // Profile
            A(RYG_NOTIF_ANALYZER_RUN,       kCatProfile,   @"Profile Analyzer progress", prog),
            A(RYG_NOTIF_ANALYZER_DONE,      kCatProfile,   @"Profile Analyzer complete", tog),
            A(RYG_NOTIF_FOLLOW_REQ_ACCEPTED, kCatProfile,  @"Follow request accepted",   tog),
            A(RYG_NOTIF_FOLLOW_REQ_REJECTED, kCatProfile,  @"Follow request declined",   tog),
            A(RYG_NOTIF_FOLLOW_REQ_RECEIVED, kCatProfile,  @"Follow request received",   tog),
            A(RYG_NOTIF_FOLLOW_REQ_WITHDRAWN, kCatProfile, @"Follow request withdrawn",  tog),

            // Errors
            A(RYG_NOTIF_MEDIA_ERROR,        kCatErrors,    @"Media extraction failed",   tog),
            A(RYG_NOTIF_PERMISSION_ERROR,   kCatErrors,    @"Permission denied",         tog),
            A(RYG_NOTIF_VALIDATION_ERROR,   kCatErrors,    @"Validation error",          tog),
            A(RYG_NOTIF_NETWORK_ERROR,      kCatErrors,    @"Network / API error",       tog),
            A(RYG_NOTIF_ACTION_ERROR,       kCatErrors,    @"Action error fallback",     tog),

            // Security & Privacy
            A(RYG_NOTIF_LOCK_SETUP,         kCatSecurity,  @"Passcode set",              tog),
            A(RYG_NOTIF_LOCK_CHANGED,       kCatSecurity,  @"Passcode changed",          tog),
            A(RYG_NOTIF_LOCK_RESET,         kCatSecurity,  @"Passcode reset",            tog),
            A(RYG_NOTIF_LOCK_FAILED,        kCatSecurity,  @"Unlock failed",             tog),
            A(RYG_NOTIF_LOCK_CHAT_TOGGLE,   kCatSecurity,  @"Chat locked / unlocked",    tog),

            // Other
            A(RYG_NOTIF_PASTE_LINK_INVALID, kCatMisc,      @"Invalid clipboard link",    tog),
            A(RYG_NOTIF_EXPERIMENTAL_WARN,  kCatMisc,      @"Experimental flag warning", tog),
            A(RYG_NOTIF_SETTINGS_ACTION,    kCatMisc,      @"Settings action confirmed", tog),
            A(RYG_NOTIF_CACHE_CLEAR,        kCatMisc,      @"Cache clearing progress",   prog),
            A(RYG_NOTIF_BACKUP,             kCatMisc,      @"Backup export / import",    prog),
            A(RYG_NOTIF_GENERIC,            kCatMisc,      @"Other / uncategorized",     tog),
        ];
    });
    return all;
}
#undef A

RYGNotificationActionInfo *RYGNotificationActionInfoForID(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary new];
        for (RYGNotificationActionInfo *info in RYGNotificationActionsAll()) {
            m[info.identifier] = info;
        }
        map = [m copy];
    });
    return map[identifier];
}

NSArray<NSString *> *RYGNotificationCategoriesAll(void) {
    static NSArray *cats;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *m = [NSMutableArray new];
        NSMutableSet *seen = [NSMutableSet new];
        for (RYGNotificationActionInfo *info in RYGNotificationActionsAll()) {
            if (![seen containsObject:info.category]) {
                [seen addObject:info.category];
                [m addObject:info.category];
            }
        }
        cats = [m copy];
    });
    return cats;
}
