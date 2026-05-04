#import "SCIMobileConfigBrokerRouter.h"
#import "SCIMobileConfigBrokerStore.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <substrate.h>

// C-broker router for FBSharedFramework MobileConfig/EasyGating bool readers.
// This is deliberately separate from DexKit ObjC getter scanning.

typedef BOOL (*SCIIGMCBoolFn)(id ctx, BOOL defaultValue, uint64_t specifier);
typedef uintptr_t (*SCIGeneric8Fn)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);

static NSMutableDictionary<NSString *, NSValue *> *gOriginals;
static NSMutableDictionary<NSString *, SCIMobileConfigBrokerDescriptor *> *gInstalled;

static void SCIEnsureMaps(void) {
    if (!gOriginals) gOriginals = [NSMutableDictionary dictionary];
    if (!gInstalled) gInstalled = [NSMutableDictionary dictionary];
}

static NSString *SCIDescForError(NSError **error, NSInteger code, NSString *msg) {
    if (error) *error = [NSError errorWithDomain:@"SCIMobileConfigBrokerRouter" code:code userInfo:@{NSLocalizedDescriptionKey: msg ?: @"unknown"}];
    return msg ?: @"unknown";
}

static void *SCIDlsymFlexible(const char *symbol) {
    if (!symbol || !symbol[0]) return NULL;
    void *p = dlsym(RTLD_DEFAULT, symbol);
    if (p) return p;
    if (symbol[0] == '_') return dlsym(RTLD_DEFAULT, symbol + 1);
    char buf[512];
    snprintf(buf, sizeof(buf), "_%s", symbol);
    return dlsym(RTLD_DEFAULT, buf);
}

static BOOL SCIValidateOwner(void *sym, SCIMobileConfigBrokerDescriptor *broker, NSError **error) {
    if (!sym) { SCIDescForError(error, 1, @"symbol not found"); return NO; }
    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr(sym, &info) == 0 || !info.dli_fname) { SCIDescForError(error, 2, @"dladdr failed"); return NO; }
    NSString *base = @(info.dli_fname).lastPathComponent;
    if (![base isEqualToString:broker.imageName]) {
        SCIDescForError(error, 3, [NSString stringWithFormat:@"owner mismatch: %@", base ?: @"nil"]);
        return NO;
    }
    if (broker.expectedOrig8 != 0) {
        uint64_t cur = 0;
        memcpy(&cur, sym, sizeof(cur));
        if (cur != broker.expectedOrig8) {
            SCIDescForError(error, 4, [NSString stringWithFormat:@"fingerprint mismatch cur=0x%016llx expected=0x%016llx", (unsigned long long)cur, (unsigned long long)broker.expectedOrig8]);
            return NO;
        }
    }
    return YES;
}

static NSString *SCIOverrideKey(SCIMobileConfigBrokerDescriptor *broker, uint64_t value) {
    return [SCIMobileConfigBrokerStore overrideKeyForBroker:broker value:value];
}

static BOOL SCIThreadGuardEnter(NSString *name) {
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    NSString *key = [@"scimcbr.reentry." stringByAppendingString:name ?: @""];
    if ([td[key] boolValue]) return NO;
    td[key] = @YES;
    return YES;
}

static void SCIThreadGuardExit(NSString *name) {
    NSString *key = [@"scimcbr.reentry." stringByAppendingString:name ?: @""];
    [NSThread.currentThread.threadDictionary removeObjectForKey:key];
}

static BOOL SCIHandleForcedOrObserved(SCIMobileConfigBrokerDescriptor *broker, uint64_t keyValue, BOOL original, BOOL *outValue) {
    NSString *key = SCIOverrideKey(broker, keyValue);
    NSNumber *forced = [SCIMobileConfigBrokerStore overrideValueForKey:key];
    if (forced) {
        [SCIMobileConfigBrokerStore noteObservedValue:forced.boolValue forOverrideKey:key];
        if (outValue) *outValue = forced.boolValue;
        return YES;
    }
    [SCIMobileConfigBrokerStore noteObservedValue:original forOverrideKey:key];
    if (outValue) *outValue = original;
    return NO;
}

static SCIMobileConfigBrokerDescriptor *SCIBroker(NSString *brokerID) {
    return [SCIMobileConfigBrokerDescriptor descriptorForID:brokerID];
}

