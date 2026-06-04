#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIGalleryFolderCellLayout) {
	SCIGalleryFolderCellLayoutList = 0,
	SCIGalleryFolderCellLayoutGrid = 1,
};

@interface SCIGalleryFolderCell : UICollectionViewCell

- (void)configureWithFolderName:(NSString *)name
					   subtitle:(nullable NSString *)subtitle
				 thumbnailPaths:(nullable NSArray<NSString *> *)thumbnailPaths
					 layoutMode:(SCIGalleryFolderCellLayout)layoutMode
				   isUserFolder:(BOOL)isUserFolder;

@end

NS_ASSUME_NONNULL_END
