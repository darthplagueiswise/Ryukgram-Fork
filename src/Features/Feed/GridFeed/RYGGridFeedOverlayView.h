#import <UIKit/UIKit.h>
#import "RYGGridFeedService.h"

// Renders the configurable info chips (ordered, per RYGGridFeedInfo) plus the
// corner media-type badge over a grid tile. Shared by the real cell and the
// settings live preview so they always match.
@interface RYGGridFeedOverlayView : UIView
@property (nonatomic, strong) UIImage *avatarImage;
- (void)configureWithPost:(RYGGridFeedPost *)post;
@end
