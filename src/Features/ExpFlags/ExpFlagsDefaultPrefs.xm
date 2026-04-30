#import <Foundation/Foundation.h>

@interface RGExpFlagsDefaultPrefs : NSObject
@end

@implementation RGExpFlagsDefaultPrefs

+ (void)load {
    @autoreleasepool {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *observerKeys = @[
            @"sci_exp_flags_enabled",
            @"igt_internaluse_observer",
            @"igt_mobileconfig_update_observer",
            @"sci_exp_mc_hooks_enabled",
            @"sci_exp_mc_c_hooks_enabled"
        ];
        BOOL firstPass = ![ud boolForKey:@"sci_exp_default_observers_v5_done"];
        for (NSString *key in observerKeys) {
            if (firstPass || [ud objectForKey:key] == nil) {
                [ud setBool:YES forKey:key];
            }
        }

        // Console logging is not required for the observer/override lab and is intentionally
        // kept quiet unless explicitly enabled by the user.
        if (firstPass || [ud objectForKey:@"igt_runtime_mc_symbol_observer_verbose"] == nil) {
            [ud setBool:NO forKey:@"igt_runtime_mc_symbol_observer_verbose"];
        }

        [ud setBool:YES forKey:@"sci_exp_default_observers_v5_done"];
        [ud synchronize];
        NSLog(@"[RyukGram][ExpFlags] observer defaults applied v5 firstPass=%d", firstPass ? 1 : 0);
    }
}

@end
