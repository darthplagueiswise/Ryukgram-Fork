#import <CoreData/CoreData.h>
#import <UIKit/UIKit.h>

#import "RYGGallerySaveMetadata.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int16_t, RYGGalleryMediaType) {
	RYGGalleryMediaTypeImage = 0,
	RYGGalleryMediaTypeVideo = 1,
	RYGGalleryMediaTypeAudio = 2,
	RYGGalleryMediaTypeGIF   = 3
};

FOUNDATION_EXPORT NSString *RYGFileNameForMedia(NSURL *originalURL, RYGGalleryMediaType mediaType, RYGGallerySaveMetadata * _Nullable metadata);

// Unknown extension falls back to Image.
FOUNDATION_EXPORT RYGGalleryMediaType RYGGalleryMediaTypeForExtension(NSString * _Nullable ext);

/// YES for audio extensions (m4a, aac, mp3, ogg, opus, wav, aiff, flac).
FOUNDATION_EXPORT BOOL RYGGalleryExtensionIsAudio(NSString * _Nullable ext);


typedef NS_ENUM(int16_t, RYGGallerySource) {
	RYGGallerySourceOther   = 0,
	RYGGallerySourceFeed	= 1,
	RYGGallerySourceStories = 2,
	RYGGallerySourceReels   = 3,
	RYGGallerySourceProfile = 4,
	RYGGallerySourceDMs	 = 5,
	RYGGallerySourceThumbnail = 6,
	RYGGallerySourceNotes   = 7,
	RYGGallerySourceComments = 8,
	RYGGallerySourceInstants = 9,
	RYGGallerySourceCalls = 10,
	RYGGallerySourceImported = 11
};

@interface RYGGalleryFile : NSManagedObject

@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *relativePath;
@property (nonatomic) int16_t mediaType;
@property (nonatomic) int16_t source;
@property (nonatomic, strong) NSDate *dateAdded;
@property (nonatomic) int64_t fileSize;
@property (nonatomic) BOOL isFavorite;
@property (nonatomic, copy, nullable) NSString *folderPath;
@property (nonatomic, copy, nullable) NSString *customName;
@property (nonatomic, copy, nullable) NSString *sourceUsername;
@property (nonatomic, copy, nullable) NSString *sourceUserPK;
@property (nonatomic, copy, nullable) NSString *sourceProfileURLString;
@property (nonatomic, copy, nullable) NSString *sourceMediaPK;
@property (nonatomic, copy, nullable) NSString *sourceMediaCode;
@property (nonatomic, copy, nullable) NSString *sourceMediaURLString;
@property (nonatomic) int32_t pixelWidth;
@property (nonatomic) int32_t pixelHeight;
@property (nonatomic) double durationSeconds;

+ (nullable RYGGalleryFile *)saveFileToGallery:(NSURL *)fileURL
										source:(RYGGallerySource)source
									 mediaType:(RYGGalleryMediaType)mediaType
										 error:(NSError **)error;

+ (nullable RYGGalleryFile *)saveFileToGallery:(NSURL *)fileURL
										source:(RYGGallerySource)source
									 mediaType:(RYGGalleryMediaType)mediaType
									folderPath:(nullable NSString *)folderPath
										 error:(NSError **)error;

/// When `metadata` is non-nil, its fields override `source` and populate list UI. File is probed for any missing dimensions/duration.
+ (nullable RYGGalleryFile *)saveFileToGallery:(NSURL *)fileURL
										source:(RYGGallerySource)source
									 mediaType:(RYGGalleryMediaType)mediaType
									folderPath:(nullable NSString *)folderPath
									  metadata:(nullable RYGGallerySaveMetadata *)metadata
										 error:(NSError **)error;

- (BOOL)removeWithError:(NSError *_Nullable *_Nullable)error;

/// Posted after a gallery file is removed (userInfo: source, sourceMediaPK, sourceMediaCode) so owners can cascade.
FOUNDATION_EXPORT NSNotificationName const RYGGalleryFileDidRemoveNotification;

/// References a file in place (absolute path, no copy) — the gallery entry points at the original file.
/// Used to share call recordings without duplicating them. Deduped by metadata.sourceMediaPK.
+ (nullable RYGGalleryFile *)referenceFileAtPath:(NSString *)absolutePath
										 source:(RYGGallerySource)source
									  mediaType:(RYGGalleryMediaType)mediaType
									   metadata:(nullable RYGGallerySaveMetadata *)metadata
										  error:(NSError **)error;

- (NSString *)filePath;
- (NSURL *)fileURL;
- (BOOL)fileExists;
- (NSString *)thumbnailPath;
- (BOOL)thumbnailExists;

/// User-facing display name — customName if set, else the portion of relativePath after the timestamp prefix.
- (NSString *)displayName;

/// `displayName` with the file's real extension — the name for Photos / share.
- (NSString *)exportFilename;

- (NSString *)sourceLabel;

- (NSString *)shortSourceLabel;

/// Primary line in list mode: username when known, else `displayName`.
- (NSString *)listPrimaryTitle;

/// Second line: duration · size · resolution · bitrate (video), or size · resolution (image).
- (NSString *)listTechnicalLine;

- (NSString *)listDownloadDateString;
- (nullable NSURL *)preferredProfileURL;
- (nullable NSURL *)preferredOriginalMediaURL;
- (BOOL)hasOpenableProfile;
- (BOOL)hasOpenableOriginalMedia;

+ (NSString *)shortLabelForSource:(RYGGallerySource)source;

+ (void)generateThumbnailForFile:(RYGGalleryFile *)file
					  completion:(void(^_Nullable)(BOOL success))completion;

+ (nullable UIImage *)loadThumbnailForFile:(RYGGalleryFile *)file;

+ (NSString *)labelForSource:(RYGGallerySource)source;

+ (NSString *)symbolNameForSource:(RYGGallerySource)source;

@end

NS_ASSUME_NONNULL_END
