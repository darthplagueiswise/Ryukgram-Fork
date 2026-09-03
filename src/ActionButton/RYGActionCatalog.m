#import "RYGActionCatalog.h"
#import "../Localization/RYGLocalization.h"

// MARK: - Action ID constants

NSString *const RYGAID_Expand              = @"expand";
NSString *const RYGAID_ViewCover           = @"view_cover";
NSString *const RYGAID_Repost              = @"repost";
NSString *const RYGAID_CopyCaption         = @"copy_caption";
NSString *const RYGAID_CopyURL             = @"copy_url";
NSString *const RYGAID_DownloadShare       = @"download_share";
NSString *const RYGAID_DownloadSave        = @"download_save";
NSString *const RYGAID_DownloadGallery     = @"download_gallery";
NSString *const RYGAID_DownloadWithMusic        = @"download_with_music";
NSString *const RYGAID_DownloadWithMusicGallery = @"download_with_music_gallery";
NSString *const RYGAID_DownloadImageOnly        = @"download_image_only";
NSString *const RYGAID_DownloadImageOnlyGallery = @"download_image_only_gallery";
NSString *const RYGAID_BulkCopyURLs        = @"bulk_copy_urls";
NSString *const RYGAID_BulkDownloadShare   = @"bulk_download_share";
NSString *const RYGAID_BulkDownloadSave    = @"bulk_download_save";
NSString *const RYGAID_BulkDownloadGallery = @"bulk_download_gallery";
NSString *const RYGAID_Settings            = @"settings";

NSString *const RYGAID_ViewMentions        = @"view_mentions";
NSString *const RYGAID_ToggleAudio         = @"toggle_audio";
NSString *const RYGAID_ExcludeUser         = @"exclude_user";

NSString *const RYGAID_DMMarkSeen          = @"dm_mark_seen";

NSString *const RYGAID_CopyInfo            = @"copy_info";
NSString *const RYGAID_ViewPicture         = @"view_picture";
NSString *const RYGAID_SharePicture        = @"share_picture";
NSString *const RYGAID_SavePicturePhotos   = @"save_picture_photos";
NSString *const RYGAID_SavePictureGallery  = @"save_picture_gallery";
NSString *const RYGAID_ProfileSettings        = @"profile_settings";
NSString *const RYGAID_ProfileInfoPrivacy     = @"profile_info_privacy";
NSString *const RYGAID_ProfileInfoFollowers   = @"profile_info_followers";
NSString *const RYGAID_ProfileInfoFollowing   = @"profile_info_following";

NSString *const RYGAID_CopyID              = @"copy_id";
NSString *const RYGAID_CopyUsername        = @"copy_username";
NSString *const RYGAID_CopyName            = @"copy_name";
NSString *const RYGAID_CopyBio             = @"copy_bio";
NSString *const RYGAID_CopyLink            = @"copy_link";
NSString *const RYGAID_CopyAll             = @"copy_all";

// MARK: - Models

@implementation RYGActionDescriptor
+ (instancetype)descriptorWithID:(NSString *)identifier
                            title:(NSString *)title
                           iconSF:(NSString *)iconSF
              eligibleForDefaultTap:(BOOL)eligible
                  disabledByDefault:(BOOL)disabledByDefault {
    RYGActionDescriptor *d = [RYGActionDescriptor new];
    d->_identifier = [identifier copy];
    d->_title = [title copy];
    d->_iconSF = [iconSF copy];
    d->_eligibleForDefaultTap = eligible;
    d->_disabledByDefault = disabledByDefault;
    return d;
}
@end

