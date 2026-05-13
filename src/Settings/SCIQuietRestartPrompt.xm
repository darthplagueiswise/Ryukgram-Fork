#import "../Utils.h"
#import <Foundation/Foundation.h>

%hook SCIUtils
+ (void)showRestartConfirmation {
    static NSTimeInterval lastShown = 0;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (now - lastShown < 2.0) return;
    lastShown = now;
    [self showToastForDuration:2.0
                         title:SCILocalized(@"Restart required")
                      subtitle:SCILocalized(@"Restart the app after changing restart-required options")];
}
%end
