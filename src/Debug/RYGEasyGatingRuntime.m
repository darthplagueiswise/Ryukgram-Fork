#import "RYGEasyGatingRuntime.h"
#import "../../modules/fishhook/fishhook.h"
#import <os/lock.h>
#import <stdatomic.h>
#import <stdint.h>
#import <dlfcn.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif
#include <stdlib.h>

NSString *const RYGEasyGatingDidObserveNotification = @"RYGEasyGatingDidObserveNotification";
NSString *const RYGEasyGatingGateIDUserInfoKey = @"gateID";

static NSString *const kRYGEasyGatingOverridesKey = @"ryg_easy_gating_platform_bool_overrides_v2";

// Current FBShared ABI, verified with LIEF + Capstone + llvm-objdump:
//
// EasyGatingGetBoolean_Internal_DoNotUseOrMock(context, selectorIndex,
//                                              defaultValue, exposureSource)
// maps selectorIndex to the FINAL gate ID, normalizes exposureSource to a bool,
// and then tail-branches to EasyGatingPlatformGetBoolean(context, finalGateID,
//                                                        defaultValue, exposure).
//
// Sideload rule: no instruction in FBSharedFramework.__TEXT is modified. The
// 1207 build used MSHookFunction on EasyGatingPlatformGetBoolean at +0x50faf4;
// that lives in the same signed 16 KiB page as the later crash at +0x50d0ac.
// iOS killed the process with CODESIGNING/Invalid Page. This implementation
// only rebinds imported symbol slots and READS the wrapper's mapping table.
typedef uint32_t (*RYGEasyGatingBoolFn)(uintptr_t context,
                                        uint32_t selectorOrGateID,
                                        uint32_t defaultValue,
                                        uint32_t exposureValue);

static RYGEasyGatingBoolFn gRYGOriginalEasyGatingWrapper;
static RYGEasyGatingBoolFn gRYGOriginalEasyGatingPlatformGetBoolean;
static os_unfair_lock gRYGEasyGatingLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, RYGEasyGatingObservation *> *gRYGEasyGatingObservations;
static NSDictionary<NSString *, NSNumber *> *gRYGEasyGatingOverrideCache;
static atomic_bool gRYGEasyGatingRebindingRegistered = false;

@implementation RYGEasyGatingObservation
- (NSNumber *)overrideValue { return [[RYGEasyGatingRuntime shared] overrideForGateID:self.gateID]; }
@end

static NSDictionary<NSString *, NSNumber *> *RYGEasyGatingReadOverrides(void) {
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:kRYGEasyGatingOverridesKey];
    if (![raw isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary<NSString *, NSNumber *> *clean = [NSMutableDictionary dictionary];
    [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        (void)stop;
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSNumber.class]) return;
        const char *digits = [(NSString *)key UTF8String];
        if (!digits || !*digits || *digits == '-') return;
        char *end = NULL;
        unsigned long long numeric = strtoull(digits, &end, 10);
        if (end == digits || *end != '\0' || numeric > UINT32_MAX) return;
        clean[key] = @([value boolValue]);
    }];
    return clean.copy;
}

static void RYGEasyGatingRefreshOverrideCache(void) {
    NSDictionary *next = RYGEasyGatingReadOverrides();
    os_unfair_lock_lock(&gRYGEasyGatingLock);
    gRYGEasyGatingOverrideCache = next;
    os_unfair_lock_unlock(&gRYGEasyGatingLock);
}

static NSNumber *RYGEasyGatingCachedOverride(uint32_t gateID) {
    NSString *key = [NSString stringWithFormat:@"%u", gateID];
    os_unfair_lock_lock(&gRYGEasyGatingLock);
    NSNumber *value = gRYGEasyGatingOverrideCache[key];
    os_unfair_lock_unlock(&gRYGEasyGatingLock);
    return value;
}

static void RYGEasyGatingRecord(uint32_t gateID,
                                BOOL defaultValue,
                                BOOL exposureEnabled,
                                BOOL nativeValue) {
    BOOL notify = NO;
    os_unfair_lock_lock(&gRYGEasyGatingLock);
    if (!gRYGEasyGatingObservations) gRYGEasyGatingObservations = [NSMutableDictionary dictionary];
    NSNumber *key = @(gateID);
    RYGEasyGatingObservation *row = gRYGEasyGatingObservations[key];
    if (!row) {
        row = [RYGEasyGatingObservation new];
        row.gateID = gateID;
        row.defaultValue = defaultValue;
        row.exposureEnabled = exposureEnabled;
        row.nativeValue = nativeValue;
        row.callCount = 1;
        row.lastSeen = NSDate.date;
        gRYGEasyGatingObservations[key] = row;
        notify = YES;
    } else {
        row.callCount += 1;
        if (row.defaultValue != defaultValue ||
            row.exposureEnabled != exposureEnabled ||
            row.nativeValue != nativeValue) {
            row.defaultValue = defaultValue;
            row.exposureEnabled = exposureEnabled;
            row.nativeValue = nativeValue;
            notify = YES;
        }
        if ((row.callCount & 63u) == 0u || notify) row.lastSeen = NSDate.date;
    }
    os_unfair_lock_unlock(&gRYGEasyGatingLock);

    if (notify) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGEasyGatingDidObserveNotification
                                                              object:nil
                                                            userInfo:@{RYGEasyGatingGateIDUserInfoKey:@(gateID)}];
        });
    }
}

