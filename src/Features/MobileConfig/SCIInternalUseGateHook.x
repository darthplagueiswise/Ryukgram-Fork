// SCIInternalUseGateHook.x
//
// Safe C-import gate forcing for FBShared symbols imported by Instagram.
//
// Rules followed here:
//   • fishhook only imported C functions with ABI/disassembly validated.
//   • %ctor reads prefs once into C static caches; replacement reads C only.
//   • no NSUserDefaults/ObjC from inside replacements.
//   • MCI/MCIExtension/MCDDasm stay blocked: hot-path/PAC readers crash when forced.

#import <Foundation/Foundation.h>
#import "../../../modules/fishhook/fishhook.h"
#import <os/log.h>

#define SCILOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] MCGate " fmt,##__VA_ARGS__)

static NSString * const kMCBool      = @"sci_force_mc_internal_use_boolean";
static NSString * const kInternalApp = @"sci_force_ig_internal_apps_installed_after_ios18";
static NSString * const kMinos       = @"sci_force_minos_dogfood_mek_encryption";
static NSString * const kEasyAll     = @"sci_force_easy_gating_all";
static NSString * const kEasyInt     = @"sci_force_easy_gating_internal";
static NSString * const kMSGCAll     = @"sci_force_sessioned_mc_all";
static NSString * const kMSGC        = @"sci_force_msgc_sessioned_boolean";

static volatile BOOL sCacheMCBool      = NO;
static volatile BOOL sCacheInternalApp = NO;
static volatile BOOL sCacheMinos       = NO;
static volatile BOOL sCacheEasyInt     = NO;
static volatile BOOL sCacheMSGC        = NO;

static void SCIRefreshHookCache(void) {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;

    // Keep the old master constrained to the safe reader set. It does NOT
    // enable MCI/MCIExtension/MCDDasm; those are explicitly crash-blocked.
    BOOL safeAll = [ud boolForKey:@"sci_force_all_mc_gates"] || [ud boolForKey:@"sci_force_mc_internal_use_all"];

    sCacheMCBool      = safeAll || [ud boolForKey:kMCBool];
    sCacheInternalApp = [ud boolForKey:kInternalApp];
    sCacheMinos       = [ud boolForKey:kMinos];
    sCacheEasyInt     = [ud boolForKey:kEasyAll] || [ud boolForKey:kEasyInt];
    sCacheMSGC        = [ud boolForKey:kMSGCAll] || [ud boolForKey:kMSGC];

    SCILOG("cache mc=%d apps=%d minos=%d easy=%d msgc=%d",
           (int)sCacheMCBool, (int)sCacheInternalApp, (int)sCacheMinos,
           (int)sCacheEasyInt, (int)sCacheMSGC);
}

typedef BOOL (*MCBoolFn_t)(id, BOOL, void *);
typedef BOOL (*SimpleBoolFn_t)(void);
typedef BOOL (*GenericBoolFn_t)(void *, void *, void *, void *, void *, void *, void *, void *);

static MCBoolFn_t     orig_MCBool       = NULL;
static SimpleBoolFn_t orig_InternalApps = NULL;
static SimpleBoolFn_t orig_Minos        = NULL;
static GenericBoolFn_t orig_EasyInt     = NULL;
static GenericBoolFn_t orig_MSGC        = NULL;

static BOOL my_MCBool(id session, BOOL def, void *p) {
    if (sCacheMCBool) return YES;
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
static BOOL my_EasyInt(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7) {
    if (sCacheEasyInt) return YES;
    return orig_EasyInt ? orig_EasyInt(a0,a1,a2,a3,a4,a5,a6,a7) : NO;
}
static BOOL my_MSGC(void *a0, void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7) {
    if (sCacheMSGC) return YES;
    return orig_MSGC ? orig_MSGC(a0,a1,a2,a3,a4,a5,a6,a7) : NO;
}

@interface SCIMCGateObserver : NSObject @end
@implementation SCIMCGateObserver
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)obj change:(NSDictionary *)c context:(void *)ctx {
    SCIRefreshHookCache();
}
@end
static SCIMCGateObserver *sObserver = nil;

static void SCIInstallKVOObserver(void) {
    if (sObserver) return;
    sObserver = [SCIMCGateObserver new];
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[
        kMCBool, kInternalApp, kMinos, kEasyAll, kEasyInt, kMSGCAll, kMSGC,
        @"sci_force_mc_internal_use_all", @"sci_force_all_mc_gates"
    ];
    for (NSString *key in keys) {
        [ud addObserver:sObserver forKeyPath:key options:NSKeyValueObservingOptionNew context:NULL];
    }
}

void SCIInstallMobileConfigInternalUseGateIfNeeded(void) {
    static BOOL done = NO;
    SCIRefreshHookCache();

    BOOL any = sCacheMCBool || sCacheInternalApp || sCacheMinos || sCacheEasyInt || sCacheMSGC;
    if (!any) { SCILOG("skip install: all safe C gates disabled"); return; }
    if (done) return;
    done = YES;

    struct rebinding r[] = {
        {"IGMobileConfigBooleanValueForInternalUse", (void *)my_MCBool, (void **)&orig_MCBool},
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)my_InternalApps, (void **)&orig_InternalApps},
        {"MEBIsMinosDogfoodMekEncryptionVersionEnabled", (void *)my_Minos, (void **)&orig_Minos},
        {"EasyGatingGetBoolean_Internal_DoNotUseOrMock", (void *)my_EasyInt, (void **)&orig_EasyInt},
        {"MSGCSessionedMobileConfigGetBoolean", (void *)my_MSGC, (void **)&orig_MSGC},
    };
    int rc = rebind_symbols(r, sizeof(r) / sizeof(r[0]));
    SCILOG("rebind_symbols safe-set rc=%d", rc);
    SCIInstallKVOObserver();
}

%ctor {
    @autoreleasepool {
        SCIInstallMobileConfigInternalUseGateIfNeeded();
    }
}
