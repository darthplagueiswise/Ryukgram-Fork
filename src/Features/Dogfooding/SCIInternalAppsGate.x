// SCIInternalAppsGate.x
// =====================================================================
// Força a determinação concreta "internal apps installed" que o Instagram
// importa do FBSharedFramework.
// =====================================================================
// Reanálise (LIEF + Capstone; Instagram UUID 4C4C4424-5555-3144-A12A-
// 21F40609AAF2, FBSharedFramework 4C4C446A-5555-3144-A1AD-1FC955150EC5):
//
//   _IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 é uma FUNÇÃO
//   BOOL(void) real em FBSharedFramework __text (0x4AC1C4), importada pelo
//   Instagram. Ela checa se apps Meta internos estão instalados (via URL
//   schemes) e retorna 1 se sim — um dos sinais de device usados pra tratar a
//   sessão como interna/test-user. `tbnz w20,#0 -> mov w0,#1`.
//
// fishhook-safe: o símbolo é import GOT (rebind mexe só na memória do processo,
// nunca no binário em disco), a ABI é BOOL sem argumentos, e o replacement
// latcha um C bool uma vez (nenhum ObjC no caminho da chamada). Requer restart
// pra ativar/desativar (flag latched no %ctor).
//
// IMPORTANTE — o que NÃO está aqui e por quê:
//   Os gates de employee/test-user (_ig_is_employee, _ig_is_employee_or_test_user,
//   _ig_dogfooding_assistant, _ig_dogfooding_first_client, _ig_user_session_canary_test,
//   _ig_device_session_canary_test, _xav_switcher_ig_ios_test_user_check_fdid) são
//   DATA descriptors em __TEXT,__const — pares de ponteiros fixup-encoded, NÃO
//   funções. Eles são avaliados por EasyGatingGetBoolean_Internal_DoNotUseOrMock
//   (FBSharedFramework 0x64773C) por ÍNDICE inteiro (jump table), não por ponteiro
//   de descriptor. Forçar isso com segurança exige o índice exato de cada gate,
//   que deve ser identificado on-device (log dos índices consultados ao tocar a
//   linha), não chutado. Isso fica pra um probe separado.

#include "../../../modules/fishhook/fishhook.h"
#import "../../Utils.h"
#import "SCIInternalGatePrefs.h"
#import <os/log.h>

static BOOL sForceInternalApps = NO; // latched once at %ctor

static int (*orig_SCIIGAppIsInternalApps)(void) = NULL;
static int sci_IGAppIsInternalApps(void) {
	if (sForceInternalApps) return 1;
	return orig_SCIIGAppIsInternalApps ? orig_SCIIGAppIsInternalApps() : 0;
}

void SCIInstallInternalAppsGateIfNeeded(void) {
	static BOOL installed = NO;
	if (installed) return;
	sForceInternalApps = [SCIInternalGatePrefs employeeInternalMasterEnabled];
	if (!sForceInternalApps) return;
	installed = YES;

	struct rebinding rb[] = {
		{ "IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
		  (void *)sci_IGAppIsInternalApps,
		  (void **)&orig_SCIIGAppIsInternalApps },
	};
	int rc = rebind_symbols(rb, sizeof(rb) / sizeof(rb[0]));
	os_log(OS_LOG_DEFAULT,
	       "[SCIGate] InternalAppsGate rebind rc=%d bound=%d",
	       rc, orig_SCIIGAppIsInternalApps != NULL);
}

%ctor {
	@autoreleasepool {
		SCIInstallInternalAppsGateIfNeeded();
	}
}
