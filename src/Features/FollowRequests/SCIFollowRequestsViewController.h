#import <UIKit/UIKit.h>
#import "SCIFollowRequestModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIFollowRequestsViewController : UIViewController
- (instancetype)initWithScope:(SCIFollowRequestDirection)scope;
// Present the list (own popup chrome) opened to a scope — used by notification taps.
+ (void)presentAtScope:(SCIFollowRequestDirection)scope;
@end

NS_ASSUME_NONNULL_END