static int64_t RYGSignExtend21(uint32_t value) {
    uint64_t raw = (uint64_t)value & 0x1fffffULL;
    uint64_t sign = 1ULL << 20;
    return (int64_t)((raw ^ sign) - sign);
}

static uintptr_t RYGStripFunctionPointer(RYGEasyGatingBoolFn function) {
    if (!function) return 0;
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip((void *)function, ptrauth_key_function_pointer);
#else
    return (uintptr_t)function;
#endif
}

// Decode the exact read-only mapper embedded in the current wrapper instead of
// jumping into the middle of signed code. This remains safe with BTI/PAC because
// no indirect branch targets an interior instruction.
static BOOL RYGResolveFinalGateID(RYGEasyGatingBoolFn wrapper,
                                  uint32_t selectorIndex,
                                  uint32_t *finalGateID) {
    uintptr_t wrapperAddress = RYGStripFunctionPointer(wrapper);
    if (!wrapperAddress || !finalGateID || selectorIndex > 0xffffu) return NO;

    Dl_info info = {0};
    if (!dladdr((const void *)wrapperAddress, &info) || !info.dli_fname) return NO;
    NSString *image = [NSString stringWithUTF8String:info.dli_fname] ?: @"";
    if (![image.lastPathComponent containsString:@"FBSharedFramework"]) return NO;

    // FBSharedFramework(20260819-042733): mapper starts at wrapper + 0x34.
    // Validate ARM64 ADRP/ADD/ADR instructions before trusting any address so a
    // future build simply becomes unobservable instead of reading arbitrary data.
    uintptr_t helper = wrapperAddress + 0x34;
    uint32_t adrp = *(const uint32_t *)(helper + 0x0c);
    uint32_t add  = *(const uint32_t *)(helper + 0x10);
    uint32_t adr  = *(const uint32_t *)(helper + 0x14);
    if ((adrp & 0x9f000000u) != 0x90000000u || (adrp & 0x1fu) != 9u) return NO;
    if ((add & 0x7f000000u) != 0x11000000u || (add & 0x1fu) != 9u || ((add >> 5) & 0x1fu) != 9u) return NO;
    if ((adr & 0x9f000000u) != 0x10000000u || (adr & 0x1fu) != 10u) return NO;

    uint32_t adrpImm21 = (((adrp >> 5) & 0x7ffffu) << 2) | ((adrp >> 29) & 0x3u);
    uintptr_t adrpPC = helper + 0x0c;
    intptr_t pageDelta = (intptr_t)(RYGSignExtend21(adrpImm21) << 12);
    uintptr_t table = (uintptr_t)((intptr_t)(adrpPC & ~(uintptr_t)0xfff) + pageDelta);
    uint32_t addImm = (add >> 10) & 0xfffu;
    if ((add >> 22) & 1u) addImm <<= 12;
    table += addImm;

    uint32_t adrImm21 = (((adr >> 5) & 0x7ffffu) << 2) | ((adr >> 29) & 0x3u);
    uintptr_t adrPC = helper + 0x14;
    uintptr_t jumpBase = (uintptr_t)((intptr_t)adrPC + RYGSignExtend21(adrImm21));

    uint16_t jumpUnits = *(const uint16_t *)(table + (uintptr_t)selectorIndex * sizeof(uint16_t));
    uintptr_t target = jumpBase + (uintptr_t)jumpUnits * 4u;
    if (target < wrapperAddress + 0x34 || target >= wrapperAddress + 0x2000) return NO;

    uint32_t movz = *(const uint32_t *)target;
    if ((movz & 0x7f80001fu) != 0x52800000u) return NO; // MOVZ W0, #imm
    uint32_t hw = (movz >> 21) & 0x3u;
    if (hw > 1u) return NO;
    uint32_t value = ((movz >> 5) & 0xffffu) << (hw * 16u);

    uint32_t next = *(const uint32_t *)(target + 4);
    if ((next & 0x7f80001fu) == 0x72800000u) { // optional MOVK W0
        uint32_t nextHW = (next >> 21) & 0x3u;
        if (nextHW > 1u) return NO;
        uint32_t shift = nextHW * 16u;
        uint32_t mask = 0xffffu << shift;
        value = (value & ~mask) | (((next >> 5) & 0xffffu) << shift);
    }
    if (!value) return NO;
    *finalGateID = value;
    return YES;
}

