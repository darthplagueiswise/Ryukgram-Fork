#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Self-camera routing state for the grid. The frames themselves come from
// RYGCallSelfCaptureTap (the AVCapture delegate); this just holds the on/off flag
// (set when recording with "include my camera") and the tile key.
@interface RYGCallSelfVideoTap : NSObject
+ (void)setGroupMode:(BOOL)on;
+ (BOOL)groupModeActive;
+ (void *)selfTileKey;
@end

NS_ASSUME_NONNULL_END
