// Reusable "add someone" picker: recent DM people shown immediately, plus a
// live username search over the IG API. On pick, calls back with a normalized
// user dict { pk, username, fullName, profilePicURL }.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGUserPickerViewController : UIViewController

+ (void)presentFromViewController:(nullable UIViewController *)presenter
                            title:(nullable NSString *)title
                           onPick:(void (^)(NSDictionary *user))onPick;

// idLabel names the raw-numeric "add by ID" row (e.g. "Add by thread ID"); the
// returned dict carries manualID=@YES for that row. nil = "Add by user ID".
+ (void)presentFromViewController:(nullable UIViewController *)presenter
                            title:(nullable NSString *)title
                          idLabel:(nullable NSString *)idLabel
                           onPick:(void (^)(NSDictionary *user))onPick;

@end

NS_ASSUME_NONNULL_END
