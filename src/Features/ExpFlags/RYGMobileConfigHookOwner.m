#import "RYGMobileConfig.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/lock.h>
#import <dlfcn.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// Session-only MobileConfig getter owner.
//
// Persisted overrides belong to Instagram's native <user>.data document and
// StartupConfigs table. This owner exists only to make a user mutation visible
// immediately in the current process. It performs no disk/NSUserDefaults work,
// does not fabricate/canonicalize unit bits, and does not install getters during
// an ordinary cold start with no in-memory mutation.

#define RYG_MC_HOT_CAPACITY 16384u

typedef struct {
    atomic_uint_fast64_t pid;
    atomic_uintptr_t value;
} RYGMCHotSlot;

static RYGMCHotSlot gRYGMCHotSlots[RYG_MC_HOT_CAPACITY];
static os_unfair_lock gRYGMCHotMutationLock = OS_UNFAIR_LOCK_INIT;
static atomic_uint_fast32_t gRYGMCHotCount = 0;
static atomic_bool gRYGMCHooksInstalled = false;
static atomic_bool gRYGMCImageCallbackRegistered = false;

static IMP gRYGMCUpBool;
static IMP gRYGMCUpBoolDef;
static IMP gRYGMCUpBoolOpts;
static IMP gRYGMCUpBoolOptsDef;
static IMP gRYGMCUpInt;
static IMP gRYGMCUpIntDef;
static IMP gRYGMCUpIntOpts;
static IMP gRYGMCUpIntOptsDef;
static IMP gRYGMCUpDouble;
static IMP gRYGMCUpDoubleDef;
static IMP gRYGMCUpDoubleOpts;
static IMP gRYGMCUpDoubleOptsDef;
static IMP gRYGMCUpString;
static IMP gRYGMCUpStringDef;
static IMP gRYGMCUpStringOpts;
static IMP gRYGMCUpStringOptsDef;

static NSUInteger RYGMCHotIndex(uint64_t pid) {
    uint64_t x = pid;
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return (NSUInteger)(x & (RYG_MC_HOT_CAPACITY - 1u));
}

static RYGMCHotSlot *RYGMCHotFindSlot(uint64_t pid, BOOL create) {
    if (!pid) return NULL;
    NSUInteger start = RYGMCHotIndex(pid);
    for (NSUInteger probe = 0; probe < RYG_MC_HOT_CAPACITY; probe++) {
        RYGMCHotSlot *slot = &gRYGMCHotSlots[(start + probe) & (RYG_MC_HOT_CAPACITY - 1u)];
        uint64_t existing = atomic_load_explicit(&slot->pid, memory_order_acquire);
        if (existing == pid) return slot;
        if (existing == 0) {
            if (!create) return NULL;
            uint64_t expected = 0;
            if (atomic_compare_exchange_strong_explicit(&slot->pid, &expected, pid, memory_order_acq_rel, memory_order_acquire)) return slot;
            if (expected == pid) return slot;
        }
    }
    return NULL;
}

static void RYGMCHotSet(uint64_t pid, id value) {
    if (!pid) return;
    os_unfair_lock_lock(&gRYGMCHotMutationLock);
    RYGMCHotSlot *slot = RYGMCHotFindSlot(pid, value != nil);
    if (slot) {
        uintptr_t previous = atomic_load_explicit(&slot->value, memory_order_acquire);
        uintptr_t next = value ? (uintptr_t)(__bridge_retained void *)value : 0;
        atomic_store_explicit(&slot->value, next, memory_order_release);
        if (!previous && next) atomic_fetch_add_explicit(&gRYGMCHotCount, 1, memory_order_acq_rel);
        else if (previous && !next) atomic_fetch_sub_explicit(&gRYGMCHotCount, 1, memory_order_acq_rel);
        // Previous mutation objects remain retained for process lifetime to keep
        // the hot read path reclamation-free and lock-free.
    }
    os_unfair_lock_unlock(&gRYGMCHotMutationLock);
}

