#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGStoriesArchiveCell : UICollectionViewCell

// token guards against a recycled cell showing a stale async thumbnail.
- (void)configureWithThumbnailPath:(nullable NSString *)thumbPath
                           isVideo:(BOOL)isVideo
                       viewerCount:(NSInteger)viewerCount
                         likeCount:(NSInteger)likeCount;

- (void)configureDate:(nullable NSDate *)date;
- (void)setChecked:(BOOL)checked;   // multi-select

@end

NS_ASSUME_NONNULL_END
