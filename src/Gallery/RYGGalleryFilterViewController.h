#import <UIKit/UIKit.h>
#import "RYGGalleryFile.h"
#import "RYGGallerySheetViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class RYGGalleryFilterViewController;

@protocol RYGGalleryFilterViewControllerDelegate <NSObject>
- (void)filterController:(RYGGalleryFilterViewController *)controller
		   didApplyTypes:(NSSet<NSNumber *> *)types
				 sources:(NSSet<NSNumber *> *)sources
			   usernames:(NSSet<NSString *> *)usernames
		   favoritesOnly:(BOOL)favoritesOnly
				dateFrom:(nullable NSDate *)dateFrom
				  dateTo:(nullable NSDate *)dateTo;

- (void)filterControllerDidClear:(RYGGalleryFilterViewController *)controller;
@end

/// Sheet controller for filtering the gallery by type, source, username and favorites.
@interface RYGGalleryFilterViewController : RYGGallerySheetViewController

@property (nonatomic, weak) id<RYGGalleryFilterViewControllerDelegate> delegate;

@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterTypes;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *filterSources;
@property (nonatomic, strong) NSMutableSet<NSString *> *filterUsernames;
@property (nonatomic, assign) BOOL filterFavoritesOnly;
@property (nonatomic, strong, nullable) NSDate *filterDateFrom;
@property (nonatomic, strong, nullable) NSDate *filterDateTo;

/// Filter parts only (type/source/username/favorites/date), no folder-path constraint. Nil if no filters are active.
+ (nullable NSPredicate *)filterPredicateForTypes:(NSSet<NSNumber *> *)types
										  sources:(NSSet<NSNumber *> *)sources
										usernames:(NSSet<NSString *> *)usernames
									favoritesOnly:(BOOL)favoritesOnly
										 dateFrom:(nullable NSDate *)dateFrom
										   dateTo:(nullable NSDate *)dateTo;

/// Composes an NSPredicate from the given filters, or nil if no filters are active.
+ (nullable NSPredicate *)predicateForTypes:(NSSet<NSNumber *> *)types
									sources:(NSSet<NSNumber *> *)sources
								  usernames:(NSSet<NSString *> *)usernames
							  favoritesOnly:(BOOL)favoritesOnly
								   dateFrom:(nullable NSDate *)dateFrom
									 dateTo:(nullable NSDate *)dateTo
								 folderPath:(nullable NSString *)folderPath;

@end

NS_ASSUME_NONNULL_END
