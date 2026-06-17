// SCIInternalUseGateHook.x
//
// CRASH HISTORY:
//   Run 226: unconditional rebind of MobileConfig ACTION functions caused a C
//            function pointer to land where IG expected an ObjC object → crash
//            in objc_retain. Fixed: only rebind BOOL-returning gates.
//
//   Run 229: stack overflow (depth 4751) during dyld init.
//            my_MCBool called gateOn() → [NSUserDefaults boolForKey:] → IG's
//            custom pref domain calls IGMobileConfigBooleanValueForInternalUse
//            internally → our hook → gateOn() → NSUserDefaults → ∞
//
// ROOT CAUSE: calling NSUserDefaults (or ANY ObjC message) inside a fishhook
// replacement for a function that NSUserDefaults itself calls internally.
//
// FIX: hooks read only plain C static BOOLs. Those are written once at
// %ctor time from NSUserDefaults and never touched again from inside a hook.
// A KVO observer on NSUserDefaults refreshes the cache when the user changes
// a setting — so live toggles still work without re-entry risk.

#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import <os/log.h>

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] MCGate " fmt,##__VA_ARGS__)

// ── Pref keys ──────────────────────────────────────────────────────────────
static NSString * const kBool        = @"sci_force_mc_internal_use_boolean";
static NSString * const kInternalApp = @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString * const kMinos       = @"sci_force_minos_dogfood_mek_encryption";

// ── C-only cache (NO ObjC, NO NSUserDefaults inside hooks) ─────────────────
// Written at %ctor and whenever the user flips a toggle (KVO).
// Hooks read these atomically — zero risk of re-entrant NSUserDefaults call.
static volatile BOOL sCacheBool        = NO;
static volatile BOOL sCacheInternalApp = NO;
static volatile BOOL sCacheMinos       = NO;
// EasyGating / MCI / MSGC — cada um gated por SEU PRÓPRIO toggle individual.
// NÃO há master que arraste todos: forçar MCI/MSGC pode abortar no pipeline MCI
// (crash 2026-06-17). A decisão de ligar/testar cada um é do usuário.
static volatile BOOL sCacheEasyInternal = NO;   // EasyGatingGetBoolean_Internal_DoNotUseOrMock
static volatile BOOL sCacheEasyAuth     = NO;   // EasyGatingGetBooleanUsingAuthDataContext...
static volatile BOOL sCacheEasyMCQ      = NO;   // MCQEasyGatingGetBooleanInternalDoNotUseOrMock
static volatile BOOL sCacheMSGC         = NO;   // MSGCSessionedMobileConfigGetBoolean
static volatile BOOL sCacheMCIExp       = NO;   // MCIExperimentCacheGetMobileConfigBoolean
static volatile BOOL sCacheMCIExt       = NO;   // MCIExtensionExperimentCacheGetMobileConfigBoolean

static void SCIRefreshHookCache(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    BOOL all = [ud boolForKey:@"sci_force_mc_internal_use_all"] || [ud boolForKey:@"sci_force_all_mc_gates"];
    sCacheBool        = all || [ud boolForKey:kBool];
    sCacheInternalApp = all || [ud boolForKey:kInternalApp];
    sCacheMinos       = all || [ud boolForKey:kMinos];
    // EasyGating: o "force all easygating" só arrasta os EasyGating (não os MCI).
    BOOL easyAll = [ud boolForKey:@"sci_force_easy_gating_all"];
    sCacheEasyInternal = easyAll || [ud boolForKey:@"sci_force_easy_gating_internal"];
    sCacheEasyAuth     = easyAll || [ud boolForKey:@"sci_force_easy_gating_auth"];
    sCacheEasyMCQ      = easyAll || [ud boolForKey:@"sci_force_easy_gating_mcq"];
    // MSGC/MCI: o "force all sessioned/MCI" arrasta SÓ esses 3 (não os demais).
    // Continuam separados dos masters globais para o force-all geral não derrubar.
    BOOL mciAll = [ud boolForKey:@"sci_force_sessioned_mc_all"];
    sCacheMSGC   = mciAll || [ud boolForKey:@"sci_force_msgc_sessioned_boolean"];
    sCacheMCIExp = mciAll || [ud boolForKey:@"sci_force_mci_experiment_boolean"];
    sCacheMCIExt = mciAll || [ud boolForKey:@"sci_force_mci_extension_boolean"];
    SCILOG("cache refreshed — bool=%d apps=%d minos=%d easy(i=%d a=%d mcq=%d) msgc=%d mci(exp=%d ext=%d)",
           (int)sCacheBool, (int)sCacheInternalApp, (int)sCacheMinos,
           (int)sCacheEasyInternal, (int)sCacheEasyAuth, (int)sCacheEasyMCQ,
           (int)sCacheMSGC, (int)sCacheMCIExp, (int)sCacheMCIExt);
}

