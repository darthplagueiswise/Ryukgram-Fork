// Reusable passcode entry view — dots + numpad + biometric button.
// Stateless about correctness; delegate decides what to do with each entered code.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class RYGLockPasscodeView;

@protocol RYGLockPasscodeViewDelegate <NSObject>
- (void)passcodeView:(RYGLockPasscodeView *)v didCompleteCode:(NSString *)code;
@optional
- (void)passcodeViewDidTapBiometric:(RYGLockPasscodeView *)v;
- (void)passcodeViewDidTapCancel:(RYGLockPasscodeView *)v;

/// Fired the moment the user enters their first digit — used to dismiss any
/// pending biometric system prompt so the pad doesn't sit behind it.
- (void)passcodeViewDidBeginInput:(RYGLockPasscodeView *)v;
@end

@interface RYGLockPasscodeView : UIView

@property (nonatomic, weak, nullable) id<RYGLockPasscodeViewDelegate> delegate;
@property (nonatomic) NSInteger codeLength; // 4 or 6
@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *subtitleText;
@property (nonatomic) BOOL biometricButtonVisible;
@property (nonatomic, copy, nullable) NSString *cancelTitle; // shows a cancel button on the bottom-left when set

- (void)reset;						 // clear digits + shake-free
- (void)flashError;					 // shake + clear
- (void)setSubtitleText:(NSString *)t flash:(BOOL)flash;

@end

NS_ASSUME_NONNULL_END