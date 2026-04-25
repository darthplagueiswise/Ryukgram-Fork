#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <libkern/OSCacheControl.h>
#import <sys/mman.h>
#import <unistd.h>

// Experimental runtime patcher for MobileConfig boolean gates.
// Default OFF. Enable the master toggle and then one or more per-symbol toggles.
// Strict mode is default: first 8 bytes must match the captured pattern.
// Optional relaxed mode is controlled by igt_runtime_mc_true_patcher_relaxed.

typedef struct {
    const char *symbol;
    uint64_t orig8;
    const char *prefKey;
} RGMC_PatchSpec;

// ARM64: mov w0,#1 ; ret
static const uint64_t kRGStubTrue = 0xd65f03c052800020ULL;

static const RGMC_PatchSpec kRGMCPatches[] = {
    {"_IGMobileConfigBooleanValueForInternalUse", 0xa90157f6a9bc5ff8ULL, "igt_runtime_mc_patch_ig_internaluse"},
    {"_IGMobileConfigForceUpdateConfigs", 0x97e1c552a9bf7bfdULL, "igt_runtime_mc_patch_ig_force_update"},
    {"_IGMobileConfigSetConfigOverrides", 0x97e1c70ea9bf7bfdULL, "igt_runtime_mc_patch_ig_set_overrides"},
    {"_IGMobileConfigTryUpdateConfigsWithCompletion", 0x140b9f5c52800004ULL, "igt_runtime_mc_patch_ig_try_update"},

    {"_MCIMobileConfigGetBoolean", 0xa9014ff4a9bd57f6ULL, "igt_runtime_mc_patch_mci_bool"},
    {"_METAExtensionsExperimentGetBoolean", 0, "igt_runtime_mc_patch_meta_ext_bool"},
    {"_METAExtensionsExperimentGetBooleanWithoutExposure", 0, "igt_runtime_mc_patch_meta_ext_bool_noexp"},
    {"_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock", 0xa9014ff4a9bd57f6ULL, "igt_runtime_mc_patch_mcqmem_cql_bool"},
    {"_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock", 0xa9014ff4a9bd57f6ULL, "igt_runtime_mc_patch_mem_capability_bool"},
    {"_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock", 0xa9014ff4a9bd57f6ULL, "igt_runtime_mc_patch_mem_devconfig_bool"},
    {"_MEMMobileConfigPlatformGetBoolean", 0x72aeec04528a16c4ULL, "igt_runtime_mc_patch_mem_platform_bool"},
    {"_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock", 0xa9014ff4a9bd57f6ULL, "igt_runtime_mc_patch_mem_protocol_bool"},
};

static BOOL RGMCEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_true_patcher"];
}

static BOOL RGMCRelaxed(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_true_patcher_relaxed"];
}

static BOOL RGMCSpecEnabled(const RGMC_PatchSpec *spec) {
    if (!spec || !spec->prefKey) return NO;
    NSString *key = [NSString stringWithUTF8String:spec->prefKey];
    return [SCIUtils getBoolPref:key];
}

static void *RGDlsymFlexible(const char *symbol) {
    if (!symbol || !symbol[0]) return NULL;

    void *sym = dlsym(RTLD_DEFAULT, symbol);
    if (sym) return sym;

    if (symbol[0] == '_') {
        sym = dlsym(RTLD_DEFAULT, symbol + 1);
        if (sym) return sym;
    } else {
        char underscored[512];
        snprintf(underscored, sizeof(underscored), "_%s", symbol);
        sym = dlsym(RTLD_DEFAULT, underscored);
        if (sym) return sym;
    }

    return NULL;
}

static BOOL RGPatchOneSymbol(const RGMC_PatchSpec *spec, BOOL relaxed) {
    if (!spec || !spec->symbol) return NO;

    void *sym = RGDlsymFlexible(spec->symbol);
    if (!sym) {
        NSLog(@"[RyukGram][RGMC] symbol not found: %s", spec->symbol);
        return NO;
    }

    uint8_t *p = (uint8_t *)sym;
    uint64_t cur = 0;
    memcpy(&cur, p, sizeof(cur));

    if (cur == kRGStubTrue) {
        NSLog(@"[RyukGram][RGMC] already patched: %s pref=%s", spec->symbol, spec->prefKey ?: "");
        return YES;
    }

    if (!relaxed && spec->orig8 != 0 && cur != spec->orig8) {
        NSLog(@"[RyukGram][RGMC] pattern mismatch: %s cur=0x%016llx expected=0x%016llx; skipped pref=%s",
              spec->symbol,
              (unsigned long long)cur,
              (unsigned long long)spec->orig8,
              spec->prefKey ?: "");
        return NO;
    }

    long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) pageSize = 0x4000;

    uintptr_t addr = (uintptr_t)p;
    uintptr_t page = addr & ~((uintptr_t)pageSize - 1);

    if (mprotect((void *)page, (size_t)pageSize, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        NSLog(@"[RyukGram][RGMC] mprotect RWX failed: %s errno=%d pref=%s", spec->symbol, errno, spec->prefKey ?: "");
        return NO;
    }

    memcpy(p, &kRGStubTrue, sizeof(kRGStubTrue));
    sys_icache_invalidate(p, sizeof(kRGStubTrue));

    if (mprotect((void *)page, (size_t)pageSize, PROT_READ | PROT_EXEC) != 0) {
        NSLog(@"[RyukGram][RGMC] mprotect RX failed after patch: %s errno=%d pref=%s", spec->symbol, errno, spec->prefKey ?: "");
    }

    uint64_t verify = 0;
    memcpy(&verify, p, sizeof(verify));
    BOOL ok = (verify == kRGStubTrue);
    NSLog(@"[RyukGram][RGMC] %@: %s cur=0x%016llx relaxed=%d pref=%s",
          ok ? @"patched" : @"patch-verify-failed",
          spec->symbol,
          (unsigned long long)cur,
          relaxed,
          spec->prefKey ?: "");
    return ok;
}

%ctor {
    if (!RGMCEnabled()) return;

    BOOL relaxed = RGMCRelaxed();
    NSUInteger okCount = 0;
    NSUInteger selected = 0;
    NSUInteger total = sizeof(kRGMCPatches) / sizeof(kRGMCPatches[0]);

    NSLog(@"[RyukGram][RGMC] runtime MobileConfig true patcher master enabled; relaxed=%d total=%lu", relaxed, (unsigned long)total);
    for (NSUInteger i = 0; i < total; i++) {
        const RGMC_PatchSpec *spec = &kRGMCPatches[i];
        if (!RGMCSpecEnabled(spec)) {
            NSLog(@"[RyukGram][RGMC] disabled by toggle: %s pref=%s", spec->symbol, spec->prefKey ?: "");
            continue;
        }
        selected++;
        if (RGPatchOneSymbol(spec, relaxed)) okCount++;
    }
    NSLog(@"[RyukGram][RGMC] runtime patcher finished selected=%lu ok=%lu/%lu", (unsigned long)selected, (unsigned long)okCount, (unsigned long)total);
}
