// Current experiment C-gate bridge for Instagram(29) + FBSharedFramework(105).
// The removed IGMobileConfigBooleanValueForInternalUse symbol is intentionally
// absent. Every remaining target below was confirmed as an Instagram import and
// FBSharedFramework export in the supplied binaries.
#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import <os/log.h>
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

static inline BOOL P(NSUserDefaults *ud, NSString *key) { return key.length && [ud boolForKey:key]; }
typedef bool (*Bool8)(void*,void*,void*,void*,void*,void*,void*,void*);
typedef bool (*Bool0)(void);

static Bool8 oEasyInternal, oEasyAuth, oEasyMCQ, oEasyPlatform;
static Bool8 oMSGC, oMCIExp, oMCIExt, oMetaExt, oMetaExtNoExposure;
static Bool0 oInternalApps, oMinos;

#define REPL8(name,orig) static bool name(void*a0,void*a1,void*a2,void*a3,void*a4,void*a5,void*a6,void*a7){ if(orig) (void)orig(a0,a1,a2,a3,a4,a5,a6,a7); return true; }
// --- EasyGating: SELETIVO por gate-ID (a1), nunca cego ---
// O avaliador EasyGating e compartilhado por milhares de gates (a1 = ID).
// Forcar TODOS (return true cego) habilita gates sem dependencia -> crash
// (confirmado: EXC_BAD_ACCESS + o log runtime "eg call a1=0x181/0x87/0x32").
// Aqui forcamos true SO para os IDs na allowlist abaixo; o resto cai em %orig.
// Allowlist VAZIA = observe-only (nao crasha). Preencher com os IDs dos gates
// de employee/test-user/dogfooder capturados no log [SCIGate] ao tocar Internal
// Settings.
static const uint64_t kSCIEasyForceIDs[] = {
	// TODO: preencher com IDs de employee/test-user/dogfooder capturados no log.
	// Sentinela impossivel (a1 real e um ID pequeno) -> allowlist efetivamente vazia.
	0xFFFFFFFFFFFFFFFFULL,
};
enum { kSCIEasyForceN = (int)(sizeof(kSCIEasyForceIDs)/sizeof(kSCIEasyForceIDs[0])) };
static inline bool sciEasyForce(uint64_t gid) {
	for (int i = 0; i < kSCIEasyForceN; i++) if (kSCIEasyForceIDs[i] == gid) return true;
	return false;
}
static uint64_t sciEasySeen[128];
static volatile int sciEasySeenN = 0;
static inline void sciEasyLog(const char *tag, void *a1, void *a2, bool orig) {
	if (!SCIFileLogIsEnabled()) return;
	uint64_t g = (uint64_t)a1;
	int n = sciEasySeenN;
	for (int i = 0; i < n && i < 128; i++) if (sciEasySeen[i] == g) return;
	if (n < 128) { sciEasySeen[n] = g; sciEasySeenN = n + 1; }
	SCIFLog(@"SCIGate", @"%s a1=0x%llx a2=0x%llx orig=%d", tag,
	        (unsigned long long)g, (unsigned long long)(uint64_t)a2, orig);
}
#define REPL_EASY(name,orig,tag) static bool name(void*a0,void*a1,void*a2,void*a3,void*a4,void*a5,void*a6,void*a7){ \
	bool r = orig ? orig(a0,a1,a2,a3,a4,a5,a6,a7) : false; \
	sciEasyLog(tag,a1,a2,r); \
	if (sciEasyForce((uint64_t)a1) || sciEasyForce((uint64_t)a2)) return true; \
	return r; \
}
REPL_EASY(rEasyInternal,oEasyInternal,"egInternal")
REPL_EASY(rEasyAuth,oEasyAuth,"egAuth")
REPL_EASY(rEasyMCQ,oEasyMCQ,"egMCQ")
REPL_EASY(rEasyPlatform,oEasyPlatform,"egPlatform")
REPL8(rMSGC,oMSGC)
REPL8(rMCIExp,oMCIExp)
REPL8(rMCIExt,oMCIExt)
REPL8(rMetaExt,oMetaExt)
REPL8(rMetaExtNoExposure,oMetaExtNoExposure)
static bool rInternalApps(void){ if(oInternalApps) (void)oInternalApps(); return true; }
static bool rMinos(void){ if(oMinos) (void)oMinos(); return true; }

static void Add(struct rebinding *r, size_t *n, const char *symbol, void *replacement, void **original) {
	if (*n >= 16) return;
	r[*n].name = symbol; r[*n].replacement = replacement; r[*n].replaced = original; (*n)++;
}

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
	static BOOL done = NO; if (done) return;
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	BOOL easyAll = P(ud,kEasyAll), sessionAll = P(ud,kSessionedAll);
	struct rebinding r[16] = {0}; size_t n = 0;
	if (P(ud,kInternalApp)) Add(r,&n,"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",(void*)rInternalApps,(void**)&oInternalApps);
	if (P(ud,kMinos)) Add(r,&n,"MEBIsMinosDogfoodMekEncryptionVersionEnabled",(void*)rMinos,(void**)&oMinos);
	if (easyAll || P(ud,kEasyInternal)) Add(r,&n,"EasyGatingGetBoolean_Internal_DoNotUseOrMock",(void*)rEasyInternal,(void**)&oEasyInternal);
	if (easyAll || P(ud,kEasyAuth)) Add(r,&n,"EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",(void*)rEasyAuth,(void**)&oEasyAuth);
	if (easyAll || P(ud,kEasyMCQ)) Add(r,&n,"MCQEasyGatingGetBooleanInternalDoNotUseOrMock",(void*)rEasyMCQ,(void**)&oEasyMCQ);
	if (easyAll || P(ud,kEasyPlatform)) Add(r,&n,"EasyGatingPlatformGetBoolean",(void*)rEasyPlatform,(void**)&oEasyPlatform);
	if (sessionAll || P(ud,kMSGCBoolean)) Add(r,&n,"MSGCSessionedMobileConfigGetBoolean",(void*)rMSGC,(void**)&oMSGC);
	if (sessionAll || P(ud,kMCIExpBool)) Add(r,&n,"MCIExperimentCacheGetMobileConfigBoolean",(void*)rMCIExp,(void**)&oMCIExp);
	if (sessionAll || P(ud,kMCIExtBool)) Add(r,&n,"MCIExtensionExperimentCacheGetMobileConfigBoolean",(void*)rMCIExt,(void**)&oMCIExt);
	if (P(ud,kMetaExtBool)) {
		Add(r,&n,"METAExtensionsExperimentGetBoolean",(void*)rMetaExt,(void**)&oMetaExt);
		Add(r,&n,"METAExtensionsExperimentGetBooleanWithoutExposure",(void*)rMetaExtNoExposure,(void**)&oMetaExtNoExposure);
	}
	if (!n) return;
	[SCIInternalGatePrefs installCrashGuardIfNeeded];
	done = YES;
	int rc = rebind_symbols(r,n);
	SCILOG("rebind count=%lu rc=%d",(unsigned long)n,rc);
}

%ctor { @autoreleasepool { SCIInstallMobileConfigInternalUseGateIfNeeded(); } }
