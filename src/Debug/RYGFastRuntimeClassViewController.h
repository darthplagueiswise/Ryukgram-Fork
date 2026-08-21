#import <UIKit/UIKit.h>
@class RYGRuntimeImageIndex, RYGRuntimeClassRow;

@interface RYGFastRuntimeClassViewController : UITableViewController
- (instancetype)initWithIndex:(RYGRuntimeImageIndex *)index
                     classRow:(RYGRuntimeClassRow *)row
                 initialQuery:(NSString *)query;
@end
