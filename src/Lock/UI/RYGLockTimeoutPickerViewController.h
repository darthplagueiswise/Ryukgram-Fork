// Dedicated picker for the per-group idle timeout. Pushed onto the
// group-detail nav stack rather than presented as an action sheet so the list
// of options is readable and respects the inset-grouped chrome.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGLockTimeoutPickerViewController : UIViewController
- (instancetype)initWithGroupID:(NSString *)groupID;
@end

NS_ASSUME_NONNULL_END
