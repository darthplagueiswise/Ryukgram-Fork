#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

// Crash-safe view-only observer for current 426 MobileConfig-ish C boolean gates.
// IMPORTANT:
// The wide C observer can be noisy and some signatures are not stable across versions.
// To avoid the "flags browser crashes after a few seconds" path, this file no longer auto-installs
// all wide fishhooks just because sci_exp_flags_enabled is ON.
//
// InternalUse observation still happens through InternalModeHooks.xm when exp flags are ON.
// This file installs only when verbose C symbol observer is explicitly enabled:
//   igt_runtime_mc_symbol_observer_verbose
//
// Legacy MEM/MCQMEM 411 symbols were removed because they are not exported in the 426 framework.

static BOOL RGMCBoolObserverEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer_verbose"];
}

static NSString *RGMCSourceForSymbol(const char *symbol) {
    if (!symbol) return @"Unknown";
    NSString *s = [NSString stringWithUTF8String:symbol];
    if ([s hasPrefix:@"_"]) s = [s substringFromIndex:1];
    if ([s hasPrefix:@"MCIMobileConfig"]) return @"MCI MobileConfig";
    if ([s hasPrefix:@"MCIExperimentCache"]) return @"MCI ExperimentCache";
    if ([s hasPrefix:@"MCIExtensionExperimentCache"]) return @"MCI ExtensionExperimentCache";
    if ([s hasPrefix:@"METAExtensionsExperiment"]) return @"METAExtensionsExperiment";
    if ([s hasPrefix:@"MSGCSessionedMobileConfig"]) return @"MSGC SessionedMobileConfig";
    if ([s hasPrefix:@"EasyGatingPlatform"]) return @"EasyGating Platform";
    if ([s hasPrefix:@"EasyGating"]) return @"EasyGating Internal";
    if ([s hasPrefix:@"MCQEasyGating"]) return @"MCQ EasyGating";
    if ([s hasPrefix:@"MCDDasmNative"] || [s hasPrefix:@"MCDCoreDasmNative"]) return @"MCD DASM Native";
    return @"Other MobileConfig C API";
}

static unsigned long long RGMCBestSpecifierCandidate(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5) {
    uintptr_t args[] = {a0, a1, a2, a3, a4, a5};

    for (NSUInteger i = 0; i < sizeof(args) / sizeof(args[0]); i++) {
        unsigned long long v = (unsigned long long)args[i];
        if (v >= 0x0001000000000000ULL && v <= 0x00ffffffffffffffULL) return v;
    }

    for (NSUInteger i = 1; i < sizeof(args) / sizeof(args[0]); i++) {
        unsigned long long v = (unsigned long long)args[i];
        if (v > 0 && v <= 0xffffffffULL) return v;
    }

    unsigned long long a0v = (unsigned long long)a0;
    if (a0v > 0 && a0v <= 0xffffffffULL) return a0v;
    return 0;
}

static void RGRecordCBooleanObservation(const char *symbol, BOOL result, uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, void *caller) {
    if (!RGMCBoolObserverEnabled()) return;

    unsigned long long candidate = RGMCBestSpecifierCandidate(a0, a1, a2, a3, a4, a5);
    NSString *sym = symbol ? [NSString stringWithUTF8String:symbol] : @"unknown";
    NSString *source = RGMCSourceForSymbol(symbol);
    NSString *def = [NSString stringWithFormat:@"source=%@ · symbol=%@ · result=%d · id=0x%llx · a0=0x%lx a1=0x%lx a2=0x%lx a3=0x%lx a4=0x%lx a5=0x%lx · caller=%p",
                     source,
                     sym,
                     result,
                     candidate,
                     (unsigned long)a0,
                     (unsigned long)a1,
                     (unsigned long)a2,
                     (unsigned long)a3,
                     (unsigned long)a4,
                     (unsigned long)a5,
                     caller];

    [SCIExpFlags recordMCParamID:candidate type:SCIExpMCTypeBool defaultValue:def];

    NSLog(@"[RyukGram][MCSymbolObserver][%@] %@ result=%d candidate=0x%016llx a0=0x%lx a1=0x%lx a2=0x%lx a3=0x%lx a4=0x%lx a5=0x%lx caller=%p",
          source,
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

typedef BOOL (*RGMCBoolRawFn)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);

#define RG_DECLARE_BOOL_OBSERVER(KEY, SYMBOL) \
    static RGMCBoolRawFn orig_##KEY = NULL; \
    static BOOL hook_##KEY(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5) { \
        BOOL result = orig_##KEY ? orig_##KEY(a0, a1, a2, a3, a4, a5) : NO; \
        RGRecordCBooleanObservation(SYMBOL, result, a0, a1, a2, a3, a4, a5, __builtin_return_address(0)); \
        return result; \
    }

