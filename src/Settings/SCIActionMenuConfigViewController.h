// Configure-menu screen — one instance per source. Lets the user reorder
// menu actions, toggle them on/off, mark sections as collapsible (rendered
// as a submenu), set a default-tap action, and toggle the date header.

#import <UIKit/UIKit.h>
#import "../ActionButton/SCIActionCatalog.h"
#import "../UI/SCIReorderTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCIActionMenuConfigViewController : SCIReorderTableViewController
- (instancetype)initForSource:(SCIActionSource)source;
@end

NS_ASSUME_NONNULL_END
