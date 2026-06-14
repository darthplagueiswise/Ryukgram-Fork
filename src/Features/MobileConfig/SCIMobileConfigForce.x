// SCIMobileConfigForce.x — force MobileConfig BOOL getters to YES via fishhook.
//
// Why: Instagram gates its [ig-only] / [internal-only] features behind
// MobileConfig boolean reads. Patching those functions on disk to `mov w0,#1; ret`
// does enable the features, but it breaks the code signature and is unusable for
// sideload. fishhook rebinds the GOT entries in-process at runtime instead — the
// binary on disk is never touched, so there is no signing problem (baseline §5).
//
// All targets were validated against this exact build:
//   • imported by Instagram   — otool -arch arm64 -Iv Instagram
//   • defined in FBSharedFramework, return BOOL in w0 — llvm-objdump --syms +
//     capstone disassembly of each function prologue/epilogue.
// Because each replacement returns a constant, it is ABI-safe regardless of the
// callee's real arity: the args (x0..x3 / stack) are ignored and 1 is returned in
// w0. The flag is latched once in %ctor; the hot path never reads NSUserDefaults.
//
// ⚠️ Risk tiers (opt-in, all default OFF):
//   - InternalUse / MCI / MSGC boolean getters: scoped to internal-feature reads,
//     comparatively safe.
//   - MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter is the UNIVERSAL native
//     boolean reader: forcing it makes every boolean config (including
//     killswitches) read YES, which can trip the launch watchdog. It is wired
//     only under the explicit "all BOOL gates" master, never on by default.

#import <Foundation/Foundation.h>
#import "../../Utils.h"
#include "../../../modules/fishhook/fishhook.h"

// Superset signature: safe for any callee arity, constant BOOL return in w0.
typedef BOOL (*mc_bool_fn)(void *, void *, void *, void *);

#define MC_FORCE(fn) \
	static mc_bool_fn orig_##fn = NULL; \
	static BOOL repl_##fn(void *a, void *b, void *c, void *d) { return YES; }

MC_FORCE(IGMobileConfigBooleanValueForInternalUse)
MC_FORCE(MCIExperimentCacheGetMobileConfigBoolean)
MC_FORCE(MCIExtensionExperimentCacheGetMobileConfigBoolean)
MC_FORCE(MSGCSessionedMobileConfigGetBoolean)
MC_FORCE(MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter)

%ctor {
	@autoreleasepool {
		BOOL master   = [SCIUtils getBoolPref:@"sci_force_all_mc_gates"];
		BOOL internal = master || [SCIUtils getBoolPref:@"sci_force_mc_internal_use_boolean"];
		BOOL sessAll  = master || [SCIUtils getBoolPref:@"sci_force_sessioned_mc_all"];
		BOOL msgc     = sessAll || [SCIUtils getBoolPref:@"sci_force_msgc_sessioned_boolean"];
		BOOL mciExp   = sessAll || [SCIUtils getBoolPref:@"sci_force_mci_experiment_boolean"];
		BOOL mciExt   = sessAll || [SCIUtils getBoolPref:@"sci_force_mci_extension_boolean"];
		// Universal adapter: ONLY under the explicit "all BOOL gates" master.
		BOOL universal = master || [SCIUtils getBoolPref:@"sci_force_mc_internal_use_all"];

		struct rebinding r[5];
		size_t n = 0;
		if (internal)
			r[n++] = (struct rebinding){"IGMobileConfigBooleanValueForInternalUse",
				(void *)repl_IGMobileConfigBooleanValueForInternalUse,
				(void **)&orig_IGMobileConfigBooleanValueForInternalUse};
		if (mciExp)
			r[n++] = (struct rebinding){"MCIExperimentCacheGetMobileConfigBoolean",
				(void *)repl_MCIExperimentCacheGetMobileConfigBoolean,
				(void **)&orig_MCIExperimentCacheGetMobileConfigBoolean};
		if (mciExt)
			r[n++] = (struct rebinding){"MCIExtensionExperimentCacheGetMobileConfigBoolean",
				(void *)repl_MCIExtensionExperimentCacheGetMobileConfigBoolean,
				(void **)&orig_MCIExtensionExperimentCacheGetMobileConfigBoolean};
		if (msgc)
			r[n++] = (struct rebinding){"MSGCSessionedMobileConfigGetBoolean",
				(void *)repl_MSGCSessionedMobileConfigGetBoolean,
				(void **)&orig_MSGCSessionedMobileConfigGetBoolean};
		if (universal)
			r[n++] = (struct rebinding){"MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",
				(void *)repl_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter,
				(void **)&orig_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter};

		if (n > 0) rebind_symbols(r, n);
	}
}
