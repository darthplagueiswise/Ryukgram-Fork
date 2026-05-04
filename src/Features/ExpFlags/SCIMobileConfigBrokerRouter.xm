#import "SCIMobileConfigBrokerRouter.h"
#import "SCIMobileConfigBrokerStore.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <substrate.h>

static NSMutableDictionary<NSString *, NSValue *> *gMCBROriginals;
static NSMutableDictionary<NSValue *, NSString *> *gMCBRAddressToID;
static NSMutableSet<NSString *> *gMCBRInstalledIDs;
static NSMutableDictionary<NSString *, NSString *> *gMCBRErrors;

// Primary IG InternalUse signature validated from existing project code:
// BOOL fn(id ctx, BOOL defaultValue, unsigned long long specifier)
typedef BOOL (*MCBRIGInternalFn)(id, BOOL, unsigned long long);

// Generic register-preserving integer/pointer ABI wrapper for bool-returning C brokers.
// Extra integer args are harmless for callees that accept fewer args on arm64.
typedef BOOL (*MCBRGenericFn)(void *, void *, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);

static void MCBREnsureState(void) {
    if (!gMCBROriginals) gMCBROriginals = [NSMutableDictionary dictionary];
    if (!gMCBRAddressToID) gMCBRAddressToID = [NSMutableDictionary dictionary];
    if (!gMCBRInstalledIDs) gMCBRInstalledIDs = [NSMutableSet set];
    if (!gMCBRErrors) gMCBRErrors = [NSMutableDictionary dictionary];
}

static NSString *MCBRBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
}

static BOOL MCBRImageIsFBSharedFramework(void *addr) {
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (!addr || dladdr(addr, &info) == 0) return NO;
    return [MCBRBasename(info.dli_fname) isEqualToString:@"FBSharedFramework"];
}

static void *MCBRDlsymFlexible(const char *symbol) {
    if (!symbol || !symbol[0]) return NULL;
    void *p = dlsym(RTLD_DEFAULT, symbol);
    if (p) return p;
    if (symbol[0] == '_') return dlsym(RTLD_DEFAULT, symbol + 1);
    char underscored[512];
    snprintf(underscored, sizeof(underscored), "_%s", symbol);
    return dlsym(RTLD_DEFAULT, underscored);
}

static NSString *MCBRIDForReturnAddress(void *ret) {
    @synchronized([SCIMobileConfigBrokerRouter class]) {
        MCBREnsureState();
        return gMCBRAddressToID[[NSValue valueWithPointer:ret]];
    }
}

static NSString *MCBRIDForSymbolAddress(void *addr) {
    @synchronized([SCIMobileConfigBrokerRouter class]) {
        MCBREnsureState();
        return gMCBRAddressToID[[NSValue valueWithPointer:addr]];
    }
}

static BOOL MCBRResolveOverride(NSString *brokerID, BOOL original) {
    NSNumber *forced = [SCIMobileConfigBrokerStore overrideValueForBrokerID:brokerID];
    BOOL wasForced = (forced != nil);
    BOOL ret = forced ? forced.boolValue : original;
    [SCIMobileConfigBrokerStore noteObservedValue:original brokerID:brokerID];
    [SCIMobileConfigBrokerStore noteHitForBrokerID:brokerID forced:wasForced];
    return ret;
}

static BOOL hook_IGInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    NSString *bid = @"ig";
    MCBRIGInternalFn orig = NULL;
    @synchronized([SCIMobileConfigBrokerRouter class]) { orig = (MCBRIGInternalFn)gMCBROriginals[bid].pointerValue; }
    BOOL original = orig ? orig(ctx, defaultValue, specifier) : defaultValue;
    return MCBRResolveOverride(bid, original);
}

static BOOL hook_IGSessionlessInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    NSString *bid = @"igsl";
    MCBRIGInternalFn orig = NULL;
    @synchronized([SCIMobileConfigBrokerRouter class]) { orig = (MCBRIGInternalFn)gMCBROriginals[bid].pointerValue; }
    BOOL original = orig ? orig(ctx, defaultValue, specifier) : defaultValue;
    return MCBRResolveOverride(bid, original);
}

static BOOL hook_GenericBoolBroker(void *a0, void *a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) {
    // The same replacement is used for several C bool brokers. We map by original stub address is not available here,
    // so use return address only for diagnostics fallback; direct mapping is handled by per-symbol installation below.
    // For generic brokers we deliberately keep a single current broker lookup by thread-local install map unavailable,
    // so each generic symbol gets a tiny selector below through trampoline-specific functions.
    (void)a0; (void)a1; (void)a2; (void)a3; (void)a4; (void)a5; (void)a6; (void)a7;
    return NO;
}

#define MCBR_GENERIC_HOOK(NAME, BID) \
static BOOL NAME(void *a0, void *a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7) { \
    NSString *bid = @BID; \
    MCBRGenericFn orig = NULL; \
    @synchronized([SCIMobileConfigBrokerRouter class]) { orig = (MCBRGenericFn)gMCBROriginals[bid].pointerValue; } \
    BOOL original = orig ? orig(a0, a1, a2, a3, a4, a5, a6, a7) : NO; \
    return MCBRResolveOverride(bid, original); \
}

MCBR_GENERIC_HOOK(hook_EasyGatingPlatformGetBoolean, "eg")
MCBR_GENERIC_HOOK(hook_MCIMobileConfigGetBoolean, "mci")
MCBR_GENERIC_HOOK(hook_EasyGatingInternalGetBoolean, "egi")
MCBR_GENERIC_HOOK(hook_MCIExperimentCacheBool, "mcic")
MCBR_GENERIC_HOOK(hook_MCIExtensionExperimentCacheBool, "mcie")
MCBR_GENERIC_HOOK(hook_METAExtensionsBool, "meta")
MCBR_GENERIC_HOOK(hook_METAExtensionsBoolNoExposure, "metanx")
MCBR_GENERIC_HOOK(hook_MSGCSessionedBool, "msgc")

