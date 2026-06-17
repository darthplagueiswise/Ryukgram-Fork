// SCIDogfoodParamGateHook.x
//
// Sideload-safe enablement of dogfood / internal / employee mode by forcing the
// MobileConfig / EasyGating / MSGC / MCI boolean readers that are EXPORTED by
// FBSharedFramework and IMPORTED by the exec. fishhook rewrites the exec's GOT
// (in __DATA, writable) → allowed in sideload (no __TEXT patch, no jailbreak).
//
// DESIGN (per user decision — the user decides what stays, not me):
//   • Every boolean reader below gets its OWN toggle. Forcing is OPT-IN per symbol.
//   • Two modes per symbol, chosen by the user:
//       FORCE-ALL  : reader always returns YES (broad; unlocks everything that
//                    reader gates — the user accepts the trade-off / crash risk).
//       FILTERED   : returns YES only when the param pointer matches an enabled
//                    descriptor (ig_is_employee / dogfood / a user-captured key).
//   • LOG mode: captures the param pointer of every call to a hooked reader so the
//     user can discover which key unlocks what and then switch to FILTERED.
//
// RE-ENTRANCY (run-229): replacements read ONLY plain C atomics. No ObjC /
// NSUserDefaults inside a hook (IG's pref domain itself calls these readers →
// infinite recursion). Cache is filled at %ctor and refreshed by KVO on main.
//
// VALIDATED (FBSharedFramework, __TEXT vmaddr 0x0; all imported by exec):
//   IGMobileConfigBooleanValueForInternalUse  @0xd8501c  (x0 sess,x1 def,x2 param)
//   MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter @0x707074 (hot-path/PAC)
//   MCIExperimentCacheGetMobileConfigBoolean  @0x6f6298  (hot-path)
//   MCIExtensionExperimentCacheGetMobileConfigBoolean @0x6f0908 (x2 param)
//   MSGCSessionedMobileConfigGetBoolean       @0x16f157c (x2 param)
//   MEBIsMinosDogfoodMekEncryptionVersionEnabled @0xf12db0
//   EasyGatingGetBoolean_Internal_DoNotUseOrMock @0x696c44 (x0 id)
//   EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock @0xdf6950
//   IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 @0x4aa9dc
//   MCQEasyGatingGetBooleanInternalDoNotUseOrMock @0x6f3de4
//   Param descriptors (FB offsets): ig_is_employee 0x2283fe8,
//     ig_is_employee_or_test_user 0x2283ff8, ig_dogfooding_assistant 0x23c4a80,
//     ig_dogfooding_first_client 0x2276e40.

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <stdatomic.h>
#import <os/log.h>
#import "../../../modules/fishhook/fishhook.h"

#define DLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Dogfood " fmt,##__VA_ARGS__)

// ── Master / mode prefs (read at %ctor / KVO only) ──────────────────────────
static NSString *const kEmployee = @"sci_force_ig_is_employee";       // employee master
static NSString *const kInternal = @"sci_force_ig_internal_employee"; // alt master
static NSString *const kDogfood  = @"sci_force_ig_dogfooding";        // dogfood params
static NSString *const kLogMode  = @"sci_dogfood_log_keys";           // capture param ptrs

// Per-reader force toggles (the user flips these in the Dev menu).
// Key pattern: sci_force_reader_<shortname>
typedef struct {
    const char *symbol;        // exact import name for fishhook
    NSString   *pref;          // per-symbol force toggle
    int         param_reg;     // which arg reg holds the param ptr (-1 = none/unknown)
} SCIReaderDef;

