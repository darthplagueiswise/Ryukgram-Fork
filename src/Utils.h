#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import <os/log.h>
#import <objc/message.h>

#import "InstagramHeaders.h"
#import "QuickLook.h"
#import "Localization/RYGLocalization.h"

#import "Settings/RYGSettingsViewController.h"

#define RYGLog(fmt, ...) \
    do { \
        NSString *tmpStr = [NSString stringWithFormat:(fmt), ##__VA_ARGS__]; \
        os_log(OS_LOG_DEFAULT, "[RyukGram] %{public}s", tmpStr.UTF8String); \
    } while(0)

#define RYGLogId(prefix, obj) os_log(OS_LOG_DEFAULT, "[RyukGram] %{public}@: %{public}@", prefix, obj);

@interface RYGUtils : NSObject

+ (BOOL)getBoolPref:(NSString *)key;
+ (double)getDoublePref:(NSString *)key;
+ (NSString *)getStringPref:(NSString *)key;
+ (NSDictionary *)getDictPref:(NSString *)key;
+ (NSArray *)getArrayPref:(NSString *)key;
+ (void)setPref:(id)value forKey:(NSString *)key;

// Master kill switch: when on, getBoolPref returns NO for all keys so the tweak behaves like stock IG.
+ (BOOL)allTweakOptionsDisabled;

// Registered RyukGram defaults (set once at app launch by Tweak.x). Used by
// the settings backup so any new pref is included automatically.
+ (NSDictionary<NSString *, id> *)rygRegisteredDefaults;
+ (void)setRygRegisteredDefaults:(NSDictionary<NSString *, id> *)defaults;

+ (_Bool)liquidGlassEnabledBool:(_Bool)fallback;

+ (NSString *)stripTrackingParams:(NSString *)urlString;

// Displaying View Controllers
+ (void)showQuickLookVC:(NSArray<id> *)items;
+ (void)showShareVC:(id)item;
// Clean-named hardlink for a scratch file so share/QuickLook never show ryuk_tmp_; clean names pass through.
+ (NSURL *)shareReadyURL:(NSURL *)fileURL;
// WebP becomes PNG so Photos keeps the quality; other formats pass through.
+ (NSURL *)photoSafeImageFileURL:(NSURL *)fileURL;
+ (void)showSettingsVC:(UIWindow *)window;
+ (void)showSettingsVC:(UIWindow *)window atTopLevelEntry:(NSString *)entryTitle;
+ (void)showSettingsVC:(UIWindow *)window atTopLevelEntry:(NSString *)entryTitle scrollToSection:(NSString *)sectionHeader;

// iOS 26 drops touches on action sheets whose presenter is mid-animation or
// layered under a popover. Hosting the alert in its own UIWindow sidesteps it.
+ (void)presentAlertInOwnWindow:(UIAlertController *)alert;

// Colours
+ (UIColor *)RYGColor_Primary;
+ (UIColor *)RYGColor_InstagramBackground;
+ (UIColor *)RYGColor_InstagramSecondaryBackground;
+ (UIColor *)RYGColor_InstagramTertiaryBackground;
+ (UIColor *)RYGColor_InstagramGroupedBackground;
+ (UIColor *)RYGColor_InstagramPrimaryText;
+ (UIColor *)RYGColor_InstagramSecondaryText;
+ (UIColor *)RYGColor_InstagramTertiaryText;
+ (UIColor *)RYGColor_InstagramSeparator;
+ (UIColor *)RYGColor_InstagramFavorite;
+ (UIColor *)RYGColor_InstagramDestructive;
+ (UIColor *)RYGColor_InstagramPressedBackground;

// Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc;
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode;

+ (void)showErrorHUDWithDescription:(NSString *)errorDesc;
+ (void)showErrorHUDWithDescription:(NSString *)errorDesc dismissAfterDelay:(CGFloat)dismissDelay;

// Media
// IGAPIStorableObject's snake_case Pando _fieldCache dict. Many IG fields
// aren't exposed through KVC (the resolver returns NSNull for absent keys);
// reading the dict directly is the reliable path. Returns nil when obj has
// no _fieldCache ivar or the value is missing.
+ (NSDictionary *)fieldCacheForObject:(id)obj;
+ (id)fieldCacheValue:(id)obj forKey:(NSString *)key;

+ (NSURL *)getPhotoUrl:(IGPhoto *)photo;
+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media;

+ (NSURL *)getVideoUrl:(IGVideo *)video;
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media;

// View Controllers
+ (UIViewController *)viewControllerForView:(UIView *)view;
+ (UIViewController *)viewControllerForAncestralView:(UIView *)view;
+ (UIViewController *)nearestViewControllerForView:(UIView *)view;

// Count formatters. Full = 1,234,567. Short = 1.2K/4.2M/15B (round-down).
// IG-style = full under 10,000, short above, no trailing ".0".
+ (NSString *)fullCount:(long long)n;
+ (NSString *)shortCount:(long long)n;
+ (NSString *)igStyleCount:(long long)n;
+ (NSString *)formatCount:(long long)n shortened:(BOOL)shortened;

// Functions
+ (NSString *)IGVersionString;
+ (BOOL)isNotch;

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view;

// Alerts
// Pass the matching Settings toggle title for `title` (reuses localized strings). nil = generic.
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler;

// gated NO runs onConfirm immediately; presenter nil = top-most.
+ (void)confirmIfNeeded:(BOOL)gated
                  title:(NSString *)title
                message:(NSString *)message
           confirmTitle:(NSString *)confirmTitle
                   from:(UIViewController *)presenter
              onConfirm:(void(^)(void))onConfirm
               onCancel:(void(^)(void))onCancel;

+ (void)showRestartConfirmation;
+ (void)showRestartConfirmationWithTitle:(NSString *)title message:(NSString *)message;

// Toasts
+ (void)showToastForDuration:(double)duration title:(NSString *)title;
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle;
+ (void)showIGNativeToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle;
+ (void)showIGNativeToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle onTap:(void (^)(void))onTap;

// Math
+ (NSUInteger)decimalPlacesInDouble:(double)value;

// Ivars
+ (id)getIvarForObj:(id)obj name:(const char *)name;
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value;

// Active IG user session (walks all connected scenes for the first window
// with a non-nil `userSession`).
+ (id)activeUserSession;
// PK string read from an IGUser object's `_pk` ivar (walks superclass chain).
+ (NSString *)pkFromIGUser:(id)user;
+ (NSString *)currentUserPK;

@end