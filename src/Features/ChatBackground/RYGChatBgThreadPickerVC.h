#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Library grid scoped to a chat. nil threadID targets the global default.
@interface RYGChatBgThreadPickerVC : UIViewController

- (instancetype)initWithThreadID:(NSString *_Nullable)threadID;

// Active-thread cache — primed by IGDirectThreadViewController lifecycle hooks.
+ (NSString *_Nullable)activeThreadID;
+ (void)setActiveThreadID:(NSString *_Nullable)threadID;

@end

NS_ASSUME_NONNULL_END