static uint32_t RYGEasyGatingWrapperReplacement(uintptr_t context,
                                                 uint32_t selectorIndex,
                                                 uint32_t defaultValue,
                                                 uint32_t exposureValue) {
    RYGEasyGatingBoolFn original = gRYGOriginalEasyGatingWrapper;
    uint32_t native = original ? original(context, selectorIndex, defaultValue, exposureValue)
                               : (defaultValue ? 1u : 0u);
    uint32_t finalID = 0;
    if (!RYGResolveFinalGateID(original, selectorIndex, &finalID)) return native;
    BOOL exposure = exposureValue == 1u;
    RYGEasyGatingRecord(finalID, defaultValue != 0, exposure, native != 0);
    NSNumber *forced = RYGEasyGatingCachedOverride(finalID);
    return forced ? (forced.boolValue ? 1u : 0u) : native;
}

static uint32_t RYGEasyGatingPlatformReplacement(uintptr_t context,
                                                  uint32_t finalGateID,
                                                  uint32_t defaultValue,
                                                  uint32_t exposureValue) {
    RYGEasyGatingBoolFn original = gRYGOriginalEasyGatingPlatformGetBoolean;
    uint32_t native = original ? original(context, finalGateID, defaultValue, exposureValue)
                               : (defaultValue ? 1u : 0u);
    if (!finalGateID) return native;
    RYGEasyGatingRecord(finalGateID, defaultValue != 0, exposureValue != 0, native != 0);
    NSNumber *forced = RYGEasyGatingCachedOverride(finalGateID);
    return forced ? (forced.boolValue ? 1u : 0u) : native;
}

static BOOL RYGRegisterEasyGatingRebindings(void) {
    if (atomic_load(&gRYGEasyGatingRebindingRegistered)) return YES;
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gRYGEasyGatingRebindingRegistered, &expected, true)) return YES;

    struct rebinding bindings[] = {
        {
            .name = "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
            .replacement = (void *)&RYGEasyGatingWrapperReplacement,
            .replaced = (void **)&gRYGOriginalEasyGatingWrapper,
        },
        {
            .name = "EasyGatingPlatformGetBoolean",
            .replacement = (void *)&RYGEasyGatingPlatformReplacement,
            .replaced = (void **)&gRYGOriginalEasyGatingPlatformGetBoolean,
        },
    };
    if (rebind_symbols(bindings, sizeof(bindings) / sizeof(bindings[0])) != 0) {
        atomic_store(&gRYGEasyGatingRebindingRegistered, false);
        return NO;
    }
    return YES;
}

@implementation RYGEasyGatingRuntime

+ (instancetype)shared {
    static RYGEasyGatingRuntime *runtime;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        runtime = [RYGEasyGatingRuntime new];
        RYGEasyGatingRefreshOverrideCache();
    });
    return runtime;
}

- (void)installIfNeeded { (void)RYGRegisterEasyGatingRebindings(); }

- (NSArray<RYGEasyGatingObservation *> *)observations {
    os_unfair_lock_lock(&gRYGEasyGatingLock);
    NSArray *rows = gRYGEasyGatingObservations.allValues.copy ?: @[];
    os_unfair_lock_unlock(&gRYGEasyGatingLock);
    return [rows sortedArrayUsingComparator:^NSComparisonResult(RYGEasyGatingObservation *left, RYGEasyGatingObservation *right) {
        if (left.gateID < right.gateID) return NSOrderedAscending;
        if (left.gateID > right.gateID) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (NSNumber *)overrideForGateID:(uint32_t)gateID { return RYGEasyGatingCachedOverride(gateID); }

- (void)setOverride:(NSNumber *)value forGateID:(uint32_t)gateID {
    NSMutableDictionary<NSString *, NSNumber *> *overrides = [RYGEasyGatingReadOverrides() mutableCopy];
    NSString *key = [NSString stringWithFormat:@"%u", gateID];
    if (value) overrides[key] = @([value boolValue]);
    else [overrides removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults setObject:overrides.copy forKey:kRYGEasyGatingOverridesKey];
    RYGEasyGatingRefreshOverrideCache();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGEasyGatingDidObserveNotification
                                                          object:nil
                                                        userInfo:@{RYGEasyGatingGateIDUserInfoKey:@(gateID)}];
    });
}

- (void)clearObservations {
    os_unfair_lock_lock(&gRYGEasyGatingLock);
    [gRYGEasyGatingObservations removeAllObjects];
    os_unfair_lock_unlock(&gRYGEasyGatingLock);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGEasyGatingDidObserveNotification object:nil];
    });
}

@end
