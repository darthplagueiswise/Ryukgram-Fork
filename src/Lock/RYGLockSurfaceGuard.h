#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGLockSurfaceGuard : NSObject

+ (void)attachToVC:(UIViewController *)vc forGroup:(NSString *)groupID;
+ (void)attachToVC:(UIViewController *)vc forGroup:(NSString *)groupID onCancel:(nullable void (^)(UIViewController *vc))onCancel;

+ (void)recheckForVC:(UIViewController *)vc;
+ (void)recheckAll;

+ (nullable NSString *)attachedGroupIDForVC:(UIViewController *)vc;
+ (nullable NSString *)visibleAttachedGroupID;

@end

NS_ASSUME_NONNULL_END