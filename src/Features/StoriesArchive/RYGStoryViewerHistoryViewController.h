#import <UIKit/UIKit.h>

@class RYGAudienceMember;

NS_ASSUME_NONNULL_BEGIN

// The stories one person watched, newest first, with what they reacted with.
@interface RYGStoryViewerHistoryViewController : UIViewController

+ (void)showMember:(RYGAudienceMember *)member from:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
