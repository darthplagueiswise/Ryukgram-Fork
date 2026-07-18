// SCIEasyGatingForce.x
// =====================================================================
// Força os gates EasyGating de employee/test-user/dogfooder que o Instagram
// importa do FBSharedFramework — a determinação REAL por trás das linhas
// internas do menu de bug report (Internal Settings, Dogfooding Assistant,
// Logged Out, Set Sandbox).
// =====================================================================
// Reanálise (LIEF chained-fixups + Capstone; Instagram UUID 4C4C4424-5555-
// 3144-A12A-21F40609AAF2, FBSharedFramework 4C4C446A-5555-3144-A1AD-
// 1FC955150EC5):
//
//   Os símbolos abaixo NÃO são funções — são DATA descriptors (16 bytes:
//   pares de ponteiros fixup-encoded {field0=config, field1}) em
//   FBSharedFramework __TEXT,__const, importados pelo Instagram. Slots GOT
//   confirmados: ig_is_employee_or_test_user=0x10e0394e8, ig_is_employee=
//   0x10e04b5e8, ig_dogfooding_assistant=0x10e03e7b8, ig_dogfooding_first_client=
//   0x10e0487b8, ig_user_session_canary_test=0x10e0297e8,
//   ig_device_session_canary_test=0x10e0297f0, xav_switcher_..._fdid=0x10e06b108.
//
//   O código lê o descriptor (adrp+ldr do GOT), extrai descriptor->field0
//   (ponteiro de config do gate resolvido em runtime) e passa esse ponteiro
//   para o avaliador EasyGatingGetBoolean...Internal_DoNotUseOrMock
//   (funções importadas; GOT 0x10e02a860 / 0x10e067268 / 0x10e059368).
//   Prova de relevância: ig_dogfooding_assistant é lido em 0x103eca9a4, dentro
//   do builder do IGBugReportMenuViewController que computa showDogfoodingAssistant.
//
// COMO FORÇAR (o "não tem hook pra isso" resolvido):
//   1. fishhook os 3 avaliadores EasyGating (são imports -> fishhook rebind GOT,
//      só memória do processo, sideload-safe).
//   2. dlsym em runtime resolve o ponteiro de cada um dos 7 descriptors
//      (FBSharedFramework os exporta) e também lê field0 = *descriptor.
//   3. No replacement (C puro, passthrough de ABI de 6 args -> preserva os
//      registradores exatos, sem quebrar a ABI real de 2/3 args), se qualquer
//      argumento for o ponteiro de um descriptor-alvo OU seu field0, retorna YES.
//      Só os 7 gates são afetados; todo o resto cai em %orig. Nenhum ObjC no
//      hot-path. Latched no %ctor atrás do master. Requer restart pra (des)ativar.

#include "../../../modules/fishhook/fishhook.h"
#import "../../Utils.h"
#import "SCIInternalGatePrefs.h"
#import <dlfcn.h>
#import <os/log.h>

static const char *kSCIGateSyms[] = {
	"ig_is_employee",
	"ig_is_employee_or_test_user",
	"ig_dogfooding_assistant",
	"ig_dogfooding_first_client",
	"ig_user_session_canary_test",
	"ig_device_session_canary_test",
	"xav_switcher_ig_ios_test_user_check_fdid",
};
enum { kSCIGateCount = (int)(sizeof(kSCIGateSyms) / sizeof(kSCIGateSyms[0])) };

static void *sDesc[kSCIGateCount];   // runtime descriptor pointer
static void *sField0[kSCIGateCount]; // descriptor->field0 (resolved gate config)
static int   sGateN = 0;
static BOOL  sForce = NO;
static volatile int sLoggedMask = 0; // dedup: 1 bit per gate index

static inline int sci_matchGate(void *p) {
	if (!p) return -1;
	for (int i = 0; i < sGateN; i++)
		if (p == sDesc[i] || p == sField0[i]) return i;
	return -1;
}

static inline int sci_matchArgs(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5) {
	int m;
	if ((m = sci_matchGate(a0)) >= 0) return m;
	if ((m = sci_matchGate(a1)) >= 0) return m;
	if ((m = sci_matchGate(a2)) >= 0) return m;
	if ((m = sci_matchGate(a3)) >= 0) return m;
	if ((m = sci_matchGate(a4)) >= 0) return m;
	if ((m = sci_matchGate(a5)) >= 0) return m;
	return -1;
}

static inline void sci_logMatchOnce(int idx) {
	int bit = 1 << idx;
	if (sLoggedMask & bit) return;
	sLoggedMask |= bit;
	os_log(OS_LOG_DEFAULT, "[SCIGate] forced EasyGating gate '%s' -> YES", kSCIGateSyms[idx]);
}

#define SCI_EG_HOOK(TAG) \
	static BOOL (*orig_##TAG)(void *, void *, void *, void *, void *, void *) = NULL; \
	static BOOL sci_##TAG(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5) { \
		if (sForce) { \
			int m = sci_matchArgs(a0, a1, a2, a3, a4, a5); \
			if (m >= 0) { sci_logMatchOnce(m); return YES; } \
		} \
		return orig_##TAG ? orig_##TAG(a0, a1, a2, a3, a4, a5) : NO; \
	}

SCI_EG_HOOK(egBool)
SCI_EG_HOOK(egAuth)
SCI_EG_HOOK(egMCQ)

void SCIInstallEasyGatingForceIfNeeded(void) {
	static BOOL done = NO;
	if (done) return;
	sForce = [SCIInternalGatePrefs employeeInternalMasterEnabled];
	if (!sForce) return;
	done = YES;

	for (int i = 0; i < kSCIGateCount; i++) {
		void *d = dlsym(RTLD_DEFAULT, kSCIGateSyms[i]);
		if (!d) continue;
		sDesc[sGateN]   = d;
		sField0[sGateN] = *(void **)d; // field0 = resolved gate config pointer
		sGateN++;
	}

	struct rebinding rb[] = {
		{ "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
		  (void *)sci_egBool, (void **)&orig_egBool },
		{ "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
		  (void *)sci_egAuth, (void **)&orig_egAuth },
		{ "MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
		  (void *)sci_egMCQ, (void **)&orig_egMCQ },
	};
	int rc = rebind_symbols(rb, sizeof(rb) / sizeof(rb[0]));
	os_log(OS_LOG_DEFAULT,
	       "[SCIGate] EasyGatingForce rc=%d gates=%d/%d egBool=%d egAuth=%d egMCQ=%d",
	       rc, sGateN, kSCIGateCount,
	       orig_egBool != NULL, orig_egAuth != NULL, orig_egMCQ != NULL);
}

%ctor {
	@autoreleasepool {
		SCIInstallEasyGatingForceIfNeeded();
	}
}
