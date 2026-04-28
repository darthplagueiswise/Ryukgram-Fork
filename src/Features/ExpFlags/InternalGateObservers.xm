#import "../../Utils.h"
#import "SCIExpFlags.h"
#import <Foundation/Foundation.h>
#import <stdint.h>
#include "../../../modules/fishhook/fishhook.h"

// Extra MobileConfig / EasyGating force hooks for Instagram FBSharedFramework.
//
// Complements src/Features/ExpFlags/InternalModeHooks.xm.
// Do NOT duplicate the existing IGMobileConfigBooleanValueForInternalUse hooks here.
//
// InternalModeHooks.xm already owns:
//   IGMobileConfigBooleanValueForInternalUse
//   IGMobileConfigSessionlessBooleanValueForInternalUse
//   IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18
//
// This file handles the additional exported gate families:
//   MCIMobileConfigGetBoolean
//   MCIExperimentCacheGetMobileConfigBoolean
//   MCIExtensionExperimentCacheGetMobileConfigBoolean
//   METAExtensionsExperimentGetBoolean
//   METAExtensionsExperimentGetBooleanWithoutExposure
//   MSGCSessionedMobileConfigGetBoolean
//   EasyGatingPlatformGetBoolean
//   EasyGatingGetBoolean_Internal_DoNotUseOrMock
//   EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock
//   MCQEasyGatingGetBooleanInternalDoNotUseOrMock
//   MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter
//
// Fishhook symbol names must be passed WITHOUT the leading "_".
// Correct:   "MCIMobileConfigGetBoolean"
// Incorrect: "_MCIMobileConfigGetBoolean"

static BOOL rgObserverEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_internaluse_observer"] ||
           [SCIUtils getBoolPref:@"sci_exp_flags_enabled"];
}

static BOOL rgForceEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_true_patcher"] ||
           [SCIUtils getBoolPref:@"igt_employee_master"] ||
           [SCIUtils getBoolPref:@"igt_employee"] ||
           [SCIUtils getBoolPref:@"igt_employee_mc"] ||
           [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"] ||
           [SCIUtils getBoolPref:@"igt_employee_devoptions_gate"];
}

static BOOL rgShouldInstall(void) {
    return rgObserverEnabled() || rgForceEnabled();
}

static BOOL rgLooksLikeMCSpecifier(uint64_t value) {
    return value != 0 && ((value >> 56) == 0) && ((value >> 48) != 0);
}

static uint64_t rgPickSpecifier(uint64_t preferred,
                                uint64_t a0,
                                uint64_t a1,
                                uint64_t a2,
                                uint64_t a3) {
    if (rgLooksLikeMCSpecifier(preferred)) return preferred;
    if (rgLooksLikeMCSpecifier(a2)) return a2;
    if (rgLooksLikeMCSpecifier(a1)) return a1;
    if (rgLooksLikeMCSpecifier(a3)) return a3;
    if (rgLooksLikeMCSpecifier(a0)) return a0;
    return preferred;
}

static NSString *rgArgLabel(NSString *family, NSString *preferred) {
    return [NSString stringWithFormat:@"%@ · %@", family ?: @"gate", preferred ?: @"arg?"];
}

static BOOL rgApplyForcedValue(uint64_t specifier, BOOL originalValue) {
    SCIExpFlagOverride manual = [SCIExpFlags internalUseOverrideForSpecifier:specifier];

    if (manual == SCIExpFlagOverrideTrue) return YES;
    if (manual == SCIExpFlagOverrideFalse) return NO;

    if (rgForceEnabled()) return YES;

    return originalValue;
}

static void rgRecordGate(NSString *functionName,
                         NSString *label,
                         uint64_t specifier,
                         BOOL defaultValue,
                         BOOL originalValue,
                         BOOL returnedValue,
                         void *caller) {
    BOOL forced = originalValue != returnedValue;

    if (!rgObserverEnabled() && !forced) return;

    [SCIExpFlags recordInternalUseSpecifier:specifier
                               functionName:functionName ?: @"Gate"
                              specifierName:label ?: @"unknown"
                               defaultValue:defaultValue
                                resultValue:returnedValue
                                forcedValue:forced
                              callerAddress:caller];

    if ([SCIUtils getBoolPref:@"igt_internaluse_observer"]) {
        NSLog(@"[RyukGram][GateForce][%@] %@ spec=0x%016llx default=%d original=%d returned=%d forced=%d caller=%p",
              functionName ?: @"Gate",
              label ?: @"unknown",
              specifier,
              defaultValue,
              originalValue,
              returnedValue,
              forced,
              caller);
    }
}

