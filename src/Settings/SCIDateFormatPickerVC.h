#import <UIKit/UIKit.h>

@interface SCIDateFormatPickerVC : UIViewController <UITableViewDataSource, UITableViewDelegate>

/// Returns the formatted example string for the currently selected format.
+ (NSString *)currentFormatExample;

@end

/// Editor for one saved custom date-format template.
@interface SCIDateFormatCustomVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (instancetype)initWithEntryID:(NSString *)entryID;

@end
