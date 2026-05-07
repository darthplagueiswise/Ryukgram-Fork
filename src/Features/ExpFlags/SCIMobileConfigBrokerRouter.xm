#import "SCIMobileConfigBrokerRouter.h"
#import "SCIMobileConfigBrokerStore.h"
#import "SCIDexKitNameResolver.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

typedef BOOL (*MCBRIGBoolFn)(id ctx, BOOL def, unsigned long long specifier);
typedef uintptr_t (*MCBRGeneric8Fn)(uintptr_t, uintptr_t, uintptr_t, uintptr_t,
                                    uintptr_t, uintptr_t, uintptr_t, uintptr_t);

static MCBRIGBoolFn orig_ig = NULL;
static MCBRIGBoolFn orig_igsl = NULL;
static MCBRGeneric8Fn orig_eg = NULL;
static MCBRGeneric8Fn orig_mci = NULL;
static MCBRGeneric8Fn orig_egi = NULL;
static MCBRGeneric8Fn orig_ega = NULL;
static MCBRGeneric8Fn orig_mcic = NULL;
static MCBRGeneric8Fn orig_mcie = NULL;
static MCBRGeneric8Fn orig_meta = NULL;
static MCBRGeneric8Fn orig_metanx = NULL;
static MCBRGeneric8Fn orig_msgc = NULL;

static __thread int gMCBRReentryDepth = 0;
static NSMutableDictionary<NSString *, NSString *> *gMCBRErrors;
static NSMutableSet<NSString *> *gMCBRInstalled;
static NSMutableSet<NSString *> *gMCBRResolverNoted;

static void MCBREnsureState(void) {
    if (!gMCBRErrors) gMCBRErrors = [NSMutableDictionary dictionary];
    if (!gMCBRInstalled) gMCBRInstalled = [NSMutableSet set];
    if (!gMCBRResolverNoted) gMCBRResolverNoted = [NSMutableSet set];
}

static NSString *MCBRBasename(const char *path) {
    if (!path) return @"";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"";
}

static NSString *MCBRFishhookName(NSString *symbol) {
    NSString *s = symbol ?: @"";
    while ([s hasPrefix:@"_"]) s = [s substringFromIndex:1];
    return s;
}

static NSString *MCBRHex64(uint64_t value) {
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)value];
}

static void *MCBRDlsymFlexible(NSString *symbol) {
    if (!symbol.length) return NULL;
    NSString *plain = MCBRFishhookName(symbol);
    void *p = dlsym(RTLD_DEFAULT, plain.UTF8String);
    if (p) return p;
    NSString *underscored = [@"_" stringByAppendingString:plain];
    return dlsym(RTLD_DEFAULT, underscored.UTF8String);
}

static NSError *MCBRError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"SCIMobileConfigBrokerRouter" code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"unknown"}];
}

static NSString *MCBRReadOnlyStatusForDescriptor(SCIMobileConfigBrokerDescriptor *d) {
    if (!d.symbol.length) return @"missing symbol";
    void *addr = MCBRDlsymFlexible(d.symbol);
    if (!addr) return [NSString stringWithFormat:@"symbol not loaded yet: %@", d.symbol];

    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr(addr, &info) == 0 || !info.dli_fname) return @"dladdr failed";

    NSString *owner = MCBRBasename(info.dli_fname);
    uint64_t cur = 0;
    memcpy(&cur, addr, sizeof(cur));

    NSMutableString *status = [NSMutableString stringWithFormat:@"scan · owner=%@ · addr=%p · orig8=0x%016llx", owner ?: @"?", addr, (unsigned long long)cur];
    if (d.imageName.length && ![owner isEqualToString:d.imageName]) {
        [status appendFormat:@" · owner mismatch expected=%@", d.imageName];
    }
    if (d.expectedOrig8 && cur != d.expectedOrig8) {
        [status appendFormat:@" · fingerprint mismatch expected=0x%016llx", (unsigned long long)d.expectedOrig8];
    }
    [status appendString:@" · import-only observer supported · full body patch remains offline-only"];
    return status;
}

