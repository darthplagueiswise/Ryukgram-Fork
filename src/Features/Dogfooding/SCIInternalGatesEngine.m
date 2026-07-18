// SCIInternalGatesEngine.m
// =====================================================================
// Força os gates EasyGating de employee/test-user/dogfooder + o sinal de
// internal-apps, e expõe estado ao vivo pra tela Internal Gates.
// =====================================================================
// Base (LIEF chained-fixups + Capstone; Instagram 4C4C4424..., FBShared 4C4C446A...):
//   ig_*/xav_* = DATA descriptors ({field0=config, field1}) em FBSharedFramework
//   __TEXT,__const, importados pelo Instagram. Avaliados por
//   EasyGatingGetBoolean...Internal_DoNotUseOrMock (FBSharedFramework).
//
// POR QUE MUDOU DE fishhook PARA MSHookFunction:
//   O diagnóstico anterior mostrou 3/3 avaliadores "hooked" mas 0 forces. Causa:
//   fishhook reescreve o GOT do Instagram -> só intercepta chamadas Instagram->FB.
//   A avaliação desses gates acontece DENTRO do FBSharedFramework (FB->FB), que
//   NÃO passa pelo GOT do Instagram. MSHookFunction no símbolo real (via dlsym)
//   substitui a implementação -> pega TODOS os callers (Instagram + FB-internos).
//
// Replacement: C puro, passthrough de 6 args (preserva registradores exatos).
// Conta toda chamada (sEGCalls), força YES quando um arg é o ponteiro de um
// descriptor-alvo OU seu field0 (dlsym), e loga args crus deduplicados (se o file
// log estiver ligado) pra revelar o índice caso o caminho seja por índice.

#import <substrate.h>
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
static volatile long sEGCalls = 0;

// raw-arg dedup log (reveals index-based paths)
static uint64_t      sSeenA0[48];
static volatile int  sSeenN = 0;

static BOOL sInstalled = NO, sEGActive = NO, sIAActive = NO;
static int  sEGHooked = 0;  static BOOL sIAHooked = NO;

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
			SCIFLog(@"SCIGate", @"forced gate '%s' -> YES", kSCIGateSyms[i]);
	}
}

static inline void sci_logRawArgOnce(void *a0, void *a1, void *a2) {
	if (!SCIFileLogIsEnabled()) return;
	uint64_t v = (uint64_t)a0;
	int n = sSeenN;
	for (int i = 0; i < n && i < 48; i++) if (sSeenA0[i] == v) return;
	if (n < 48) { sSeenA0[n] = v; sSeenN = n + 1; }
	SCIFLog(@"SCIGate", @"eg call a0=0x%llx (int %d) a1=0x%llx a2=0x%llx",
	        (unsigned long long)v, (int)(intptr_t)a0,
	        (unsigned long long)(uint64_t)a1, (unsigned long long)(uint64_t)a2);
}

#define SCI_EG_HOOK(TAG) \
	static BOOL (*orig_##TAG)(void *, void *, void *, void *, void *, void *) = NULL; \
	static BOOL sci_##TAG(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5) { \
		sEGCalls++; \
		if (sEGActive) { \
			int m = sci_matchGate(a0); \
			if (m < 0) m = sci_matchGate(a1); \
			if (m < 0) m = sci_matchGate(a2); \
			if (m < 0) m = sci_matchGate(a3); \
			if (m < 0) m = sci_matchGate(a4); \
			if (m < 0) m = sci_matchGate(a5); \
			if (m >= 0) { sci_noteForced(m); return YES; } \
			sci_logRawArgOnce(a0, a1, a2); \
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

static BOOL sci_hook(const char *sym, void *repl, void **orig) {
	void *p = dlsym(RTLD_DEFAULT, sym);
	if (!p) return NO;
	MSHookFunction(p, repl, orig);
	return (*orig != NULL);
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
			sDesc[i] = d; sField0[i] = *(void **)d; sResolved[i] = YES;
		}
		sEGHooked  = sci_hook("EasyGatingGetBoolean_Internal_DoNotUseOrMock", (void *)sci_egBool, (void **)&orig_egBool) ? 1 : 0;
		sEGHooked += sci_hook("EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", (void *)sci_egAuth, (void **)&orig_egAuth) ? 1 : 0;
		sEGHooked += sci_hook("MCQEasyGatingGetBooleanInternalDoNotUseOrMock", (void *)sci_egMCQ, (void **)&orig_egMCQ) ? 1 : 0;
	}
	if (sIAActive) {
		sIAHooked = sci_hook("IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)sci_igAppis, (void **)&orig_igAppis);
	}

	if (SCIFileLogIsEnabled())
		SCIFLog(@"SCIGate", @"install(MSHook): eg=%d(hooked %d) apps=%d(hooked %d)",
		        sEGActive, sEGHooked, sIAActive, sIAHooked);
}

@implementation SCIInternalGatesEngine
+ (BOOL)installed { return sInstalled; }
+ (BOOL)easyGatingForceActive { return sEGActive; }
+ (BOOL)internalAppsForceActive { return sIAActive; }
+ (NSInteger)easyGatingEvaluatorsHooked { return sEGHooked; }
+ (BOOL)internalAppsHooked { return sIAHooked; }
+ (NSInteger)gateCount { return kGateN; }
+ (NSInteger)evaluatorCallsSeen { return sEGCalls; }
+ (NSInteger)totalForcedHits {
	NSInteger t = 0; for (int i = 0; i < kGateN; i++) t += sForced[i]; return t;
}
+ (NSArray<NSDictionary *> *)gateStatuses {
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:kGateN];
	for (int i = 0; i < kGateN; i++)
		[out addObject:@{ @"name": [NSString stringWithUTF8String:kSCIGateSyms[i]],
		                  @"resolved": @(sResolved[i]), @"forced": @(sForced[i]) }];
	return out;
}
@end
