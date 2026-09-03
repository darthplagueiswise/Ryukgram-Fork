// Standalone export / import of MobileConfig overrides and notes.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGMobileConfigBackup : NSObject

+ (void)presentExportFrom:(UIViewController *)presenter;
+ (void)presentImportFrom:(UIViewController *)presenter completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