static void RYGMCHotClear(void) {
    os_unfair_lock_lock(&gRYGMCHotMutationLock);
    for (NSUInteger index = 0; index < RYG_MC_HOT_CAPACITY; index++)
        atomic_store_explicit(&gRYGMCHotSlots[index].value, 0, memory_order_release);
    atomic_store_explicit(&gRYGMCHotCount, 0, memory_order_release);
    os_unfair_lock_unlock(&gRYGMCHotMutationLock);
}

static id RYGMCOwnedOverride(uint64_t pid) {
    if (!pid) return nil;
    RYGMCHotSlot *slot = RYGMCHotFindSlot(pid, NO);
    if (!slot) return nil;
    uintptr_t raw = atomic_load_explicit(&slot->value, memory_order_acquire);
    return raw ? (__bridge id)((void *)raw) : nil;
}

static BOOL RYGMCOwnerShouldRunFast(void) {
    return atomic_load_explicit(&gRYGMCHotCount, memory_order_acquire) > 0;
}

static const char *RYGMCUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGMCOwnerTypeMatches(const char *raw, char expected) {
    const char *type = RYGMCUnqualified(raw);
    if (!type || !*type) return NO;
    switch (expected) {
        case 'P': return *type == 'Q' || *type == 'q' || (*type == '{' && (strstr(type, "=Q}") || strstr(type, "=q}")));
        case 'B': return *type == 'B' || *type == 'c' || *type == 'C';
        case 'Q': return *type == 'q' || *type == 'Q';
        case 'D': return *type == 'd';
        case '@': return *type == '@';
        default: return NO;
    }
}

