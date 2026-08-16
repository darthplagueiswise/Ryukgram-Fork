#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class RYGGalleryFile;

@interface RYGGalleryViewController : UIViewController

+ (void)presentGallery;

/// Initializes the gallery for browsing the given folder path. Pass nil for root.
- (instancetype)initWithFolderPath:(nullable NSString *)folderPath;

/// Opens the gallery scoped to a single uploader's downloads.
- (instancetype)initWithUsernameScope:(NSString *)username;

/// Picker presentation — single-tap-to-select, pre-filtered to the given
/// media types (NSNumber-wrapped RYGGalleryMediaType). Completion fires with
/// the picked file URL, or nil on cancel.
+ (void)presentPickerWithMediaTypes:(nullable NSArray<NSNumber *> *)allowedMediaTypes
                              title:(nullable NSString *)title
                             fromVC:(UIViewController *)fromVC
                         completion:(void (^)(NSURL * _Nullable pickedURL,
                                              RYGGalleryFile * _Nullable pickedFile))completion;

@end

NS_ASSUME_NONNULL_END
