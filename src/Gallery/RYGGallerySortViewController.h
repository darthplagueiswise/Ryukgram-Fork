#import <UIKit/UIKit.h>
#import "RYGGallerySheetViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGGallerySortOrder) {
	RYGGallerySortOrderDate = 0,
	RYGGallerySortOrderName,
	RYGGallerySortOrderSize,
};

typedef NS_ENUM(NSInteger, RYGGallerySortTypeFirst) {
	RYGGallerySortTypeFirstNone = 0,
	RYGGallerySortTypeFirstImages,
	RYGGallerySortTypeFirstVideos,
};

@class RYGGallerySortViewController;

@protocol RYGGallerySortViewControllerDelegate <NSObject>
- (void)sortControllerDidChange:(RYGGallerySortViewController *)controller;
@end

@interface RYGGallerySortViewController : RYGGallerySheetViewController

@property (nonatomic, weak) id<RYGGallerySortViewControllerDelegate> delegate;

@property (nonatomic, class, readonly) RYGGallerySortOrder currentOrder;
@property (nonatomic, class, readonly) BOOL currentAscending;
@property (nonatomic, class, readonly) RYGGallerySortTypeFirst currentTypeFirst;
@property (nonatomic, class, readonly) BOOL favoritesFirst;

/// File descriptors from the persisted axes (favorites → type → order); no section key.
+ (NSArray<NSSortDescriptor *> *)fileSortDescriptors;

@end

NS_ASSUME_NONNULL_END
