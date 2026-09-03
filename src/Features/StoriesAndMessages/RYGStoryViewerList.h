// Our own story-viewer list, replacing IG's native list: paginated fetch from
// list_reel_media_viewer with our own search / filter / sort / pins.
#import <UIKit/UIKit.h>

@interface RYGStoryViewerListView : UIView
- (instancetype)initWithMediaID:(NSString *)mediaID;
- (void)reload;
@end
