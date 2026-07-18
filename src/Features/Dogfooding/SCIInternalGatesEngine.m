// SCIInternalGatesEngine.m
// =====================================================================
// Força os gates EasyGating de employee/test-user/dogfooder + o sinal de
// internal-apps, e expõe o estado ao vivo pra tela Internal Gates.
// =====================================================================
// Base binária (LIEF chained-fixups + Capstone; Instagram UUID 4C4C4424-5555-
// 3144-A12A-21F40609AAF2, FBSharedFramework 4C4C446A-5555-3144-A1AD-1FC955150EC5):
//
//   Os 7 símbolos ig_*/xav_* são DATA descriptors (16 bytes: {field0=config,
//   field1}) em FBSharedFramework __TEXT,__const, importados pelo Instagram.
//   Slots GOT: ig_is_employee_or_test_user=0x10e0394e8, ig_is_employee=0x10e04b5e8,
//   ig_dogfooding_assistant=0x10e03e7b8, ig_dogfooding_first_client=0x10e0487b8,
//   ig_user_session_canary_test=0x10e0297e8, ig_device_session_canary_test=
//   0x10e0297f0, xav_switcher_..._fdid=0x10e06b108. O código lê descriptor->field0
//   e passa ao avaliador EasyGatingGetBoolean...Internal_DoNotUseOrMock
//   (GOT 0x10e02a860 / 0x10e067268 / 0x10e059368). Prova: ig_dogfooding_assistant
//   é lido em 0x103eca9a4, dentro do builder do IGBugReportMenuViewController.
//
//   IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 (FB __text 0x4AC1C4)
//   é função BOOL(void), importada. Sinal de device interno.
//
// Método: fishhook (rebind GOT, só memória do processo -> sideload-safe) nos 3
// avaliadores + na função internal-apps. No replacement (C puro, passthrough de
// 6 args -> preserva os registradores exatos), força YES só quando um argumento
// é o ponteiro de um descriptor-alvo OU seu field0 (resolvidos via dlsym). Só os
// 7 gates; resto cai em %orig. Nenhum ObjC no hot path (exceto o log deduped, no
// máximo 1x por gate, e só se o file log estiver ligado).

#include "../../../modules/fishhook/fishhook.h"
#import "SCIInternalGatesEngine.h"
#import "SCIInternalGatePrefs.h"
#import "../../Utils.h"
#import "../../SCIFileLog.h"
#import <dlfcn.h>

static const char *kSCIGateSyms[] = {
	"ig_is_employee",
	"ig_is_employee_or_test_user",
	"ig_dogfooding_assistant",
	"ig_dogfooding_first_client",
	"ig_user_session_canary_test",
	"ig_device_session_canary_test",
	"xav_switcher_ig_ios_test_user_check_fdid",
};
enum { kGateN = (int)(sizeof(kSCIGateSyms) / sizeof(kSCIGateSyms[0])) };

static void         *sDesc[kGateN];
static void         *sField0[kGateN];
static BOOL          sResolved[kGateN];
static volatile int  sForced[kGateN];
static volatile int  sLoggedMask = 0;

static BOOL sInstalled       = NO;
static BOOL sEGActive        = NO;
static BOOL sIAActive        = NO;
static int  sEGHooked        = 0;
static BOOL sIAHooked        = NO;

static inline int sci_matchGate(void *p) {
	if (!p) return -1;
	for (int i = 0; i < kGateN; i++)
		if (sResolved[i] && (p == sDesc[i] || p == sField0[i])) return i;
	return -1;
}

static inline void sci_noteForced(int i) {
	sForced[i]++;
	int bit = 1 << i;
	if (!(sLoggedMask & bit)) {
		sLoggedMask |= bit;
		if (SCIFileLogIsEnabled())
			SCIFLog(@"SCIGate", @"forced EasyGating gate '%s' -> YES", kSCIGateSyms[i]);
	}
}

