#import "../../UI/RYGIDListViewController.h"

NS_ASSUME_NONNULL_BEGIN

// Per-person notification list: who gets a custom activity notification setup.
// Built on the shared list UI (search + rich "+" picker); a row drills into the
// per-event checklist.
@interface RYGActivityMatrixViewController : RYGIDListViewController
- (instancetype)init;
@end

NS_ASSUME_NONNULL_END
