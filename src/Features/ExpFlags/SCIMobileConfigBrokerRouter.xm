#import "SCIMobileConfigBrokerRouter.h"
#import "SCIMobileConfigBrokerStore.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <substrate.h>

typedef BOOL (*MCBRIGInternalFn)(id, BOOL, unsigned long long);
typedef uintptr_t (*MCBRGeneric8Fn)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);

static NSMutableDictionary<NSString *, NSValue *> *gMCBROriginals;
static NSMutableSet<NSString *> *gMCBRInstalledIDs;
static NSMutableSet<NSString *> *gMCBRPendingIDs;
static NSMutableDictionary<NSString *, NSString *> *gMCBRErrors;

static void MCBREnsureState(void) {
    if (!gMCBROriginals) gMCBROriginals = [NSMutableDictionary dictionary];
    if (!gMCBRInstalledIDs) gMCBRInstalledIDs = [NSMutableSet set];
    if (!gMCBRPendingIDs) gMCBRPendingIDs = [NSMutableSet set];
    if (!gMCBRErrors) gMCBRErrors = [NSMutableDictionary dictionary];
}

static NSString *MCBRBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
}

static void *MCBRDlsymFlexible(NSString *symbol) {
    if (!symbol.length) return NULL;
    const char *s = symbol.UTF8String;
    void *p = dlsym(RTLD_DEFAULT, s);
    if (p) return p;
    if (s[0] == '_') return dlsym(RTLD_DEFAULT, s + 1);
    NSString *underscored = [@"_" stringByAppendingString:symbol];
    return dlsym(RTLD_DEFAULT, underscored.UTF8String);
}

static NSError *MCBRError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"SCIMobileConfigBrokerRouter" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"unknown"}];
}

static BOOL MCBRAddressIsExpectedOwner(void *addr, SCIMobileConfigBrokerDescriptor *d, NSString **ownerOut) {
    Dl_info info; memset(&info, 0, sizeof(info));
    if (!addr || dladdr(addr, &info) == 0 || !info.dli_fname) return NO;
    NSString *base = MCBRBasename(info.dli_fname);
    if (ownerOut) *ownerOut = base;
    return [base isEqualToString:d.imageName ?: @""];
}

static NSString *MCBRThreadKey(NSString *brokerID) {
    return [@"scimcbr.reentry." stringByAppendingString:(brokerID ?: @"")];
}

static BOOL MCBRThreadEnter(NSString *brokerID) {
    NSString *key = MCBRThreadKey(brokerID);
    NSMutableDictionary *td = NSThread.currentThread.threadDictionary;
    if ([td[key] boolValue]) return NO;
    td[key] = @YES;
    return YES;
}

static void MCBRThreadExit(NSString *brokerID) {
    [NSThread.currentThread.threadDictionary removeObjectForKey:MCBRThreadKey(brokerID)];
}

static NSValue *MCBROriginalValue(NSString *brokerID) {
    @synchronized([SCIMobileConfigBrokerRouter class]) {
        MCBREnsureState();
        return gMCBROriginals[brokerID ?: @""];
    }
}

static SCIMobileConfigBrokerDescriptor *MCBRDesc(NSString *brokerID) {
    return [SCIMobileConfigBrokerDescriptor descriptorForID:brokerID];
}

static BOOL MCBRForcedValueIfPresent(SCIMobileConfigBrokerDescriptor *d, uint64_t value, BOOL *outValue) {
    if (!d.brokerID.length) return NO;
    NSString *key = [SCIMobileConfigBrokerStore overrideKeyForBroker:d value:value];
    NSNumber *forced = [SCIMobileConfigBrokerStore overrideValueForKey:key];
    if (!forced) return NO;
    if (outValue) *outValue = forced.boolValue;
    [SCIMobileConfigBrokerStore noteHitForBrokerID:d.brokerID value:value forced:YES];
    return YES;
}

static BOOL MCBRRecordOriginalAndReturn(SCIMobileConfigBrokerDescriptor *d, uint64_t value, BOOL original) {
    if (!d.brokerID.length) return original;
    NSString *key = [SCIMobileConfigBrokerStore overrideKeyForBroker:d value:value];
    [SCIMobileConfigBrokerStore noteObservedValue:original forOverrideKey:key];
    [SCIMobileConfigBrokerStore noteHitForBrokerID:d.brokerID value:value forced:NO];
    return original;
}

static BOOL hook_IGInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    SCIMobileConfigBrokerDescriptor *d = MCBRDesc(@"ig");
    BOOL forced = NO;
    if (MCBRForcedValueIfPresent(d, specifier, &forced)) return forced;

    MCBRIGInternalFn orig = (MCBRIGInternalFn)MCBROriginalValue(@"ig").pointerValue;
    if (!MCBRThreadEnter(@"ig")) return orig ? orig(ctx, defaultValue, specifier) : defaultValue;
    BOOL original = orig ? orig(ctx, defaultValue, specifier) : defaultValue;
    MCBRThreadExit(@"ig");
    return MCBRRecordOriginalAndReturn(d, specifier, original);
}

