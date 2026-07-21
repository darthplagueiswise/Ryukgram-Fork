// Current experiment C-gate bridge for Instagram + FBSharedFramework.
//
// Employee identity is resolved at the shared EasyGating evaluators, mirroring
// InstaEclipse's Android strategy. The imported ig_is_employee and
// ig_is_employee_or_test_user symbols are DATA descriptors, not functions. We
// read each descriptor's first u32 index and force only that index. fishhook is
// registered in the tweak constructor and also covers images loaded later, so
// this no longer depends on ObjC MobileConfig classes existing before session
// construction or on a willFinishLaunching retry.
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

static NSString *const kInternalApp = @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString *const kMinos = @"sci_force_minos_dogfood_mek_encryption";
static NSString *const kEasyAll = @"sci_force_easy_gating_all";
static NSString *const kEasyInternal = @"sci_force_easy_gating_internal";
static NSString *const kEasyAuth = @"sci_force_easy_gating_auth";
static NSString *const kEasyMCQ = @"sci_force_easy_gating_mcq";
static NSString *const kEasyPlatform = @"sci_force_easy_gating_platform";
static NSString *const kSessionedAll = @"sci_force_sessioned_mc_all";
static NSString *const kMSGCBoolean = @"sci_force_msgc_sessioned_boolean";
static NSString *const kMCIExpBool = @"sci_force_mci_experiment_boolean";
static NSString *const kMCIExtBool = @"sci_force_mci_extension_boolean";
static NSString *const kMetaExtBool = @"sci_force_meta_ext_experiment";

static inline BOOL P(NSUserDefaults *ud, NSString *key) {
	return key.length && [ud boolForKey:key];
}

typedef bool (*Bool8)(void *, void *, void *, void *, void *, void *, void *, void *);
typedef bool (*Bool0)(void);

static Bool8 oEasyInternal, oEasyAuth, oEasyMCQ, oEasyPlatform;
static Bool8 oMSGC, oMCIExp, oMCIExt, oMetaExt, oMetaExtNoExposure;
static Bool0 oInternalApps, oMinos;

static _Atomic(BOOL) sEmployeeGateEnabled = NO;
static _Atomic(BOOL) sEmployeeIndexResolved = NO;
static _Atomic(BOOL) sEmployeeOrTestIndexResolved = NO;
static _Atomic(uint32_t) sEmployeeIndex = 0;
static _Atomic(uint32_t) sEmployeeOrTestIndex = 0;
static _Atomic(uint32_t) sEmployeeHitMask = 0;

static _Atomic(BOOL) sForceInternalApps = NO;
static _Atomic(BOOL) sForceMinos = NO;
static _Atomic(BOOL) sForceSessionedAll = NO;
static _Atomic(BOOL) sForceMSGC = NO;
static _Atomic(BOOL) sForceMCIExp = NO;
static _Atomic(BOOL) sForceMCIExt = NO;
static _Atomic(BOOL) sForceMetaExt = NO;

static void SCIResolveEmployeeGateIndices(void) {
	if (!atomic_load_explicit(&sEmployeeIndexResolved, memory_order_acquire)) {
		const void *descriptor = dlsym(RTLD_DEFAULT, "ig_is_employee");
		if (descriptor) {
			uint32_t index = *(const uint32_t *)descriptor;
			if (index != 0 && index != UINT32_MAX) {
				atomic_store_explicit(&sEmployeeIndex, index, memory_order_release);
				atomic_store_explicit(&sEmployeeIndexResolved, YES, memory_order_release);
			}
		}
	}

	if (!atomic_load_explicit(&sEmployeeOrTestIndexResolved, memory_order_acquire)) {
		const void *descriptor = dlsym(RTLD_DEFAULT, "ig_is_employee_or_test_user");
		if (descriptor) {
			uint32_t index = *(const uint32_t *)descriptor;
			if (index != 0 && index != UINT32_MAX) {
				atomic_store_explicit(&sEmployeeOrTestIndex, index, memory_order_release);
				atomic_store_explicit(&sEmployeeOrTestIndexResolved, YES, memory_order_release);
			}
		}
	}
}

