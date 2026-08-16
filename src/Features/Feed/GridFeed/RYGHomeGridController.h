#import <UIKit/UIKit.h>

// Hosts the grid overlay inside IG's home feed VC: seeds from the feed's own
// loaded posts (instant), paginates via the API, keeps the stories tray above.
@interface RYGHomeGridController : NSObject
- (instancetype)initWithHost:(UIViewController *)host;
- (void)syncActive;
- (void)hostDidLayout;
- (void)recoverStoryTray;
// Home-tab tap on the active grid: scrolls to top. Returns NO if no grid is live.
+ (BOOL)handleHomeButtonTap;
@end
