#import "SCIAutofillInternalDevMode.h"
#import "../../Utils.h"

%hook IGInstagramAppDelegate

- (_Bool)application:(UIApplication *)application didFinishLaunchingWithOptions:(id)arg2 {
    _Bool ret = %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [SCIAutofillInternalDevMode applyEnabledToggles];
    });
    return ret;
}

- (void)applicationDidBecomeActive:(id)arg1 {
    %orig;
    [SCIAutofillInternalDevMode applyEnabledToggles];
}

%end
