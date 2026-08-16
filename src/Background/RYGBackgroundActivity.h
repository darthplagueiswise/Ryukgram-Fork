#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Keeps the app alive in the background while a long-running op is in flight, by
// looping a silent track to hold the `audio` background-mode assertion. Driven by
// named sources so concurrent ops can't trip each other's start/stop.
@interface RYGBackgroundActivity : NSObject

// Idempotent. Runs while ≥1 active source is authorized by its own pref.
+ (void)setSource:(NSString *)source active:(BOOL)active;

@end

NS_ASSUME_NONNULL_END
