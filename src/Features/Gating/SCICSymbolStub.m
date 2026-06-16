// SCICSymbolStub.m
#import "SCICSymbolStub.h"
#import "../../Utils.h"
#import "../../../modules/fishhook/fishhook.h"
#import <dlfcn.h>
#import <os/log.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <stdint.h>
#import <string.h>

#define SLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] CStub " fmt,##__VA_ARGS__)

static NSString *const kForceOverrides = @"sci_csym_stub_overrides"; // { name: @(1|0) }
static NSString *const kObserveOverrides = @"sci_csym_stub_observe"; // { name: @YES }

typedef NS_ENUM(NSInteger, SCICStubProfile) {
    SCICStubProfileUnknown = 0,
    SCICStubProfileIGMobileConfigBoolean,       // bool(id spec, BOOL defaultValue, void *ctx)
    SCICStubProfileEasyGatingBoolean,           // bool(uint32_t gateId)
    SCICStubProfileEasyGatingAuthBoolean,       // bool(void *auth, void *ctx, void *unused, void *gate)
    SCICStubProfileMSGCSessionedBoolean,        // bool(void *session, void *unused, void *key)
    SCICStubProfileNoArgBool,                   // bool(void)
};

static NSString *SCIStubBlacklistReason(NSString *name) {
    static NSDictionary *bl = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bl = @{
            @"MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter": @"hot-path + x30/LR/PAC; can crash on return",
            @"MCDDasmNativeGetMobileConfigInt64V2DvmAdapter": @"hot-path + x30/LR/PAC",
            @"MCDDasmNativeGetMobileConfigStringV2DvmAdapter": @"hot-path + x30/LR/PAC",
            @"MCIExperimentCacheGetMobileConfigBoolean": @"hot-path MCI; forcing can abort in MCIStatsIncrement",
            @"MCIExperimentCacheGetMobileConfigInt64": @"hot-path MCI",
            @"MCIExtensionExperimentCacheGetMobileConfigBoolean": @"hot-path MCI; forcing can abort",
            @"MCIExtensionExperimentCacheGetMobileConfigInt64": @"hot-path MCI",
            @"MCIExtensionExperimentCacheGetMobileConfigString": @"hot-path MCI",
            @"IGDirectOneWayGatingGetBoolValue": @"x30/LR/PAC reader; force blocked",
            @"MCIStatsIncrement": @"stats counter; never hook/force",
            @"FBHandleFailedProductionAssertInternal": @"production assert helper; never hook/force",
        };
    });
    return bl[name];
}

static SCICStubProfile SCIStubProfileForSymbol(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length) return SCICStubProfileUnknown;
    if ([SCIStubBlacklistReason(name) length]) return SCICStubProfileUnknown;
    if ([name isEqualToString:@"IGMobileConfigBooleanValueForInternalUse"]) return SCICStubProfileIGMobileConfigBoolean;
    if ([name isEqualToString:@"EasyGatingGetBoolean_Internal_DoNotUseOrMock"]) return SCICStubProfileEasyGatingBoolean;
    if ([name isEqualToString:@"EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock"]) return SCICStubProfileEasyGatingAuthBoolean;
    if ([name isEqualToString:@"MSGCSessionedMobileConfigGetBoolean"]) return SCICStubProfileMSGCSessionedBoolean;
    if ([name isEqualToString:@"MEBIsMinosDogfoodMekEncryptionVersionEnabled"]) return SCICStubProfileNoArgBool;
    if ([name isEqualToString:@"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18"]) return SCICStubProfileNoArgBool;
    return SCICStubProfileUnknown;
}

static BOOL SCIStubSymbolLooksBool(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length) return NO;
    if (SCIStubProfileForSymbol(name) != SCICStubProfileUnknown) return YES;
    NSString *lower = name.lowercaseString ?: @"";
    return [lower containsString:@"boolean"] || [lower containsString:@"bool"] || [lower hasPrefix:@"is"] || [lower containsString:@"enabled"];
}

static BOOL SCIStubProfileIsForceable(SCICStubProfile p) {
    // Multi-key readers are observe-only. Forcing those globally is exactly what
    // caused relaunch crashes/abort paths. Force is only for single-purpose bools.
    return p == SCICStubProfileNoArgBool;
}

#define MAX_STUBS 48
typedef struct {
    char name[192];
    void *orig;
    SCICStubProfile profile;
    atomic_int force;     // -1 passthrough, 0/1 forced
    atomic_uint hits;
    atomic_int observed;  // -1 unknown, 0/1 observed
} SCICStubSlot;
static SCICStubSlot g_slots[MAX_STUBS];
static int g_slot_count = 0;

