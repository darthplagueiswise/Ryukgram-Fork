#import "../../Utils.h"
#import "SCIExpFlags.h"
#import "SCIExpMobileConfigMapping.h"
#import "SCIMobileConfigMapping.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

// C broker hooks for MobileConfig-ish boolean gates.
// Default behavior: hook only when the explicit MC C hooks toggle is enabled.
// Verbose logging is separate so normal override testing does not spam console.

static BOOL RGMCBoolObserverEnabled(void) {
    return [SCIUtils getBoolPref:@"sci_exp_mc_c_hooks_enabled"] ||
           [SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer_verbose"] ||
           [SCIUtils getBoolPref:@"igt_runtime_mc_true_patcher"];
}

static BOOL RGMCVerboseLoggingEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_symbol_observer_verbose"];
}

static NSString *RGMCHexKey(unsigned long long pid) {
    return [NSString stringWithFormat:@"mc:0x%016llx", pid];
}

static NSString *RGMCResolvedName(unsigned long long pid) {
    NSString *mapped = [SCIMobileConfigMapping resolvedNameForParamID:pid];
    if (mapped.length) return mapped;
    mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:pid];
    return mapped.length ? mapped : nil;
}

static SCIExpFlagOverride RGMCOverrideForCandidate(const char *symbol, unsigned long long pid) {
    NSString *mapped = RGMCResolvedName(pid);
    if (mapped.length) {
        SCIExpFlagOverride ov = [SCIExpFlags overrideForName:mapped];
        if (ov != SCIExpFlagOverrideOff) return ov;
    }

    if (pid != 0) {
        SCIExpFlagOverride byHex = [SCIExpFlags overrideForName:RGMCHexKey(pid)];
        if (byHex != SCIExpFlagOverrideOff) return byHex;
    }

    if (symbol) {
        NSString *sym = [NSString stringWithUTF8String:symbol];
        if (sym.length) {
            SCIExpFlagOverride bySym = [SCIExpFlags overrideForName:sym];
            if (bySym != SCIExpFlagOverrideOff) return bySym;

            if ([sym hasPrefix:@"_"]) {
                SCIExpFlagOverride byNoUnderscore = [SCIExpFlags overrideForName:[sym substringFromIndex:1]];
                if (byNoUnderscore != SCIExpFlagOverrideOff) return byNoUnderscore;
            }
        }
    }

    return SCIExpFlagOverrideOff;
}

static BOOL RGMCApplyOverride(SCIExpFlagOverride ov, BOOL original) {
    if (ov == SCIExpFlagOverrideTrue) return YES;
    if (ov == SCIExpFlagOverrideFalse) return NO;
    return original;
}

static NSString *RGMCOverrideText(SCIExpFlagOverride ov) {
    if (ov == SCIExpFlagOverrideTrue) return @"ForceON";
    if (ov == SCIExpFlagOverrideFalse) return @"ForceOFF";
    return @"Off";
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


static NSMutableDictionary<NSString *, NSNumber *> *RGMCRecordCounts(void) {
    static NSMutableDictionary<NSString *, NSNumber *> *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

static BOOL RGMCShouldRecordC(const char *symbol, unsigned long long candidate) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.mc.c.throttle", DISPATCH_QUEUE_SERIAL); });

    NSString *sym = symbol ? [NSString stringWithUTF8String:symbol] : @"unknown";
    NSString *key = [NSString stringWithFormat:@"%@:%016llx", sym, candidate];

    __block NSUInteger count = 0;
    dispatch_sync(q, ^{
        NSMutableDictionary *d = RGMCRecordCounts();
        count = [d[key] unsignedIntegerValue] + 1;
        d[key] = @(count);
    });

    return count <= 2 || (count % 2048) == 0;
}

static BOOL RGRecordCBooleanObservation(const char *symbol, BOOL original, uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, void *caller) {
    unsigned long long candidate = RGMCBestSpecifierCandidate(a0, a1, a2, a3, a4, a5);

    // Hot path: most calls must return immediately. Mapping/name resolution happens only on sampled calls.
    if (!RGMCShouldRecordC(symbol, candidate)) {
        return original;
    }

    NSString *mappedName = RGMCResolvedName(candidate);
    SCIExpFlagOverride ov = RGMCOverrideForCandidate(symbol, candidate);
    BOOL finalValue = RGMCApplyOverride(ov, original);

    NSString *sym = symbol ? [NSString stringWithUTF8String:symbol] : @"unknown";
    NSString *source = RGMCSourceForSymbol(symbol);
    NSString *namePart = mappedName.length ? [NSString stringWithFormat:@" · name=%@", mappedName] : (candidate == 0 && sym.length ? [NSString stringWithFormat:@" · name=%@", sym] : @"");
    NSString *def = [NSString stringWithFormat:@"source=%@ · symbol=%@%@ · original=%d · final=%d · override=%@ · shadowTrue=1 · wouldChangeIfTrue=%d · id=0x%llx · a0=0x%lx a1=0x%lx a2=0x%lx a3=0x%lx a4=0x%lx a5=0x%lx · caller=%p",
                     source,
                     sym,
                     namePart,
                     original,
                     finalValue,
                     RGMCOverrideText(ov),
                     original ? 0 : 1,
                     candidate,
                     (unsigned long)a0,
                     (unsigned long)a1,
                     (unsigned long)a2,
                     (unsigned long)a3,
                     (unsigned long)a4,
                     (unsigned long)a5,
                     caller];

    [SCIExpFlags recordMCParamID:candidate
                            type:SCIExpMCTypeBool
                    defaultValue:def
                   originalValue:original ? @"YES" : @"NO"
                    contextClass:nil
                    selectorName:sym];

    if (RGMCVerboseLoggingEnabled()) {
        NSLog(@"[RyukGram][MCSymbolObserver][%@] %@ name=%@ original=%d final=%d override=%@ candidate=0x%016llx caller=%p",
              source,
              sym,
              mappedName ?: @"",
              original,
              finalValue,
              RGMCOverrideText(ov),
              candidate,
              caller);
    }
    return finalValue;
}

typedef BOOL (*RGMCBoolRawFn)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);