static BOOL RYGMCOwnerMethodMatches(Method method, char returnType, const char *arguments) {
    if (!method || !arguments || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char encoded[128] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    if (!RYGMCOwnerTypeMatches(encoded, returnType)) return NO;
    for (unsigned int index = 0; arguments[index]; index++) {
        memset(encoded, 0, sizeof(encoded));
        method_getArgumentType(method, index + 2, encoded, sizeof(encoded));
        if (!RYGMCOwnerTypeMatches(encoded, arguments[index])) return NO;
    }
    return YES;
}

static BOOL RYGMCIMPBelongsToRyukGram(IMP imp) {
    if (!imp) return NO;
    Dl_info info = {0};
    if (!dladdr((const void *)imp, &info) || !info.dli_fname) return NO;
    NSString *name = [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent].lowercaseString ?: @"";
    return [name containsString:@"ryukgram"];
}

static BOOL RYGMCOwnerInstallOne(Class cls, NSString *selectorName, IMP replacement, IMP *upstream, char returnType, const char *arguments) {
    if (!cls || !selectorName.length || !replacement || !upstream) return NO;
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(selectorName));
    if (!RYGMCOwnerMethodMatches(method, returnType, arguments)) return NO;
    IMP current = method_getImplementation(method);
    if (!current) return NO;
    if (current == replacement) return YES;
    if (!*upstream || !RYGMCIMPBelongsToRyukGram(current)) *upstream = current;
    if (!*upstream) return NO;
    method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerBool(id self, SEL cmd, uint64_t pid) { id value = RYGMCOwnedOverride(pid); return value ? [value boolValue] : (gRYGMCUpBool ? ((BOOL (*)(id,SEL,uint64_t))gRYGMCUpBool)(self,cmd,pid) : NO); }
static BOOL RYGMCOwnerBoolDef(id self, SEL cmd, uint64_t pid, BOOL def) { id value = RYGMCOwnedOverride(pid); return value ? [value boolValue] : (gRYGMCUpBoolDef ? ((BOOL (*)(id,SEL,uint64_t,BOOL))gRYGMCUpBoolDef)(self,cmd,pid,def) : def); }
static BOOL RYGMCOwnerBoolOpts(id self, SEL cmd, uint64_t pid, id opts) { id value = RYGMCOwnedOverride(pid); return value ? [value boolValue] : (gRYGMCUpBoolOpts ? ((BOOL (*)(id,SEL,uint64_t,id))gRYGMCUpBoolOpts)(self,cmd,pid,opts) : NO); }
static BOOL RYGMCOwnerBoolOptsDef(id self, SEL cmd, uint64_t pid, id opts, BOOL def) { id value = RYGMCOwnedOverride(pid); return value ? [value boolValue] : (gRYGMCUpBoolOptsDef ? ((BOOL (*)(id,SEL,uint64_t,id,BOOL))gRYGMCUpBoolOptsDef)(self,cmd,pid,opts,def) : def); }
static long long RYGMCOwnerInt(id self, SEL cmd, uint64_t pid) { id value = RYGMCOwnedOverride(pid); return value ? [value longLongValue] : (gRYGMCUpInt ? ((long long (*)(id,SEL,uint64_t))gRYGMCUpInt)(self,cmd,pid) : 0); }
static long long RYGMCOwnerIntDef(id self, SEL cmd, uint64_t pid, long long def) { id value = RYGMCOwnedOverride(pid); return value ? [value longLongValue] : (gRYGMCUpIntDef ? ((long long (*)(id,SEL,uint64_t,long long))gRYGMCUpIntDef)(self,cmd,pid,def) : def); }
static long long RYGMCOwnerIntOpts(id self, SEL cmd, uint64_t pid, id opts) { id value = RYGMCOwnedOverride(pid); return value ? [value longLongValue] : (gRYGMCUpIntOpts ? ((long long (*)(id,SEL,uint64_t,id))gRYGMCUpIntOpts)(self,cmd,pid,opts) : 0); }
static long long RYGMCOwnerIntOptsDef(id self, SEL cmd, uint64_t pid, id opts, long long def) { id value = RYGMCOwnedOverride(pid); return value ? [value longLongValue] : (gRYGMCUpIntOptsDef ? ((long long (*)(id,SEL,uint64_t,id,long long))gRYGMCUpIntOptsDef)(self,cmd,pid,opts,def) : def); }
static double RYGMCOwnerDouble(id self, SEL cmd, uint64_t pid) { id value = RYGMCOwnedOverride(pid); return value ? [value doubleValue] : (gRYGMCUpDouble ? ((double (*)(id,SEL,uint64_t))gRYGMCUpDouble)(self,cmd,pid) : 0.0); }
static double RYGMCOwnerDoubleDef(id self, SEL cmd, uint64_t pid, double def) { id value = RYGMCOwnedOverride(pid); return value ? [value doubleValue] : (gRYGMCUpDoubleDef ? ((double (*)(id,SEL,uint64_t,double))gRYGMCUpDoubleDef)(self,cmd,pid,def) : def); }
static double RYGMCOwnerDoubleOpts(id self, SEL cmd, uint64_t pid, id opts) { id value = RYGMCOwnedOverride(pid); return value ? [value doubleValue] : (gRYGMCUpDoubleOpts ? ((double (*)(id,SEL,uint64_t,id))gRYGMCUpDoubleOpts)(self,cmd,pid,opts) : 0.0); }
static double RYGMCOwnerDoubleOptsDef(id self, SEL cmd, uint64_t pid, id opts, double def) { id value = RYGMCOwnedOverride(pid); return value ? [value doubleValue] : (gRYGMCUpDoubleOptsDef ? ((double (*)(id,SEL,uint64_t,id,double))gRYGMCUpDoubleOptsDef)(self,cmd,pid,opts,def) : def); }
static id RYGMCOwnerString(id self, SEL cmd, uint64_t pid) { id value = RYGMCOwnedOverride(pid); return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpString ? ((id (*)(id,SEL,uint64_t))gRYGMCUpString)(self,cmd,pid) : nil); }
static id RYGMCOwnerStringDef(id self, SEL cmd, uint64_t pid, id def) { id value = RYGMCOwnedOverride(pid); return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpStringDef ? ((id (*)(id,SEL,uint64_t,id))gRYGMCUpStringDef)(self,cmd,pid,def) : def); }
static id RYGMCOwnerStringOpts(id self, SEL cmd, uint64_t pid, id opts) { id value = RYGMCOwnedOverride(pid); return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpStringOpts ? ((id (*)(id,SEL,uint64_t,id))gRYGMCUpStringOpts)(self,cmd,pid,opts) : nil); }
static id RYGMCOwnerStringOptsDef(id self, SEL cmd, uint64_t pid, id opts, id def) { id value = RYGMCOwnedOverride(pid); return [value isKindOfClass:NSString.class] ? value : (gRYGMCUpStringOptsDef ? ((id (*)(id,SEL,uint64_t,id,id))gRYGMCUpStringOptsDef)(self,cmd,pid,opts,def) : def); }

