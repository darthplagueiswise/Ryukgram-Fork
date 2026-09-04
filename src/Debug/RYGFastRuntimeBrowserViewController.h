#import <UIKit/UIKit.h>

@interface RYGFastRuntimeBrowserViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery;
- (instancetype)initWithTitle:(NSString *)title
                  initialQuery:(NSString *)initialQuery
    allowsBulkVisibilityOverride:(BOOL)allowsBulkVisibilityOverride;
@end
