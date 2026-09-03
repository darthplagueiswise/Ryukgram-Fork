#import <UIKit/UIKit.h>
#import "RYGActivityConfig.h"

NS_ASSUME_NONNULL_BEGIN

// One mode per activity event. pk == nil edits the global defaults; a pk edits
// that person's override.
@interface RYGActivityPersonViewController : UITableViewController
- (instancetype)initWithPK:(nullable NSString *)pk username:(nullable NSString *)username;
@end

NS_ASSUME_NONNULL_END
