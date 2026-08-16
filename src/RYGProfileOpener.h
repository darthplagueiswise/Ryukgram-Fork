// Opens an IG profile in-app over the caller, so Back returns to where you were
// instead of IG's home tab. Falls back to the instagram://user deep link.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGProfileOpener : NSObject

+ (BOOL)openProfileForPK:(nullable NSString *)pk
                username:(nullable NSString *)username
                    from:(nullable UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
