#import <UIKit/UIKit.h>

// Routes an image / video / GIF through the right editor, imports it, returns the
// stored relative asset. Used by the importer and for re-editing in place.
@interface RYGChatBgEditor : NSObject

+ (void)editImage:(UIImage *)image from:(UIViewController *)host completion:(void (^)(NSString *_Nullable rel))completion;
+ (void)editFileURL:(NSURL *)url from:(UIViewController *)host completion:(void (^)(NSString *_Nullable rel))completion;
+ (void)reEditAsset:(NSString *)relPath from:(UIViewController *)host completion:(void (^)(NSString *_Nullable rel))completion;

@end
