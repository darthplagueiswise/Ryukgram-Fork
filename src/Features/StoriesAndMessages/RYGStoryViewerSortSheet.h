#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Shared filter & sort sheet over the RYGStoryViewerFilter model. Used by both
// the live story-viewer list and the archive's viewers sheet.
@interface RYGStoryViewerSortSheet : UITableViewController

@property (nonatomic, copy, nullable) void (^onChange)(void);
@property (nonatomic, assign) BOOL hidePinned;   // the archive has no pinned viewers

+ (void)presentFrom:(UIViewController *)host hidePinned:(BOOL)hidePinned onChange:(nullable void (^)(void))onChange;
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
