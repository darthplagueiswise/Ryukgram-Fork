#import "RYGEasyGatingRuntime.h"
#import <Foundation/Foundation.h>

static NSString *const kRYGPersistedEasyGatingOverridesKey = @"ryg_easy_gating_platform_bool_overrides_v2";

__attribute__((constructor)) static void RYGInstallDeveloperPersistenceBootstrap(void) {
    @autoreleasepool {
        // EasyGating persistence is an exact gate-ID registry. Installing its
        // one main-executable import binding does not require Runtime Browser,
        // Objective-C enumeration, MobileConfig prepare, or a delayed retry.
        NSDictionary *overrides = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGPersistedEasyGatingOverridesKey];
        if (overrides.count) [RYGEasyGatingRuntime.shared installIfNeeded];
    }
}
