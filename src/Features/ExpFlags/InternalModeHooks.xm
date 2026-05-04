#import "../../Utils.h"
#import <Foundation/Foundation.h>
#include "../../../modules/fishhook/fishhook.h"

// SCI DexKit v2.0 removed IGMobileConfigBooleanValueForInternalUse and
// IGMobileConfigSessionlessBooleanValueForInternalUse from this legacy file.
// Those C brokers are owned only by SCIMobileConfigBrokerRouter.xm now.
// This file keeps only the separate internal-apps gate spoof.

static BOOL (*orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18)(void) = NULL;

static BOOL SCIInternalAppsGateEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_internal_apps_spoof"] ||
           [SCIUtils getBoolPref:@"igt_internal_apps_gate"] ||
           [SCIUtils getBoolPref:@"igt_employee_master"] ||
           [SCIUtils getBoolPref:@"igt_employee"] ||
           [SCIUtils getBoolPref:@"igt_employee_devoptions_gate"];
}

static BOOL hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18(void) {
    if (SCIInternalAppsGateEnabled()) return YES;
    return orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 ? orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18() : NO;
}

%ctor {
    if (!SCIInternalAppsGateEnabled()) return;
    struct rebinding rebindings[] = {
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18, (void **)&orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][InternalAppsGate] installed rc=%d orig=%p", rc, orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18);
}