@implementation RYGActionConfigSection
+ (instancetype)sectionWithID:(NSString *)identifier
                         title:(NSString *)title
                        iconSF:(NSString *)iconSF
                   collapsible:(BOOL)collapsible
                       actions:(NSArray<NSString *> *)actions {
    RYGActionConfigSection *s = [RYGActionConfigSection new];
    s.identifier = identifier;
    s.title = title ?: @"";
    s.iconSF = iconSF ?: @"";
    s.collapsible = collapsible;
    s.actionIDs = [(actions ?: @[]) mutableCopy];
    return s;
}
- (id)copyWithZone:(NSZone *)zone {
    return [RYGActionConfigSection sectionWithID:self.identifier
                                            title:self.title
                                           iconSF:self.iconSF
                                      collapsible:self.collapsible
                                          actions:self.actionIDs];
}
- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.identifier ?: @"",
        @"title": self.title ?: @"",
        @"icon": self.iconSF ?: @"",
        @"collapsible": @(self.collapsible),
        @"actions": [self.actionIDs copy] ?: @[],
    };
}
+ (instancetype)sectionFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *identifier = dict[@"id"];
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return nil;
    NSString *title = [dict[@"title"] isKindOfClass:[NSString class]] ? dict[@"title"] : @"";
    NSString *icon  = [dict[@"icon"]  isKindOfClass:[NSString class]] ? dict[@"icon"]  : @"";
    BOOL collapsible = [dict[@"collapsible"] respondsToSelector:@selector(boolValue)]
                       ? [dict[@"collapsible"] boolValue] : NO;
    NSArray *actions = [dict[@"actions"] isKindOfClass:[NSArray class]] ? dict[@"actions"] : @[];
    NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:actions.count];
    for (id v in actions) if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) [cleaned addObject:v];
    return [RYGActionConfigSection sectionWithID:identifier title:title iconSF:icon collapsible:collapsible actions:cleaned];
}
@end

// MARK: - Catalog

static NSDictionary<NSNumber *, NSArray *> *gRYGActionCatalogCache = nil;

@implementation RYGActionCatalog

+ (void)initialize {
    if (self == [RYGActionCatalog class]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"RYGLanguageDidChange"
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *_) {
            gRYGActionCatalogCache = nil;
        }];
    }
}

+ (NSString *)slugForSource:(RYGActionSource)source {
    switch (source) {
        case RYGActionSourceFeed: return @"feed";
        case RYGActionSourceReels: return @"reels";
        case RYGActionSourceStories: return @"stories";
        case RYGActionSourceDM: return @"dm";
        case RYGActionSourceProfile: return @"profile";
        case RYGActionSourceInstants: return @"instants";
        case RYGActionSourceDMNativeSave: return @"dm_native_save";
        case RYGActionSourceCount: break;
    }
    return @"unknown";
}

+ (NSString *)displayNameForSource:(RYGActionSource)source {
    switch (source) {
        case RYGActionSourceFeed: return RYGLocalized(@"Feed");
        case RYGActionSourceReels: return RYGLocalized(@"Reels");
        case RYGActionSourceStories: return RYGLocalized(@"Stories");
        case RYGActionSourceDM: return RYGLocalized(@"DM disappearing media");
        case RYGActionSourceProfile: return RYGLocalized(@"Profile");
        case RYGActionSourceInstants: return RYGLocalized(@"Instants");
        case RYGActionSourceDMNativeSave: return RYGLocalized(@"DM Save button");
        case RYGActionSourceCount: break;
    }
    return @"";
}

+ (NSString *)prefKeyForSource:(RYGActionSource)source {
    return [NSString stringWithFormat:@"action_menu_cfg_%@", [self slugForSource:source]];
}

+ (NSString *)legacyDefaultTapPrefKeyForSource:(RYGActionSource)source {
    switch (source) {
        case RYGActionSourceFeed:    return @"feed_action_default";
        case RYGActionSourceReels:   return @"reels_action_default";
        case RYGActionSourceStories: return @"stories_action_default";
        case RYGActionSourceDM:      return @"dm_visual_action_default";
        case RYGActionSourceProfile: return @"action_button_profile_default_action";
        case RYGActionSourceInstants: return nil;  // new source, no legacy migration
        case RYGActionSourceDMNativeSave: return nil;  // new source, no legacy migration
        case RYGActionSourceCount: break;
    }
    return nil;
}

