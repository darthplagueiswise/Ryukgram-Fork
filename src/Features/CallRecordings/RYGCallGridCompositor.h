#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

// Real-time grid compositor: participants' decode sessions and your camera push
// frames keyed by a stable pointer; a timer lays out the live tiles into one video.
@interface RYGCallGridCompositor : NSObject
+ (BOOL)startToURL:(NSURL *)url;
+ (void)addFrame:(CVImageBufferRef)image forKey:(void *)key isSelf:(BOOL)isSelf;
+ (void)stopWithCompletion:(void (^)(BOOL ok))completion;
+ (BOOL)isActive;
+ (BOOL)sawFrames;
+ (double)firstFrameWallTime;
@end

NS_ASSUME_NONNULL_END
