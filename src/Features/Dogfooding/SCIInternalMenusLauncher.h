#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SCIInternalMenusLauncher : NSObject
// Presents IG's own internal/dogfooding menus using validated entrypoints and
// the live user session/config observed from Instagram runtime.
+ (NSString *)openInstagramDebugMenu; // compatibility wrapper
+ (void)openInstagramDebugMenuWithCompletion:(void (^)(NSString *result))completion;
+ (NSString *)openDogfoodingNotesSettings;
+ (NSString *)openDogfoodingSettingsVC;
+ (NSString *)openInternalURLString:(NSString *)urlString;
@end
NS_ASSUME_NONNULL_END