static void *MCBRReplacementForID(NSString *brokerID) {
    if ([brokerID isEqualToString:@"ig"]) return (void *)hook_IGInternalUse;
    if ([brokerID isEqualToString:@"igsl"]) return (void *)hook_IGSessionlessInternalUse;
    if ([brokerID isEqualToString:@"eg"]) return (void *)hook_EasyGatingPlatformGetBoolean;
    if ([brokerID isEqualToString:@"mci"]) return (void *)hook_MCIMobileConfigGetBoolean;
    if ([brokerID isEqualToString:@"egi"]) return (void *)hook_EasyGatingInternalGetBoolean;
    if ([brokerID isEqualToString:@"mcic"]) return (void *)hook_MCIExperimentCacheBool;
    if ([brokerID isEqualToString:@"mcie"]) return (void *)hook_MCIExtensionExperimentCacheBool;
    if ([brokerID isEqualToString:@"meta"]) return (void *)hook_METAExtensionsBool;
    if ([brokerID isEqualToString:@"metanx"]) return (void *)hook_METAExtensionsBoolNoExposure;
    if ([brokerID isEqualToString:@"msgc"]) return (void *)hook_MSGCSessionedBool;
    return NULL;
}

@implementation SCIMobileConfigBrokerRouter

+ (NSError *)error:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:@"SCIMobileConfigBrokerRouter" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown"}];
}

+ (BOOL)installBroker:(SCIMobileConfigBrokerDescriptor *)descriptor error:(NSError **)error {
    if (!descriptor.brokerID.length || !descriptor.symbol.length) {
        if (error) *error = [self error:1 message:@"Missing broker descriptor fields"];
        return NO;
    }

    @synchronized(self) {
        MCBREnsureState();
        if ([gMCBRInstalledIDs containsObject:descriptor.brokerID]) return YES;
    }

    void *addr = MCBRDlsymFlexible(descriptor.symbol.UTF8String);
    if (!addr) {
        NSString *msg = [NSString stringWithFormat:@"Symbol not found: %@", descriptor.symbol];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = [self error:2 message:msg];
        return NO;
    }

    if (!MCBRImageIsFBSharedFramework(addr)) {
        NSString *msg = [NSString stringWithFormat:@"Refused non-FBSharedFramework address for %@", descriptor.symbol];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = [self error:3 message:msg];
        return NO;
    }

    uint64_t cur = 0;
    memcpy(&cur, addr, sizeof(cur));
    if (descriptor.expectedOrig8 != 0 && cur != descriptor.expectedOrig8) {
        NSString *msg = [NSString stringWithFormat:@"Build guard mismatch %@ cur=0x%016llx expected=0x%016llx", descriptor.symbol, (unsigned long long)cur, (unsigned long long)descriptor.expectedOrig8];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = [self error:4 message:msg];
        return NO;
    }

    void *replacement = MCBRReplacementForID(descriptor.brokerID);
    if (!replacement) {
        NSString *msg = [NSString stringWithFormat:@"No replacement for broker id %@", descriptor.brokerID];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = [self error:5 message:msg];
        return NO;
    }

    void *orig = NULL;
    MSHookFunction(addr, replacement, &orig);
    if (!orig) {
        NSString *msg = [NSString stringWithFormat:@"MSHookFunction returned nil original for %@", descriptor.symbol];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = [self error:6 message:msg];
        return NO;
    }

    @synchronized(self) {
        MCBREnsureState();
        gMCBROriginals[descriptor.brokerID] = [NSValue valueWithPointer:orig];
        gMCBRAddressToID[[NSValue valueWithPointer:addr]] = descriptor.brokerID;
        [gMCBRInstalledIDs addObject:descriptor.brokerID];
        [gMCBRErrors removeObjectForKey:descriptor.brokerID];
    }

    [SCIMobileConfigBrokerStore noteLastError:nil brokerID:descriptor.brokerID];
    NSLog(@"[RyukGram][MCBR] installed %@ %@ addr=%p", descriptor.brokerID, descriptor.symbol, addr);
    return YES;
}

+ (BOOL)isInstalled:(NSString *)brokerID {
    @synchronized(self) { MCBREnsureState(); return [gMCBRInstalledIDs containsObject:brokerID ?: @""]; }
}

+ (NSUInteger)installedCount {
    @synchronized(self) { MCBREnsureState(); return gMCBRInstalledIDs.count; }
}

+ (NSDictionary<NSString *,NSString *> *)installErrors {
    @synchronized(self) { MCBREnsureState(); return [gMCBRErrors copy] ?: @{}; }
}

+ (void)installEnabledBrokers {
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        BOOL shouldInstall = [SCIMobileConfigBrokerStore isBrokerHookEnabledForID:d.brokerID] || [SCIMobileConfigBrokerStore overrideValueForBrokerID:d.brokerID] != nil;
        if (!shouldInstall) continue;
        NSError *err = nil;
        if (![self installBroker:d error:&err]) NSLog(@"[RyukGram][MCBR] install failed %@: %@", d.brokerID, err.localizedDescription ?: @"?");
    }
}

+ (void)bootstrap {
    [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
    [self installEnabledBrokers];
}

@end

%ctor {
    [SCIMobileConfigBrokerRouter bootstrap];
}