static SCICStubSlot *slot_for(const char *name) {
    if (!name) return NULL;
    for (int i = 0; i < g_slot_count; i++) if (strcmp(g_slots[i].name, name) == 0) return &g_slots[i];
    return NULL;
}

static bool call_orig_for_slot(SCICStubSlot *s, void *a0, void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7) {
    (void)a4; (void)a5; (void)a6; (void)a7;
    if (!s || !s->orig) return false;
    switch (s->profile) {
        case SCICStubProfileIGMobileConfigBoolean: {
            bool (*o)(void *, bool, void *) = (void *)s->orig;
            return o(a0, ((uintptr_t)a1) != 0, a2);
        }
        case SCICStubProfileEasyGatingBoolean: {
            bool (*o)(uint32_t) = (void *)s->orig;
            return o((uint32_t)((uintptr_t)a0));
        }
        case SCICStubProfileEasyGatingAuthBoolean: {
            bool (*o)(void *, void *, void *, void *) = (void *)s->orig;
            return o(a0, a1, a2, a3);
        }
        case SCICStubProfileMSGCSessionedBoolean: {
            bool (*o)(void *, void *, void *) = (void *)s->orig;
            return o(a0, a1, a2);
        }
        case SCICStubProfileNoArgBool: {
            bool (*o)(void) = (void *)s->orig;
            return o();
        }
        case SCICStubProfileUnknown:
        default:
            return false;
    }
}

#define DEFINE_STUB(i) \
static bool stub_repl_##i(void *a0,void *a1,void *a2,void *a3,void *a4,void *a5,void *a6,void *a7){ \
    SCICStubSlot *s=&g_slots[i]; atomic_fetch_add(&s->hits,1); \
    bool real=call_orig_for_slot(s,a0,a1,a2,a3,a4,a5,a6,a7); \
    atomic_store(&s->observed, real?1:0); \
    int f=atomic_load(&s->force); \
    return f<0 ? real : (f!=0); \
}
DEFINE_STUB(0)  DEFINE_STUB(1)  DEFINE_STUB(2)  DEFINE_STUB(3)  DEFINE_STUB(4)  DEFINE_STUB(5)
DEFINE_STUB(6)  DEFINE_STUB(7)  DEFINE_STUB(8)  DEFINE_STUB(9)  DEFINE_STUB(10) DEFINE_STUB(11)
DEFINE_STUB(12) DEFINE_STUB(13) DEFINE_STUB(14) DEFINE_STUB(15) DEFINE_STUB(16) DEFINE_STUB(17)
DEFINE_STUB(18) DEFINE_STUB(19) DEFINE_STUB(20) DEFINE_STUB(21) DEFINE_STUB(22) DEFINE_STUB(23)
DEFINE_STUB(24) DEFINE_STUB(25) DEFINE_STUB(26) DEFINE_STUB(27) DEFINE_STUB(28) DEFINE_STUB(29)
DEFINE_STUB(30) DEFINE_STUB(31) DEFINE_STUB(32) DEFINE_STUB(33) DEFINE_STUB(34) DEFINE_STUB(35)
DEFINE_STUB(36) DEFINE_STUB(37) DEFINE_STUB(38) DEFINE_STUB(39) DEFINE_STUB(40) DEFINE_STUB(41)
DEFINE_STUB(42) DEFINE_STUB(43) DEFINE_STUB(44) DEFINE_STUB(45) DEFINE_STUB(46) DEFINE_STUB(47)
static void *g_stub_repls[MAX_STUBS] = {
    (void*)stub_repl_0,(void*)stub_repl_1,(void*)stub_repl_2,(void*)stub_repl_3,(void*)stub_repl_4,(void*)stub_repl_5,
    (void*)stub_repl_6,(void*)stub_repl_7,(void*)stub_repl_8,(void*)stub_repl_9,(void*)stub_repl_10,(void*)stub_repl_11,
    (void*)stub_repl_12,(void*)stub_repl_13,(void*)stub_repl_14,(void*)stub_repl_15,(void*)stub_repl_16,(void*)stub_repl_17,
    (void*)stub_repl_18,(void*)stub_repl_19,(void*)stub_repl_20,(void*)stub_repl_21,(void*)stub_repl_22,(void*)stub_repl_23,
    (void*)stub_repl_24,(void*)stub_repl_25,(void*)stub_repl_26,(void*)stub_repl_27,(void*)stub_repl_28,(void*)stub_repl_29,
    (void*)stub_repl_30,(void*)stub_repl_31,(void*)stub_repl_32,(void*)stub_repl_33,(void*)stub_repl_34,(void*)stub_repl_35,
    (void*)stub_repl_36,(void*)stub_repl_37,(void*)stub_repl_38,(void*)stub_repl_39,(void*)stub_repl_40,(void*)stub_repl_41,
    (void*)stub_repl_42,(void*)stub_repl_43,(void*)stub_repl_44,(void*)stub_repl_45,(void*)stub_repl_46,(void*)stub_repl_47,
};

