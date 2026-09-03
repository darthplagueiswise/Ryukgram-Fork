#import <UIKit/UIKit.h>
#import "RYGFollowRequestModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGFollowRequestsViewController : UIViewController
- (instancetype)initWithScope:(RYGFollowRequestDirection)scope;
// Present the list (own popup chrome) opened to a scope — used by notification taps.
+ (void)presentAtScope:(RYGFollowRequestDirection)scope;
@end

NS_ASSUME_NONNULL_END
