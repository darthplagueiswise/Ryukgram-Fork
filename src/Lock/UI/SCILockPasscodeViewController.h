// Passcode entry / verification VC. Wraps SCILockPasscodeView, runs verification
// against SCILockManager, auto-fires biometric on appear when enabled, and shakes
// on wrong entry. Single completion fires once (YES = unlocked, NO = cancelled).

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCILockPasscodeViewController : UIViewController

@property (nonatomic, copy, nullable) NSString *promptTitle;
@property (nonatomic, copy, nullable) NSString *promptSubtitle;

@property (nonatomic) BOOL allowsBiometric; // default YES, gated by manager prefs
@property (nonatomic) BOOL allowsCancel;    // default YES, shows cancel button
@property (nonatomic) BOOL instantDismissOnSuccess; // skip the modal slide-off after auth

@property (nonatomic, copy, nullable) void (^completion)(BOOL success);

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString * _Nullable)subtitle;

@end

NS_ASSUME_NONNULL_END