static BOOL MCBRShouldProcess(SCIMobileConfigBrokerDescriptor *d) {
    if (!d.brokerID.length) return NO;
    if ([SCIMobileConfigBrokerStore isBrokerHookEnabledForID:d.brokerID]) return YES;
    if ([SCIMobileConfigBrokerStore activeOverrideKeysForBrokerID:d.brokerID].count > 0) return YES;
    return NO;
}

static void MCBRNoteResolver(SCIMobileConfigBrokerDescriptor *d,
                             uint64_t keyValue,
                             BOOL defaultValue,
                             BOOL originalValue,
                             BOOL finalValue,
                             void *caller) {
    if (!d.brokerID.length) return;

    NSString *dedupeKey = [NSString stringWithFormat:@"%@:%@", d.brokerID ?: @"", MCBRHex64(keyValue)];
    @synchronized([SCIMobileConfigBrokerRouter class]) {
        MCBREnsureState();
        if ([gMCBRResolverNoted containsObject:dedupeKey]) return;
        if (gMCBRResolverNoted.count > 8192) return;
        [gMCBRResolverNoted addObject:dedupeKey];
    }

    NSString *callerImage = @"";
    NSString *callerSymbol = @"";
    if (caller) {
        Dl_info info;
        memset(&info, 0, sizeof(info));
        if (dladdr(caller, &info) != 0) {
            callerImage = MCBRBasename(info.dli_fname);
            if (info.dli_sname) callerSymbol = [NSString stringWithUTF8String:info.dli_sname] ?: @"";
        }
    }

    NSString *className = [NSString stringWithFormat:@"SCIMCBrokerRouter:%@", d.brokerID ?: @"?"];
    NSString *selectorName = d.symbol.length ? d.symbol : (d.brokerID ?: @"?");
    NSString *source = [NSString stringWithFormat:@"c-broker:%@", d.brokerID ?: @"?"];

    [SCIDexKitNameResolver noteMobileConfigBoolReadWithClassName:className
                                                        selector:selectorName
                                                       specifier:keyValue
                                                    defaultValue:defaultValue
                                                   originalValue:originalValue
                                                      finalValue:finalValue
                                                          source:source
                                                     callerImage:callerImage
                                                    callerSymbol:callerSymbol
                                                   callerAddress:(uint64_t)(uintptr_t)caller];
}

static BOOL MCBRForcedOrOriginal(SCIMobileConfigBrokerDescriptor *d, uint64_t keyValue, BOOL original, BOOL *wasForced) {
    if (wasForced) *wasForced = NO;
    if (!d.brokerID.length) return original;

    NSString *overrideKey = [SCIMobileConfigBrokerStore overrideKeyForBroker:d value:keyValue];
    NSNumber *forced = [SCIMobileConfigBrokerStore overrideValueForKey:overrideKey];
    if (forced) {
        [SCIMobileConfigBrokerStore noteObservedValue:forced.boolValue forOverrideKey:overrideKey];
        [SCIMobileConfigBrokerStore noteHitForBrokerID:d.brokerID value:keyValue forced:YES];
        if (wasForced) *wasForced = YES;
        return forced.boolValue;
    }

    [SCIMobileConfigBrokerStore noteObservedValue:original forOverrideKey:overrideKey];
    [SCIMobileConfigBrokerStore noteHitForBrokerID:d.brokerID value:keyValue forced:NO];
    return original;
}

static BOOL MCBRHandleIG(NSString *brokerID,
                         MCBRIGBoolFn orig,
                         id ctx,
                         BOOL def,
                         unsigned long long specifier,
                         void *caller) {
    SCIMobileConfigBrokerDescriptor *d = [SCIMobileConfigBrokerDescriptor descriptorForID:brokerID];
    if (!d || gMCBRReentryDepth > 0 || !MCBRShouldProcess(d)) {
        return orig ? orig(ctx, def, specifier) : def;
    }

    gMCBRReentryDepth++;
    BOOL original = orig ? orig(ctx, def, specifier) : def;
    BOOL forced = NO;
    BOOL finalValue = MCBRForcedOrOriginal(d, (uint64_t)specifier, original, &forced);
    MCBRNoteResolver(d, (uint64_t)specifier, def, original, finalValue, caller);
    gMCBRReentryDepth--;
    return finalValue;
}

