#import <UIKit/UIKit.h>
#import "SCIDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIDeletedMessagesUserDetailViewController : UIViewController

- (instancetype)initWithGroup:(SCIDeletedMessageGroup *)group ownerPK:(nullable NSString *)ownerPK;

@end

NS_ASSUME_NONNULL_END
