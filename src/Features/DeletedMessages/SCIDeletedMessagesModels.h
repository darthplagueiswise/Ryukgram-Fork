#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIDeletedMessageKind) {
    SCIDeletedMessageKindUnknown = 0,
    SCIDeletedMessageKindText,
    SCIDeletedMessageKindPhoto,
    SCIDeletedMessageKindVideo,
    SCIDeletedMessageKindVoice,
    SCIDeletedMessageKindGif,
    SCIDeletedMessageKindSticker,
    SCIDeletedMessageKindShare,
    SCIDeletedMessageKindLink,
    SCIDeletedMessageKindAudioShare,
    SCIDeletedMessageKindReactionRemoved,
    SCIDeletedMessageKindOther,
};

FOUNDATION_EXPORT NSString *SCIDeletedMessageKindToString(SCIDeletedMessageKind kind);
FOUNDATION_EXPORT SCIDeletedMessageKind SCIDeletedMessageKindFromString(NSString * _Nullable s);
FOUNDATION_EXPORT NSString *SCIDeletedMessageKindLocalizedName(SCIDeletedMessageKind kind);
FOUNDATION_EXPORT NSString *SCIDeletedMessageKindSymbol(SCIDeletedMessageKind kind);

typedef NS_ENUM(NSInteger, SCIDeletedMessageMediaStatus) {
    SCIDeletedMessageMediaStatusNone = 0,
    SCIDeletedMessageMediaStatusSaved,
    SCIDeletedMessageMediaStatusPending,
    SCIDeletedMessageMediaStatusFailed,
    SCIDeletedMessageMediaStatusUnavailable,
};

FOUNDATION_EXPORT NSString *SCIDeletedMessageMediaStatusToString(SCIDeletedMessageMediaStatus s);
FOUNDATION_EXPORT SCIDeletedMessageMediaStatus SCIDeletedMessageMediaStatusFromString(NSString * _Nullable s);

@interface SCIDeletedMessage : NSObject

@property (nonatomic, copy)   NSString *messageId;
@property (nonatomic, copy)   NSString *threadId;
@property (nonatomic, copy, nullable) NSString *threadTitle;
@property (nonatomic, copy, nullable) NSString *threadAvatarURL;
@property (nonatomic, assign) BOOL isGroup;

@property (nonatomic, copy)   NSString *senderPk;
@property (nonatomic, copy, nullable) NSString *senderUsername;
@property (nonatomic, copy, nullable) NSString *senderFullName;
@property (nonatomic, copy, nullable) NSString *senderProfilePicURL;

@property (nonatomic, strong) NSDate   *sentAt;
@property (nonatomic, strong) NSDate   *capturedAt;
@property (nonatomic, strong) NSDate   *deletedAt;

@property (nonatomic, assign) SCIDeletedMessageKind kind;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *previewText;

@property (nonatomic, copy, nullable) NSString *mediaURL;
@property (nonatomic, copy, nullable) NSString *mediaPath;       // relative under media root
@property (nonatomic, copy, nullable) NSString *thumbnailURL;
@property (nonatomic, copy, nullable) NSString *thumbnailPath;
@property (nonatomic, copy, nullable) NSString *mediaMimeType;

@property (nonatomic, assign) SCIDeletedMessageMediaStatus mediaStatus;
@property (nonatomic, assign) BOOL isEphemeral;                  // view-once / disappearing media
@property (nonatomic, copy, nullable) NSString *mediaPk;         // feed/reshare media PK, for refetch-by-PK
// Ordered download fallbacks, best first; persisted so a retry can replay the chain.
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *mediaCandidates;

@property (nonatomic, assign) double   durationSeconds;          // voice/video
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *waveform;
@property (nonatomic, assign) CGFloat  width;
@property (nonatomic, assign) CGFloat  height;

// Server id of the replied-to message; best-effort from metadata/KVC.
@property (nonatomic, copy, nullable) NSString *replyToMessageId;

// Reaction-removed records: emoji removed + target message (`text` = its snapshot).
@property (nonatomic, copy, nullable) NSString *reactionEmoji;
@property (nonatomic, copy, nullable) NSString *targetMessageId;
@property (nonatomic, copy, nullable) NSString *reactionTargetUsername;

// Edits: chain of {text, at} dicts (oldest → newest). `originalText` is the
// pre-edit body; `text` is the latest version seen before unsend.
@property (nonatomic, copy, nullable) NSString *originalText;
@property (nonatomic, assign) NSUInteger editCount;
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *edits;

+ (instancetype)messageFromJSONDict:(NSDictionary *)dict;
- (NSDictionary *)toJSONDict;

@end

// UI note for a non-viewable record (Pending/Failed/Unavailable); nil when media is present.
FOUNDATION_EXPORT NSString * _Nullable SCIDeletedMessageMediaStatusNote(SCIDeletedMessage *message);

// One thread's records: 1-1 DM (isGroup NO, sender* = other party) or group (isGroup YES, threadTitle = name).
@interface SCIDeletedMessageGroup : NSObject
@property (nonatomic, copy, nullable) NSString *threadId;
@property (nonatomic, assign) BOOL isGroup;
@property (nonatomic, copy, nullable) NSString *threadTitle;
@property (nonatomic, copy, nullable) NSString *threadAvatarURL;

@property (nonatomic, copy) NSString *senderPk;
@property (nonatomic, copy, nullable) NSString *senderUsername;
@property (nonatomic, copy, nullable) NSString *senderFullName;
@property (nonatomic, copy, nullable) NSString *senderProfilePicURL;
@property (nonatomic, strong) NSArray<SCIDeletedMessage *> *messages; // newest-first
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly, nullable) NSDate *lastDeletedAt;
@property (nonatomic, readonly, nullable) SCIDeletedMessage *latest;

// Stable per-row identity: threadId, else "s:<senderPk>" for legacy records.
@property (nonatomic, readonly) NSString *identifier;
// Distinct senders in this thread, newest-first (one message each).
@property (nonatomic, readonly) NSArray<SCIDeletedMessage *> *distinctSenders;
@end

NS_ASSUME_NONNULL_END