typedef uintptr_t (*RGGenericGateFn)(uintptr_t,
                                     uintptr_t,
                                     uintptr_t,
                                     uintptr_t,
                                     uintptr_t,
                                     uintptr_t,
                                     uintptr_t,
                                     uintptr_t);

static uintptr_t rgBoolReturn(uintptr_t originalRaw,
                              NSString *functionName,
                              NSString *label,
                              uint64_t specifier,
                              BOOL defaultValue,
                              void *caller) {
    BOOL originalValue = originalRaw ? YES : NO;
    BOOL returnedValue = rgApplyForcedValue(specifier, originalValue);

    rgRecordGate(functionName,
                 label,
                 specifier,
                 defaultValue,
                 originalValue,
                 returnedValue,
                 caller);

    return returnedValue ? 1 : 0;
}

// -----------------------------------------------------------------------------
// MCI MobileConfig
// MCIMobileConfigGetBoolean uses x2 as the most important specifier-like arg.
// Cache variants usually follow the same practical family pattern.
// We prefer x2, but fall back through x1/x3/x0.
// -----------------------------------------------------------------------------

static RGGenericGateFn orig_MCIMobileConfigGetBoolean = NULL;

static uintptr_t hook_MCIMobileConfigGetBoolean(uintptr_t a0,
                                                uintptr_t a1,
                                                uintptr_t a2,
                                                uintptr_t a3,
                                                uintptr_t a4,
                                                uintptr_t a5,
                                                uintptr_t a6,
                                                uintptr_t a7) {
    uintptr_t original = orig_MCIMobileConfigGetBoolean ?
        orig_MCIMobileConfigGetBoolean(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    uint64_t specifier = rgPickSpecifier((uint64_t)a2,
                                         (uint64_t)a0,
                                         (uint64_t)a1,
                                         (uint64_t)a2,
                                         (uint64_t)a3);

    return rgBoolReturn(original,
                        @"MCIMobileConfigGetBoolean",
                        rgArgLabel(@"MCI mobileconfig", @"preferred=x2"),
                        specifier,
                        (BOOL)(a2 & 1),
                        __builtin_return_address(0));
}

static RGGenericGateFn orig_MCIExperimentCacheGetMobileConfigBoolean = NULL;

static uintptr_t hook_MCIExperimentCacheGetMobileConfigBoolean(uintptr_t a0,
                                                               uintptr_t a1,
                                                               uintptr_t a2,
                                                               uintptr_t a3,
                                                               uintptr_t a4,
                                                               uintptr_t a5,
                                                               uintptr_t a6,
                                                               uintptr_t a7) {
    uintptr_t original = orig_MCIExperimentCacheGetMobileConfigBoolean ?
        orig_MCIExperimentCacheGetMobileConfigBoolean(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    uint64_t specifier = rgPickSpecifier((uint64_t)a2,
                                         (uint64_t)a0,
                                         (uint64_t)a1,
                                         (uint64_t)a2,
                                         (uint64_t)a3);

    return rgBoolReturn(original,
                        @"MCIExperimentCacheGetMobileConfigBoolean",
                        rgArgLabel(@"MCI experiment cache", @"preferred=x2"),
                        specifier,
                        (BOOL)(a2 & 1),
                        __builtin_return_address(0));
}

static RGGenericGateFn orig_MCIExtensionExperimentCacheGetMobileConfigBoolean = NULL;

static uintptr_t hook_MCIExtensionExperimentCacheGetMobileConfigBoolean(uintptr_t a0,
                                                                        uintptr_t a1,
                                                                        uintptr_t a2,
                                                                        uintptr_t a3,
                                                                        uintptr_t a4,
                                                                        uintptr_t a5,
                                                                        uintptr_t a6,
                                                                        uintptr_t a7) {
    uintptr_t original = orig_MCIExtensionExperimentCacheGetMobileConfigBoolean ?
        orig_MCIExtensionExperimentCacheGetMobileConfigBoolean(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    uint64_t specifier = rgPickSpecifier((uint64_t)a2,
                                         (uint64_t)a0,
                                         (uint64_t)a1,
                                         (uint64_t)a2,
                                         (uint64_t)a3);

    return rgBoolReturn(original,
                        @"MCIExtensionExperimentCacheGetMobileConfigBoolean",
                        rgArgLabel(@"MCI extension cache", @"preferred=x2"),
                        specifier,
                        (BOOL)(a2 & 1),
                        __builtin_return_address(0));
}

// -----------------------------------------------------------------------------
// META Extensions
// These wrappers set w4 = 1 or w4 = 0 and branch into shared dispatch.
// We hook the exported wrappers and prefer x1 for the gate/specifier-like value.
// -----------------------------------------------------------------------------

static RGGenericGateFn orig_METAExtensionsExperimentGetBoolean = NULL;

static uintptr_t hook_METAExtensionsExperimentGetBoolean(uintptr_t a0,
                                                         uintptr_t a1,
                                                         uintptr_t a2,
                                                         uintptr_t a3,
                                                         uintptr_t a4,
                                                         uintptr_t a5,
                                                         uintptr_t a6,
                                                         uintptr_t a7) {
    uintptr_t original = orig_METAExtensionsExperimentGetBoolean ?
        orig_METAExtensionsExperimentGetBoolean(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    uint64_t specifier = rgPickSpecifier((uint64_t)a1,
                                         (uint64_t)a0,
                                         (uint64_t)a1,
                                         (uint64_t)a2,
                                         (uint64_t)a3);

    return rgBoolReturn(original,
                        @"METAExtensionsExperimentGetBoolean",
                        rgArgLabel(@"META extensions exposure", @"preferred=x1"),
                        specifier,
                        (BOOL)(a2 & 1),
                        __builtin_return_address(0));
}

static RGGenericGateFn orig_METAExtensionsExperimentGetBooleanWithoutExposure = NULL;

static uintptr_t hook_METAExtensionsExperimentGetBooleanWithoutExposure(uintptr_t a0,
                                                                        uintptr_t a1,
                                                                        uintptr_t a2,
                                                                        uintptr_t a3,
                                                                        uintptr_t a4,
                                                                        uintptr_t a5,
                                                                        uintptr_t a6,
                                                                        uintptr_t a7) {
    uintptr_t original = orig_METAExtensionsExperimentGetBooleanWithoutExposure ?
        orig_METAExtensionsExperimentGetBooleanWithoutExposure(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    uint64_t specifier = rgPickSpecifier((uint64_t)a1,
                                         (uint64_t)a0,
                                         (uint64_t)a1,
                                         (uint64_t)a2,
                                         (uint64_t)a3);

    return rgBoolReturn(original,
                        @"METAExtensionsExperimentGetBooleanWithoutExposure",
                        rgArgLabel(@"META extensions no-exposure", @"preferred=x1"),
                        specifier,
                        (BOOL)(a2 & 1),
                        __builtin_return_address(0));
}

// -----------------------------------------------------------------------------
// MSGC sessioned MobileConfig
// -----------------------------------------------------------------------------

static RGGenericGateFn orig_MSGCSessionedMobileConfigGetBoolean = NULL;

static uintptr_t hook_MSGCSessionedMobileConfigGetBoolean(uintptr_t a0,
                                                          uintptr_t a1,
                                                          uintptr_t a2,
                                                          uintptr_t a3,
                                                          uintptr_t a4,
                                                          uintptr_t a5,
                                                          uintptr_t a6,
                                                          uintptr_t a7) {
    uintptr_t original = orig_MSGCSessionedMobileConfigGetBoolean ?
        orig_MSGCSessionedMobileConfigGetBoolean(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    uint64_t specifier = rgPickSpecifier((uint64_t)a1,
                                         (uint64_t)a0,
                                         (uint64_t)a1,
                                         (uint64_t)a2,
                                         (uint64_t)a3);

    return rgBoolReturn(original,
                        @"MSGCSessionedMobileConfigGetBoolean",
                        rgArgLabel(@"MSGC sessioned mobileconfig", @"preferred=x1"),
                        specifier,
                        (BOOL)(a2 & 1),
                        __builtin_return_address(0));
}

// -----------------------------------------------------------------------------
// EasyGating
// Raw EasyGating functions often use x0/x1 as gate ids instead of IG MC specifiers.
// We still record those raw ids in the same InternalUse browser.
// -----------------------------------------------------------------------------

static RGGenericGateFn orig_EasyGatingPlatformGetBoolean = NULL;

static uintptr_t hook_EasyGatingPlatformGetBoolean(uintptr_t a0,
                                                   uintptr_t a1,
                                                   uintptr_t a2,
                                                   uintptr_t a3,
                                                   uintptr_t a4,
                                                   uintptr_t a5,
                                                   uintptr_t a6,
                                                   uintptr_t a7) {
    uintptr_t original = orig_EasyGatingPlatformGetBoolean ?
        orig_EasyGatingPlatformGetBoolean(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    uint64_t specifier = rgPickSpecifier((uint64_t)a1,
                                         (uint64_t)a0,
                                         (uint64_t)a1,
                                         (uint64_t)a2,
                                         (uint64_t)a3);

    return rgBoolReturn(original,
                        @"EasyGatingPlatformGetBoolean",
                        rgArgLabel(@"EasyGating platform", @"preferred=x1"),
                        specifier,
                        (BOOL)(a2 & 1),
                        __builtin_return_address(0));
}

static RGGenericGateFn orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock = NULL;

static uintptr_t hook_EasyGatingGetBoolean_Internal_DoNotUseOrMock(uintptr_t gate,
                                                                   uintptr_t a1,
                                                                   uintptr_t defaultValue,
                                                                   uintptr_t a3,
                                                                   uintptr_t a4,
                                                                   uintptr_t a5,
                                                                   uintptr_t a6,
                                                                   uintptr_t a7) {
    uintptr_t original = orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock ?
        orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock(gate, a1, defaultValue, a3, a4, a5, a6, a7) : 0;

    return rgBoolReturn(original,
                        @"EasyGatingGetBoolean_Internal_DoNotUseOrMock",
                        rgArgLabel(@"EasyGating raw gate", @"preferred=x0"),
                        (uint64_t)gate,
                        (BOOL)(defaultValue & 1),
                        __builtin_return_address(0));
}

static RGGenericGateFn orig_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock = NULL;

static uintptr_t hook_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock(uintptr_t a0,
                                                                                       uintptr_t gate,
                                                                                       uintptr_t defaultValue,
                                                                                       uintptr_t authCtx,
                                                                                       uintptr_t a4,
                                                                                       uintptr_t a5,
                                                                                       uintptr_t a6,
                                                                                       uintptr_t a7) {
    uintptr_t original = orig_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock ?
        orig_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock(a0, gate, defaultValue, authCtx, a4, a5, a6, a7) : 0;

    return rgBoolReturn(original,
                        @"EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
                        rgArgLabel(@"EasyGating auth-data raw gate", @"preferred=x1"),
                        (uint64_t)gate,
                        (BOOL)(defaultValue & 1),
                        __builtin_return_address(0));
}

// -----------------------------------------------------------------------------
// MCQ EasyGating
// This is NOT a clean BOOL return. It returns status and writes the boolean into
// an output pointer. We preserve original status and force only *outValue.
// -----------------------------------------------------------------------------

typedef int (*RGMCQEasyGatingFn)(uintptr_t,
                                 unsigned int,
                                 uintptr_t,
                                 uintptr_t,
                                 unsigned char *);

static RGMCQEasyGatingFn orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock = NULL;

static int hook_MCQEasyGatingGetBooleanInternalDoNotUseOrMock(uintptr_t a0,
                                                              unsigned int gate,
                                                              uintptr_t a2,
                                                              uintptr_t defaultValue,
                                                              unsigned char *outValue) {
    int status = orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock ?
        orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock(a0, gate, a2, defaultValue, outValue) : 0;

    BOOL originalValue = outValue ? (*outValue ? YES : NO) : (status == 0);
    BOOL returnedValue = rgApplyForcedValue((uint64_t)gate, originalValue);

    if (outValue) {
        *outValue = returnedValue ? 1 : 0;
    }

    rgRecordGate(@"MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
                 rgArgLabel(@"MCQ EasyGating raw gate", @"x1 result=*x4"),
                 (uint64_t)gate,
                 (BOOL)(defaultValue & 1),
                 originalValue,
                 returnedValue,
                 __builtin_return_address(0));

    return status;
}

// -----------------------------------------------------------------------------
// DVM/DASM adapter
// Do not force this directly yet. It reads/writes through DVM/DASM support stack,
// not a clean C bool signature. Returning 1 directly here is crash-prone.
// -----------------------------------------------------------------------------

static RGGenericGateFn orig_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter = NULL;

static uintptr_t hook_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter(uintptr_t a0,
                                                                      uintptr_t a1,
                                                                      uintptr_t a2,
                                                                      uintptr_t a3,
                                                                      uintptr_t a4,
                                                                      uintptr_t a5,
                                                                      uintptr_t a6,
                                                                      uintptr_t a7) {
    uintptr_t original = orig_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter ?
        orig_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter(a0, a1, a2, a3, a4, a5, a6, a7) : 0;

    BOOL originalValue = original ? YES : NO;

    rgRecordGate(@"MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",
                 rgArgLabel(@"DASM/DVM adapter", @"VM stack · observe-only"),
                 0,
                 NO,
                 originalValue,
                 originalValue,
                 __builtin_return_address(0));

    return original;
}

// -----------------------------------------------------------------------------
// Install
// -----------------------------------------------------------------------------

%ctor {
    if (!rgShouldInstall()) return;

    struct rebinding binds[] = {
        {
            "MCIMobileConfigGetBoolean",
            (void *)hook_MCIMobileConfigGetBoolean,
            (void **)&orig_MCIMobileConfigGetBoolean
        },
        {
            "MCIExperimentCacheGetMobileConfigBoolean",
            (void *)hook_MCIExperimentCacheGetMobileConfigBoolean,
            (void **)&orig_MCIExperimentCacheGetMobileConfigBoolean
        },
        {
            "MCIExtensionExperimentCacheGetMobileConfigBoolean",
            (void *)hook_MCIExtensionExperimentCacheGetMobileConfigBoolean,
            (void **)&orig_MCIExtensionExperimentCacheGetMobileConfigBoolean
        },
        {
            "METAExtensionsExperimentGetBoolean",
            (void *)hook_METAExtensionsExperimentGetBoolean,
            (void **)&orig_METAExtensionsExperimentGetBoolean
        },
        {
            "METAExtensionsExperimentGetBooleanWithoutExposure",
            (void *)hook_METAExtensionsExperimentGetBooleanWithoutExposure,
            (void **)&orig_METAExtensionsExperimentGetBooleanWithoutExposure
        },
        {
            "MSGCSessionedMobileConfigGetBoolean",
            (void *)hook_MSGCSessionedMobileConfigGetBoolean,
            (void **)&orig_MSGCSessionedMobileConfigGetBoolean
        },
        {
            "EasyGatingPlatformGetBoolean",
            (void *)hook_EasyGatingPlatformGetBoolean,
            (void **)&orig_EasyGatingPlatformGetBoolean
        },
        {
            "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
            (void *)hook_EasyGatingGetBoolean_Internal_DoNotUseOrMock,
            (void **)&orig_EasyGatingGetBoolean_Internal_DoNotUseOrMock
        },
        {
            "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
            (void *)hook_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock,
            (void **)&orig_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock
        },
        {
            "MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
            (void *)hook_MCQEasyGatingGetBooleanInternalDoNotUseOrMock,
            (void **)&orig_MCQEasyGatingGetBooleanInternalDoNotUseOrMock
        },
        {
            "MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",
            (void *)hook_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter,
            (void **)&orig_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter
        }
    };

    int rc = rebind_symbols(binds, sizeof(binds) / sizeof(binds[0]));

    NSLog(@"[RyukGram][GateForce] installed rc=%d force=%d observer=%d mci=%p mciCache=%p mciExt=%p meta=%p metaNoExposure=%p msgc=%p egPlatform=%p egInternal=%p egAuth=%p mcq=%p dvm=%p",
          rc,
          rgForceEnabled(),
          rgObserverEnabled(),
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
