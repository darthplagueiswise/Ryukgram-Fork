#import <UIKit/UIKit.h>
#import "RYGCallRecordingModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGCallRecordingDetailViewController : UIViewController
- (instancetype)initWithGroup:(RYGCallRecordingGroup *)group ownerPK:(NSString *)ownerPK;
@end

NS_ASSUME_NONNULL_END
