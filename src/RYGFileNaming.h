// Every user-visible file name the tweak produces comes from here — downloads,
// ffmpeg output, gallery storage, Photos exports and share sheets.

#import <Foundation/Foundation.h>
#import "Gallery/RYGGalleryTypes.h"

@class RYGGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface RYGFileName : NSObject

+ (NSString *)contextSlugForSource:(RYGGallerySource)source;

/// `[ryuk_]@username_context_yyyy-MM-dd_HH-mm-ss[_index]`, no extension.
+ (NSString *)stemForUsername:(nullable NSString *)username
					  context:(nullable NSString *)context
						 date:(nullable NSDate *)date
						index:(NSInteger)index;

+ (NSString *)stemForMetadata:(nullable RYGGallerySaveMetadata *)metadata;

/// A URL already carrying one of our stems keeps it, otherwise metadata wins.
+ (NSString *)stemForURL:(nullable NSURL *)url
				metadata:(nullable RYGGallerySaveMetadata *)metadata;

/// Extension normalized (jpeg→jpg, unknown→per media type).
+ (NSString *)nameForURL:(nullable NSURL *)url
			   mediaType:(RYGGalleryMediaType)mediaType
				metadata:(nullable RYGGallerySaveMetadata *)metadata;

/// Real extension preserved, so Photos never re-encodes the file.
+ (NSString *)exportNameForURL:(NSURL *)url
					  metadata:(nullable RYGGallerySaveMetadata *)metadata;

+ (NSString *)uniqueName:(NSString *)name inDirectory:(NSString *)directory;

@end

NS_ASSUME_NONNULL_END