static BOOL hook_IGSessionlessInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    SCIMobileConfigBrokerDescriptor *d = MCBRDesc(@"igsl");
    BOOL forced = NO;
    if (MCBRForcedValueIfPresent(d, specifier, &forced)) return forced;

    MCBRIGInternalFn orig = (MCBRIGInternalFn)MCBROriginalValue(@"igsl").pointerValue;
    if (!MCBRThreadEnter(@"igsl")) return orig ? orig(ctx, defaultValue, specifier) : defaultValue;
    BOOL original = orig ? orig(ctx, defaultValue, specifier) : defaultValue;
    MCBRThreadExit(@"igsl");
    return MCBRRecordOriginalAndReturn(d, specifier, original);
}

static uintptr_t MCBRGenericHook(NSString *brokerID,
                                 uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3,
                                 uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    SCIMobileConfigBrokerDescriptor *d = MCBRDesc(brokerID);
    uintptr_t args[8] = {a0,a1,a2,a3,a4,a5,a6,a7};
    NSUInteger keyIndex = MIN((NSUInteger)7, d.keyArgumentIndex);
    NSUInteger defIndex = MIN((NSUInteger)7, d.defaultArgumentIndex);
    uint64_t keyValue = (uint64_t)args[keyIndex];
    BOOL forced = NO;
    if (MCBRForcedValueIfPresent(d, keyValue, &forced)) return forced ? 1 : 0;

    MCBRGeneric8Fn orig = (MCBRGeneric8Fn)MCBROriginalValue(brokerID).pointerValue;
    if (!MCBRThreadEnter(brokerID)) return orig ? orig(a0,a1,a2,a3,a4,a5,a6,a7) : (args[defIndex] & 1);
    uintptr_t raw = orig ? orig(a0,a1,a2,a3,a4,a5,a6,a7) : (args[defIndex] & 1);
    MCBRThreadExit(brokerID);
    BOOL original = raw ? YES : NO;
    return MCBRRecordOriginalAndReturn(d, keyValue, original) ? 1 : 0;
}

#define MCBR_GENERIC_WRAPPER(NAME, BID) \
static uintptr_t NAME(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) { \
    return MCBRGenericHook(@BID, a0, a1, a2, a3, a4, a5, a6, a7); \
}

MCBR_GENERIC_WRAPPER(hook_EasyGatingPlatformGetBoolean, "eg")
MCBR_GENERIC_WRAPPER(hook_MCIMobileConfigGetBoolean, "mci")
MCBR_GENERIC_WRAPPER(hook_EasyGatingInternalGetBoolean, "egi")
MCBR_GENERIC_WRAPPER(hook_EasyGatingAuthDataGetBoolean, "ega")
MCBR_GENERIC_WRAPPER(hook_MCIExperimentCacheBool, "mcic")
MCBR_GENERIC_WRAPPER(hook_MCIExtensionExperimentCacheBool, "mcie")
MCBR_GENERIC_WRAPPER(hook_METAExtensionsBool, "meta")
MCBR_GENERIC_WRAPPER(hook_METAExtensionsBoolNoExposure, "metanx")
MCBR_GENERIC_WRAPPER(hook_MSGCSessionedBool, "msgc")

static void *MCBRReplacementForID(NSString *brokerID) {
    if ([brokerID isEqualToString:@"ig"]) return (void *)hook_IGInternalUse;
    if ([brokerID isEqualToString:@"igsl"]) return (void *)hook_IGSessionlessInternalUse;
    if ([brokerID isEqualToString:@"eg"]) return (void *)hook_EasyGatingPlatformGetBoolean;
    if ([brokerID isEqualToString:@"mci"]) return (void *)hook_MCIMobileConfigGetBoolean;
    if ([brokerID isEqualToString:@"egi"]) return (void *)hook_EasyGatingInternalGetBoolean;
    if ([brokerID isEqualToString:@"ega"]) return (void *)hook_EasyGatingAuthDataGetBoolean;
    if ([brokerID isEqualToString:@"mcic"]) return (void *)hook_MCIExperimentCacheBool;
    if ([brokerID isEqualToString:@"mcie"]) return (void *)hook_MCIExtensionExperimentCacheBool;
    if ([brokerID isEqualToString:@"meta"]) return (void *)hook_METAExtensionsBool;
    if ([brokerID isEqualToString:@"metanx"]) return (void *)hook_METAExtensionsBoolNoExposure;
    if ([brokerID isEqualToString:@"msgc"]) return (void *)hook_MSGCSessionedBool;
    return NULL;
}

static NSString *MCBRBasenameForHeader(const struct mach_header *mh) {
    Dl_info info; memset(&info, 0, sizeof(info));
    if (!mh || dladdr((const void *)mh, &info) == 0 || !info.dli_fname) return @"";
    return MCBRBasename(info.dli_fname);
}

