// DM inbox row context menu — appends a Hide chat action.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIHiddenChatsMenu : NSObject
+ (NSArray<UIAction *> *)actionsForEntry:(NSDictionary *)entry;
@end

NS_ASSUME_NONNULL_END