#define RG_DECLARE_BOOL_OBSERVER(KEY, SYMBOL) \
    static RGMCBoolRawFn orig_##KEY = NULL; \
    static BOOL hook_##KEY(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5) { \
        BOOL original = orig_##KEY ? orig_##KEY(a0, a1, a2, a3, a4, a5) : NO; \
        return RGRecordCBooleanObservation(SYMBOL, original, a0, a1, a2, a3, a4, a5, __builtin_return_address(0)); \
    }

RG_DECLARE_BOOL_OBSERVER(IGMobileConfigBooleanValueForInternalUse, "_IGMobileConfigBooleanValueForInternalUse")
RG_DECLARE_BOOL_OBSERVER(IGMobileConfigSessionlessBooleanValueForInternalUse, "_IGMobileConfigSessionlessBooleanValueForInternalUse")
RG_DECLARE_BOOL_OBSERVER(IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18, "_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18")
RG_DECLARE_BOOL_OBSERVER(EasyGatingGetBoolean_Internal_DoNotUseOrMock, "_EasyGatingGetBoolean_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(EasyGatingPlatformGetBoolean, "_EasyGatingPlatformGetBoolean")
RG_DECLARE_BOOL_OBSERVER(EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock, "_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MCQEasyGatingGetBooleanInternalDoNotUseOrMock, "_MCQEasyGatingGetBooleanInternalDoNotUseOrMock")
RG_DECLARE_BOOL_OBSERVER(MCIMobileConfigGetBoolean, "_MCIMobileConfigGetBoolean")
RG_DECLARE_BOOL_OBSERVER(MCIExperimentCacheGetMobileConfigBoolean, "_MCIExperimentCacheGetMobileConfigBoolean")
RG_DECLARE_BOOL_OBSERVER(MCIExtensionExperimentCacheGetMobileConfigBoolean, "_MCIExtensionExperimentCacheGetMobileConfigBoolean")
RG_DECLARE_BOOL_OBSERVER(MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter, "_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter")
RG_DECLARE_BOOL_OBSERVER(METAExtensionsExperimentGetBoolean, "_METAExtensionsExperimentGetBoolean")
RG_DECLARE_BOOL_OBSERVER(METAExtensionsExperimentGetBooleanWithoutExposure, "_METAExtensionsExperimentGetBooleanWithoutExposure")
RG_DECLARE_BOOL_OBSERVER(MSGCSessionedMobileConfigGetBoolean, "_MSGCSessionedMobileConfigGetBoolean")
RG_DECLARE_BOOL_OBSERVER(MEBIsMinosDogfoodMekEncryptionVersionEnabled, "_MEBIsMinosDogfoodMekEncryptionVersionEnabled")
RG_DECLARE_BOOL_OBSERVER(IGDirectNotesFriendMapEnabled, "_IGDirectNotesFriendMapEnabled")
RG_DECLARE_BOOL_OBSERVER(IGDirectNotesEnableAudioNoteReplyType, "_IGDirectNotesEnableAudioNoteReplyType")
RG_DECLARE_BOOL_OBSERVER(IGDirectNotesEnableAvatarReplyTypes, "_IGDirectNotesEnableAvatarReplyTypes")
RG_DECLARE_BOOL_OBSERVER(IGDirectNotesEnableGifsStickersReplyTypes, "_IGDirectNotesEnableGifsStickersReplyTypes")
RG_DECLARE_BOOL_OBSERVER(IGDirectNotesEnablePhotoNoteReplyType, "_IGDirectNotesEnablePhotoNoteReplyType")
RG_DECLARE_BOOL_OBSERVER(IGTabBarStyleForLauncherSet, "_IGTabBarStyleForLauncherSet")
RG_DECLARE_BOOL_OBSERVER(IGTabBarShouldEnableBlurDebugListener, "_IGTabBarShouldEnableBlurDebugListener")
RG_DECLARE_BOOL_OBSERVER(IGTabBarDynamicSizingEnabled, "_IGTabBarDynamicSizingEnabled")
RG_DECLARE_BOOL_OBSERVER(IGTabBarHomecomingWithFloatingTabEnabled, "_IGTabBarHomecomingWithFloatingTabEnabled")
RG_DECLARE_BOOL_OBSERVER(IGTabBarEnhancedDynamicSizingEnabled, "_IGTabBarEnhancedDynamicSizingEnabled")

#define RG_REBIND(KEY, SYMBOL) {SYMBOL, (void *)hook_##KEY, (void **)&orig_##KEY}

%ctor {
    if (!RGMCBoolObserverEnabled()) return;

    struct rebinding rebindings[] = {
        RG_REBIND(IGMobileConfigBooleanValueForInternalUse, "IGMobileConfigBooleanValueForInternalUse"),
        RG_REBIND(IGMobileConfigSessionlessBooleanValueForInternalUse, "IGMobileConfigSessionlessBooleanValueForInternalUse"),
        RG_REBIND(IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18, "IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18"),
        RG_REBIND(EasyGatingGetBoolean_Internal_DoNotUseOrMock, "EasyGatingGetBoolean_Internal_DoNotUseOrMock"),
        RG_REBIND(EasyGatingPlatformGetBoolean, "EasyGatingPlatformGetBoolean"),
        RG_REBIND(EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock, "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock"),
        RG_REBIND(MCQEasyGatingGetBooleanInternalDoNotUseOrMock, "MCQEasyGatingGetBooleanInternalDoNotUseOrMock"),
        RG_REBIND(MCIMobileConfigGetBoolean, "MCIMobileConfigGetBoolean"),
        RG_REBIND(MCIExperimentCacheGetMobileConfigBoolean, "MCIExperimentCacheGetMobileConfigBoolean"),
        RG_REBIND(MCIExtensionExperimentCacheGetMobileConfigBoolean, "MCIExtensionExperimentCacheGetMobileConfigBoolean"),
        RG_REBIND(MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter, "MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter"),
        RG_REBIND(METAExtensionsExperimentGetBoolean, "METAExtensionsExperimentGetBoolean"),
        RG_REBIND(METAExtensionsExperimentGetBooleanWithoutExposure, "METAExtensionsExperimentGetBooleanWithoutExposure"),
        RG_REBIND(MSGCSessionedMobileConfigGetBoolean, "MSGCSessionedMobileConfigGetBoolean"),
        RG_REBIND(MEBIsMinosDogfoodMekEncryptionVersionEnabled, "MEBIsMinosDogfoodMekEncryptionVersionEnabled"),
        RG_REBIND(IGDirectNotesFriendMapEnabled, "IGDirectNotesFriendMapEnabled"),
        RG_REBIND(IGDirectNotesEnableAudioNoteReplyType, "IGDirectNotesEnableAudioNoteReplyType"),
        RG_REBIND(IGDirectNotesEnableAvatarReplyTypes, "IGDirectNotesEnableAvatarReplyTypes"),
        RG_REBIND(IGDirectNotesEnableGifsStickersReplyTypes, "IGDirectNotesEnableGifsStickersReplyTypes"),
        RG_REBIND(IGDirectNotesEnablePhotoNoteReplyType, "IGDirectNotesEnablePhotoNoteReplyType"),
        RG_REBIND(IGTabBarStyleForLauncherSet, "IGTabBarStyleForLauncherSet"),
        RG_REBIND(IGTabBarShouldEnableBlurDebugListener, "IGTabBarShouldEnableBlurDebugListener"),
        RG_REBIND(IGTabBarDynamicSizingEnabled, "IGTabBarDynamicSizingEnabled"),
        RG_REBIND(IGTabBarHomecomingWithFloatingTabEnabled, "IGTabBarHomecomingWithFloatingTabEnabled"),
        RG_REBIND(IGTabBarEnhancedDynamicSizingEnabled, "IGTabBarEnhancedDynamicSizingEnabled"),
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][MCSymbolObserver] C MobileConfig hooks rc=%d", rc);
}
