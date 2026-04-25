#import <Foundation/Foundation.h>

static void RGSetDefaultOnIfMissing(NSString *key) {
    if (!key.length) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:key] == nil) [ud setBool:YES forKey:key];
}

__attribute__((constructor)) static void RGExpFlagsDefaultPrefs(void) {
    @autoreleasepool {
        RGSetDefaultOnIfMissing(@"sci_exp_flags_enabled");
        RGSetDefaultOnIfMissing(@"igt_internaluse_observer");
        RGSetDefaultOnIfMissing(@"igt_mobileconfig_update_observer");
        RGSetDefaultOnIfMissing(@"igt_runtime_mc_symbol_observer");
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"[RyukGram][ExpFlags] default observer prefs ensured ON when missing");
    }
}
