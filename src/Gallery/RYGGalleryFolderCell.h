#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGGalleryFolderCellLayout) {
	RYGGalleryFolderCellLayoutList = 0,
	RYGGalleryFolderCellLayoutGrid = 1,
};

@interface RYGGalleryFolderCell : UICollectionViewCell

- (void)configureWithFolderName:(NSString *)name
					   subtitle:(nullable NSString *)subtitle
				 thumbnailPaths:(nullable NSArray<NSString *> *)thumbnailPaths
					 layoutMode:(RYGGalleryFolderCellLayout)layoutMode
				   isUserFolder:(BOOL)isUserFolder;

@end

NS_ASSUME_NONNULL_END