static NSDictionary *SCIDictPref(NSString *key) {
    NSDictionary *d = [SCIUtils getDictPref:key];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

static void SCIStubRefreshCache(void) {
    NSDictionary *ov = SCIDictPref(kForceOverrides);
    for (int i = 0; i < g_slot_count; i++) {
        NSString *key = [NSString stringWithUTF8String:g_slots[i].name];
        id v = ov[key];
        if ([v isKindOfClass:NSNumber.class] && SCIStubProfileIsForceable(g_slots[i].profile)) atomic_store(&g_slots[i].force, [v boolValue] ? 1 : 0);
        else atomic_store(&g_slots[i].force, -1);
    }
}

@implementation SCICSymbolStub

+ (BOOL)isBoolLikeSymbol:(NSString *)name { return SCIStubSymbolLooksBool(name); }
// Only single-purpose no-arg BOOL functions get a live fishhook toggle here.
// Multi-key MobileConfig/EasyGating/MSGC readers are validated, but forcing or
// even observing them through a generic C-symbol hook can hit hot startup/MCI
// paths. Those belong in the key/param-specific MobileConfig/EasyGating browser.
+ (BOOL)isHookableSymbol:(NSString *)name { return SCIStubProfileForSymbol(name) == SCICStubProfileNoArgBool; }
+ (BOOL)isForceableSymbol:(NSString *)name { return SCIStubProfileIsForceable(SCIStubProfileForSymbol(name)); }
+ (NSString *)blacklistReasonForSymbol:(NSString *)name { return SCIStubBlacklistReason(name); }
+ (NSString *)notHookableReasonForSymbol:(NSString *)name {
    NSString *r = SCIStubBlacklistReason(name);
    if (r) return r;
    SCICStubProfile p = SCIStubProfileForSymbol(name);
    if (p != SCICStubProfileUnknown) return @"validated multi-key reader; use MobileConfig/EasyGating key browser, not generic C hook.";
    return @"ABI/profile not validated for C hook; list-only.";
}
+ (NSString *)notForceableReasonForSymbol:(NSString *)name {
    NSString *r = SCIStubBlacklistReason(name);
    if (r) return r;
    SCICStubProfile p = SCIStubProfileForSymbol(name);
    if (p != SCICStubProfileUnknown && p != SCICStubProfileNoArgBool) return @"validated multi-key reader; force specific keys in MobileConfig/EasyGating browser.";
    if (![self isHookableSymbol:name]) return @"ABI/profile not validated for C hook; list-only.";
    if (![self isForceableSymbol:name]) return @"multi-key reader; observe-only. Force specific keys in MobileConfig/EasyGating browser.";
    return nil;
}

+ (BOOL)observeForSymbol:(NSString *)name { return [SCIDictPref(kObserveOverrides)[name ?: @""] boolValue]; }
+ (BOOL)setObserve:(BOOL)value forSymbol:(NSString *)name {
    if (![name isKindOfClass:NSString.class] || !name.length) return NO;
    if (value && ![self isHookableSymbol:name]) return NO;
    NSMutableDictionary *d = [SCIDictPref(kObserveOverrides) mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) d[name] = @YES; else [d removeObjectForKey:name];
    [SCIUtils setPref:d forKey:kObserveOverrides];
    if (value) [self installStubForSymbol:name];
    return YES;
}
+ (NSArray<NSString *> *)observedSymbols { return SCIDictPref(kObserveOverrides).allKeys ?: @[]; }

+ (NSNumber *)forceForSymbol:(NSString *)name {
    id v = SCIDictPref(kForceOverrides)[name ?: @""];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}
+ (BOOL)setForce:(NSNumber *)value forSymbol:(NSString *)name {
    if (![name isKindOfClass:NSString.class] || !name.length) return NO;
    if (value && ![self isForceableSymbol:name]) return NO;
    NSMutableDictionary *d = [SCIDictPref(kForceOverrides) mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) d[name] = value; else [d removeObjectForKey:name];
    [SCIUtils setPref:d forKey:kForceOverrides];
    if (value) [self setObserve:YES forSymbol:name];
    SCICStubSlot *s = slot_for(name.UTF8String);
    if (s) atomic_store(&s->force, value ? (value.boolValue ? 1 : 0) : -1);
    if (value) [self installStubForSymbol:name];
    return YES;
}
+ (NSArray<NSString *> *)forcedSymbols { return SCIDictPref(kForceOverrides).allKeys ?: @[]; }

+ (BOOL)hookInstalledForSymbol:(NSString *)name { SCICStubSlot *s = slot_for(name.UTF8String); return s && s->orig; }
+ (NSUInteger)callCountForSymbol:(NSString *)name { SCICStubSlot *s = slot_for(name.UTF8String); return s ? atomic_load(&s->hits) : 0; }
+ (NSNumber *)observedValueForSymbol:(NSString *)name {
    SCICStubSlot *s = slot_for(name.UTF8String);
    if (!s) return nil;
    int ov = atomic_load(&s->observed);
    return ov < 0 ? nil : @(ov != 0);
}

+ (void)refreshCacheFromDefaults { SCIStubRefreshCache(); }

+ (NSUInteger)installStubsForSymbols:(NSSet<NSString *> *)wanted {
    if (![wanted isKindOfClass:NSSet.class] || wanted.count == 0) return 0;
    NSDictionary *forced = SCIDictPref(kForceOverrides);
    struct rebinding rebs[MAX_STUBS];
    int nreb = 0;
    for (NSString *name in wanted) {
        if (nreb >= MAX_STUBS || g_slot_count >= MAX_STUBS) break;
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        SCICStubProfile profile = SCIStubProfileForSymbol(name);
        if (profile == SCICStubProfileUnknown) { SLOG("skip non-hookable %{public}s", name.UTF8String); continue; }
        if (slot_for(name.UTF8String)) { SCIStubRefreshCache(); continue; }
        NSString *under = [@"_" stringByAppendingString:name];
        if (dlsym(RTLD_DEFAULT, name.UTF8String) == NULL && dlsym(RTLD_DEFAULT, under.UTF8String) == NULL) {
            SLOG("skip %{public}s — not resolvable via dlsym", name.UTF8String);
            continue;
        }
        SCICStubSlot *slot = &g_slots[g_slot_count];
        memset(slot, 0, sizeof(*slot));
        strncpy(slot->name, name.UTF8String, sizeof(slot->name)-1);
        slot->profile = profile;
        id v = forced[name];
        if ([v isKindOfClass:NSNumber.class] && SCIStubProfileIsForceable(profile)) atomic_store(&slot->force, [v boolValue] ? 1 : 0);
        else atomic_store(&slot->force, -1);
        atomic_store(&slot->hits, 0);
        atomic_store(&slot->observed, -1);
        slot->orig = NULL;
        rebs[nreb].name = slot->name;
        rebs[nreb].replacement = g_stub_repls[g_slot_count];
        rebs[nreb].replaced = (void **)&slot->orig;
        g_slot_count++;
        nreb++;
        SLOG("runtime rebind %{public}s profile=%ld force=%d", name.UTF8String, (long)profile, atomic_load(&slot->force));
    }
    if (nreb == 0) return 0;
    int rc = rebind_symbols(rebs, nreb);
    SLOG("runtime rebind_symbols installed=%d rc=%d", nreb, rc);
    return (NSUInteger)nreb;
}

+ (BOOL)installStubForSymbol:(NSString *)name {
    if (![name isKindOfClass:NSString.class] || !name.length) return NO;
    if (![self isHookableSymbol:name]) return NO;
    if (slot_for(name.UTF8String)) { SCIStubRefreshCache(); return YES; }
    return [self installStubsForSymbols:[NSSet setWithObject:name]] > 0;
}

+ (void)reinstallPersistedStubs {
    NSMutableSet<NSString *> *wanted = [NSMutableSet set];
    [wanted addObjectsFromArray:SCIDictPref(kObserveOverrides).allKeys ?: @[]];
    [wanted addObjectsFromArray:SCIDictPref(kForceOverrides).allKeys ?: @[]];
    if (wanted.count == 0) { SLOG("no persisted stubs"); return; }
    [self installStubsForSymbols:wanted];
}

@end
