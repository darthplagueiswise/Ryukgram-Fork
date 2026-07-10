#import "SCINotificationActions.h"

#define DEF(name, value) NSString *const name = @value
DEF(SCI_NOTIF_DOWNLOAD,             "download");
DEF(SCI_NOTIF_DOWNLOAD_BULK,        "download_bulk");
DEF(SCI_NOTIF_GALLERY_SAVE,         "gallery_save");
DEF(SCI_NOTIF_REPOST,               "repost");

DEF(SCI_NOTIF_COPY_URL,             "copy_url");
DEF(SCI_NOTIF_COPY_CAPTION,         "copy_caption");
DEF(SCI_NOTIF_COPY_COMMENT,         "copy_comment");
DEF(SCI_NOTIF_COPY_NOTE,            "copy_note");
DEF(SCI_NOTIF_COPY_PROFILE,         "copy_profile");
DEF(SCI_NOTIF_COPY_GIF,             "copy_gif");
DEF(SCI_NOTIF_COPY_AUDIO_URL,       "copy_audio_url");
DEF(SCI_NOTIF_COPY_QUALITY_URL,     "copy_quality_url");
DEF(SCI_NOTIF_COPY_PASSWORD,        "copy_password");
DEF(SCI_NOTIF_COPY_DESCRIPTION,     "copy_description");

DEF(SCI_NOTIF_BLOCK_TOGGLE,         "block_toggle");
DEF(SCI_NOTIF_EXCLUDE_CHAT,         "exclude_chat");
DEF(SCI_NOTIF_EXCLUDE_STORY,        "exclude_story");
DEF(SCI_NOTIF_PIN_THREAD,           "pin_thread");
DEF(SCI_NOTIF_PIN_STORY_VIEWER,     "pin_story_viewer");

DEF(SCI_NOTIF_SEEN_DM,              "seen_dm");
DEF(SCI_NOTIF_SEEN_STORY,           "seen_story");
DEF(SCI_NOTIF_READ_RECEIPT,         "read_receipt");

DEF(SCI_NOTIF_VOICE_SEND,           "voice_send");
DEF(SCI_NOTIF_AUDIO_EXTRACT,        "audio_extract");

DEF(SCI_NOTIF_UNSENT_MESSAGE,       "unsent_message");
DEF(SCI_NOTIF_REACTION_REMOVED,     "reaction_removed");
DEF(SCI_NOTIF_LIVE_TOGGLE,          "live_toggle");
DEF(SCI_NOTIF_GIF_SENT,             "gif_sent");
DEF(SCI_NOTIF_GIF_FAVORITE,         "gif_favorite");

DEF(SCI_NOTIF_ANALYZER_DONE,        "analyzer_done");
DEF(SCI_NOTIF_ANALYZER_RUN,         "analyzer_run");
DEF(SCI_NOTIF_FOLLOW_REQ_ACCEPTED,  "follow_req_accepted");
DEF(SCI_NOTIF_FOLLOW_REQ_REJECTED,  "follow_req_rejected");
DEF(SCI_NOTIF_FOLLOW_REQ_RECEIVED,  "follow_req_received");
DEF(SCI_NOTIF_FOLLOW_REQ_WITHDRAWN, "follow_req_withdrawn");

DEF(SCI_NOTIF_MEDIA_ERROR,          "media_error");
DEF(SCI_NOTIF_PERMISSION_ERROR,     "permission_error");
DEF(SCI_NOTIF_VALIDATION_ERROR,     "validation_error");
DEF(SCI_NOTIF_NETWORK_ERROR,        "network_error");
DEF(SCI_NOTIF_ACTION_ERROR,         "action_error");

DEF(SCI_NOTIF_LOCK_SETUP,           "lock_setup");
DEF(SCI_NOTIF_LOCK_CHANGED,         "lock_changed");
DEF(SCI_NOTIF_LOCK_RESET,           "lock_reset");
DEF(SCI_NOTIF_LOCK_FAILED,          "lock_failed");
DEF(SCI_NOTIF_LOCK_CHAT_TOGGLE,     "lock_chat_toggle");

