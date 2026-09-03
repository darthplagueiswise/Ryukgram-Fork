#import <UIKit/UIKit.h>

// Reusable full-screen image editor: free/preset or fixed-aspect crop with pan-zoom +
// background removal. onDone gets the edited image; cancel calls nothing.
@interface RYGImageEditor : NSObject
+ (void)presentForImage:(UIImage *)image
                   from:(UIViewController *)presenter
                 onDone:(void (^)(UIImage *edited))onDone;

+ (void)presentForImage:(UIImage *)image
                   from:(UIViewController *)presenter
            fixedAspect:(CGFloat)fixedAspect
                 onDone:(void (^)(UIImage *edited))onDone;
@end
