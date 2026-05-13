#import <Foundation/Foundation.h>

@interface RGExpFlagsDefaultPrefs : NSObject
@end

@implementation RGExpFlagsDefaultPrefs

+ (void)load {
    @autoreleasepool {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        BOOL crashSafeFirstPass = ![ud boolForKey:@"sci_exp_default_observers_v8_crashsafe_done"];

        NSDictionary<NSString *, NSNumber *> *defaults = @{
            @"sci_exp_flags_enabled": @YES,
            @"igt_internaluse_observer": @YES,
            @"igt_mobileconfig_update_observer": @YES,

            // Crash-safe default: no MobileConfig hook is installed at startup.
            // MC ObjC Observers are opt-in from Dev Mode and then per broker/ID.
            @"sci_exp_mc_hooks_enabled": @NO,
            @"sci_exp_mc_objc_getter_observer_enabled": @NO,
            @"sci_exp_mc_objc_startup_hooks_enabled": @NO,
            @"sci_exp_mc_objc_apply_overrides_enabled": @NO,
            @"sci_exp_mc_legacy_getter_hooks_enabled": @NO,
            @"sci_exp_mc_c_hooks_enabled": @NO,
            @"sci_exp_mc_c_broker_body_hooks_enabled": @NO,
            @"igt_runtime_mc_symbol_observer_verbose": @NO,
        };

        for (NSString *key in defaults) {
            if (crashSafeFirstPass || [ud objectForKey:key] == nil) {
                [ud setObject:defaults[key] forKey:key];
            }
        }

        if (crashSafeFirstPass) {
            NSArray<NSString *> *brokerIDs = @[
                @"ig", @"igsl", @"igus",
                @"fb", @"fbsl", @"fbus",
                @"fbapt", @"fbctx", @"fbpd",
                @"metaser", @"metaut",
                @"eg", @"mci", @"egi", @"ega", @"mcic", @"mcie", @"meta", @"metanx", @"msgc"
            ];
            for (NSString *brokerID in brokerIDs) {
                [ud setBool:NO forKey:[@"mcbr.hook:" stringByAppendingString:brokerID]];
            }
            [ud setObject:@[] forKey:@"mcbr.hooks"];
            [ud setBool:YES forKey:@"sci_exp_default_observers_v8_crashsafe_done"];
        }

        [ud synchronize];
        NSLog(@"[RyukGram][ExpFlags] crash-safe observer defaults applied v8 firstPass=%d", crashSafeFirstPass ? 1 : 0);
    }
}

@end
