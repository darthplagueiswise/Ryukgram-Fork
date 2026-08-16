// RYGActionCatalog — registry of available action menu entries per source +
// the default section layout for each source. Used by RYGActionMenuConfig as
// the schema source of truth.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGActionSource) {
    RYGActionSourceFeed = 0,
    RYGActionSourceReels,
    RYGActionSourceStories,
    RYGActionSourceDM,
    RYGActionSourceProfile,
    RYGActionSourceInstants,
    RYGActionSourceDMNativeSave,
    RYGActionSourceCount
};

// MARK: - Action ID constants

// Common (Feed/Reels/Stories)
extern NSString *const RYGAID_Expand;
extern NSString *const RYGAID_ViewCover;        // Feed videos, Reels
extern NSString *const RYGAID_Repost;
extern NSString *const RYGAID_CopyCaption;
extern NSString *const RYGAID_CopyURL;
extern NSString *const RYGAID_DownloadShare;
extern NSString *const RYGAID_DownloadSave;     // to Photos
extern NSString *const RYGAID_DownloadGallery;  // to RyukGram Gallery (no-op until Phase 2)
extern NSString *const RYGAID_DownloadWithMusic;        // photo posts with a music track → Photos
extern NSString *const RYGAID_DownloadWithMusicGallery; // photo posts with a music track → Gallery
extern NSString *const RYGAID_DownloadImageOnly;        // image stories with IG music → raw image, no audio → Photos
extern NSString *const RYGAID_DownloadImageOnlyGallery; // same → Gallery
extern NSString *const RYGAID_BulkCopyURLs;
extern NSString *const RYGAID_BulkDownloadShare;
extern NSString *const RYGAID_BulkDownloadSave;
extern NSString *const RYGAID_BulkDownloadGallery;
extern NSString *const RYGAID_Settings;

// Stories-only
extern NSString *const RYGAID_ViewMentions;
extern NSString *const RYGAID_ToggleAudio;
extern NSString *const RYGAID_ExcludeUser;

// DM-only
extern NSString *const RYGAID_DMMarkSeen;

// Profile-only
extern NSString *const RYGAID_CopyInfo;          // submenu (id/username/name/bio/link)
extern NSString *const RYGAID_ViewPicture;
extern NSString *const RYGAID_SharePicture;
extern NSString *const RYGAID_SavePicturePhotos;
extern NSString *const RYGAID_SavePictureGallery;
extern NSString *const RYGAID_ProfileSettings;
extern NSString *const RYGAID_ProfileInfoPrivacy;     // disabled info row: privacy
extern NSString *const RYGAID_ProfileInfoFollowers;   // disabled info row: follower count
extern NSString *const RYGAID_ProfileInfoFollowing;   // disabled info row: following count

// Profile copy-info sub-IDs (for default copy info pref)
extern NSString *const RYGAID_CopyID;
extern NSString *const RYGAID_CopyUsername;
extern NSString *const RYGAID_CopyName;
extern NSString *const RYGAID_CopyBio;
extern NSString *const RYGAID_CopyLink;
extern NSString *const RYGAID_CopyAll;       // Copies username/name/bio/link/ID as labeled lines

// MARK: - Models

@interface RYGActionDescriptor : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *title;       // localized fallback
@property (nonatomic, copy, readonly) NSString *iconSF;      // SF symbol fallback
@property (nonatomic, assign, readonly) BOOL eligibleForDefaultTap;
/// Off in fresh installs (still selectable in the configure screen).
@property (nonatomic, assign, readonly) BOOL disabledByDefault;
+ (instancetype)descriptorWithID:(NSString *)identifier
                            title:(NSString *)title
                           iconSF:(NSString *)iconSF
              eligibleForDefaultTap:(BOOL)eligible
                  disabledByDefault:(BOOL)disabledByDefault;
@end

@interface RYGActionConfigSection : NSObject <NSCopying>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconSF;
@property (nonatomic, assign) BOOL collapsible;
@property (nonatomic, strong) NSMutableArray<NSString *> *actionIDs;
+ (instancetype)sectionWithID:(NSString *)identifier
                         title:(NSString *)title
                        iconSF:(NSString *)iconSF
                   collapsible:(BOOL)collapsible
                       actions:(NSArray<NSString *> *)actions;
- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)sectionFromDictionary:(NSDictionary *)dict;
@end

@interface RYGActionCatalog : NSObject
+ (NSArray<RYGActionDescriptor *> *)descriptorsForSource:(RYGActionSource)source;
+ (nullable RYGActionDescriptor *)descriptorForActionID:(NSString *)actionID
                                                  source:(RYGActionSource)source;
+ (NSArray<RYGActionConfigSection *> *)defaultSectionsForSource:(RYGActionSource)source;
+ (BOOL)sourceSupportsDate:(RYGActionSource)source;
+ (BOOL)sourceSupportsDefaultTap:(RYGActionSource)source;
+ (NSString *)displayNameForSource:(RYGActionSource)source;
+ (NSString *)slugForSource:(RYGActionSource)source;   // "feed"/"reels"/...
+ (NSString *)prefKeyForSource:(RYGActionSource)source; // action_menu_cfg_<slug>
+ (NSString *)legacyDefaultTapPrefKeyForSource:(RYGActionSource)source;  // <slug>_action_default
+ (NSString *)legacyDateTogglePrefKeyForSource:(RYGActionSource)source;  // menu_date_<slug>, nil for DM/Profile

@end

NS_ASSUME_NONNULL_END
