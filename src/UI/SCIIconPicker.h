// SCIIconPicker — grid picker for action button icons.
// Default init edits the global icon. The source init edits a per-source
// override (and adds a "Use default" affordance to clear it).

#import <UIKit/UIKit.h>
#import "../ActionButton/SCIActionCatalog.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIIconPickerViewController : UIViewController
- (instancetype)initForSource:(SCIActionSource)source;
@end

NS_ASSUME_NONNULL_END
