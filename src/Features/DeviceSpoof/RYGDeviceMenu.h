// Shared device-identity actions, presented from any host VC. Used by the
// login floating button and the Settings → Advanced → Device ID submenu so
// both behave identically. `onChange` fires after a state change so the caller
// can refresh its UI (button colour, settings rows).

#import <UIKit/UIKit.h>

@interface RYGDeviceMenu : NSObject

+ (void)presentRollOptionsFrom:(UIViewController *)host onChange:(void (^)(void))onChange;
+ (void)presentCustomIDFrom:(UIViewController *)host onChange:(void (^)(void))onChange;
+ (void)presentMaskEverythingConfirmFrom:(UIViewController *)host;
+ (void)presentWipeConfirmFrom:(UIViewController *)host;
+ (void)revertOnChange:(void (^)(void))onChange;
+ (void)copyCurrentID;
+ (void)copyMachineID;
+ (void)presentCustomMachineIDFrom:(UIViewController *)host onChange:(void (^)(void))onChange;

@end
