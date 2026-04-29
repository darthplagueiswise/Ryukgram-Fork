#import "../../Utils.h"
#import <Foundation/Foundation.h>

%ctor {
    if ([SCIUtils getBoolPref:@"igt_mobileconfig_update_observer"]) {
        NSLog(@"[RyukGram][MCUpdate] observer not installed automatically");
    }
}