static SCIIGMCBoolFn orig_ig = NULL;
static BOOL hook_ig(id ctx, BOOL defaultValue, uint64_t specifier) {
    SCIMobileConfigBrokerDescriptor *broker = SCIBroker(@"ig");
    NSString *name = @"ig";
    if (!SCIThreadGuardEnter(name)) return orig_ig ? orig_ig(ctx, defaultValue, specifier) : defaultValue;
    BOOL original = orig_ig ? orig_ig(ctx, defaultValue, specifier) : defaultValue;
    BOOL ret = original;
    SCIHandleForcedOrObserved(broker, specifier, original, &ret);
    SCIThreadGuardExit(name);
    return ret;
}

static SCIIGMCBoolFn orig_igsl = NULL;
static BOOL hook_igsl(id ctx, BOOL defaultValue, uint64_t specifier) {
    SCIMobileConfigBrokerDescriptor *broker = SCIBroker(@"igsl");
    NSString *name = @"igsl";
    if (!SCIThreadGuardEnter(name)) return orig_igsl ? orig_igsl(ctx, defaultValue, specifier) : defaultValue;
    BOOL original = orig_igsl ? orig_igsl(ctx, defaultValue, specifier) : defaultValue;
    BOOL ret = original;
    SCIHandleForcedOrObserved(broker, specifier, original, &ret);
    SCIThreadGuardExit(name);
    return ret;
}

static SCIGeneric8Fn orig_egp = NULL;
static uintptr_t hook_egp(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    SCIMobileConfigBrokerDescriptor *broker = SCIBroker(@"egp");
    if (!SCIThreadGuardEnter(@"egp")) return orig_egp ? orig_egp(a0,a1,a2,a3,a4,a5,a6,a7) : (a2 & 1);
    uintptr_t raw = orig_egp ? orig_egp(a0,a1,a2,a3,a4,a5,a6,a7) : (a2 & 1);
    BOOL ret = raw ? YES : NO;
    SCIHandleForcedOrObserved(broker, (uint64_t)a1, ret, &ret);
    SCIThreadGuardExit(@"egp");
    return ret ? 1 : 0;
}

static SCIGeneric8Fn orig_mci = NULL;
static uintptr_t hook_mci(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    SCIMobileConfigBrokerDescriptor *broker = SCIBroker(@"mci");
    if (!SCIThreadGuardEnter(@"mci")) return orig_mci ? orig_mci(a0,a1,a2,a3,a4,a5,a6,a7) : 0;
    uintptr_t raw = orig_mci ? orig_mci(a0,a1,a2,a3,a4,a5,a6,a7) : 0;
    BOOL ret = raw ? YES : NO;
    SCIHandleForcedOrObserved(broker, (uint64_t)a2, ret, &ret);
    SCIThreadGuardExit(@"mci");
    return ret ? 1 : 0;
}

