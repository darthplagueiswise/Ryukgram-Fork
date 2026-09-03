// RYGRepostSheet — download media, save to Photos, open IG's creation flow.

#import <UIKit/UIKit.h>

@interface RYGRepostSheet : NSObject

/// Download media, save to Photos, open IG's creation flow.
+ (void)repostWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL;

@end
