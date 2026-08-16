#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// RyukGram debug console — permanent reusable module. DO NOT DELETE.
// Disable for release by renaming .m → .m_ (Theos only discovers .m/.x/.xm).
// See CLAUDE.md for usage.

#ifdef __cplusplus
extern "C" {
#endif

void RYGDebugLog(NSString * _Nullable category, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
NSString *RYGDebugLogDump(void);
void RYGDebugLogClear(void);

#ifdef __cplusplus
}
#endif

@interface RYGDebugLogViewController : UIViewController
+ (void)presentFromTopViewController;
@end

@interface RYGDebugConsole : NSObject
+ (instancetype)shared;
- (void)installIfNeeded;
- (void)show;
- (void)toggleMinimised;
@end
