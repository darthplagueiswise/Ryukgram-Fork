#import <UIKit/UIKit.h>

// Compact bottom-sheet wheel picker for a time-of-day pref stored as "HH:mm".
@interface RYGTimePickerViewController : UIViewController

+ (void)presentForKey:(NSString *)key
                title:(NSString *)title
                 from:(UIViewController *)presenter
               onSave:(void (^)(void))onSave;

@end
