#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Per-image opacity / blur / dim sliders with a live preview. Stored against
// the asset path — overrides apply wherever the image is used.
@interface SCIChatBgPerImageSheet : UIViewController
- (instancetype)initWithAsset:(NSString *)asset;
@end

NS_ASSUME_NONNULL_END