// param_reg: 2 = x2 carries the param descriptor pointer (filterable).
static SCIReaderDef kReaders[] = {
    { "IGMobileConfigBooleanValueForInternalUse",                     @"sci_force_reader_igmc_bool",       2 },
    { "MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",              @"sci_force_reader_mcdasm_bool",    -1 },
    { "MCIExperimentCacheGetMobileConfigBoolean",                     @"sci_force_reader_mci_bool",       -1 },
    { "MCIExtensionExperimentCacheGetMobileConfigBoolean",            @"sci_force_reader_mciext_bool",     2 },
    { "MSGCSessionedMobileConfigGetBoolean",                          @"sci_force_reader_msgc_bool",       2 },
    { "MEBIsMinosDogfoodMekEncryptionVersionEnabled",                 @"sci_force_reader_meb_minos",      -1 },
    { "EasyGatingGetBoolean_Internal_DoNotUseOrMock",                 @"sci_force_reader_easy_bool",      -1 },
    { "EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", @"sci_force_reader_easy_auth",  -1 },
    { "IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",  @"sci_force_reader_ig_internalapps",-1 },
    { "MCQEasyGatingGetBooleanInternalDoNotUseOrMock",                @"sci_force_reader_mcq_easy",       -1 },
};
#define NREADERS (sizeof(kReaders)/sizeof(kReaders[0]))

// Param descriptors for FILTERED mode (employee/dogfood).
typedef struct { const char *name; uint64_t fb_offset; NSString *pref; } SCIParamDesc;
static SCIParamDesc kParams[] = {
    { "ig_is_employee",              0x2283fe8, @"sci_force_ig_is_employee" },
    { "ig_is_employee_or_test_user", 0x2283ff8, @"sci_force_ig_is_employee" },
    { "ig_dogfooding_assistant",     0x23c4a80, @"sci_force_ig_dogfooding"  },
    { "ig_dogfooding_first_client",  0x2276e40, @"sci_force_ig_dogfooding"  },
};
#define NPARAMS (sizeof(kParams)/sizeof(kParams[0]))

// ── State (plain C atomics) ─────────────────────────────────────────────────
static atomic_int  g_reader_force[NREADERS];   // per-reader FORCE-ALL on/off
static atomic_int  g_filtered;                 // 1 = FILTERED (only matching params)
static atomic_int  g_logmode;                  // 1 = log param ptrs
static uintptr_t   g_param_addr[NPARAMS];
static atomic_int  g_param_on[NPARAMS];
static void       *g_orig[NREADERS];
static atomic_int  g_installed;

// ── Resolve FBSharedFramework slide once ────────────────────────────────────
static uintptr_t sciFBBase(void) {
    static uintptr_t base = 0; static dispatch_once_t once;
    dispatch_once(&once, ^{
        uint32_t n = _dyld_image_count();
        for (uint32_t i = 0; i < n; i++) {
            const char *nm = _dyld_get_image_name(i);
            if (nm && strstr(nm, "/FBSharedFramework")) {
                base = (uintptr_t)_dyld_get_image_vmaddr_slide(i);
                DLOG("FB slide=0x%lx", (unsigned long)base); break;
            }
        }
    });
    return base;
}

// ── Decide: should this call be forced? (plain C only) ──────────────────────
static inline BOOL sciShouldForce(int idx, void *param) {
    if (!atomic_load(&g_reader_force[idx])) return NO;       // reader not forced
    if (atomic_load(&g_logmode) && kReaders[idx].param_reg == 2)
        DLOG("call %{public}s param=%p", kReaders[idx].symbol, param);
    if (!atomic_load(&g_filtered)) return YES;               // FORCE-ALL mode
    // FILTERED: only if param matches an enabled descriptor (needs param_reg==2)
    if (kReaders[idx].param_reg != 2) return NO;
    uintptr_t p = (uintptr_t)param;
    for (size_t i = 0; i < NPARAMS; i++)
        if (g_param_addr[i] && p == g_param_addr[i] && atomic_load(&g_param_on[i])) return YES;
    return NO;
}

