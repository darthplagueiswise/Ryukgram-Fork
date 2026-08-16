#import <UIKit/UIKit.h>

@interface RYGDateFormatPickerVC : UIViewController <UITableViewDataSource, UITableViewDelegate>

/// Returns the formatted example string for the currently selected format.
+ (NSString *)currentFormatExample;

@end

/// Editor for one saved custom date-format template.
@interface RYGDateFormatCustomVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>

- (instancetype)initWithEntryID:(NSString *)entryID;

@end