// ── Originals ──────────────────────────────────────────────────────────────
typedef BOOL (*MCBoolFn_t)(id, BOOL, void *);
typedef BOOL (*SimpleBoolFn_t)(void);
// Assinatura genérica para readers com ABIs variadas (EasyGating/MSGC/MCI).
// Em arm64 passar args a mais é inofensivo; só lemos o cache e, se OFF, repassamos.
typedef BOOL (*GenBoolFn_t)(void *, void *, void *, void *, void *, void *);

static MCBoolFn_t        orig_MCBool        = NULL;
static SimpleBoolFn_t    orig_InternalApps  = NULL;
static SimpleBoolFn_t    orig_Minos         = NULL;
static GenBoolFn_t       orig_EasyInternal  = NULL;
static GenBoolFn_t       orig_EasyAuth      = NULL;
static GenBoolFn_t       orig_EasyMCQ       = NULL;
static GenBoolFn_t       orig_MSGC          = NULL;
static GenBoolFn_t       orig_MCIExp        = NULL;
static GenBoolFn_t       orig_MCIExt        = NULL;

// ── Hook implementations — plain C, zero ObjC ─────────────────────────────
static BOOL my_MCBool(id session, BOOL def, void *p) {
    if (sCacheBool) return YES;
    return orig_MCBool ? orig_MCBool(session, def, p) : def;
}
static BOOL my_InternalApps(void) {
    if (sCacheInternalApp) return YES;
    return orig_InternalApps ? orig_InternalApps() : NO;
}
static BOOL my_Minos(void) {
    if (sCacheMinos) return YES;
    return orig_Minos ? orig_Minos() : NO;
}
static BOOL my_EasyInternal(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5) {
    if (sCacheEasyInternal) return YES;
    return orig_EasyInternal ? orig_EasyInternal(a0,a1,a2,a3,a4,a5) : NO;
}
static BOOL my_EasyAuth(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5) {
    if (sCacheEasyAuth) return YES;
    return orig_EasyAuth ? orig_EasyAuth(a0,a1,a2,a3,a4,a5) : NO;
}
static BOOL my_EasyMCQ(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5) {
    if (sCacheEasyMCQ) return YES;
    return orig_EasyMCQ ? orig_EasyMCQ(a0,a1,a2,a3,a4,a5) : NO;
}
static BOOL my_MSGC(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5) {
    if (sCacheMSGC) return YES;
    return orig_MSGC ? orig_MSGC(a0,a1,a2,a3,a4,a5) : NO;
}
static BOOL my_MCIExp(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5) {
    if (sCacheMCIExp) return YES;
    return orig_MCIExp ? orig_MCIExp(a0,a1,a2,a3,a4,a5) : NO;
}
static BOOL my_MCIExt(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5) {
    if (sCacheMCIExt) return YES;
    return orig_MCIExt ? orig_MCIExt(a0,a1,a2,a3,a4,a5) : NO;
}

// ── KVO observer — refreshes cache on settings change ─────────────────────
@interface SCIMCGateObserver : NSObject @end
@implementation SCIMCGateObserver
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)obj
                        change:(NSDictionary *)c context:(void *)ctx {
    SCIRefreshHookCache();
}
@end
static SCIMCGateObserver *sObserver = nil;

