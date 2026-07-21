// Shared MobileConfig / EasyGating bridge for Instagram + FBSharedFramework.
//
// ig_is_employee and ig_is_employee_or_test_user are DATA descriptors. Their
// first u32 is the per-build evaluator index. The two replacements below call
// the real evaluator first and force true only when that exact index matches.
// fishhook is registered in the tweak constructor and applies to future-loaded
// images, so identity is covered before user-session construction without dyld
// image scans, ObjC class scans, delayed retries, or preference reads on the
// evaluator hot path.
#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import <dlfcn.h>
#import <os/log.h>
#import <stdatomic.h>
#import <stdint.h>
#import "../../SCIFileLog.h"
#import "../../Utils.h"
#import "../Dogfooding/SCIInternalGatePrefs.h"

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] CurrentC " fmt,##__VA_ARGS__)

typedef bool (*Bool8)(void *, void *, void *, void *, void *, void *, void *, void *);
typedef bool (*Bool0)(void);

static Bool8 oEasyInternal, oEasyAuth, oEasyMCQ, oEasyPlatform;
static Bool8 oMSGC, oMCIExp, oMCIExt, oMetaExt, oMetaExtNoExposure;
static Bool0 oInternalApps, oMinos;

static atomic_bool sEmployeeGateEnabled;
static atomic_bool sEmployeeIndexResolved;
static atomic_bool sEmployeeOrTestIndexResolved;
static atomic_uint sEmployeeIndex;
static atomic_uint sEmployeeOrTestIndex;
static atomic_uint sEmployeeHitMask;

static atomic_bool sForceInternalApps;
static atomic_bool sForceMinos;
static atomic_bool sForceSessionedAll;
static atomic_bool sForceMSGC;
static atomic_bool sForceMCIExp;
static atomic_bool sForceMCIExt;
static atomic_bool sForceMetaExt;

static atomic_bool sGateCapture;
static atomic_int sGateCaptureCount;

static inline BOOL SCIReadPref(NSUserDefaults *defaults, NSString *key) {
	return key.length && [defaults boolForKey:key];
}

static void SCIResolveEmployeeGateIndices(void) {
	if (!atomic_load_explicit(&sEmployeeIndexResolved, memory_order_acquire)) {
		const void *descriptor = dlsym(RTLD_DEFAULT, "ig_is_employee");
		if (descriptor) {
			uint32_t index = *(const uint32_t *)descriptor;
			if (index != 0 && index != UINT32_MAX) {
				atomic_store_explicit(&sEmployeeIndex, index, memory_order_release);
				atomic_store_explicit(&sEmployeeIndexResolved, true, memory_order_release);
			}
		}
	}

	if (!atomic_load_explicit(&sEmployeeOrTestIndexResolved, memory_order_acquire)) {
		const void *descriptor = dlsym(RTLD_DEFAULT, "ig_is_employee_or_test_user");
		if (descriptor) {
			uint32_t index = *(const uint32_t *)descriptor;
			if (index != 0 && index != UINT32_MAX) {
				atomic_store_explicit(&sEmployeeOrTestIndex, index, memory_order_release);
				atomic_store_explicit(&sEmployeeOrTestIndexResolved, true, memory_order_release);
			}
		}
	}
}

static void SCIRefreshInternalGateState(void) {
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	bool employee = [SCIInternalGatePrefs employeeInternalMasterEnabled] ||
		[SCIUtils getBoolPref:@"sci_force_mc_session_employee_gate"];
	bool sessionedAll = SCIReadPref(defaults, @"sci_force_sessioned_mc_all");

	atomic_store_explicit(&sEmployeeGateEnabled, employee, memory_order_release);
	atomic_store_explicit(&sForceInternalApps,
		SCIReadPref(defaults, @"sci_force_ig_internal_apps_installed_after_ios18"), memory_order_release);
	atomic_store_explicit(&sForceMinos,
		SCIReadPref(defaults, @"sci_force_minos_dogfood_mek_encryption"), memory_order_release);
	atomic_store_explicit(&sForceSessionedAll, sessionedAll, memory_order_release);
	atomic_store_explicit(&sForceMSGC,
		SCIReadPref(defaults, @"sci_force_msgc_sessioned_boolean"), memory_order_release);
	atomic_store_explicit(&sForceMCIExp,
		SCIReadPref(defaults, @"sci_force_mci_experiment_boolean"), memory_order_release);
	atomic_store_explicit(&sForceMCIExt,
		SCIReadPref(defaults, @"sci_force_mci_extension_boolean"), memory_order_release);
	atomic_store_explicit(&sForceMetaExt,
		SCIReadPref(defaults, @"sci_force_meta_ext_experiment"), memory_order_release);

	if (employee) SCIResolveEmployeeGateIndices();
}

