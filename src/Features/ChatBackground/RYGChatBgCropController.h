#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Full-screen crop sheet. Source image pans + zooms inside a rect locked to the
// device aspect ratio. Confirm renders the visible crop window; cancel returns nil.
@interface RYGChatBgCropController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong, nullable) UIImage *sourceImage;
@property (nonatomic, copy, nullable) void (^onConfirm)(UIImage *_Nullable cropped);
@end

NS_ASSUME_NONNULL_END