static NSUInteger RYGMCOwnerScore(Class cls) {
    NSUInteger score = 0;
    for (NSString *selector in @[@"getBool:", @"getInt64:", @"getDouble:", @"getString:"])
        if (class_getInstanceMethod(cls, NSSelectorFromString(selector))) score++;
    return score;
}

static void RYGMCOwnerInstallHooks(void) {
    if (!RYGMCOwnerShouldRunFast()) return;
    Class fb = objc_lookUpClass("FBMobileConfigContextManager");
    Class ig = objc_lookUpClass("IGMobileConfigContextManager");
    Class cls = RYGMCOwnerScore(fb) >= RYGMCOwnerScore(ig) ? fb : ig;
    if (!cls) return;

    BOOL installed = NO;
    installed |= RYGMCOwnerInstallOne(cls,@"getBool:",(IMP)RYGMCOwnerBool,&gRYGMCUpBool,'B',"P");
    installed |= RYGMCOwnerInstallOne(cls,@"getBool:withDefault:",(IMP)RYGMCOwnerBoolDef,&gRYGMCUpBoolDef,'B',"PB");
    installed |= RYGMCOwnerInstallOne(cls,@"getBool:withOptions:",(IMP)RYGMCOwnerBoolOpts,&gRYGMCUpBoolOpts,'B',"P@");
    installed |= RYGMCOwnerInstallOne(cls,@"getBool:withOptions:withDefault:",(IMP)RYGMCOwnerBoolOptsDef,&gRYGMCUpBoolOptsDef,'B',"P@B");
    installed |= RYGMCOwnerInstallOne(cls,@"getInt64:",(IMP)RYGMCOwnerInt,&gRYGMCUpInt,'Q',"P");
    installed |= RYGMCOwnerInstallOne(cls,@"getInt64:withDefault:",(IMP)RYGMCOwnerIntDef,&gRYGMCUpIntDef,'Q',"PQ");
    installed |= RYGMCOwnerInstallOne(cls,@"getInt64:withOptions:",(IMP)RYGMCOwnerIntOpts,&gRYGMCUpIntOpts,'Q',"P@");
    installed |= RYGMCOwnerInstallOne(cls,@"getInt64:withOptions:withDefault:",(IMP)RYGMCOwnerIntOptsDef,&gRYGMCUpIntOptsDef,'Q',"P@Q");
    installed |= RYGMCOwnerInstallOne(cls,@"getDouble:",(IMP)RYGMCOwnerDouble,&gRYGMCUpDouble,'D',"P");
    installed |= RYGMCOwnerInstallOne(cls,@"getDouble:withDefault:",(IMP)RYGMCOwnerDoubleDef,&gRYGMCUpDoubleDef,'D',"PD");
    installed |= RYGMCOwnerInstallOne(cls,@"getDouble:withOptions:",(IMP)RYGMCOwnerDoubleOpts,&gRYGMCUpDoubleOpts,'D',"P@");
    installed |= RYGMCOwnerInstallOne(cls,@"getDouble:withOptions:withDefault:",(IMP)RYGMCOwnerDoubleOptsDef,&gRYGMCUpDoubleOptsDef,'D',"P@D");
    installed |= RYGMCOwnerInstallOne(cls,@"getString:",(IMP)RYGMCOwnerString,&gRYGMCUpString,'@',"P");
    installed |= RYGMCOwnerInstallOne(cls,@"getString:withDefault:",(IMP)RYGMCOwnerStringDef,&gRYGMCUpStringDef,'@',"P@");
    installed |= RYGMCOwnerInstallOne(cls,@"getString:withOptions:",(IMP)RYGMCOwnerStringOpts,&gRYGMCUpStringOpts,'@',"P@");
    installed |= RYGMCOwnerInstallOne(cls,@"getString:withOptions:withDefault:",(IMP)RYGMCOwnerStringOptsDef,&gRYGMCUpStringOptsDef,'@',"P@@");
    if (installed) atomic_store_explicit(&gRYGMCHooksInstalled, true, memory_order_release);
}