// ── Per-reader replacements (capture orig with matching arity) ──────────────
// All readers return BOOL in w0. We force by returning YES; otherwise call orig.
// Signatures use enough leading pointer args to cover the real ABI; extra args
// are ignored on arm64 (caller-cleaned, regs preserved). x2 is the param on the
// readers marked param_reg==2.
#define REPL(idx, oname) \
static BOOL oname(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5) { \
    if (sciShouldForce(idx, a2)) return YES; \
    BOOL (*o)(void*,void*,void*,void*,void*,void*) = (void*)g_orig[idx]; \
    return o ? o(a0,a1,a2,a3,a4,a5) : (BOOL)(uintptr_t)a1; \
}
REPL(0, repl_igmc_bool)
REPL(1, repl_mcdasm_bool)
REPL(2, repl_mci_bool)
REPL(3, repl_mciext_bool)
REPL(4, repl_msgc_bool)
REPL(5, repl_meb_minos)
REPL(6, repl_easy_bool)
REPL(7, repl_easy_auth)
REPL(8, repl_ig_internalapps)
REPL(9, repl_mcq_easy)
static void *g_repls[NREADERS] = {
    (void*)repl_igmc_bool,(void*)repl_mcdasm_bool,(void*)repl_mci_bool,(void*)repl_mciext_bool,
    (void*)repl_msgc_bool,(void*)repl_meb_minos,(void*)repl_easy_bool,(void*)repl_easy_auth,
    (void*)repl_ig_internalapps,(void*)repl_mcq_easy,
};

// ── Refresh cache (main/KVO; never inside a hook) ───────────────────────────
static void sciRefreshCache(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    BOOL master = [ud boolForKey:kEmployee] || [ud boolForKey:kInternal];
    BOOL all    = [ud boolForKey:@"sci_force_all_mc_gates"] || [ud boolForKey:@"sci_force_mc_internal_use_all"];
    atomic_store(&g_filtered, [ud boolForKey:@"sci_dogfood_filtered"] ? 1 : 0);
    atomic_store(&g_logmode,  [ud boolForKey:kLogMode] ? 1 : 0);
    for (size_t i = 0; i < NREADERS; i++) {
        // A reader is forced if its own toggle is on, OR a master/all switch is on.
        BOOL on = all || master || [ud boolForKey:kReaders[i].pref];
        atomic_store(&g_reader_force[i], on ? 1 : 0);
    }
    for (size_t i = 0; i < NPARAMS; i++)
        atomic_store(&g_param_on[i], (master || [ud boolForKey:kParams[i].pref]) ? 1 : 0);
}

@interface SCIDogfoodObs : NSObject @end
@implementation SCIDogfoodObs
- (void)observeValueForKeyPath:(NSString*)k ofObject:(id)o change:(NSDictionary*)c context:(void*)x { sciRefreshCache(); }
@end
static SCIDogfoodObs *g_obs = nil;

static void sciInstall(void) {
    if (atomic_load(&g_installed)) return;
    sciRefreshCache();
    BOOL any = NO;
    for (size_t i = 0; i < NREADERS && !any; i++) if (atomic_load(&g_reader_force[i])) any = YES;
    if (!any) { DLOG("skip: no reader forced"); return; }

    uintptr_t base = sciFBBase();
    for (size_t i = 0; i < NPARAMS; i++) g_param_addr[i] = base ? base + kParams[i].fb_offset : 0;

    atomic_store(&g_installed, 1);
    struct rebinding rebs[NREADERS]; int n = 0;
    for (size_t i = 0; i < NREADERS; i++) {
        // Only rebind readers that are actually forced (avoid touching hot-path
        // readers the user didn't enable).
        if (!atomic_load(&g_reader_force[i])) continue;
        rebs[n].name = kReaders[i].symbol;
        rebs[n].replacement = g_repls[i];
        rebs[n].replaced = (void **)&g_orig[i];
        n++;
    }
    if (n > 0) {
        int rc = rebind_symbols(rebs, n);
        DLOG("rebound %d readers rc=%d filtered=%d log=%d", n, rc,
             atomic_load(&g_filtered), atomic_load(&g_logmode));
    }
    g_obs = [SCIDogfoodObs new];
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSMutableArray *keys = [@[kEmployee,kInternal,kDogfood,kLogMode,
                              @"sci_force_all_mc_gates",@"sci_force_mc_internal_use_all",
                              @"sci_dogfood_filtered"] mutableCopy];
    for (size_t i = 0; i < NREADERS; i++) [keys addObject:kReaders[i].pref];
    for (NSString *k in keys) [ud addObserver:g_obs forKeyPath:k options:NSKeyValueObservingOptionNew context:NULL];
}

%ctor {
    @autoreleasepool { sciInstall(); }
}