static void SCIInstallKVOObserver(void) {
    sObserver = [SCIMCGateObserver new];
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[kBool, kInternalApp, kMinos,
                            @"sci_force_mc_internal_use_all", @"sci_force_all_mc_gates",
                            @"sci_force_easy_gating_all", @"sci_force_easy_gating_internal",
                            @"sci_force_easy_gating_auth", @"sci_force_easy_gating_mcq",
                            @"sci_force_sessioned_mc_all", @"sci_force_msgc_sessioned_boolean",
                            @"sci_force_mci_experiment_boolean", @"sci_force_mci_extension_boolean"]) {
        [ud addObserver:sObserver forKeyPath:key
               options:NSKeyValueObservingOptionNew context:NULL];
    }
}

// ── Install ────────────────────────────────────────────────────────────────
void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
    static BOOL done = NO;

    // Read prefs before installing hooks. If every pref is OFF, do not touch GOT/fishhook.
    SCIRefreshHookCache();
    BOOL any = sCacheBool || sCacheInternalApp || sCacheMinos ||
               sCacheEasyInternal || sCacheEasyAuth || sCacheEasyMCQ ||
               sCacheMSGC || sCacheMCIExp || sCacheMCIExt;
    if (!any) {
        SCILOG("skip install: all prefs disabled");
        return;
    }

    if (done) return;
    done = YES;

    // Monta a lista de rebind dinamicamente: só rebinda o reader cujo cache está
    // ON. Assim um reader desligado NÃO tem o GOT tocado (e readers de hot-path
    // como MCI/MSGC só entram quando o usuário liga explicitamente o toggle).
    struct rebinding r[12];
    int n = 0;
    if (sCacheBool)        { r[n].name="IGMobileConfigBooleanValueForInternalUse"; r[n].replacement=(void*)my_MCBool; r[n].replaced=(void**)&orig_MCBool; n++; }
    if (sCacheInternalApp) { r[n].name="IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18"; r[n].replacement=(void*)my_InternalApps; r[n].replaced=(void**)&orig_InternalApps; n++; }
    if (sCacheMinos)       { r[n].name="MEBIsMinosDogfoodMekEncryptionVersionEnabled"; r[n].replacement=(void*)my_Minos; r[n].replaced=(void**)&orig_Minos; n++; }
    if (sCacheEasyInternal){ r[n].name="EasyGatingGetBoolean_Internal_DoNotUseOrMock"; r[n].replacement=(void*)my_EasyInternal; r[n].replaced=(void**)&orig_EasyInternal; n++; }
    if (sCacheEasyAuth)    { r[n].name="EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock"; r[n].replacement=(void*)my_EasyAuth; r[n].replaced=(void**)&orig_EasyAuth; n++; }
    if (sCacheEasyMCQ)     { r[n].name="MCQEasyGatingGetBooleanInternalDoNotUseOrMock"; r[n].replacement=(void*)my_EasyMCQ; r[n].replaced=(void**)&orig_EasyMCQ; n++; }
    if (sCacheMSGC)        { r[n].name="MSGCSessionedMobileConfigGetBoolean"; r[n].replacement=(void*)my_MSGC; r[n].replaced=(void**)&orig_MSGC; n++; }
    if (sCacheMCIExp)      { r[n].name="MCIExperimentCacheGetMobileConfigBoolean"; r[n].replacement=(void*)my_MCIExp; r[n].replaced=(void**)&orig_MCIExp; n++; }
    if (sCacheMCIExt)      { r[n].name="MCIExtensionExperimentCacheGetMobileConfigBoolean"; r[n].replacement=(void*)my_MCIExt; r[n].replaced=(void**)&orig_MCIExt; n++; }
    int rc = (n > 0) ? rebind_symbols(r, n) : 0;
    SCILOG("rebind_symbols n=%d rc=%d (0=ok)", n, rc);

    SCIInstallKVOObserver();
}

%ctor {
    @autoreleasepool {
        SCIInstallMobileConfigInternalUseGateIfNeeded();
    }
}
