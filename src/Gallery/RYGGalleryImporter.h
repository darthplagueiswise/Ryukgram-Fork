#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGGalleryImporter : NSObject

// Presents a Photos / Files chooser, imports the picked media into the gallery
// under `folderPath`, and reports how many entries were added.
+ (void)presentImportFrom:(UIViewController *)host
			   folderPath:(nullable NSString *)folderPath
			   completion:(nullable void (^)(NSUInteger added))completion;

@end

NS_ASSUME_NONNULL_END