static void SCILogEmployeeGateHit(uint32_t bit, const char *name, uint32_t index) {
	if (!SCIFileLogIsEnabled()) return;
	uint32_t seen = atomic_fetch_or_explicit(&sEmployeeHitMask, bit, memory_order_relaxed);
	if (seen & bit) return;
	SCIFLog(@"SCIGate", @"forced %s index=%u before session identity consumers", name, index);
}

void SCIGateSetCapture(BOOL on) {
	if (on) {
		atomic_store_explicit(&sGateCaptureCount, 0, memory_order_relaxed);
		atomic_store_explicit(&sGateCapture, true, memory_order_release);
		if (SCIFileLogIsEnabled()) SCIFLog(@"SCIGate", @"=== CAPTURE START ===");
	} else {
		atomic_store_explicit(&sGateCapture, false, memory_order_release);
		if (SCIFileLogIsEnabled()) {
			SCIFLog(@"SCIGate", @"=== CAPTURE STOP (%d gates) ===",
				atomic_load_explicit(&sGateCaptureCount, memory_order_relaxed));
		}
	}
}

BOOL SCIGateIsCapturing(void) {
	return atomic_load_explicit(&sGateCapture, memory_order_acquire);
}

static inline void SCICaptureGate(const char *tag, uint64_t gate, uint64_t auxiliary, bool original) {
	if (!atomic_load_explicit(&sGateCapture, memory_order_acquire) || !SCIFileLogIsEnabled()) return;
	int ordinal = atomic_fetch_add_explicit(&sGateCaptureCount, 1, memory_order_relaxed);
	if (ordinal >= 5000) return;
	SCIFLog(@"SCIGate", @"CAP %s gate=0x%llx aux=0x%llx orig=%d", tag,
		(unsigned long long)gate, (unsigned long long)auxiliary, original);
}

// Manual diagnostic allowlist. It deliberately never means "all gates".
static const uint64_t kSCIEasyForceIDs[] = { UINT64_MAX };
static inline bool SCIForceAllowlistedGate(uint64_t gate) {
	for (size_t i = 0; i < sizeof(kSCIEasyForceIDs) / sizeof(kSCIEasyForceIDs[0]); i++) {
		if (kSCIEasyForceIDs[i] == gate) return true;
	}
	return false;
}