static uintptr_t MCBRHandleGeneric(NSString *brokerID,
                                   MCBRGeneric8Fn orig,
                                   uintptr_t a0,
                                   uintptr_t a1,
                                   uintptr_t a2,
                                   uintptr_t a3,
                                   uintptr_t a4,
                                   uintptr_t a5,
                                   uintptr_t a6,
                                   uintptr_t a7,
                                   void *caller) {
    SCIMobileConfigBrokerDescriptor *d = [SCIMobileConfigBrokerDescriptor descriptorForID:brokerID];
    if (!d || gMCBRReentryDepth > 0 || !MCBRShouldProcess(d)) {
        return orig ? orig(a0, a1, a2, a3, a4, a5, a6, a7) : 0;
    }

    uintptr_t args[8] = {a0, a1, a2, a3, a4, a5, a6, a7};
    NSUInteger keyIndex = MIN((NSUInteger)MAX(d.keyArgumentIndex, 0), (NSUInteger)7);
    NSUInteger defaultIndex = MIN((NSUInteger)MAX(d.defaultArgumentIndex, 0), (NSUInteger)7);
    uint64_t keyValue = (uint64_t)args[keyIndex];
    BOOL defaultValue = (BOOL)(args[defaultIndex] & 1);

    gMCBRReentryDepth++;
    uintptr_t raw = orig ? orig(a0, a1, a2, a3, a4, a5, a6, a7) : (defaultValue ? 1 : 0);
    BOOL original = raw ? YES : NO;
    BOOL forced = NO;
    BOOL finalValue = MCBRForcedOrOriginal(d, keyValue, original, &forced);
    MCBRNoteResolver(d, keyValue, defaultValue, original, finalValue, caller);
    gMCBRReentryDepth--;
    return finalValue ? 1 : 0;
}

static BOOL hook_ig(id ctx, BOOL def, unsigned long long specifier) {
    return MCBRHandleIG(@"ig", orig_ig, ctx, def, specifier, __builtin_return_address(0));
}

static BOOL hook_igsl(id ctx, BOOL def, unsigned long long specifier) {
    return MCBRHandleIG(@"igsl", orig_igsl, ctx, def, specifier, __builtin_return_address(0));
}

