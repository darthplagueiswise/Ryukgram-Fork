#import <Foundation/Foundation.h>

@class RYGGalleryFile;
@class RYGGallerySaveMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface RYGGalleryOriginController : NSObject

+ (void)populateMetadata:(RYGGallerySaveMetadata *)metadata fromMedia:(id _Nullable)media;
+ (void)populateProfileMetadata:(RYGGallerySaveMetadata *)metadata username:(nullable NSString *)username user:(id _Nullable)user;
+ (BOOL)openOriginalPostForGalleryFile:(RYGGalleryFile *)file;

@end

NS_ASSUME_NONNULL_END