static void MCBRImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    NSString *base = MCBRBasenameForHeader(mh);
    if (![base isEqualToString:@"FBSharedFramework"]) return;
    [SCIMobileConfigBrokerRouter retryPendingBrokersForImageBasename:base];
}

@implementation SCIMobileConfigBrokerRouter

+ (BOOL)installBroker:(SCIMobileConfigBrokerDescriptor *)descriptor error:(NSError * _Nullable * _Nullable)error {
    if (!descriptor.brokerID.length || !descriptor.symbol.length) {
        if (error) *error = MCBRError(1, @"Missing broker descriptor fields");
        return NO;
    }

    @synchronized(self) {
        MCBREnsureState();
        if ([gMCBRInstalledIDs containsObject:descriptor.brokerID]) return YES;
    }

    void *addr = MCBRDlsymFlexible(descriptor.symbol);
    if (!addr) {
        NSString *msg = [NSString stringWithFormat:@"Symbol not found yet: %@", descriptor.symbol];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        @synchronized(self) { MCBREnsureState(); [gMCBRPendingIDs addObject:descriptor.brokerID]; }
        if (error) *error = MCBRError(2, msg);
        return NO;
    }

    NSString *owner = nil;
    if (!MCBRAddressIsExpectedOwner(addr, descriptor, &owner)) {
        NSString *msg = [NSString stringWithFormat:@"Owner mismatch %@ for %@", owner ?: @"?", descriptor.symbol];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        @synchronized(self) { MCBREnsureState(); [gMCBRPendingIDs addObject:descriptor.brokerID]; }
        if (error) *error = MCBRError(3, msg);
        return NO;
    }

    uint64_t cur = 0;
    memcpy(&cur, addr, sizeof(cur));
    if (descriptor.expectedOrig8 != 0 && cur != descriptor.expectedOrig8) {
        NSString *msg = [NSString stringWithFormat:@"Build guard mismatch %@ cur=0x%016llx expected=0x%016llx", descriptor.symbol, (unsigned long long)cur, (unsigned long long)descriptor.expectedOrig8];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = MCBRError(4, msg);
        return NO;
    }

    void *replacement = MCBRReplacementForID(descriptor.brokerID);
    if (!replacement) {
        NSString *msg = [NSString stringWithFormat:@"No replacement for broker id %@", descriptor.brokerID];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = MCBRError(5, msg);
        return NO;
    }

    void *orig = NULL;
    MSHookFunction(addr, replacement, &orig);
    if (!orig) {
        NSString *msg = [NSString stringWithFormat:@"MSHookFunction returned nil original for %@", descriptor.symbol];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = MCBRError(6, msg);
        return NO;
    }

    @synchronized(self) {
        MCBREnsureState();
        gMCBROriginals[descriptor.brokerID] = [NSValue valueWithPointer:orig];
        [gMCBRInstalledIDs addObject:descriptor.brokerID];
        [gMCBRPendingIDs removeObject:descriptor.brokerID];
        [gMCBRErrors removeObjectForKey:descriptor.brokerID];
    }
    [SCIMobileConfigBrokerStore noteLastError:nil brokerID:descriptor.brokerID];
    NSLog(@"[RyukGram][MCBR] installed %@ %@ addr=%p", descriptor.brokerID, descriptor.symbol, addr);
    return YES;
}

+ (BOOL)isInstalled:(NSString *)brokerID {
    @synchronized(self) { MCBREnsureState(); return [gMCBRInstalledIDs containsObject:(brokerID ?: @"")]; }
}

+ (NSUInteger)installedCount {
    @synchronized(self) { MCBREnsureState(); return gMCBRInstalledIDs.count; }
}

+ (NSDictionary<NSString *,NSString *> *)installErrors {
    @synchronized(self) { MCBREnsureState(); return [gMCBRErrors copy] ?: @{}; }
}

+ (void)installEnabledBrokers {
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        if (![SCIMobileConfigBrokerStore shouldInstallBrokerID:d.brokerID]) continue;
        NSError *err = nil;
        if (![self installBroker:d error:&err]) NSLog(@"[RyukGram][MCBR] install failed %@: %@", d.brokerID, err.localizedDescription ?: @"?");
    }
}

+ (void)retryPendingBrokersForImageBasename:(NSString *)basename {
    if (![basename isEqualToString:@"FBSharedFramework"]) return;
    NSArray<NSString *> *ids = nil;
    @synchronized(self) { MCBREnsureState(); ids = gMCBRPendingIDs.allObjects; }
    for (NSString *bid in ids) {
        SCIMobileConfigBrokerDescriptor *d = [SCIMobileConfigBrokerDescriptor descriptorForID:bid];
        if (!d || ![SCIMobileConfigBrokerStore shouldInstallBrokerID:bid]) continue;
        NSError *err = nil;
        [self installBroker:d error:&err];
    }
}

+ (void)bootstrap {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
        _dyld_register_func_for_add_image(MCBRImageAdded);
        [self installEnabledBrokers];
    });
}

@end

%ctor {
    [SCIMobileConfigBrokerRouter bootstrap];
}