// Plain EasyGating receives its descriptor index in w0/x0.
static bool rEasyInternal(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyInternal ? oEasyInternal(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	uint32_t index = (uint32_t)(uintptr_t)a0;
	SCICaptureGate("egInternal", index, (uint64_t)(uintptr_t)a1, result);

	if (atomic_load_explicit(&sEmployeeGateEnabled, memory_order_acquire)) {
		if (!atomic_load_explicit(&sEmployeeOrTestIndexResolved, memory_order_acquire)) {
			SCIResolveEmployeeGateIndices();
		}
		if (atomic_load_explicit(&sEmployeeOrTestIndexResolved, memory_order_acquire) &&
			index == atomic_load_explicit(&sEmployeeOrTestIndex, memory_order_acquire)) {
			SCILogEmployeeGateHit(UINT32_C(1), "ig_is_employee_or_test_user", index);
			return true;
		}
	}
	return SCIForceAllowlistedGate(index) ? true : result;
}

// MCQ EasyGating receives its descriptor index in w1/x1.
static bool rEasyMCQ(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyMCQ ? oEasyMCQ(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	uint32_t index = (uint32_t)(uintptr_t)a1;
	SCICaptureGate("egMCQ", index, (uint64_t)(uintptr_t)a2, result);

	if (atomic_load_explicit(&sEmployeeGateEnabled, memory_order_acquire)) {
		if (!atomic_load_explicit(&sEmployeeIndexResolved, memory_order_acquire)) {
			SCIResolveEmployeeGateIndices();
		}
		if (atomic_load_explicit(&sEmployeeIndexResolved, memory_order_acquire) &&
			index == atomic_load_explicit(&sEmployeeIndex, memory_order_acquire)) {
			SCILogEmployeeGateHit(UINT32_C(2), "ig_is_employee", index);
			return true;
		}
	}
	return SCIForceAllowlistedGate(index) ? true : result;
}

static bool rEasyAuth(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyAuth ? oEasyAuth(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	uint64_t gate = (uint64_t)(uintptr_t)a1;
	SCICaptureGate("egAuth", gate, (uint64_t)(uintptr_t)a2, result);
	return (SCIForceAllowlistedGate(gate) || SCIForceAllowlistedGate((uint64_t)(uintptr_t)a2)) ? true : result;
}

static bool rEasyPlatform(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyPlatform ? oEasyPlatform(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	uint64_t gate = (uint64_t)(uintptr_t)a1;
	SCICaptureGate("egPlatform", gate, (uint64_t)(uintptr_t)a2, result);
	return (SCIForceAllowlistedGate(gate) || SCIForceAllowlistedGate((uint64_t)(uintptr_t)a2)) ? true : result;
}

static bool rMSGC(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oMSGC ? oMSGC(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	return (atomic_load_explicit(&sForceSessionedAll, memory_order_acquire) ||
		atomic_load_explicit(&sForceMSGC, memory_order_acquire)) ? true : result;
}

static bool rMCIExp(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oMCIExp ? oMCIExp(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	return (atomic_load_explicit(&sForceSessionedAll, memory_order_acquire) ||
		atomic_load_explicit(&sForceMCIExp, memory_order_acquire)) ? true : result;
}

static bool rMCIExt(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oMCIExt ? oMCIExt(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	return (atomic_load_explicit(&sForceSessionedAll, memory_order_acquire) ||
		atomic_load_explicit(&sForceMCIExt, memory_order_acquire)) ? true : result;
}

static bool rMetaExt(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oMetaExt ? oMetaExt(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	return atomic_load_explicit(&sForceMetaExt, memory_order_acquire) ? true : result;
}

static bool rMetaExtNoExposure(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oMetaExtNoExposure ? oMetaExtNoExposure(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	return atomic_load_explicit(&sForceMetaExt, memory_order_acquire) ? true : result;
}

static bool rInternalApps(void) {
	bool result = oInternalApps ? oInternalApps() : false;
	return atomic_load_explicit(&sForceInternalApps, memory_order_acquire) ? true : result;
}

static bool rMinos(void) {
	bool result = oMinos ? oMinos() : false;
	return atomic_load_explicit(&sForceMinos, memory_order_acquire) ? true : result;
}

static void SCIAddRebinding(struct rebinding *items, size_t *count, const char *symbol,
	void *replacement, void **original) {
	if (*count >= 16) return;
	items[*count].name = symbol;
	items[*count].replacement = replacement;
	items[*count].replaced = original;
	(*count)++;
}

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
	SCIRefreshInternalGateState();

	static dispatch_once_t once;
	dispatch_once(&once, ^{
		struct rebinding items[16] = {0};
		size_t count = 0;

		// Always register identity evaluators. They remain transparent unless the
		// exact employee master/index matches.
		SCIAddRebinding(items, &count, "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
			(void *)rEasyInternal, (void **)&oEasyInternal);
		SCIAddRebinding(items, &count, "MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
			(void *)rEasyMCQ, (void **)&oEasyMCQ);
		SCIAddRebinding(items, &count, "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
			(void *)rEasyAuth, (void **)&oEasyAuth);
		SCIAddRebinding(items, &count, "EasyGatingPlatformGetBoolean",
			(void *)rEasyPlatform, (void **)&oEasyPlatform);
		SCIAddRebinding(items, &count, "MSGCSessionedMobileConfigGetBoolean",
			(void *)rMSGC, (void **)&oMSGC);
		SCIAddRebinding(items, &count, "MCIExperimentCacheGetMobileConfigBoolean",
			(void *)rMCIExp, (void **)&oMCIExp);
		SCIAddRebinding(items, &count, "MCIExtensionExperimentCacheGetMobileConfigBoolean",
			(void *)rMCIExt, (void **)&oMCIExt);
		SCIAddRebinding(items, &count, "METAExtensionsExperimentGetBoolean",
			(void *)rMetaExt, (void **)&oMetaExt);
		SCIAddRebinding(items, &count, "METAExtensionsExperimentGetBooleanWithoutExposure",
			(void *)rMetaExtNoExposure, (void **)&oMetaExtNoExposure);
		SCIAddRebinding(items, &count, "IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
			(void *)rInternalApps, (void **)&oInternalApps);
		SCIAddRebinding(items, &count, "MEBIsMinosDogfoodMekEncryptionVersionEnabled",
			(void *)rMinos, (void **)&oMinos);

		bool anyForced = atomic_load_explicit(&sEmployeeGateEnabled, memory_order_acquire) ||
			atomic_load_explicit(&sForceInternalApps, memory_order_acquire) ||
			atomic_load_explicit(&sForceMinos, memory_order_acquire) ||
			atomic_load_explicit(&sForceSessionedAll, memory_order_acquire) ||
			atomic_load_explicit(&sForceMSGC, memory_order_acquire) ||
			atomic_load_explicit(&sForceMCIExp, memory_order_acquire) ||
			atomic_load_explicit(&sForceMCIExt, memory_order_acquire) ||
			atomic_load_explicit(&sForceMetaExt, memory_order_acquire);
		if (anyForced) [SCIInternalGatePrefs installCrashGuardIfNeeded];

		int rc = rebind_symbols(items, count);
		SCILOG("rebind count=%lu rc=%d", (unsigned long)count, rc);
	});
}

%ctor {
	@autoreleasepool {
		SCIInstallMobileConfigInternalUseGateIfNeeded();
	}
}
