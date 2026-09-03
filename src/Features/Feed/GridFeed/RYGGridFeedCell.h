#import <UIKit/UIKit.h>
#import "RYGGridFeedService.h"

@interface RYGGridFeedCell : UICollectionViewCell
- (void)configureWithPost:(RYGGridFeedPost *)post;
- (void)configureSkeleton;
// Update the stat/info overlay in place without touching the image (no flash).
- (void)refreshOverlayWithPost:(RYGGridFeedPost *)post;
@end
