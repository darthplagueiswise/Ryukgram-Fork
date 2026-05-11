#import <Foundation/Foundation.h>
#import "../Features/ExpFlags/SCIMobileConfigMapping.h"
#import "../Features/ExpFlags/SCIDexKitNameResolver.h"

// beta2 stability fix:
// This file must not install Dogfooding persistence hooks or MobileConfig
// persistExtraData hooks at startup. The previous beta2 version scheduled work
// at 0.2s/1s/3s/6s and hooked a C++ MobileConfig storage symbol once loaded.
// That can crash during cold start/login even when the user has not activated
// any feature.
//
// For beta2, keep exported symbols and crash-guard cleanup, but make all runtime
// hook installation manual-disabled/no-op. id_name_mapping should be obtained by
// explicit export/debug flow later, not by startup C++ hook.

static NSString * const kSCIDogCrashActiveKey = @"sci.dogfooding.crash_guard.active";
static NSString * const kSCIDogCrashTrippedKey = @"sci.dogfooding.crash_guard.tripped";
static NSString * const kSCIDogCrashReasonKey = @"sci.dogfooding.crash_guard.reason";
static NSString * const kSCIDogCrashDateKey = @"sci.dogfooding.crash_guard.date";
static NSString * const kSCIDogCrashDisableKey = @"sci.dogfooding.persistence.disabled";

static void SCIDogCrashGuardBootstrap(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:kSCIDogCrashActiveKey]) {
        NSString *reason = [ud stringForKey:kSCIDogCrashReasonKey] ?: @"previous dogfooding operation did not finish";
        [ud setBool:YES forKey:kSCIDogCrashTrippedKey];
        [ud setObject:[NSDate date] forKey:kSCIDogCrashDateKey];
        [ud setObject:reason forKey:kSCIDogCrashReasonKey];
        [ud setBool:YES forKey:kSCIDogCrashDisableKey];
        [ud removeObjectForKey:kSCIDogCrashActiveKey];
        [ud synchronize];
        NSLog(@"[RyukGram][DogfoodPersist] crash guard tripped; disabled persistence reason=%@", reason);
    }
}

static void SCIRecordIDNameObserverStatus(NSString *source, NSString *key, NSString *path, NSUInteger bytes, NSString *errorText) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:source ?: @"" forKey:@"sci.mc.id_name_observer.source"];
    [ud setObject:key ?: @"" forKey:@"sci.mc.id_name_observer.key"];
    [ud setObject:path ?: @"" forKey:@"sci.mc.id_name_observer.path"];
    [ud setObject:@(bytes) forKey:@"sci.mc.id_name_observer.bytes"];
    [ud setObject:[NSDate date] forKey:@"sci.mc.id_name_observer.date"];
    if (errorText.length) [ud setObject:errorText forKey:@"sci.mc.id_name_observer.error"];
    else [ud removeObjectForKey:@"sci.mc.id_name_observer.error"];
    [ud synchronize];
}

#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("default"))) void SCIInstallDogfoodingPersistenceHooks(void) {
    NSLog(@"[RyukGram][DogfoodPersist] install requested but disabled for beta2 launch stability");
}

__attribute__((visibility("default"))) void SCIInstallPassiveIDNameMappingPersistObserver(void) {
    SCIRecordIDNameObserverStatus(@"disabled", @"", @"", 0, @"persistExtraData hook disabled for beta2 launch stability");
    NSLog(@"[RyukGram][MCIDName] persistExtraData observer disabled for beta2 launch stability");
}

__attribute__((visibility("default"))) BOOL SCIIsPassiveIDNameMappingPersistObserverInstalled(void) {
    return NO;
}
#ifdef __cplusplus
}
#endif

__attribute__((constructor))
static void SCIDogfoodingPersistenceInit(void) {
    @autoreleasepool {
        SCIDogCrashGuardBootstrap();
        SCIRecordIDNameObserverStatus(@"startup-inert", @"", @"", 0, @"startup observer disabled for beta2 launch stability");
        NSLog(@"[RyukGram][DogfoodPersist] startup inert; no Dogfooding hooks, no id_name observer timers");
    }
}