+ (NSString *)legacyDateTogglePrefKeyForSource:(RYGActionSource)source {
    switch (source) {
        case RYGActionSourceFeed:    return @"menu_date_feed";
        case RYGActionSourceReels:   return @"menu_date_reels";
        case RYGActionSourceStories: return @"menu_date_stories";
        default: return nil;
    }
}

+ (BOOL)sourceSupportsDate:(RYGActionSource)source {
    return [self legacyDateTogglePrefKeyForSource:source] != nil;
}

+ (BOOL)sourceSupportsDefaultTap:(RYGActionSource)source {
    // All sources support default tap selection.
    return source != RYGActionSourceCount;
}

+ (NSArray<RYGActionDescriptor *> *)descriptorsForSource:(RYGActionSource)source {
    if (!gRYGActionCatalogCache) {
        RYGActionDescriptor *(^d)(NSString *, NSString *, NSString *, BOOL) =
            ^(NSString *i, NSString *t, NSString *sf, BOOL eligible) {
                return [RYGActionDescriptor descriptorWithID:i title:t iconSF:sf
                                       eligibleForDefaultTap:eligible
                                           disabledByDefault:NO];
            };
        // Variant: ship off in fresh installs (gallery rows).
        RYGActionDescriptor *(^dOff)(NSString *, NSString *, NSString *, BOOL) =
            ^(NSString *i, NSString *t, NSString *sf, BOOL eligible) {
                return [RYGActionDescriptor descriptorWithID:i title:t iconSF:sf
                                       eligibleForDefaultTap:eligible
                                           disabledByDefault:YES];
            };

        // Feed
        NSArray *feed = @[
            d(RYGAID_Expand,              RYGLocalized(@"Expand"),                 @"bcn_arrow-expand_outline_24", YES),
            d(RYGAID_ViewCover,           RYGLocalized(@"View cover"),             @"bcn_image_outline_24",                              YES),
            d(RYGAID_Repost,              RYGLocalized(@"Repost"),                 @"bcn_repost-squircle_outline_24",                 YES),
            d(RYGAID_CopyCaption,         RYGLocalized(@"Copy caption"),           @"ig_icon_closed_captions_enabled_outline_24",                         NO),
            d(RYGAID_CopyURL,             RYGLocalized(@"Copy media URL"),         @"bcn_copy_outline_24",                               YES),
            d(RYGAID_DownloadShare,       RYGLocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(RYGAID_DownloadSave,        RYGLocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
            d(RYGAID_DownloadWithMusic,   RYGLocalized(@"Save with music"),        @"ig_icon_music_import_outline_24",                         YES),
         dOff(RYGAID_DownloadWithMusicGallery, RYGLocalized(@"Gallery with music"),@"ig_icon_photo_gallery_prism_outline_24", YES),
         dOff(RYGAID_DownloadGallery,     RYGLocalized(@"Download to Gallery"),    @"ig_icon_photo_gallery_prism_outline_24", YES),
            d(RYGAID_BulkCopyURLs,        RYGLocalized(@"Copy all URLs"),          @"bcn_copy_outline_24",                         NO),
            d(RYGAID_BulkDownloadShare,   RYGLocalized(@"Download and share all"), @"square.and.arrow.up.on.square",      NO),
            d(RYGAID_BulkDownloadSave,    RYGLocalized(@"Download all to Photos"), @"square.and.arrow.down.on.square",    NO),
         dOff(RYGAID_BulkDownloadGallery, RYGLocalized(@"Download all to Gallery"),@"ig_icon_photo_gallery_prism_outline_24", NO),
            d(RYGAID_Settings,            RYGLocalized(@"Feed settings"),          @"ig_icon_settings_outline_24",                          NO),
        ];

        // Reels — same as feed minus a few
        NSArray *reels = @[
            d(RYGAID_Expand,              RYGLocalized(@"Expand"),                 @"bcn_arrow-expand_outline_24", YES),
            d(RYGAID_ViewCover,           RYGLocalized(@"View cover"),             @"bcn_image_outline_24",                              YES),
            d(RYGAID_Repost,              RYGLocalized(@"Repost"),                 @"bcn_repost-squircle_outline_24",                 YES),
            d(RYGAID_CopyCaption,         RYGLocalized(@"Copy caption"),           @"ig_icon_closed_captions_enabled_outline_24",                         NO),
            d(RYGAID_CopyURL,             RYGLocalized(@"Copy media URL"),         @"bcn_copy_outline_24",                               YES),
            d(RYGAID_DownloadShare,       RYGLocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(RYGAID_DownloadSave,        RYGLocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
         dOff(RYGAID_DownloadGallery,     RYGLocalized(@"Download to Gallery"),    @"ig_icon_photo_gallery_prism_outline_24", YES),
            d(RYGAID_BulkCopyURLs,        RYGLocalized(@"Copy all URLs"),          @"bcn_copy_outline_24",                         NO),
            d(RYGAID_BulkDownloadShare,   RYGLocalized(@"Download and share all"), @"square.and.arrow.up.on.square",      NO),
            d(RYGAID_BulkDownloadSave,    RYGLocalized(@"Download all to Photos"), @"square.and.arrow.down.on.square",    NO),
         dOff(RYGAID_BulkDownloadGallery, RYGLocalized(@"Download all to Gallery"),@"ig_icon_photo_gallery_prism_outline_24", NO),
            d(RYGAID_Settings,            RYGLocalized(@"Reels settings"),         @"ig_icon_settings_outline_24",                          NO),
        ];

        // Stories
        NSArray *stories = @[
            d(RYGAID_Expand,              RYGLocalized(@"Expand"),                 @"bcn_arrow-expand_outline_24", YES),
            d(RYGAID_Repost,              RYGLocalized(@"Repost"),                 @"bcn_repost-squircle_outline_24",                 YES),
            d(RYGAID_ViewMentions,        RYGLocalized(@"View mentions"),          @"at",                                 YES),
            d(RYGAID_ToggleAudio,         RYGLocalized(@"Mute / unmute audio"),    @"speaker.wave.2",                     NO),
            d(RYGAID_ExcludeUser,         RYGLocalized(@"Exclude/include user"),   @"ig_icon_eye_off_pano_outline_24",                          NO),
            d(RYGAID_CopyURL,             RYGLocalized(@"Copy media URL"),         @"bcn_copy_outline_24",                               YES),
            d(RYGAID_DownloadShare,       RYGLocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(RYGAID_DownloadSave,        RYGLocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
            d(RYGAID_DownloadImageOnly,   RYGLocalized(@"Save image (no music)"),  @"bcn_image_outline_24",                              YES),
         dOff(RYGAID_DownloadImageOnlyGallery, RYGLocalized(@"Gallery image (no music)"), @"ig_icon_photo_gallery_prism_outline_24", YES),
         dOff(RYGAID_DownloadGallery,     RYGLocalized(@"Download to Gallery"),    @"ig_icon_photo_gallery_prism_outline_24", YES),
            d(RYGAID_BulkCopyURLs,        RYGLocalized(@"Copy all URLs"),          @"bcn_copy_outline_24",                         NO),
            d(RYGAID_BulkDownloadShare,   RYGLocalized(@"Download and share all"), @"square.and.arrow.up.on.square",      NO),
            d(RYGAID_BulkDownloadSave,    RYGLocalized(@"Download all to Photos"), @"square.and.arrow.down.on.square",    NO),
         dOff(RYGAID_BulkDownloadGallery, RYGLocalized(@"Download all to Gallery"),@"ig_icon_photo_gallery_prism_outline_24", NO),
            d(RYGAID_Settings,            RYGLocalized(@"Stories settings"),       @"ig_icon_settings_outline_24",                          NO),
        ];

        // DM disappearing media
        NSArray *dm = @[
            d(RYGAID_Expand,              RYGLocalized(@"Expand"),                 @"bcn_arrow-expand_outline_24", YES),
            d(RYGAID_DownloadShare,       RYGLocalized(@"Download and share"),     @"square.and.arrow.up",                YES),
            d(RYGAID_DownloadSave,        RYGLocalized(@"Download to Photos"),     @"square.and.arrow.down",              YES),
         dOff(RYGAID_DownloadGallery,     RYGLocalized(@"Download to Gallery"),    @"ig_icon_photo_gallery_prism_outline_24", YES),
            d(RYGAID_DMMarkSeen,          RYGLocalized(@"Mark as viewed"),         @"ig_icon_eye_filled_24",                                YES),
            d(RYGAID_Settings,            RYGLocalized(@"Messages settings"),      @"ig_icon_settings_outline_24",                          NO),
        ];

        // Profile
        NSArray *profile = @[
            d(RYGAID_CopyUsername,          RYGLocalized(@"Copy username"),          @"bcn_user_outline_24",                                 YES),
            d(RYGAID_CopyName,              RYGLocalized(@"Copy name"),              @"ig_icon_user_nickname_outline_24",                        YES),
            d(RYGAID_CopyBio,               RYGLocalized(@"Copy bio"),               @"text.quote",                         YES),
            d(RYGAID_CopyLink,              RYGLocalized(@"Copy profile link"),      @"bcn_copy_outline_24",                               YES),
            d(RYGAID_CopyID,                RYGLocalized(@"Copy ID"),                @"number",                             YES),
            d(RYGAID_CopyAll,               RYGLocalized(@"Copy all info"),          @"bcn_copy_outline_24",                   YES),
            d(RYGAID_ViewPicture,           RYGLocalized(@"View picture"),           @"bcn_image_outline_24",                              YES),
            d(RYGAID_SharePicture,          RYGLocalized(@"Share picture"),          @"square.and.arrow.up",                YES),
            d(RYGAID_SavePicturePhotos,     RYGLocalized(@"Save to Photos"),         @"square.and.arrow.down",              YES),
         dOff(RYGAID_SavePictureGallery,    RYGLocalized(@"Save picture to Gallery"),@"ig_icon_photo_gallery_prism_outline_24", YES),
            d(RYGAID_ProfileSettings,       RYGLocalized(@"Profile settings"),       @"bcn_user_outline_24",                          YES),
            d(RYGAID_ProfileInfoPrivacy,    RYGLocalized(@"Privacy"),                @"ig_icon_unlock_prism_outline_24",                               NO),
            d(RYGAID_ProfileInfoFollowers,  RYGLocalized(@"Followers"),              @"ig_icon_users_pano_outline_24",                           NO),
            d(RYGAID_ProfileInfoFollowing,  RYGLocalized(@"Following"),              @"ig_icon_user_follow_outline_24",      NO),
        ];

        // Instants — reuses the standard download/share AIDs with Instants-
        // specific titles ("Save to Photos" rather than "Download to Photos").
        NSArray *instants = @[
            d(RYGAID_Expand,              RYGLocalized(@"Expand"),               @"bcn_arrow-expand_outline_24", YES),
            d(RYGAID_DownloadSave,        RYGLocalized(@"Save to Photos"),       @"square.and.arrow.down",              YES),
         dOff(RYGAID_DownloadGallery,     RYGLocalized(@"Save to Gallery"),      @"ig_icon_photo_gallery_prism_outline_24", YES),
            d(RYGAID_DownloadShare,       RYGLocalized(@"Share"),                @"square.and.arrow.up",                YES),
            d(RYGAID_BulkDownloadSave,    RYGLocalized(@"Save all to Photos"),   @"square.and.arrow.down.on.square",    NO),
         dOff(RYGAID_BulkDownloadGallery, RYGLocalized(@"Save all to Gallery"),  @"ig_icon_photo_gallery_prism_outline_24", NO),
        ];

        // DM native Save button reroute — Expand / Photos / Gallery / Share.
        NSArray *dmNativeSave = @[
            d(RYGAID_Expand,              RYGLocalized(@"Expand"),               @"bcn_arrow-expand_outline_24", YES),
            d(RYGAID_DownloadSave,        RYGLocalized(@"Save to Photos"),       @"square.and.arrow.down",              YES),
         dOff(RYGAID_DownloadGallery,     RYGLocalized(@"Save to Gallery"),      @"ig_icon_photo_gallery_prism_outline_24", YES),
            d(RYGAID_DownloadShare,       RYGLocalized(@"Share"),                @"square.and.arrow.up",                YES),
        ];

        gRYGActionCatalogCache = @{
            @(RYGActionSourceFeed):     feed,
            @(RYGActionSourceReels):    reels,
            @(RYGActionSourceStories):  stories,
            @(RYGActionSourceDM):       dm,
            @(RYGActionSourceProfile):  profile,
            @(RYGActionSourceInstants): instants,
            @(RYGActionSourceDMNativeSave): dmNativeSave,
        };
    }
    return gRYGActionCatalogCache[@(source)] ?: @[];
}

+ (RYGActionDescriptor *)descriptorForActionID:(NSString *)actionID source:(RYGActionSource)source {
    if (!actionID.length) return nil;
    for (RYGActionDescriptor *d in [self descriptorsForSource:source]) {
        if ([d.identifier isEqualToString:actionID]) return d;
    }
    return nil;
}

+ (NSArray<RYGActionConfigSection *> *)defaultSectionsForSource:(RYGActionSource)source {
    RYGActionConfigSection *(^section)(NSString *, NSString *, NSString *, BOOL, NSArray *) =
        ^(NSString *identifier, NSString *title, NSString *icon, BOOL collapsible, NSArray *actions) {
            return [RYGActionConfigSection sectionWithID:identifier
                                                    title:title
                                                   iconSF:icon
                                              collapsible:collapsible
                                                  actions:actions];
        };

    switch (source) {
        case RYGActionSourceFeed:
            return @[
                section(@"navigation",
                        RYGLocalized(@"Navigation"), @"ig_icon_hand_point_outline_24", NO,
                        @[RYGAID_Expand, RYGAID_ViewCover, RYGAID_Repost, RYGAID_Settings]),
                section(@"copy",
                        RYGLocalized(@"Copy"), @"ig_icon_copy_prism_outline_24", NO,
                        @[RYGAID_CopyCaption, RYGAID_CopyURL]),
                section(@"download",
                        RYGLocalized(@"Download"), @"ig_icon_download_outline_24", NO,
                        @[RYGAID_DownloadShare, RYGAID_DownloadSave, RYGAID_DownloadWithMusic, RYGAID_DownloadGallery, RYGAID_DownloadWithMusicGallery]),
                section(@"bulk",
                        RYGLocalized(@"Bulk download"), @"ig_icon_feeds_outline_24", YES,
                        @[RYGAID_BulkCopyURLs, RYGAID_BulkDownloadShare, RYGAID_BulkDownloadSave, RYGAID_BulkDownloadGallery]),
            ];

        case RYGActionSourceReels:
            return @[
                section(@"navigation",
                        RYGLocalized(@"Navigation"), @"ig_icon_hand_point_outline_24", NO,
                        @[RYGAID_Expand, RYGAID_ViewCover, RYGAID_Repost, RYGAID_Settings]),
                section(@"copy",
                        RYGLocalized(@"Copy"), @"ig_icon_copy_prism_outline_24", NO,
                        @[RYGAID_CopyCaption, RYGAID_CopyURL]),
                section(@"download",
                        RYGLocalized(@"Download"), @"ig_icon_download_outline_24", NO,
                        @[RYGAID_DownloadShare, RYGAID_DownloadSave, RYGAID_DownloadGallery]),
                section(@"bulk",
                        RYGLocalized(@"Bulk download"), @"ig_icon_feeds_outline_24", YES,
                        @[RYGAID_BulkCopyURLs, RYGAID_BulkDownloadShare, RYGAID_BulkDownloadSave, RYGAID_BulkDownloadGallery]),
            ];

        case RYGActionSourceStories:
            return @[
                section(@"navigation",
                        RYGLocalized(@"Navigation"), @"ig_icon_hand_point_outline_24", NO,
                        @[RYGAID_Expand, RYGAID_Repost, RYGAID_ViewMentions, RYGAID_Settings]),
                section(@"audio",
                        RYGLocalized(@"Audio & visibility"), @"ig_icon_sliders_pano_outline_24", NO,
                        @[RYGAID_ToggleAudio, RYGAID_ExcludeUser]),
                section(@"copy",
                        RYGLocalized(@"Copy"), @"ig_icon_copy_prism_outline_24", NO,
                        @[RYGAID_CopyURL]),
                section(@"download",
                        RYGLocalized(@"Download"), @"ig_icon_download_outline_24", NO,
                        @[RYGAID_DownloadShare, RYGAID_DownloadSave, RYGAID_DownloadImageOnly, RYGAID_DownloadImageOnlyGallery, RYGAID_DownloadGallery]),
                section(@"bulk",
                        RYGLocalized(@"Bulk download"), @"ig_icon_feeds_outline_24", YES,
                        @[RYGAID_BulkCopyURLs, RYGAID_BulkDownloadShare, RYGAID_BulkDownloadSave, RYGAID_BulkDownloadGallery]),
            ];

        case RYGActionSourceDM:
            return @[
                section(@"navigation",
                        RYGLocalized(@"Navigation"), @"ig_icon_hand_point_outline_24", NO,
                        @[RYGAID_Expand, RYGAID_DMMarkSeen, RYGAID_Settings]),
                section(@"download",
                        RYGLocalized(@"Download"), @"ig_icon_download_outline_24", NO,
                        @[RYGAID_DownloadShare, RYGAID_DownloadSave, RYGAID_DownloadGallery]),
            ];

        case RYGActionSourceProfile:
            return @[
                section(@"copy_info",
                        RYGLocalized(@"Copy Info"), @"ig_icon_copy_prism_outline_24", YES,
                        @[RYGAID_CopyUsername, RYGAID_CopyName, RYGAID_CopyBio, RYGAID_CopyLink, RYGAID_CopyID, RYGAID_CopyAll]),
                section(@"navigation",
                        RYGLocalized(@"Profile"), @"bcn_circle-user_outline_24", NO,
                        @[RYGAID_ViewPicture, RYGAID_SharePicture, RYGAID_SavePicturePhotos, RYGAID_SavePictureGallery, RYGAID_ProfileSettings]),
                section(@"info",
                        RYGLocalized(@"Info"), @"info.circle", NO,
                        @[RYGAID_ProfileInfoPrivacy, RYGAID_ProfileInfoFollowers, RYGAID_ProfileInfoFollowing]),
            ];

        case RYGActionSourceInstants:
            return @[
                section(@"current",
                        RYGLocalized(@"Current instant"), @"ig_icon_app_instants_burst_filled_24", NO,
                        @[RYGAID_Expand, RYGAID_DownloadSave, RYGAID_DownloadGallery, RYGAID_DownloadShare]),
                section(@"all",
                        RYGLocalized(@"All loaded instants"), @"ig_icon_feeds_outline_24", YES,
                        @[RYGAID_BulkDownloadSave, RYGAID_BulkDownloadGallery]),
            ];

        case RYGActionSourceDMNativeSave:
            return @[
                section(@"actions",
                        RYGLocalized(@"Download"), @"ig_icon_download_outline_24", NO,
                        @[RYGAID_Expand, RYGAID_DownloadSave, RYGAID_DownloadGallery, RYGAID_DownloadShare]),
            ];

        case RYGActionSourceCount: break;
    }
    return @[];
}

@end
