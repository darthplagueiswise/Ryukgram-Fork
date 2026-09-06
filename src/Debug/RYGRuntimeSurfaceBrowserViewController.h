#import <UIKit/UIKit.h>
@class RYGRuntimeSurfaceSpec;

NS_ASSUME_NONNULL_BEGIN
@interface RYGRuntimeSurfaceBrowserViewController : UITableViewController
- (instancetype)initWithSpec:(RYGRuntimeSurfaceSpec *)spec initialQuery:(NSString *)initialQuery;
@end
NS_ASSUME_NONNULL_END
