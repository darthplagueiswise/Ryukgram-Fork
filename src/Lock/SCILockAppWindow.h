// Whole-app lock UIWindow. Two modes: shroud (opaque cover, no auth UI, used
// for app-switcher snapshot) and passcode (full prompt).

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCILockAppWindow : NSObject

+ (instancetype)shared;

- (void)presentIfNeeded;
- (void)showShroud;
- (void)hideShroud;
- (void)dismiss;
- (void)resolveOnForeground;
- (void)prewarm;

@property (nonatomic, readonly) BOOL isPresenting;
@property (nonatomic, strong, readonly, nullable) UIWindow *window;

@end

NS_ASSUME_NONNULL_END
