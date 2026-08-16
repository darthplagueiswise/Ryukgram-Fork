// UINavigationController wrapper used by RYGLockGate. Tracks the bound group
// id for relock-on-dismiss and visibility marking.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGLockedSurfaceNavigationController : UINavigationController
@property (nonatomic, copy, nullable) NSString *lockGroupID;
@end

NS_ASSUME_NONNULL_END
