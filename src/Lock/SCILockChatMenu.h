// DM inbox row context menu — appends Lock / Unlock chat action.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCILockChatMenu : NSObject
+ (NSArray<UIAction *> *)actionsForEntry:(NSDictionary *)entry;
@end

NS_ASSUME_NONNULL_END
