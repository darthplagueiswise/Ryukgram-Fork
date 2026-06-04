#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SCIInternalMenusLauncher : NSObject
// Presents IG's own internal/dogfooding menus using validated class-method
// entrypoints + the live user session (no server gate involved).
+ (NSString *)openDogfoodingNotesSettings;     // +notesDogfoodingSettingsOpenOnViewController:userSession: (reliable)
+ (NSString *)openDogfoodingSettingsVC;        // alloc IGDogfoodingSettingsViewController + present (best-effort)
+ (NSString *)openInternalURLString:(NSString *)urlString; // +[IGURLHandler openInternalURL:...]
@end
NS_ASSUME_NONNULL_END
