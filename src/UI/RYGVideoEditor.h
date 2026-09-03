#import <UIKit/UIKit.h>

// Full-screen video editor: pan-zoom framing (aspect configurable) + trim to maxDuration.
// onDone gets an upright, trimmed mp4; cancel calls nothing.
@interface RYGVideoEditor : NSObject
+ (void)presentForVideoURL:(NSURL *)url
                      from:(UIViewController *)presenter
               maxDuration:(NSTimeInterval)maxDuration
                    onDone:(void (^)(NSURL *editedURL))onDone;

+ (void)presentForVideoURL:(NSURL *)url
                      from:(UIViewController *)presenter
               maxDuration:(NSTimeInterval)maxDuration
                   aspectW:(CGFloat)aspectW
                   aspectH:(CGFloat)aspectH
                    onDone:(void (^)(NSURL *editedURL))onDone;
@end
