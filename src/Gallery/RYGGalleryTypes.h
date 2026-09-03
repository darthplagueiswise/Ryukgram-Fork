#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int16_t, RYGGalleryMediaType) {
	RYGGalleryMediaTypeImage = 0,
	RYGGalleryMediaTypeVideo = 1,
	RYGGalleryMediaTypeAudio = 2,
	RYGGalleryMediaTypeGIF   = 3
};

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

// Unknown extension falls back to Image.
FOUNDATION_EXPORT RYGGalleryMediaType RYGGalleryMediaTypeForExtension(NSString * _Nullable ext);

FOUNDATION_EXPORT BOOL RYGGalleryExtensionIsAudio(NSString * _Nullable ext);

NS_ASSUME_NONNULL_END
