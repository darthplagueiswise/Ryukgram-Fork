#import <UIKit/UIKit.h>

@interface SCIDeletedMessagesViewController : UIViewController

// Presents the log full-screen via SCIPopupChrome.
+ (void)presentFromViewController:(UIViewController *)presenter;

@end
