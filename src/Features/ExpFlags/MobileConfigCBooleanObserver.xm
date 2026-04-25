#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

// View-only observer for exported MobileConfig-ish C boolean gates.
// No overrides here. Stub/force behavior is controlled separately by MobileConfigRuntimePatcher.xm.

static BOOL RGMCBoolObserverEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer"] || [SCIUtils getBoolPref:@"sci_exp_flags_enabled"];
}

static void *RGObserverDlsymFlexible(const char *symbol) {
    if (!symbol || !symbol[0]) return NULL;
    void *sym = dlsym(RTLD_DEFAULT, symbol);
    if (sym) return sym;
    if (symbol[0] == '_') return dlsym(RTLD_DEFAULT, symbol + 1);
    char underscored[512];
    snprintf(underscored, sizeof(underscored), "_%s", symbol);
    return dlsym(RTLD_DEFAULT, underscored);
}

static unsigned long long RGMCBestSpecifierCandidate(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5) {
    uintptr_t args[] = {a0, a1, a2, a3, a4, a5};
    for (NSUInteger i = 0; i < sizeof(args) / sizeof(args[0]); i++) {
        unsigned long long v = (unsigned long long)args[i];
        if (v >= 0x0001000000000000ULL && v <= 0x00ffffffffffffffULL) return v;
    }
    for (NSUInteger i = 0; i < sizeof(args) / sizeof(args[0]); i++) {
        unsigned long long v = (unsigned long long)args[i];
        if (v > 0 && v <= 0xffffffffULL) return v;
    }
    return 0;
}

static void RGRecordCBooleanObservation(const char *symbol, BOOL result, uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, void *caller) {
    unsigned long long candidate = RGMCBestSpecifierCandidate(a0, a1, a2, a3, a4, a5);
    NSString *sym = symbol ? [NSString stringWithUTF8String:symbol] : @"unknown";
    NSString *def = [NSString stringWithFormat:@"%@ result=%d a0=0x%lx a1=0x%lx a2=0x%lx a3=0x%lx a4=0x%lx a5=0x%lx caller=%p",
                     sym,
                     result,
                     (unsigned long)a0,
                     (unsigned long)a1,
                     (unsigned long)a2,
                     (unsigned long)a3,
                     (unsigned long)a4,
                     (unsigned long)a5,
                     caller];
    [SCIExpFlags recordMCParamID:candidate type:SCIExpMCTypeBool defaultValue:def];

    if ([SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer_verbose"]) {
        NSLog(@"[RyukGram][MCSymbolObserver] %@ result=%d candidate=0x%016llx a0=0x%lx a1=0x%lx a2=0x%lx a3=0x%lx a4=0x%lx a5=0x%lx caller=%p",
              sym,
              result,
              candidate,
              (unsigned long)a0,
              (unsigned long)a1,
              (unsigned long)a2,
              (unsigned long)a3,
              (unsigned long)a4,
              (unsigned long)a5,
              caller);
    }
}

typedef BOOL (*RGMCBoolRawFn)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);

#define RG_DECLARE_BOOL_OBSERVER(KEY, SYMBOL) \
    static RGMCBoolRawFn orig_##KEY = NULL; \
    static BOOL hook_##KEY(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5) { \
        BOOL result = orig_##KEY ? orig_##KEY(a0, a1, a2, a3, a4, a5) : NO; \
        RGRecordCBooleanObservation(SYMBOL, result, a0, a1, a2, a3, a4, a5, __builtin_return_address(0)); \
        return result; \
    }

RG_DECLARE_BOOL_OBSERVER(MCIMobileConfigGetBoolean, "_MCIMobileConfigGetBoolean")
RG_DECLARE_BOOL_OBSERVER(METAExtensionsExperimentGetBoolean, "_METAExtensionsExperimentGetBoolean")
RG_DECLARE_BOOL_OBSERVER(METAExtensionsExperimentGetBooleanWithoutExposure, "_METAExtensionsExperimentGetBooleanWithoutExposure")
RG_DECLARE_BOOL_OBSERVER(MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock, "_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock, "_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock, "_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigPlatformGetBoolean, "_MEMMobileConfigPlatformGetBoolean")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock, "_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock")

static void RGLogSymbolAvailability(const char *phase) {
    const char *symbols[] = {
        "_MCIMobileConfigGetBoolean",
        "_METAExtensionsExperimentGetBoolean",
        "_METAExtensionsExperimentGetBooleanWithoutExposure",
        "_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock",
        "_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock",
        "_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock",
        "_MEMMobileConfigPlatformGetBoolean",
        "_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock",
    };
    for (NSUInteger i = 0; i < sizeof(symbols) / sizeof(symbols[0]); i++) {
        void *addr = RGObserverDlsymFlexible(symbols[i]);
        NSLog(@"[RyukGram][MCSymbolObserver] %s %s -> %p", phase ?: "phase", symbols[i], addr);
    }
}

%ctor {
    if (!RGMCBoolObserverEnabled()) return;

    struct rebinding rebindings[] = {
        {"MCIMobileConfigGetBoolean", (void *)hook_MCIMobileConfigGetBoolean, (void **)&orig_MCIMobileConfigGetBoolean},
        {"METAExtensionsExperimentGetBoolean", (void *)hook_METAExtensionsExperimentGetBoolean, (void **)&orig_METAExtensionsExperimentGetBoolean},
        {"METAExtensionsExperimentGetBooleanWithoutExposure", (void *)hook_METAExtensionsExperimentGetBooleanWithoutExposure, (void **)&orig_METAExtensionsExperimentGetBooleanWithoutExposure},
        {"MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock", (void *)hook_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock, (void **)&orig_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock},
        {"MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock", (void *)hook_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock, (void **)&orig_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock},
        {"MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock", (void *)hook_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock, (void **)&orig_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock},
        {"MEMMobileConfigPlatformGetBoolean", (void *)hook_MEMMobileConfigPlatformGetBoolean, (void **)&orig_MEMMobileConfigPlatformGetBoolean},
        {"MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock", (void *)hook_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock, (void **)&orig_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][MCSymbolObserver] fishhook rc=%d mci=%p meta=%p metaNoExp=%p mcqmem=%p cap=%p dev=%p platform=%p protocol=%p",
          rc,
          orig_MCIMobileConfigGetBoolean,
          orig_METAExtensionsExperimentGetBoolean,
          orig_METAExtensionsExperimentGetBooleanWithoutExposure,
          orig_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock,
          orig_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock,
          orig_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock,
          orig_MEMMobileConfigPlatformGetBoolean,
          orig_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock);
    RGLogSymbolAvailability("ctor");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RGLogSymbolAvailability("delayed");
    });
}
