// RYGMediaActions — shared media extraction + action handlers for the action menu.

#import <UIKit/UIKit.h>
#import "../InstagramHeaders.h"
#import "../Downloader/Download.h"
#import "RYGActionMenu.h"

@class RYGDashRepresentation;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGActionContext) {
    RYGActionContextFeed,
    RYGActionContextReels,
    RYGActionContextStories,
};

@interface RYGMediaActions : NSObject

// MARK: - Filename naming

+ (NSString *)contextLabelForContext:(RYGActionContext)ctx;

// Names the media the user last acted on — muxed output and bulk legs.
+ (NSString *)currentFilenameStem;

// MARK: - Media extraction

// Falls back to _fieldCache["caption"]["text"] when selectors fail.
+ (nullable NSString *)captionForMedia:(id)media;

+ (BOOL)isCarouselMedia:(id)media;

// Empty array for non-carousels.
+ (NSArray *)carouselChildrenForMedia:(id)media;

// Lets a media provider return a child page while keeping the carousel reachable for bulk actions.
+ (void)stashCarouselParentMedia:(nullable id)parent onView:(UIView *)view;

+ (BOOL)mediaHasAudio:(id)media;

+ (BOOL)mediaHasMusic:(id)media parentMedia:(nullable id)parentMedia;

// Image story with IG-set music, so the raw image saves without the soundtrack.
+ (BOOL)mediaIsStillImageWithAudio:(id)media parentMedia:(nullable id)parentMedia;

+ (void)downloadPhotoWithMusicForMedia:(id)media
                           parentMedia:(nullable id)parentMedia
                                action:(DownloadAction)action;

+ (void)downloadPhotoOnlyForMedia:(id)media action:(DownloadAction)action;

// Photos can't hold audio, so both actions end at the share sheet.
+ (void)downloadAudioOnlyForMedia:(id)media action:(DownloadAction)action;

+ (void)downloadAudioRepresentation:(RYGDashRepresentation *)audio action:(DownloadAction)action;

// Prefers video URL, falls back to photo; nil if nothing extractable.
+ (nullable NSURL *)bestURLForMedia:(id)media;

// Returns NO when unavailable so the caller can fall back to the progressive URL.
+ (BOOL)downloadVisualDMVideo:(id)igVideo
                       action:(DownloadAction)action
                     metadata:(nullable id)metadata;

+ (nullable NSURL *)coverURLForMedia:(id)media;

// Search/explore media arrive without video_versions, so DASH and duration decide too.
+ (BOOL)mediaIsVideo:(nullable id)media;

// Progressive URL for media that shipped without one, fetched from /media/{id}/info/ and cached.
+ (void)progressiveVideoURLForMedia:(nullable id)media completion:(void(^)(NSURL * _Nullable url))completion;
+ (nullable NSURL *)cachedProgressiveVideoURLForMedia:(nullable id)media;

// MARK: - Primary actions (each directly triggerable from a menu entry)

+ (void)expandMedia:(id)media
        fromView:(UIView *)sourceView
         caption:(nullable NSString *)caption;

+ (void)downloadAndShareMedia:(id)media;

+ (void)downloadAndSaveMedia:(id)media;

+ (void)downloadAndSaveMediaToGallery:(id)media fromView:(nullable UIView *)sourceView;

+ (void)copyURLForMedia:(id)media;

+ (void)copyCaptionForMedia:(id)media;

+ (void)triggerRepostForContext:(RYGActionContext)ctx sourceView:(UIView *)sourceView;

+ (void)openSettingsForContext:(RYGActionContext)ctx fromView:(UIView *)sourceView;

// MARK: - Carousel bulk actions

+ (void)downloadAllAndShareMedia:(id)carouselMedia;

+ (void)downloadAllAndSaveMedia:(id)carouselMedia;

+ (void)downloadAllAndSaveMediaToGallery:(id)carouselMedia context:(RYGActionContext)ctx;

// Per-file metadata is optional; falls back to defaultMetadata when shorter.
+ (void)bulkSaveFilesToGallery:(NSArray<NSURL *> *)files
                  perFileMetadata:(nullable NSArray<id> *)perFileMetadata
                  defaultMetadata:(nullable id)defaultMetadata;

+ (void)copyAllURLsForMedia:(id)carouselMedia;

// MARK: - Menu builders

// MARK: - Bulk URL download helpers

+ (void)bulkDownloadURLs:(NSArray<NSURL *> *)urls
                   title:(NSString *)title
                username:(nullable NSString *)username
                    done:(void(^)(NSArray<NSURL *> *fileURLs))done;

+ (void)bulkSaveFiles:(NSArray<NSURL *> *)files;

+ (NSArray<RYGAction *> *)actionsForContext:(RYGActionContext)ctx
                                      media:(nullable id)media
                                   fromView:(UIView *)sourceView;

// `includeDisabled:YES` keeps menu-disabled actions in the result. Default-tap
// fire uses this so a bound action keeps working even when hidden from the menu.
+ (NSArray<RYGAction *> *)actionsForContext:(RYGActionContext)ctx
                                      media:(nullable id)media
                                   fromView:(UIView *)sourceView
                            includeDisabled:(BOOL)includeDisabled;

+ (BOOL)executeActionForContext:(RYGActionContext)ctx
                       actionID:(NSString *)aid
                          media:(nullable id)media
                       fromView:(UIView *)sourceView;

@end

NS_ASSUME_NONNULL_END
