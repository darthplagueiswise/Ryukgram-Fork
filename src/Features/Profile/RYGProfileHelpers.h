// Profile user lookup plus HD profile-picture fetch/share/save, backed by a
// (VC pointer → IGUser) registry filled from IGProfileViewController hooks.
// Every method no-ops when no profile is active.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGProfileHelpers : NSObject

// MARK: - Active profile registry (called by hooks; not for clients)

+ (void)registerProfileVC:(UIViewController *)vc user:(nullable id)user;
+ (void)unregisterProfileVC:(UIViewController *)vc;

// MARK: - Lookup

+ (nullable id)userForView:(UIView *)view;
+ (nullable id)userForViewController:(UIViewController *)vc;

+ (nullable UIViewController *)activeProfileViewController;

// MARK: - User accessors (KVC, no reflection)

+ (nullable NSString *)usernameForUser:(id)user;
+ (nullable NSString *)pkForUser:(id)user;
+ (nullable NSString *)fullNameForUser:(id)user;
+ (nullable NSString *)biographyForUser:(id)user;
+ (nullable NSURL *)profileLinkForUser:(id)user;

// 1 = public, 2 = private, nil = unknown.
+ (nullable NSNumber *)privacyStatusForUser:(id)user;
+ (nullable NSNumber *)followerCountForUser:(id)user;

// NO unless IG has loaded friendship_status; the flags are untouched until then.
+ (BOOL)relationForUser:(id)user following:(BOOL *)following followedBy:(BOOL *)followedBy;
+ (nullable NSNumber *)followingCountForUser:(id)user;

// MARK: - Picture URL

+ (nullable NSURL *)cachedPictureURLForUser:(id)user;

// Largest hd_profile_pic_url from /users/{pk}/info/, main queue, cached URL on failure.
+ (void)resolveHDPictureURLForUser:(id)user
                          completion:(void(^)(NSURL * _Nullable url))completion;

+ (void)resolveHDPictureURLForPK:(nullable NSString *)pk
                          cached:(nullable NSURL *)cached
                      completion:(void(^)(NSURL * _Nullable url))completion;

// MARK: - Caption

// "Full Name\n@username\n\nbio"
+ (nullable NSString *)captionForUser:(id)user;

// MARK: - Actions (delegate retained internally)

+ (void)viewPictureForUser:(id)user;

// For avatar views off a profile page, where only the PK is reachable.
+ (void)viewPictureForPK:(nullable NSString *)pk fallbackURL:(nullable NSURL *)fallbackURL;

+ (void)sharePictureForUser:(id)user;

+ (void)savePictureForUser:(id)user;

+ (void)savePictureToGalleryForUser:(id)user;

@end

NS_ASSUME_NONNULL_END
