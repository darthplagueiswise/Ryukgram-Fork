// Two-step passcode setup. Pass 1 collects new code, pass 2 confirms. On match
// commits to the manager and reports success.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCILockSetupViewController : UIViewController

@property (nonatomic) NSInteger codeLength;
@property (nonatomic, copy, nullable) void (^completion)(BOOL success);

- (instancetype)initWithCodeLength:(NSInteger)length;

@end

NS_ASSUME_NONNULL_END