static void SCIRefreshInternalGateState(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	BOOL employee = [SCIInternalGatePrefs employeeInternalMasterEnabled] ||
		[SCIUtils getBoolPref:@"sci_force_mc_session_employee_gate"];
	BOOL sessionedAll = P(ud, kSessionedAll);

	atomic_store_explicit(&sEmployeeGateEnabled, employee, memory_order_release);
	atomic_store_explicit(&sForceInternalApps, P(ud, kInternalApp), memory_order_release);
	atomic_store_explicit(&sForceMinos, P(ud, kMinos), memory_order_release);
	atomic_store_explicit(&sForceSessionedAll, sessionedAll, memory_order_release);
	atomic_store_explicit(&sForceMSGC, P(ud, kMSGCBoolean), memory_order_release);
	atomic_store_explicit(&sForceMCIExp, P(ud, kMCIExpBool), memory_order_release);
	atomic_store_explicit(&sForceMCIExt, P(ud, kMCIExtBool), memory_order_release);
	atomic_store_explicit(&sForceMetaExt, P(ud, kMetaExtBool), memory_order_release);

	if (employee) SCIResolveEmployeeGateIndices();
}

static void SCILogEmployeeGateHit(uint32_t bit, const char *name, uint32_t index) {
	if (!SCIFileLogIsEnabled()) return;
	uint32_t seen = atomic_fetch_or_explicit(&sEmployeeHitMask, bit, memory_order_relaxed);
	if (seen & bit) return;
	SCIFLog(@"SCIGate", @"forced %s index=%u before session identity consumers", name, index);
}

// Optional manually-derived allowlist used by the diagnostics UI. Keep it
// selective: blindly returning true for every EasyGating index is crash-prone.
static const uint64_t kSCIEasyForceIDs[] = {
	UINT64_MAX,
};
enum { kSCIEasyForceN = (int)(sizeof(kSCIEasyForceIDs) / sizeof(kSCIEasyForceIDs[0])) };

static inline bool sciEasyForce(uint64_t gateID) {
	for (int i = 0; i < kSCIEasyForceN; i++) {
		if (kSCIEasyForceIDs[i] == gateID) return true;
	}
	return false;
}

static uint64_t sciEasySeen[128];
static volatile int sciEasySeenN = 0;
static volatile bool sGateCapture = false;
static volatile int sGateCapCount = 0;

void SCIGateSetCapture(BOOL on) {
	if (on) {
		sGateCapCount = 0;
		sGateCapture = true;
		if (SCIFileLogIsEnabled()) SCIFLog(@"SCIGate", @"=== CAPTURE START ===");
	} else {
		sGateCapture = false;
		if (SCIFileLogIsEnabled()) SCIFLog(@"SCIGate", @"=== CAPTURE STOP (%d gates) ===", sGateCapCount);
	}
}

BOOL SCIGateIsCapturing(void) { return sGateCapture; }

static inline void sciEasyLog(const char *tag, uint64_t gateID, uint64_t aux, bool original) {
	if (!SCIFileLogIsEnabled()) return;
	if (sGateCapture) {
		if (sGateCapCount < 5000) {
			sGateCapCount++;
			SCIFLog(@"SCIGate", @"CAP %s gate=0x%llx aux=0x%llx orig=%d", tag,
				(unsigned long long)gateID, (unsigned long long)aux, original);
		}
		return;
	}

	int count = sciEasySeenN;
	for (int i = 0; i < count && i < 128; i++) {
		if (sciEasySeen[i] == gateID) return;
	}
	if (count < 128) {
		sciEasySeen[count] = gateID;
		sciEasySeenN = count + 1;
	}
	SCIFLog(@"SCIGate", @"%s gate=0x%llx aux=0x%llx orig=%d", tag,
		(unsigned long long)gateID, (unsigned long long)aux, original);
}

