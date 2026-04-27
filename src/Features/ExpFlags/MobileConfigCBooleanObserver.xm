#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

// View-only observer for exported MobileConfig-ish C boolean gates.
// No overrides here. Stub/force behavior is controlled separately by MobileConfigRuntimePatcher.xm.
//
// Static scan of FBSharedFramework(23):
//   present/exported: IGMobileConfig*, MCI*, METAExtensionsExperiment*, MSGCSessionedMobileConfig*, EasyGating*, MCDDasmNative*
//   string/import anchors only in this image: _MCIMobileConfigGetBoolean, _METAExtensionsExperimentGetBoolean,
//     _EasyGatingPlatformGetBoolean, _MSGCSessionedMobileConfigGetBoolean
//   not present in this FBSharedFramework image: MEMMobileConfigFeatureDevConfig*, FeatureCapability*,
//     ProtocolExperiment*, PlatformGetBoolean and MCQMEMMobileConfigCqlGetBoolean*.
// Those MEM names can still exist in another loaded image/main executable, so we keep them as optional rebinds.

static BOOL RGMCBoolObserverEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer"] ||
           [SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer_verbose"];
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

static NSString *RGMCSourceForSymbol(const char *symbol) {
    if (!symbol) return @"Unknown";
    NSString *s = [NSString stringWithUTF8String:symbol];
    if ([s hasPrefix:@"_"]) s = [s substringFromIndex:1];
    if ([s hasPrefix:@"IGMobileConfigSessionless"]) return @"IG Sessionless C API";
    if ([s hasPrefix:@"IGMobileConfig"]) return @"IG InternalUse C API";
    if ([s containsString:@"FeatureDevConfig"]) return @"MEM FeatureDevConfig";
    if ([s containsString:@"FeatureCapability"]) return @"MEM FeatureCapability";
    if ([s containsString:@"ProtocolExperiment"]) return @"MEM ProtocolExperiment";
    if ([s hasPrefix:@"MEMMobileConfigPlatform"]) return @"MEM Platform";
    if ([s hasPrefix:@"MCQMEMMobileConfig"]) return @"MCQMEM MobileConfig";
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

    // Real MC stable specifiers are usually p64-ish values, for example 0x0081030f00000a95.
    for (NSUInteger i = 0; i < sizeof(args) / sizeof(args[0]); i++) {
        unsigned long long v = (unsigned long long)args[i];
        if (v >= 0x0001000000000000ULL && v <= 0x00ffffffffffffffULL) return v;
    }

    // MEM/EasyGating style calls observed in runtime often expose compact ids in a1, such as 0x16, 0x52, 0x102.
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

    if ([SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer_verbose"]) {
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
}

typedef BOOL (*RGMCBoolRawFn)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);

#define RG_DECLARE_BOOL_OBSERVER(KEY, SYMBOL) \
    static RGMCBoolRawFn orig_##KEY = NULL; \
    static BOOL hook_##KEY(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5) { \
        BOOL result = orig_##KEY ? orig_##KEY(a0, a1, a2, a3, a4, a5) : NO; \
        RGRecordCBooleanObservation(SYMBOL, result, a0, a1, a2, a3, a4, a5, __builtin_return_address(0)); \
        return result; \
    }

// Exported/present in FBSharedFramework(23)
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
RG_DECLARE_BOOL_OBSERVER(MCDCoreDasmNativeGetMobileConfigBoolean, "_MCDCoreDasmNativeGetMobileConfigBoolean")

// Optional symbols observed in other Instagram builds/images and in your runtime prints.
// FBSharedFramework(23) does not export these MEM names, so their availability log is the important signal.
RG_DECLARE_BOOL_OBSERVER(MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock, "_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock, "_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock, "_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigPlatformGetBoolean, "_MEMMobileConfigPlatformGetBoolean")
RG_DECLARE_BOOL_OBSERVER(MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock, "_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock")

#define RG_REBIND(KEY, SYMBOL) {SYMBOL, (void *)hook_##KEY, (void **)&orig_##KEY}

typedef struct {
    const char *symbol;
    const char *source;
    const char *status;
} RGMCObservedSymbolInfo;

static const RGMCObservedSymbolInfo kRGMCObservedSymbols[] = {
    {"_MCIMobileConfigGetBoolean", "MCI MobileConfig", "FBSharedFramework(23): exported"},
    {"_MCIExperimentCacheGetMobileConfigBoolean", "MCI ExperimentCache", "FBSharedFramework(23): exported"},
    {"_MCIExtensionExperimentCacheGetMobileConfigBoolean", "MCI ExtensionExperimentCache", "FBSharedFramework(23): exported"},
    {"_METAExtensionsExperimentGetBoolean", "METAExtensionsExperiment", "FBSharedFramework(23): exported"},
    {"_METAExtensionsExperimentGetBooleanWithoutExposure", "METAExtensionsExperiment", "FBSharedFramework(23): exported"},
    {"_MSGCSessionedMobileConfigGetBoolean", "MSGC SessionedMobileConfig", "FBSharedFramework(23): exported"},
    {"_EasyGatingPlatformGetBoolean", "EasyGating Platform", "FBSharedFramework(23): exported"},
    {"_EasyGatingGetBoolean_Internal_DoNotUseOrMock", "EasyGating Internal", "FBSharedFramework(23): exported"},
    {"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", "EasyGating Internal", "FBSharedFramework(23): exported"},
    {"_MCQEasyGatingGetBooleanInternalDoNotUseOrMock", "MCQ EasyGating", "FBSharedFramework(23): exported"},
    {"_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter", "MCD DASM Native", "FBSharedFramework(23): exported"},
    {"_MCDCoreDasmNativeGetMobileConfigBoolean", "MCD DASM Native", "FBSharedFramework(23): string in older logs / optional"},
    {"_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock", "MCQMEM MobileConfig", "FBSharedFramework(23): not exported; optional other image"},
    {"_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock", "MEM FeatureCapability", "FBSharedFramework(23): not exported; optional other image"},
    {"_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock", "MEM FeatureDevConfig", "FBSharedFramework(23): not exported; optional other image"},
    {"_MEMMobileConfigPlatformGetBoolean", "MEM Platform", "FBSharedFramework(23): not exported; optional other image"},
    {"_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock", "MEM ProtocolExperiment", "FBSharedFramework(23): not exported; optional other image"},
};

static void RGLogSymbolAvailability(const char *phase) {
    for (NSUInteger i = 0; i < sizeof(kRGMCObservedSymbols) / sizeof(kRGMCObservedSymbols[0]); i++) {
        const RGMCObservedSymbolInfo info = kRGMCObservedSymbols[i];
        void *addr = RGObserverDlsymFlexible(info.symbol);
        NSLog(@"[RyukGram][MCSymbolObserver] %s source=%s symbol=%s addr=%p note=%s",
              phase ?: "phase",
              info.source,
              info.symbol,
              addr,
              info.status);
    }
}

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
        RG_REBIND(MCDCoreDasmNativeGetMobileConfigBoolean, "MCDCoreDasmNativeGetMobileConfigBoolean"),
        RG_REBIND(MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock, "MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock"),
        RG_REBIND(MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock, "MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock"),
        RG_REBIND(MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock, "MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock"),
        RG_REBIND(MEMMobileConfigPlatformGetBoolean, "MEMMobileConfigPlatformGetBoolean"),
        RG_REBIND(MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock, "MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock"),
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][MCSymbolObserver] expanded fishhook rc=%d mci=%p mciExp=%p mciExt=%p meta=%p metaNoExp=%p msgc=%p easyPlatform=%p easyInternal=%p easyAuth=%p mcqEasy=%p mcdDasm=%p mcdCore=%p mcqmem=%p cap=%p dev=%p platform=%p protocol=%p",
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
          orig_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter,
          orig_MCDCoreDasmNativeGetMobileConfigBoolean,
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