#define SCI_EG_HOOK(TAG) \
	static BOOL (*orig_##TAG)(void *, void *, void *, void *, void *, void *) = NULL; \
	static BOOL sci_##TAG(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5) { \
		if (sEGActive) { \
			int m = sci_matchGate(a0); \
			if (m < 0) m = sci_matchGate(a1); \
			if (m < 0) m = sci_matchGate(a2); \
			if (m < 0) m = sci_matchGate(a3); \
			if (m < 0) m = sci_matchGate(a4); \
			if (m < 0) m = sci_matchGate(a5); \
			if (m >= 0) { sci_noteForced(m); return YES; } \
		} \
		return orig_##TAG ? orig_##TAG(a0, a1, a2, a3, a4, a5) : NO; \
	}

SCI_EG_HOOK(egBool)
SCI_EG_HOOK(egAuth)
SCI_EG_HOOK(egMCQ)

static int (*orig_igAppis)(void) = NULL;
static int sci_igAppis(void) {
	if (sIAActive) return 1;
	return orig_igAppis ? orig_igAppis() : 0;
}

void SCIInternalGatesInstall(void) {
	if (sInstalled) return;
	sInstalled = YES;

	BOOL master = [SCIInternalGatePrefs employeeInternalMasterEnabled];
	sEGActive = master || [SCIUtils getBoolPref:@"sci_force_easygating_internal"];
	sIAActive = master || [SCIUtils getBoolPref:@"sci_force_internal_apps_gate"];

	if (sEGActive) {
		for (int i = 0; i < kGateN; i++) {
			void *d = dlsym(RTLD_DEFAULT, kSCIGateSyms[i]);
			if (!d) continue;
			sDesc[i]     = d;
			sField0[i]   = *(void **)d;
			sResolved[i] = YES;
		}
		struct rebinding rb[] = {
			{ "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
			  (void *)sci_egBool, (void **)&orig_egBool },
			{ "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
			  (void *)sci_egAuth, (void **)&orig_egAuth },
			{ "MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
			  (void *)sci_egMCQ, (void **)&orig_egMCQ },
		};
		rebind_symbols(rb, sizeof(rb) / sizeof(rb[0]));
		sEGHooked = (orig_egBool != NULL) + (orig_egAuth != NULL) + (orig_egMCQ != NULL);
	}

	if (sIAActive) {
		struct rebinding rb2[] = {
			{ "IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
			  (void *)sci_igAppis, (void **)&orig_igAppis },
		};
		rebind_symbols(rb2, sizeof(rb2) / sizeof(rb2[0]));
		sIAHooked = (orig_igAppis != NULL);
	}

	if (SCIFileLogIsEnabled())
		SCIFLog(@"SCIGate", @"install: eg=%d(hooked %d) apps=%d(hooked %d)",
		        sEGActive, sEGHooked, sIAActive, sIAHooked);
}

@implementation SCIInternalGatesEngine
+ (BOOL)installed { return sInstalled; }
+ (BOOL)easyGatingForceActive { return sEGActive; }
+ (BOOL)internalAppsForceActive { return sIAActive; }
+ (NSInteger)easyGatingEvaluatorsHooked { return sEGHooked; }
+ (BOOL)internalAppsHooked { return sIAHooked; }
+ (NSInteger)gateCount { return kGateN; }
+ (NSInteger)totalForcedHits {
	NSInteger t = 0;
	for (int i = 0; i < kGateN; i++) t += sForced[i];
	return t;
}
+ (NSArray<NSDictionary *> *)gateStatuses {
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:kGateN];
	for (int i = 0; i < kGateN; i++) {
		[out addObject:@{
			@"name":     [NSString stringWithUTF8String:kSCIGateSyms[i]],
			@"resolved": @(sResolved[i]),
			@"forced":   @(sForced[i]),
		}];
	}
	return out;
}
@end
