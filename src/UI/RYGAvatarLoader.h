#import <UIKit/UIKit.h>

// Shared avatar provider for RYGIDList-style screens. Returns the cached
// rounded avatar (or a placeholder), loads via RYGImageCache and posts
// RYGAvatarLoadedNotification once the real image is ready.
extern NSString *const RYGAvatarLoadedNotification;

@interface RYGAvatarLoader : NSObject

// Entry dict: thread-shaped (avatarURL / isGroup / users[{pk, profilePicURL}])
// or user-shaped (pk / profilePicURL). Missing URLs backfill from the live
// direct cache or the IG API.
+ (UIImage *)avatarForEntry:(NSDictionary *)entry;

+ (UIImage *)avatarForURLString:(NSString *)urlString group:(BOOL)group;

@end
