#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Muxes the grid video with the mixed call audio into one .mp4.
@interface RYGCallVideoCapture : NSObject

// Each track is placed at its own lead-in offset so whichever started later is
// pushed back — synced in either ordering (only one offset is ever non-zero).
+ (void)muxVideo:(NSURL *)videoURL audio:(NSURL *)audioURL videoOffset:(double)videoOffset audioOffset:(double)audioOffset toURL:(NSURL *)outURL completion:(void (^)(BOOL ok))completion;

@end

NS_ASSUME_NONNULL_END
