#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Source-picker action sheet (Photos / RyukGram Gallery / Files). On selection
// runs the image through the crop sheet, imports into the library, and calls
// back with the new asset path.
@interface SCIChatBgImporter : NSObject

+ (void)presentFrom:(UIViewController *)host completion:(void (^_Nullable)(NSString *_Nullable newAsset))completion;

@end

NS_ASSUME_NONNULL_END
