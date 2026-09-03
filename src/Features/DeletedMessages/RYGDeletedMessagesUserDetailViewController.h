#import <UIKit/UIKit.h>
#import "RYGDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGDeletedMessagesUserDetailViewController : UIViewController

- (instancetype)initWithGroup:(RYGDeletedMessageGroup *)group ownerPK:(nullable NSString *)ownerPK;

@end

NS_ASSUME_NONNULL_END
