// DM inbox row menu — exclude/unexclude (or add/remove to block list).
// Returns nil when the feature is disabled.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGExcludeChatMenu : NSObject
+ (nullable UIAction *)actionForEntry:(NSDictionary *)entry;
@end

NS_ASSUME_NONNULL_END