static void RYGMCOwnerImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    if (!RYGMCOwnerShouldRunFast() || atomic_load_explicit(&gRYGMCHooksInstalled, memory_order_acquire)) return;
    if (objc_lookUpClass("FBMobileConfigContextManager") || objc_lookUpClass("IGMobileConfigContextManager")) RYGMCOwnerInstallHooks();
}

static void RYGMCOwnerEnsureLateLoadCallback(void) {
    if (atomic_load_explicit(&gRYGMCHooksInstalled, memory_order_acquire)) return;
    bool expected = false;
    if (atomic_compare_exchange_strong_explicit(&gRYGMCImageCallbackRegistered, &expected, true, memory_order_acq_rel, memory_order_acquire))
        _dyld_register_func_for_add_image(RYGMCOwnerImageDidLoad);
}

@implementation RYGMobileConfig (RYGMobileConfigHookOwner)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Only mutation methods are intercepted at load. The MobileConfig getter
        // family remains completely native until the user creates a session-only
        // in-memory override.
        Method setOriginal = class_getInstanceMethod(self, @selector(setOverride:for:));
        Method setOwned = class_getInstanceMethod(self, @selector(ryg_owner_setOverride:for:));
        if (setOriginal && setOwned) method_exchangeImplementations(setOriginal, setOwned);
        Method clearOriginal = class_getInstanceMethod(self, @selector(clearOverrideFor:));
        Method clearOwned = class_getInstanceMethod(self, @selector(ryg_owner_clearOverrideFor:));
        if (clearOriginal && clearOwned) method_exchangeImplementations(clearOriginal, clearOwned);
        Method resetOriginal = class_getInstanceMethod(self, @selector(resetAllOverrides));
        Method resetOwned = class_getInstanceMethod(self, @selector(ryg_owner_resetAllOverrides));
        if (resetOriginal && resetOwned) method_exchangeImplementations(resetOriginal, resetOwned);
    });
}

- (BOOL)ryg_owner_setOverride:(id)value for:(RYGMCParam *)param {
    BOOL success = [self ryg_owner_setOverride:value for:param];
    if (success && param.paramID) {
        RYGMCHotSet(param.paramID, value);
        RYGMCOwnerInstallHooks();
        RYGMCOwnerEnsureLateLoadCallback();
    }
    return success;
}

- (void)ryg_owner_clearOverrideFor:(RYGMCParam *)param {
    uint64_t pid = param.paramID;
    [self ryg_owner_clearOverrideFor:param];
    if (pid) RYGMCHotSet(pid, nil);
}

- (void)ryg_owner_resetAllOverrides {
    [self ryg_owner_resetAllOverrides];
    RYGMCHotClear();
}

@end
