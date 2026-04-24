#import "../../Utils.h"
#include "../../../modules/fishhook/fishhook.h"

static BOOL RGMCUpdateObserverEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_mobileconfig_update_observer"] || [SCIUtils getBoolPref:@"igt_internaluse_observer"];
}

// Pass-through only. Do not call these manually yet.
// The exported TryUpdate wrapper forwards x0-x3 and sets x4 to 0 internally.
// ForceUpdate consumes x0-x4. Keep argument forwarding raw and log only pointer values.

typedef void (*RGTryUpdateFn)(void *, void *, void *, void *);
static RGTryUpdateFn orig_RGTryUpdate = NULL;
static void hook_RGTryUpdate(void *a0, void *a1, void *a2, void *a3) {
    if (orig_RGTryUpdate) orig_RGTryUpdate(a0, a1, a2, a3);
    if (RGMCUpdateObserverEnabled()) {
        NSLog(@"[RyukGram][MCUpdate] TryUpdate pass-through a0=%p a1=%p a2=%p a3=%p", a0, a1, a2, a3);
    }
}

typedef void (*RGForceUpdateFn)(void *, void *, void *, void *, uintptr_t);
static RGForceUpdateFn orig_RGForceUpdate = NULL;
static void hook_RGForceUpdate(void *a0, void *a1, void *a2, void *a3, uintptr_t a4) {
    if (orig_RGForceUpdate) orig_RGForceUpdate(a0, a1, a2, a3, a4);
    if (RGMCUpdateObserverEnabled()) {
        NSLog(@"[RyukGram][MCUpdate] ForceUpdate pass-through a0=%p a1=%p a2=%p a3=%p a4=0x%lx", a0, a1, a2, a3, (unsigned long)a4);
    }
}

%ctor {
    if (!RGMCUpdateObserverEnabled()) return;

    struct rebinding rebindings[] = {
        {"IGMobileConfigTryUpdateConfigsWithCompletion", (void *)hook_RGTryUpdate, (void **)&orig_RGTryUpdate},
        {"IGMobileConfigForceUpdateConfigs", (void *)hook_RGForceUpdate, (void **)&orig_RGForceUpdate},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][MCUpdate] observer fishhook rc=%d try=%p force=%p", rc, orig_RGTryUpdate, orig_RGForceUpdate);
}