#define SCI_GENERIC_HOOK(ID, ORIGVAR, KEYARG, DEFARG) \
static SCIGeneric8Fn ORIGVAR = NULL; \
static uintptr_t hook_##ID(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) { \
    SCIMobileConfigBrokerDescriptor *broker = SCIBroker(@#ID); \
    if (!SCIThreadGuardEnter(@#ID)) return ORIGVAR ? ORIGVAR(a0,a1,a2,a3,a4,a5,a6,a7) : 0; \
    uintptr_t args[8] = {a0,a1,a2,a3,a4,a5,a6,a7}; \
    uintptr_t raw = ORIGVAR ? ORIGVAR(a0,a1,a2,a3,a4,a5,a6,a7) : (args[DEFARG] & 1); \
    BOOL ret = raw ? YES : NO; \
    SCIHandleForcedOrObserved(broker, (uint64_t)args[KEYARG], ret, &ret); \
    SCIThreadGuardExit(@#ID); \
    return ret ? 1 : 0; \
}

SCI_GENERIC_HOOK(egi, orig_egi, 0, 2)
SCI_GENERIC_HOOK(ega, orig_ega, 1, 2)
SCI_GENERIC_HOOK(mcic, orig_mcic, 2, 2)
SCI_GENERIC_HOOK(mcie, orig_mcie, 2, 2)
SCI_GENERIC_HOOK(meta, orig_meta, 1, 2)
SCI_GENERIC_HOOK(metanx, orig_metanx, 1, 2)
SCI_GENERIC_HOOK(msgc, orig_msgc, 2, 2)

static void *SCIDetourForBroker(NSString *brokerID, void ***origOut) {
    if ([brokerID isEqualToString:@"ig"]) { if (origOut) *origOut = (void **)&orig_ig; return (void *)&hook_ig; }
    if ([brokerID isEqualToString:@"igsl"]) { if (origOut) *origOut = (void **)&orig_igsl; return (void *)&hook_igsl; }
    if ([brokerID isEqualToString:@"egp"]) { if (origOut) *origOut = (void **)&orig_egp; return (void *)&hook_egp; }
    if ([brokerID isEqualToString:@"mci"]) { if (origOut) *origOut = (void **)&orig_mci; return (void *)&hook_mci; }
    if ([brokerID isEqualToString:@"egi"]) { if (origOut) *origOut = (void **)&orig_egi; return (void *)&hook_egi; }
    if ([brokerID isEqualToString:@"ega"]) { if (origOut) *origOut = (void **)&orig_ega; return (void *)&hook_ega; }
    if ([brokerID isEqualToString:@"mcic"]) { if (origOut) *origOut = (void **)&orig_mcic; return (void *)&hook_mcic; }
    if ([brokerID isEqualToString:@"mcie"]) { if (origOut) *origOut = (void **)&orig_mcie; return (void *)&hook_mcie; }
    if ([brokerID isEqualToString:@"meta"]) { if (origOut) *origOut = (void **)&orig_meta; return (void *)&hook_meta; }
    if ([brokerID isEqualToString:@"metanx"]) { if (origOut) *origOut = (void **)&orig_metanx; return (void *)&hook_metanx; }
    if ([brokerID isEqualToString:@"msgc"]) { if (origOut) *origOut = (void **)&orig_msgc; return (void *)&hook_msgc; }
    return NULL;
}

BOOL SCIMCBrokerInstall(SCIMobileConfigBrokerDescriptor *broker, NSError **error) {
    if (!broker.brokerID.length || !broker.symbol.length) return NO;
    @synchronized([SCIMobileConfigBrokerDescriptor class]) {
        SCIEnsureMaps();
        if (gInstalled[broker.brokerID]) return YES;
    }
    void *sym = SCIDlsymFlexible(broker.symbol.UTF8String);
    if (!SCIValidateOwner(sym, broker, error)) {
        [SCIMobileConfigBrokerStore setLastError:(error && *error) ? (*error).localizedDescription : @"validation failed" forBrokerID:broker.brokerID];
        return NO;
    }
    void **origPtr = NULL;
    void *detour = SCIDetourForBroker(broker.brokerID, &origPtr);
    if (!detour || !origPtr) {
        [SCIMobileConfigBrokerStore setLastError:@"no detour for broker" forBrokerID:broker.brokerID];
        return NO;
    }
    MSHookFunction(sym, detour, origPtr);
    @synchronized([SCIMobileConfigBrokerDescriptor class]) {
        SCIEnsureMaps();
        gInstalled[broker.brokerID] = broker;
        if (*origPtr) gOriginals[broker.brokerID] = [NSValue valueWithPointer:*origPtr];
    }
    [SCIMobileConfigBrokerStore setLastError:nil forBrokerID:broker.brokerID];
    NSLog(@"[RyukGram][MCBroker] installed %@ %@", broker.brokerID, broker.symbol);
    return YES;
}

BOOL SCIMCBrokerIsInstalled(NSString *brokerID) {
    @synchronized([SCIMobileConfigBrokerDescriptor class]) { return gInstalled[brokerID] != nil; }
}

NSUInteger SCIMCBrokerInstalledCount(void) {
    @synchronized([SCIMobileConfigBrokerDescriptor class]) { return gInstalled.count; }
}

NSString *SCIMCBrokerRuntimeSummary(void) {
    return [NSString stringWithFormat:@"installed=%lu hooks=%lu overrides=%lu", (unsigned long)SCIMCBrokerInstalledCount(), (unsigned long)[SCIMobileConfigBrokerStore enabledHookBrokerIDs].count, (unsigned long)[SCIMobileConfigBrokerStore activeOverrideKeys].count];
}

void SCIMCBrokerBootstrap(void) {
    [SCIMobileConfigBrokerStore registerDefaults];
    NSMutableSet<NSString *> *ids = [NSMutableSet setWithArray:[SCIMobileConfigBrokerStore enabledHookBrokerIDs]];
    for (NSString *key in [SCIMobileConfigBrokerStore activeOverrideKeys]) {
        NSString *bid = nil;
        [SCIMobileConfigBrokerStore parseOverrideKey:key brokerID:&bid image:nil symbol:nil kind:nil value:nil];
        if (bid.length) [ids addObject:bid];
    }
    for (NSString *bid in ids) {
        SCIMobileConfigBrokerDescriptor *d = [SCIMobileConfigBrokerDescriptor descriptorForID:bid];
        if (!d) continue;
        NSError *error = nil;
        SCIMCBrokerInstall(d, &error);
    }
}

%ctor {
    SCIMCBrokerBootstrap();
}
