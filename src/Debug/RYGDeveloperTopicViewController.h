#import <UIKit/UIKit.h>
#import "RYGDeveloperRuntimeScanner.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGDeveloperTopicViewController : UITableViewController
- (instancetype)initWithSurface:(RYGDeveloperRuntimeSurface)surface;
+ (void)activatePersistedNativeFeatures;
@end

NS_ASSUME_NONNULL_END
