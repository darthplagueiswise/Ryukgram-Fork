#import <UIKit/UIKit.h>

@class RYGGalleryFile;

NS_ASSUME_NONNULL_BEGIN

@interface RYGGalleryListCell : UITableViewCell

@property (nonatomic, strong, readonly) RYGGalleryFile *file;

- (void)configureWithGalleryFile:(RYGGalleryFile *)file;

@end

NS_ASSUME_NONNULL_END
