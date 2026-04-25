#import <Foundation/Foundation.h>

@interface RGExpFlagsDefaultPrefs : NSObject
@end

@implementation RGExpFlagsDefaultPrefs

+ (void)load {
    @autoreleasepool {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *keys = @[
            @"sci_exp_flags_enabled",
            @"igt_internaluse_observer",
            @"igt_mobileconfig_update_observer"
        ];
        BOOL firstPass = ![ud boolForKey:@"sci_exp_default_observers_v4_done"];
        for (NSString *key in keys) {
            if (firstPass || [ud objectForKey:key] == nil) {
                [ud setBool:YES forKey:key];
            }
        }
        if (firstPass) {
            [ud setBool:NO forKey:@"igt_runtime_mc_symbol_observer"];
            [ud setBool:NO forKey:@"igt_runtime_mc_symbol_observer_verbose"];
        }
        [ud setBool:YES forKey:@"sci_exp_default_observers_v4_done"];
        [ud synchronize];
        NSLog(@"[RyukGram][ExpFlags] observer defaults applied v4 firstPass=%d", firstPass ? 1 : 0);
    }
}

@end
