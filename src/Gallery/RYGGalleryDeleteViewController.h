#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGGalleryDeletePageMode) {
	RYGGalleryDeletePageModeRoot = 0,
	RYGGalleryDeletePageModeUsers
};

@interface RYGGalleryDeleteViewController : UITableViewController

@property (nonatomic, copy, nullable) void (^onDidDelete)(void);

- (instancetype)initWithMode:(RYGGalleryDeletePageMode)mode;

@end

NS_ASSUME_NONNULL_END