// Plain EasyGating receives its descriptor index in w0/x0.
static bool rEasyInternal(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyInternal ? oEasyInternal(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	uint32_t index = (uint32_t)(uintptr_t)a0;
	sciEasyLog("egInternal", index, (uint64_t)(uintptr_t)a1, result);

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
	return sciEasyForce(index) ? true : result;
}

// MCQ EasyGating receives its descriptor index in w1/x1.
static bool rEasyMCQ(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyMCQ ? oEasyMCQ(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	uint32_t index = (uint32_t)(uintptr_t)a1;
	sciEasyLog("egMCQ", index, (uint64_t)(uintptr_t)a2, result);

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
	return sciEasyForce(index) ? true : result;
}

static bool rEasyAuth(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyAuth ? oEasyAuth(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	sciEasyLog("egAuth", (uint64_t)(uintptr_t)a1, (uint64_t)(uintptr_t)a2, result);
	return (sciEasyForce((uint64_t)(uintptr_t)a1) || sciEasyForce((uint64_t)(uintptr_t)a2)) ? true : result;
}

static bool rEasyPlatform(void *a0, void *a1, void *a2, void *a3,
	void *a4, void *a5, void *a6, void *a7) {
	bool result = oEasyPlatform ? oEasyPlatform(a0, a1, a2, a3, a4, a5, a6, a7) : false;
	sciEasyLog("egPlatform", (uint64_t)(uintptr_t)a1, (uint64_t)(uintptr_t)a2, result);
	return (sciEasyForce((uint64_t)(uintptr_t)a1) || sciEasyForce((uint64_t)(uintptr_t)a2)) ? true : result;
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

static void Add(struct rebinding *rebindings, size_t *count, const char *symbol,
	void *replacement, void **original) {
	if (*count >= 16) return;
	rebindings[*count].name = symbol;
	rebindings[*count].replacement = replacement;
	rebindings[*count].replaced = original;
	(*count)++;
}

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
	SCIRefreshInternalGateState();

	static dispatch_once_t once;
	dispatch_once(&once, ^{
		struct rebinding rebindings[16] = {0};
		size_t count = 0;

		// Always register the two identity evaluators. The replacements are
		// observe/delegate-only unless the exact employee master is enabled.
		Add(rebindings, &count, "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
			(void *)rEasyInternal, (void **)&oEasyInternal);
		Add(rebindings, &count, "MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
			(void *)rEasyMCQ, (void **)&oEasyMCQ);

		Add(rebindings, &count, "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
			(void *)rEasyAuth, (void **)&oEasyAuth);
		Add(rebindings, &count, "EasyGatingPlatformGetBoolean",
			(void *)rEasyPlatform, (void **)&oEasyPlatform);
		Add(rebindings, &count, "MSGCSessionedMobileConfigGetBoolean",
			(void *)rMSGC, (void **)&oMSGC);
		Add(rebindings, &count, "MCIExperimentCacheGetMobileConfigBoolean",
			(void *)rMCIExp, (void **)&oMCIExp);
		Add(rebindings, &count, "MCIExtensionExperimentCacheGetMobileConfigBoolean",
			(void *)rMCIExt, (void **)&oMCIExt);
		Add(rebindings, &count, "METAExtensionsExperimentGetBoolean",
			(void *)rMetaExt, (void **)&oMetaExt);
		Add(rebindings, &count, "METAExtensionsExperimentGetBooleanWithoutExposure",
			(void *)rMetaExtNoExposure, (void **)&oMetaExtNoExposure);
		Add(rebindings, &count, "IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
			(void *)rInternalApps, (void **)&oInternalApps);
		Add(rebindings, &count, "MEBIsMinosDogfoodMekEncryptionVersionEnabled",
			(void *)rMinos, (void **)&oMinos);

		if (atomic_load_explicit(&sEmployeeGateEnabled, memory_order_acquire) ||
			atomic_load_explicit(&sForceInternalApps, memory_order_acquire) ||
			atomic_load_explicit(&sForceMinos, memory_order_acquire) ||
			atomic_load_explicit(&sForceSessionedAll, memory_order_acquire)) {
			[SCIInternalGatePrefs installCrashGuardIfNeeded];
		}

		int rc = rebind_symbols(rebindings, count);
		SCILOG("rebind count=%lu rc=%d", (unsigned long)count, rc);
	});
}

%ctor {
	@autoreleasepool {
		SCIInstallMobileConfigInternalUseGateIfNeeded();
	}
}
