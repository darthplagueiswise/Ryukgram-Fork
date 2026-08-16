// Photos / Gallery download submenu. Presents a Photos+Gallery action sheet
// when the gallery is enabled, falls through to Photos directly when not.
// Audio routes skip Photos (the library rejects audio).

#import <UIKit/UIKit.h>
#import "../Gallery/RYGGallerySaveMetadata.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGDownloadMenuMode) {
    RYGDownloadMenuModeRemoteURL = 0,
    RYGDownloadMenuModeLocalFile = 1
};

@interface RYGDownloadMenu : NSObject

+ (void)presentForURL:(NSURL *)url
                 mode:(RYGDownloadMenuMode)mode
        fileExtension:(nullable NSString *)fileExtension
             hudLabel:(nullable NSString *)hudLabel
             metadata:(nullable RYGGallerySaveMetadata *)metadata
              isAudio:(BOOL)isAudio
               fromVC:(nullable UIViewController *)fromVC;

// forceTarget: 0 = Photos (default), 1 = Gallery, 2 = Share.
+ (void)downloadURL:(NSURL *)url
      fileExtension:(nullable NSString *)fileExtension
           hudLabel:(nullable NSString *)hudLabel
           metadata:(nullable RYGGallerySaveMetadata *)metadata
        forceTarget:(NSInteger)forceTarget;

+ (NSArray<UIAlertAction *> *)alertActionsForURL:(NSURL *)url
                                            mode:(RYGDownloadMenuMode)mode
                                   fileExtension:(nullable NSString *)fileExtension
                                        hudLabel:(nullable NSString *)hudLabel
                                        metadata:(nullable RYGGallerySaveMetadata *)metadata
                                         isAudio:(BOOL)isAudio
                                     titlePrefix:(nullable NSString *)titlePrefix;

@end

NS_ASSUME_NONNULL_END
