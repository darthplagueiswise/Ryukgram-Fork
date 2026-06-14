#import <UIKit/UIKit.h>
#import "SCIGalleryFile.h"
#import "SCIGallerySheetViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class SCIGalleryFilterViewController;

@protocol SCIGalleryFilterViewControllerDelegate <NSObject>
- (void)filterController:(SCIGalleryFilterViewController *)controller
		   didApplyTypes:(NSSet<NSNumber *> *)types
				 sources:(NSSet<NSNumber *> *)sources
			   usernames:(NSSet<NSString *> *)usernames
		   favoritesOnly:(BOOL)favoritesOnly;

- (void)filterControllerDidClear:(SCIGalleryFilterViewController *)controller;
@end

/// Sheet controller for filtering the gallery by type, source, username and favorites.
@interface SCIGalleryFilterViewController : SCIGallerySheetViewController

@property (nonatomic, weak) id<SCIGalleryFilterViewControllerDelegate> delegate;

@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterTypes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterSources;
@property (nonatomic, strong) NSMutableSet<NSString *> *filterUsernames;
@property (nonatomic, assign) BOOL filterFavoritesOnly;

/// Filter parts only (type/source/username/favorites), no folder-path constraint. Nil if no filters are active.
+ (nullable NSPredicate *)filterPredicateForTypes:(NSSet<NSNumber *> *)types
										  sources:(NSSet<NSNumber *> *)sources
										usernames:(NSSet<NSString *> *)usernames
									favoritesOnly:(BOOL)favoritesOnly;

/// Composes an NSPredicate from the given filters, or nil if no filters are active.
+ (nullable NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
									sources:(NSSet<NSNumber *> *)sources
								  usernames:(NSSet<NSString *> *)usernames
							  favoritesOnly:(BOOL)favoritesOnly
								 folderPath:(nullable NSString *)folderPath;

@end

NS_ASSUME_NONNULL_END
