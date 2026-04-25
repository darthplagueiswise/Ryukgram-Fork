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
            @"igt_mobileconfig_update_observer",
            @"igt_runtime_mc_symbol_observer"
        ];
        BOOL firstPass = ![ud boolForKey:@"sci_exp_default_observers_v3_done"];
        for (NSString *key in keys) {
            if (firstPass || [ud objectForKey:key] == nil) {
                [ud setBool:YES forKey:key];
            }
        }
        [ud setBool:YES forKey:@"sci_exp_default_observers_v3_done"];
        [ud synchronize];
        NSLog(@"[RyukGram][ExpFlags] observer defaults applied firstPass=%d", firstPass ? 1 : 0);
    }
}

@end
