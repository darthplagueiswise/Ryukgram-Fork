#import <Foundation/Foundation.h>

@interface RGExpFlagsDefaultPrefs : NSObject
@end

@implementation RGExpFlagsDefaultPrefs

+ (void)load {
    @autoreleasepool {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        BOOL firstPass = ![ud boolForKey:@"sci_exp_default_observers_v7_objc_pass_through_done"];

        NSDictionary<NSString *, NSNumber *> *defaults = @{
            @"sci_exp_flags_enabled": @YES,
            @"igt_internaluse_observer": @YES,
            @"igt_mobileconfig_update_observer": @YES,
            @"sci_exp_mc_hooks_enabled": @YES,
            @"sci_exp_mc_objc_getter_observer_enabled": @YES,
            @"sci_exp_mc_objc_startup_hooks_enabled": @YES,
            @"sci_exp_mc_objc_apply_overrides_enabled": @YES,

            // alpha3 rebuild: MobileConfig Dev mode is ObjC pass-through first.
            // Body-level C brokers stay disabled unless a lab explicitly arms them.
            @"sci_exp_mc_c_hooks_enabled": @NO,
            @"sci_exp_mc_c_broker_body_hooks_enabled": @NO,
        };

        for (NSString *key in defaults) {
            if (firstPass || [ud objectForKey:key] == nil) {
                [ud setObject:defaults[key] forKey:key];
            }
        }

        NSArray<NSString *> *objcObserverBrokerIDs = @[
            @"ig", @"igsl", @"igus",
            @"fb", @"fbsl", @"fbus",
            @"fbapt", @"fbctx", @"fbpd",
            @"metaser", @"metaut"
        ];
        NSMutableArray<NSString *> *hookIndex = [[[ud arrayForKey:@"mcbr.hooks"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *bindings) {
            (void)bindings;
            return [obj isKindOfClass:NSString.class] && [obj length] > 0;
        }]] mutableCopy] ?: [NSMutableArray array];
        for (NSString *brokerID in objcObserverBrokerIDs) {
            NSString *key = [@"mcbr.hook:" stringByAppendingString:brokerID];
            if (firstPass || [ud objectForKey:key] == nil) [ud setBool:YES forKey:key];
            if (![hookIndex containsObject:brokerID]) [hookIndex addObject:brokerID];
        }
        [ud setObject:hookIndex forKey:@"mcbr.hooks"];

        // Explicitly do not auto-arm old C broker rows from earlier v6 defaults.
        for (NSString *brokerID in @[@"eg", @"mci", @"egi", @"ega", @"mcic", @"mcie", @"meta", @"metanx", @"msgc"]) {
            NSString *key = [@"mcbr.hook:" stringByAppendingString:brokerID];
            if (firstPass) [ud setBool:NO forKey:key];
            [hookIndex removeObject:brokerID];
        }
        [ud setObject:hookIndex forKey:@"mcbr.hooks"];

        if (firstPass || [ud objectForKey:@"igt_runtime_mc_symbol_observer_verbose"] == nil) {
            [ud setBool:NO forKey:@"igt_runtime_mc_symbol_observer_verbose"];
        }

        [ud setBool:YES forKey:@"sci_exp_default_observers_v7_objc_pass_through_done"];
        [ud synchronize];
        NSLog(@"[RyukGram][ExpFlags] ObjC pass-through observer defaults applied v7 firstPass=%d observers=%@", firstPass ? 1 : 0, objcObserverBrokerIDs);
    }
}

@end
