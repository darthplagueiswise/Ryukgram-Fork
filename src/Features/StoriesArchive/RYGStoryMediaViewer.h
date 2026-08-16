#import <UIKit/UIKit.h>

@class RYGArchivedStory, RYGStoriesArchiveStore;

NS_ASSUME_NONNULL_BEGIN

// Full-screen, swipeable archive media viewer with our own chrome: date, stat
// pills, and a viewers sheet on tap or long-press. Reusable.
@interface RYGStoryMediaViewer : UIViewController

+ (void)presentStories:(NSArray<RYGArchivedStory *> *)stories
                 store:(RYGStoriesArchiveStore *)store
            startIndex:(NSInteger)startIndex
                  from:(nullable UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