static uintptr_t hook_eg(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"eg", orig_eg, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_mci(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"mci", orig_mci, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_egi(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"egi", orig_egi, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_ega(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"ega", orig_ega, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_mcic(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"mcic", orig_mcic, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_mcie(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"mcie", orig_mcie, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_meta(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"meta", orig_meta, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_metanx(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"metanx", orig_metanx, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}
static uintptr_t hook_msgc(uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7) {
    return MCBRHandleGeneric(@"msgc", orig_msgc, a0, a1, a2, a3, a4, a5, a6, a7, __builtin_return_address(0));
}

static void *MCBRReplacementForBrokerID(NSString *brokerID) {
    if ([brokerID isEqualToString:@"ig"]) return (void *)&hook_ig;
    if ([brokerID isEqualToString:@"igsl"]) return (void *)&hook_igsl;
    if ([brokerID isEqualToString:@"eg"]) return (void *)&hook_eg;
    if ([brokerID isEqualToString:@"mci"]) return (void *)&hook_mci;
    if ([brokerID isEqualToString:@"egi"]) return (void *)&hook_egi;
    if ([brokerID isEqualToString:@"ega"]) return (void *)&hook_ega;
    if ([brokerID isEqualToString:@"mcic"]) return (void *)&hook_mcic;
    if ([brokerID isEqualToString:@"mcie"]) return (void *)&hook_mcie;
    if ([brokerID isEqualToString:@"meta"]) return (void *)&hook_meta;
    if ([brokerID isEqualToString:@"metanx"]) return (void *)&hook_metanx;
    if ([brokerID isEqualToString:@"msgc"]) return (void *)&hook_msgc;
    return NULL;
}

static void **MCBROriginalSlotForBrokerID(NSString *brokerID) {
    if ([brokerID isEqualToString:@"ig"]) return (void **)&orig_ig;
    if ([brokerID isEqualToString:@"igsl"]) return (void **)&orig_igsl;
    if ([brokerID isEqualToString:@"eg"]) return (void **)&orig_eg;
    if ([brokerID isEqualToString:@"mci"]) return (void **)&orig_mci;
    if ([brokerID isEqualToString:@"egi"]) return (void **)&orig_egi;
    if ([brokerID isEqualToString:@"ega"]) return (void **)&orig_ega;
    if ([brokerID isEqualToString:@"mcic"]) return (void **)&orig_mcic;
    if ([brokerID isEqualToString:@"mcie"]) return (void **)&orig_mcie;
    if ([brokerID isEqualToString:@"meta"]) return (void **)&orig_meta;
    if ([brokerID isEqualToString:@"metanx"]) return (void **)&orig_metanx;
    if ([brokerID isEqualToString:@"msgc"]) return (void **)&orig_msgc;
    return NULL;
}

@implementation SCIMobileConfigBrokerRouter

+ (void)bootstrap {
    [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
    [self installEnabledBrokers];
    NSLog(@"[RyukGram][MCBR] import-only broker observer ready; full C body patch remains offline-only for sideload");
}

+ (BOOL)installBroker:(SCIMobileConfigBrokerDescriptor *)descriptor error:(NSError * _Nullable * _Nullable)error {
    if (!descriptor.brokerID.length || !descriptor.symbol.length) {
        if (error) *error = MCBRError(1, @"missing broker descriptor");
        return NO;
    }

    @synchronized(self) {
        MCBREnsureState();
        if ([gMCBRInstalled containsObject:descriptor.brokerID]) return YES;
    }

    void *replacement = MCBRReplacementForBrokerID(descriptor.brokerID);
    void **origSlot = MCBROriginalSlotForBrokerID(descriptor.brokerID);
    if (!replacement || !origSlot) {
        NSString *msg = [NSString stringWithFormat:@"%@ unsupported by import observer", descriptor.brokerID];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        if (error) *error = MCBRError(2, msg);
        return NO;
    }

    NSString *status = MCBRReadOnlyStatusForDescriptor(descriptor);
    NSString *name = MCBRFishhookName(descriptor.symbol);
    struct rebinding rb;
    rb.name = (char *)name.UTF8String;
    rb.replacement = replacement;
    rb.replaced = origSlot;

    int rc = rebind_symbols(&rb, 1);
    if (rc != 0) {
        NSString *msg = [NSString stringWithFormat:@"%@ fishhook failed rc=%d · %@", descriptor.brokerID, rc, status ?: @""];
        [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
        @synchronized(self) { MCBREnsureState(); gMCBRErrors[descriptor.brokerID] = msg; }
        if (error) *error = MCBRError(3, msg);
        return NO;
    }

    [SCIMobileConfigBrokerStore setBrokerHookEnabled:YES brokerID:descriptor.brokerID];
    NSString *msg = [NSString stringWithFormat:@"import observer installed · %@", status ?: @""];
    [SCIMobileConfigBrokerStore noteLastError:msg brokerID:descriptor.brokerID];
    @synchronized(self) {
        MCBREnsureState();
        [gMCBRInstalled addObject:descriptor.brokerID];
        [gMCBRErrors removeObjectForKey:descriptor.brokerID];
    }
    NSLog(@"[RyukGram][MCBR] %@", msg);
    return YES;
}

+ (BOOL)isInstalled:(NSString *)brokerID {
    @synchronized(self) { MCBREnsureState(); return [gMCBRInstalled containsObject:brokerID ?: @""]; }
}

+ (NSUInteger)installedCount {
    @synchronized(self) { MCBREnsureState(); return gMCBRInstalled.count; }
}

+ (NSDictionary<NSString *,NSString *> *)installErrors {
    @synchronized(self) { MCBREnsureState(); return [gMCBRErrors copy] ?: @{}; }
}

+ (void)installEnabledBrokers {
    for (SCIMobileConfigBrokerDescriptor *d in [SCIMobileConfigBrokerDescriptor allDescriptors]) {
        if (![SCIMobileConfigBrokerStore shouldInstallBrokerID:d.brokerID]) continue;
        NSError *err = nil;
        [self installBroker:d error:&err];
    }
}

+ (void)retryPendingBrokersForImageBasename:(NSString *)basename {
    (void)basename;
    [self installEnabledBrokers];
}

@end

%ctor {
    [SCIMobileConfigBrokerRouter bootstrap];
}