DEF(SCI_NOTIF_PASTE_LINK_INVALID,   "paste_link_invalid");
DEF(SCI_NOTIF_EXPERIMENTAL_WARN,    "experimental_warn");
DEF(SCI_NOTIF_SETTINGS_ACTION,      "settings_action");
DEF(SCI_NOTIF_CACHE_CLEAR,          "cache_clear");
DEF(SCI_NOTIF_BACKUP,               "backup");
DEF(SCI_NOTIF_GENERIC,              "generic");
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

@implementation SCINotificationActionInfo

+ (instancetype)infoWithID:(NSString *)identifier
                  category:(NSString *)category
                      name:(NSString *)displayName
                      caps:(SCINotificationActionCaps)caps {
    SCINotificationActionInfo *info = [self new];
    info->_identifier = [identifier copy];
    info->_category = [category copy];
    info->_displayName = [displayName copy];
    info->_caps = caps;
    return info;
}

@end

#define A(_id, _cat, _name, _caps) [SCINotificationActionInfo infoWithID:(_id) category:SCILocalized(_cat) name:SCILocalized(_name) caps:(_caps)]

NSArray<SCINotificationActionInfo *> *SCINotificationActionsAll(void) {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SCINotificationActionCaps tog  = SCINotificationActionCapsAllowOff | SCINotificationActionCapsAllowIG;
        SCINotificationActionCaps prog = SCINotificationActionCapsAllowOff | SCINotificationActionCapsProgress;
        SCINotificationActionCaps togC = tog | SCINotificationActionCapsCoalesce;  // backlog-bursty

        all = @[
            // Downloads & saving
            A(SCI_NOTIF_DOWNLOAD,           kCatDownloads, @"Download progress",         prog),
            A(SCI_NOTIF_DOWNLOAD_BULK,      kCatDownloads, @"Bulk download progress",    prog),
            A(SCI_NOTIF_GALLERY_SAVE,       kCatDownloads, @"Saved to Gallery",          tog),
            A(SCI_NOTIF_REPOST,             kCatDownloads, @"Repost progress",           prog),

            // Copy to clipboard
            A(SCI_NOTIF_COPY_URL,           kCatCopy,      @"Copied post / reel URL",    tog),
            A(SCI_NOTIF_COPY_CAPTION,       kCatCopy,      @"Copied caption",            tog),
            A(SCI_NOTIF_COPY_COMMENT,       kCatCopy,      @"Copied comment text",       tog),
            A(SCI_NOTIF_COPY_GIF,           kCatCopy,      @"Copied GIF link",           tog),
            A(SCI_NOTIF_COPY_NOTE,          kCatCopy,      @"Copied note text",          tog),
            A(SCI_NOTIF_COPY_PROFILE,       kCatCopy,      @"Copied profile info",       tog),
            A(SCI_NOTIF_COPY_AUDIO_URL,     kCatCopy,      @"Copied audio URL",          tog),
            A(SCI_NOTIF_COPY_QUALITY_URL,   kCatCopy,      @"Copied quality picker URL", tog),
            A(SCI_NOTIF_COPY_PASSWORD,      kCatCopy,      @"Copied unlocked password",  tog),
            A(SCI_NOTIF_COPY_DESCRIPTION,   kCatCopy,      @"Copied description text",   tog),

            // Read receipts & seen
            A(SCI_NOTIF_SEEN_DM,            kCatSeen,      @"DM seen / read receipts",    togC),
            A(SCI_NOTIF_SEEN_STORY,         kCatSeen,      @"Story seen / read receipts", togC),
            A(SCI_NOTIF_READ_RECEIPT,       kCatSeen,      @"Someone read your message",  togC),

            // Block, exclude & pin
            A(SCI_NOTIF_BLOCK_TOGGLE,       kCatRelations, @"User blocked / unblocked",   tog),
            A(SCI_NOTIF_EXCLUDE_CHAT,       kCatRelations, @"Chat added / removed from exclude", tog),
            A(SCI_NOTIF_EXCLUDE_STORY,      kCatRelations, @"Story user added / removed from exclude", tog),
            A(SCI_NOTIF_PIN_THREAD,         kCatRelations, @"Share-sheet recipient pinned", tog),
            A(SCI_NOTIF_PIN_STORY_VIEWER,   kCatRelations, @"Story viewer pinned", tog),

            // Stories & messages
            A(SCI_NOTIF_UNSENT_MESSAGE,     kCatStories,   @"Unsent message detected",   togC),
            A(SCI_NOTIF_REACTION_REMOVED,   kCatStories,   @"Reaction removed detected",  togC),
            A(SCI_NOTIF_LIVE_TOGGLE,        kCatStories,   @"Live comments toggled",     tog),
            A(SCI_NOTIF_GIF_SENT,           kCatStories,   @"Custom GIF sent",           tog),
            A(SCI_NOTIF_GIF_FAVORITE,       kCatStories,   @"GIF favorited / unfavorited", tog),

            // Voice & audio
            A(SCI_NOTIF_VOICE_SEND,         kCatAudio,     @"Voice DM sent",             tog),
            A(SCI_NOTIF_AUDIO_EXTRACT,      kCatAudio,     @"Audio extraction status",   tog),

            // Profile
            A(SCI_NOTIF_ANALYZER_RUN,       kCatProfile,   @"Profile Analyzer progress", prog),
            A(SCI_NOTIF_ANALYZER_DONE,      kCatProfile,   @"Profile Analyzer complete", tog),
            A(SCI_NOTIF_FOLLOW_REQ_ACCEPTED, kCatProfile,  @"Follow request accepted",   tog),
            A(SCI_NOTIF_FOLLOW_REQ_REJECTED, kCatProfile,  @"Follow request declined",   tog),
            A(SCI_NOTIF_FOLLOW_REQ_RECEIVED, kCatProfile,  @"Follow request received",   tog),
            A(SCI_NOTIF_FOLLOW_REQ_WITHDRAWN, kCatProfile, @"Follow request withdrawn",  tog),

            // Errors
            A(SCI_NOTIF_MEDIA_ERROR,        kCatErrors,    @"Media extraction failed",   tog),
            A(SCI_NOTIF_PERMISSION_ERROR,   kCatErrors,    @"Permission denied",         tog),
            A(SCI_NOTIF_VALIDATION_ERROR,   kCatErrors,    @"Validation error",          tog),
            A(SCI_NOTIF_NETWORK_ERROR,      kCatErrors,    @"Network / API error",       tog),
            A(SCI_NOTIF_ACTION_ERROR,       kCatErrors,    @"Action error fallback",     tog),

            // Security & Privacy
            A(SCI_NOTIF_LOCK_SETUP,         kCatSecurity,  @"Passcode set",              tog),
            A(SCI_NOTIF_LOCK_CHANGED,       kCatSecurity,  @"Passcode changed",          tog),
            A(SCI_NOTIF_LOCK_RESET,         kCatSecurity,  @"Passcode reset",            tog),
            A(SCI_NOTIF_LOCK_FAILED,        kCatSecurity,  @"Unlock failed",             tog),
            A(SCI_NOTIF_LOCK_CHAT_TOGGLE,   kCatSecurity,  @"Chat locked / unlocked",    tog),

            // Other
            A(SCI_NOTIF_PASTE_LINK_INVALID, kCatMisc,      @"Invalid clipboard link",    tog),
            A(SCI_NOTIF_EXPERIMENTAL_WARN,  kCatMisc,      @"Experimental flag warning", tog),
            A(SCI_NOTIF_SETTINGS_ACTION,    kCatMisc,      @"Settings action confirmed", tog),
            A(SCI_NOTIF_CACHE_CLEAR,        kCatMisc,      @"Cache clearing progress",   prog),
            A(SCI_NOTIF_BACKUP,             kCatMisc,      @"Backup export / import",    prog),
            A(SCI_NOTIF_GENERIC,            kCatMisc,      @"Other / uncategorized",     tog),
        ];
    });
    return all;
}
#undef A

SCINotificationActionInfo *SCINotificationActionInfoForID(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary new];
        for (SCINotificationActionInfo *info in SCINotificationActionsAll()) {
            m[info.identifier] = info;
        }
        map = [m copy];
    });
    return map[identifier];
}

NSArray<NSString *> *SCINotificationCategoriesAll(void) {
    static NSArray *cats;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *m = [NSMutableArray new];
        NSMutableSet *seen = [NSMutableSet new];
        for (SCINotificationActionInfo *info in SCINotificationActionsAll()) {
            if (![seen containsObject:info.category]) {
                [seen addObject:info.category];
                [m addObject:info.category];
            }
        }
        cats = [m copy];
    });
    return cats;
}
