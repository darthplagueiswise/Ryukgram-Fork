#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGStoryMediaCell : UICollectionViewCell

- (void)configureWithMediaPath:(nullable NSString *)mediaPath isVideo:(BOOL)isVideo;
- (void)setActive:(BOOL)active;
- (BOOL)isZoomed;

@end

NS_ASSUME_NONNULL_END