RG_DECLARE_BOOL_OBSERVER(MCIMobileConfigGetBoolean, "_MCIMobileConfigGetBoolean")
RG_DECLARE_BOOL_OBSERVER(MCIExperimentCacheGetMobileConfigBoolean, "_MCIExperimentCacheGetMobileConfigBoolean")
RG_DECLARE_BOOL_OBSERVER(MCIExtensionExperimentCacheGetMobileConfigBoolean, "_MCIExtensionExperimentCacheGetMobileConfigBoolean")
RG_DECLARE_BOOL_OBSERVER(METAExtensionsExperimentGetBoolean, "_METAExtensionsExperimentGetBoolean")
RG_DECLARE_BOOL_OBSERVER(METAExtensionsExperimentGetBooleanWithoutExposure, "_METAExtensionsExperimentGetBooleanWithoutExposure")
RG_DECLARE_BOOL_OBSERVER(MSGCSessionedMobileConfigGetBoolean, "_MSGCSessionedMobileConfigGetBoolean")
RG_DECLARE_BOOL_OBSERVER(EasyGatingPlatformGetBoolean, "_EasyGatingPlatformGetBoolean")
RG_DECLARE_BOOL_OBSERVER(EasyGatingGetBoolean_Internal_DoNotUseOrMock, "_EasyGatingGetBoolean_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock, "_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MCQEasyGatingGetBooleanInternalDoNotUseOrMock, "_MCQEasyGatingGetBooleanInternalDoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter, "_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter")

#define RG_REBIND(KEY, SYMBOL) {SYMBOL, (void *)hook_##KEY, (void **)&orig_##KEY}

%ctor {
    if (!RGMCBoolObserverEnabled()) return;

    struct rebinding rebindings[] = {
        RG_REBIND(MCIMobileConfigGetBoolean, "MCIMobileConfigGetBoolean"),
        RG_REBIND(MCIExperimentCacheGetMobileConfigBoolean, "MCIExperimentCacheGetMobileConfigBoolean"),
        RG_REBIND(MCIExtensionExperimentCacheGetMobileConfigBoolean, "MCIExtensionExperimentCacheGetMobileConfigBoolean"),
        RG_REBIND(METAExtensionsExperimentGetBoolean, "METAExtensionsExperimentGetBoolean"),
        RG_REBIND(METAExtensionsExperimentGetBooleanWithoutExposure, "METAExtensionsExperimentGetBooleanWithoutExposure"),
        RG_REBIND(MSGCSessionedMobileConfigGetBoolean, "MSGCSessionedMobileConfigGetBoolean"),
        RG_REBIND(EasyGatingPlatformGetBoolean, "EasyGatingPlatformGetBoolean"),
        RG_REBIND(EasyGatingGetBoolean_Internal_DoNotUseOrMock, "EasyGatingGetBoolean_Internal_DoNotUseOrMock"),
        RG_REBIND(EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock, "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock"),
        RG_REBIND(MCQEasyGatingGetBooleanInternalDoNotUseOrMock, "MCQEasyGatingGetBooleanInternalDoNotUseOrMock"),
        RG_REBIND(MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter, "MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter"),
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][MCSymbolObserver] verbose-only current-426 fishhook rc=%d mci=%p mciExp=%p mciExt=%p meta=%p metaNoExp=%p msgc=%p easyPlatform=%p easyInternal=%p easyAuth=%p mcqEasy=%p mcdDasm=%p",
          rc,
          orig_MCIMobileConfigGetBoolean,
          orig_MCIExperimentCacheGetMobileConfigBoolean,
          orig_MCIExtensionExperimentCacheGetMobileConfigBoolean,
          orig_METAExtensionsExperimentGetBoolean,
          orig_METAExtensionsExperimentGetBooleanWithoutExposure,
          orig_MSGCSessionedMobileConfigGetBoolean,
          orig_EasyGatingPlatformGetBoolean,
          orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock,
          orig_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock,
          orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock,
          orig_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter);
}
