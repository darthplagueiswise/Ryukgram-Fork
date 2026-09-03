#import <UIKit/UIKit.h>

@class RYGGalleryFile;

NS_ASSUME_NONNULL_BEGIN

@interface RYGGalleryGridCell : UICollectionViewCell

- (void)configureWithGalleryFile:(RYGGalleryFile *)file
				 selectionMode:(BOOL)selectionMode
					  selected:(BOOL)selected;

- (void)setSelectionMode:(BOOL)selectionMode selected:(BOOL)selected animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
