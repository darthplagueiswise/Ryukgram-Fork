#import <UIKit/UIKit.h>

@class RYGArchivedStory;

NS_ASSUME_NONNULL_BEGIN

// Bottom sheet listing a story's viewers with avatars, badges, search, sort and
// a liked/all filter. Tap a row to open that profile. Reusable.
@interface RYGStoryViewersSheet : UIViewController

+ (void)presentForStory:(RYGArchivedStory *)story from:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
