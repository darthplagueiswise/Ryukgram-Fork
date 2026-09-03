#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGDownloadManagerViewController : UIViewController
/// Present the manager via RYGPopupChrome from the top-most controller.
+ (void)present;
/// Confirm-then-wipe the persisted download history, from anywhere.
+ (void)presentClearHistoryConfirmation;
+ (void)presentClearDuplicatesConfirmation;
@end

NS_ASSUME_NONNULL_END
