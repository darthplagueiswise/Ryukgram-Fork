#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Taps the REMOTE call video by wrapping IG's VideoToolbox decode callback and
// routing each decoded frame to the grid compositor (one tile per participant).
@interface RYGCallVideoTap : NSObject
+ (void)setGroupMode:(BOOL)on;
@end

NS_ASSUME_NONNULL_END
