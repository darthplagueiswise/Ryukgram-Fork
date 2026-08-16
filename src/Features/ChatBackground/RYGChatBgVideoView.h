#import <UIKit/UIKit.h>

@interface RYGChatBgVideoView : UIView

@property (nonatomic, copy) NSURL *videoURL;

// Fires on the main thread with the layer's readyForDisplay; callers latch on YES to drop the poster.
@property (nonatomic, copy) void (^onReadyForDisplayChanged)(BOOL ready);
@property (nonatomic, readonly) BOOL isReadyForDisplay;

// Applies a blur + black-dim overlay live, non-destructively.
- (void)setBlurRadius:(CGFloat)blur dim:(CGFloat)dim;

- (void)play;
- (void)pause;

@end
