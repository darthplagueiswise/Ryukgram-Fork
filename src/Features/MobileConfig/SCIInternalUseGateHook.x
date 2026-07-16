// Current experiment C-gate bridge for Instagram(29) + FBSharedFramework(105).
// The removed IGMobileConfigBooleanValueForInternalUse symbol is intentionally
// absent. Every remaining target below was confirmed as an Instagram import and
// FBSharedFramework export in the supplied binaries.
#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import <os/log.h>
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
REPL8(rEasyInternal,oEasyInternal)
REPL8(rEasyAuth,oEasyAuth)
REPL8(rEasyMCQ,oEasyMCQ)
REPL8(rEasyPlatform,oEasyPlatform)
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
