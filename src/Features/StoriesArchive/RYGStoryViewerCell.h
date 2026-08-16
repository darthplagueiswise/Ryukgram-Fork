#import <UIKit/UIKit.h>

@class RYGArchivedStoryViewer;

NS_ASSUME_NONNULL_BEGIN

@interface RYGStoryViewerCell : UITableViewCell
- (void)configureWithViewer:(RYGArchivedStoryViewer *)viewer pinned:(BOOL)pinned;
@end

NS_ASSUME_NONNULL_END
