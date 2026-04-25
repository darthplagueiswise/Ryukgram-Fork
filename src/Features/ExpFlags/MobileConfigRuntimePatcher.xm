#import "../../Utils.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/mman.h>
#import <unistd.h>

// Experimental runtime patcher for MobileConfig boolean gates.
// Default OFF. Enable with igt_runtime_mc_true_patcher and restart.
// Strict mode is default: first 8 bytes must match the captured pattern.
// Optional relaxed mode is controlled by igt_runtime_mc_true_patcher_relaxed.

typedef struct {
    const char *symbol;
    uint64_t orig8;
} RGMC_PatchSpec;

// ARM64: mov w0,#1 ; ret
static const uint64_t kRGStubTrue = 0xd65f03c052800020ULL;

static const RGMC_PatchSpec kRGMCPatches[] = {
    {"_IGMobileConfigBooleanValueForInternalUse", 0xa90157f6a9bc5ff8ULL},
    {"_IGMobileConfigForceUpdateConfigs", 0x97e1c552a9bf7bfdULL},
    {"_IGMobileConfigSetConfigOverrides", 0x97e1c70ea9bf7bfdULL},
    {"_IGMobileConfigTryUpdateConfigsWithCompletion", 0x140b9f5c52800004ULL},

    {"_MCIMobileConfigGetBoolean", 0xa9014ff4a9bd57f6ULL},
    {"_METAExtensionsExperimentGetBoolean", 0},
    {"_METAExtensionsExperimentGetBooleanWithoutExposure", 0},
    {"_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock", 0xa9014ff4a9bd57f6ULL},
    {"_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock", 0xa9014ff4a9bd57f6ULL},
    {"_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock", 0xa9014ff4a9bd57f6ULL},
    {"_MEMMobileConfigPlatformGetBoolean", 0x72aeec04528a16c4ULL},
    {"_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock", 0xa9014ff4a9bd57f6ULL},
};

static BOOL RGMCEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_true_patcher"];
}

static BOOL RGMCRelaxed(void) {
    return [SCIUtils getBoolPref:@"igt_runtime_mc_true_patcher_relaxed"];
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
        NSLog(@"[RyukGram][RGMC] already patched: %s", spec->symbol);
        return YES;
    }

    if (!relaxed && spec->orig8 != 0 && cur != spec->orig8) {
        NSLog(@"[RyukGram][RGMC] pattern mismatch: %s cur=0x%016llx expected=0x%016llx; skipped",
              spec->symbol,
              (unsigned long long)cur,
              (unsigned long long)spec->orig8);
        return NO;
    }

    long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) pageSize = 0x4000;

    uintptr_t addr = (uintptr_t)p;
    uintptr_t page = addr & ~((uintptr_t)pageSize - 1);

    if (mprotect((void *)page, (size_t)pageSize, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        NSLog(@"[RyukGram][RGMC] mprotect RWX failed: %s errno=%d", spec->symbol, errno);
        return NO;
    }

    memcpy(p, &kRGStubTrue, sizeof(kRGStubTrue));
    __builtin___clear_cache((char *)p, (char *)(p + sizeof(kRGStubTrue)));

    if (mprotect((void *)page, (size_t)pageSize, PROT_READ | PROT_EXEC) != 0) {
        NSLog(@"[RyukGram][RGMC] mprotect RX failed after patch: %s errno=%d", spec->symbol, errno);
    }

    uint64_t verify = 0;
    memcpy(&verify, p, sizeof(verify));
    BOOL ok = (verify == kRGStubTrue);
    NSLog(@"[RyukGram][RGMC] %@: %s cur=0x%016llx relaxed=%d",
          ok ? @"patched" : @"patch-verify-failed",
          spec->symbol,
          (unsigned long long)cur,
          relaxed);
    return ok;
}

%ctor {
    if (!RGMCEnabled()) return;

    BOOL relaxed = RGMCRelaxed();
    NSUInteger okCount = 0;
    NSUInteger total = sizeof(kRGMCPatches) / sizeof(kRGMCPatches[0]);

    NSLog(@"[RyukGram][RGMC] runtime MobileConfig true patcher enabled; relaxed=%d total=%lu", relaxed, (unsigned long)total);
    for (NSUInteger i = 0; i < total; i++) {
        if (RGPatchOneSymbol(&kRGMCPatches[i], relaxed)) okCount++;
    }
    NSLog(@"[RyukGram][RGMC] runtime patcher finished ok=%lu/%lu", (unsigned long)okCount, (unsigned long)total);
}
