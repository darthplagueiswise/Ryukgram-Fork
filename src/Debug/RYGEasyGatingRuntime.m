#import "RYGEasyGatingRuntime.h"
#include "../../modules/fishhook/fishhook.h"
#import <os/lock.h>
#import <stdatomic.h>
#import <stdint.h>

NSString *const RYGEasyGatingDidObserveNotification = @"RYGEasyGatingDidObserveNotification";
NSString *const RYGEasyGatingGateIDUserInfoKey = @"gateID";

static NSString *const kRYGEasyGatingOverridesKey = @"ryg_easy_gating_bool_overrides";

// The supplied Instagram arm64 executable has repeated call sites to
// _EasyGatingGetBoolean_Internal_DoNotUseOrMock with the observable register
// shape x0, w1, w2, x3 and a return consumed from w0. Keep the unknown context
// arguments opaque and forward them bit-for-bit; only w1 is treated as the gate
// identifier because call sites explicitly materialize IDs there (for example
// 0x139 and 0x0f0 in the supplied executable).
typedef uint32_t (*RYGEasyGatingGetBooleanFn)(uintptr_t context0,
                                              uint32_t gateID,
                                              uint32_t variant,
                                              uintptr_t context3);
static RYGEasyGatingGetBooleanFn gRYGOriginalEasyGatingGetBoolean;
static os_unfair_lock gRYGEasyGatingLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, RYGEasyGatingObservation *> *gRYGEasyGatingObservations;
static NSDictionary<NSString *, NSNumber *> *gRYGEasyGatingOverrideCache;
static atomic_bool gRYGEasyGatingInstalled = false;

@implementation RYGEasyGatingObservation
- (NSNumber *)overrideValue {
    return [[RYGEasyGatingRuntime shared] overrideForGateID:self.gateID];
}
@end

static NSDictionary<NSString *, NSNumber *> *RYGEasyGatingReadOverrides(void) {
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:kRYGEasyGatingOverridesKey];
    if (![raw isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary<NSString *, NSNumber *> *clean = [NSMutableDictionary dictionary];
    [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSNumber.class]) return;
        unsigned long long numeric = [(NSString *)key longLongValue];
        if (numeric > UINT32_MAX) return;
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

static void RYGEasyGatingRecord(uint32_t gateID, uint32_t variant, BOOL nativeValue) {
    __block BOOL notify = NO;
    __block RYGEasyGatingObservation *snapshot = nil;

    os_unfair_lock_lock(&gRYGEasyGatingLock);
    if (!gRYGEasyGatingObservations) gRYGEasyGatingObservations = [NSMutableDictionary dictionary];
    NSNumber *key = @(gateID);
    RYGEasyGatingObservation *row = gRYGEasyGatingObservations[key];
    if (!row) {
        row = [RYGEasyGatingObservation new];
        row.gateID = gateID;
        row.variant = variant;
        row.nativeValue = nativeValue;
        row.callCount = 1;
        row.lastSeen = [NSDate date];
        gRYGEasyGatingObservations[key] = row;
        notify = YES;
    } else {
        row.callCount += 1;
        row.variant = variant;
        if (row.nativeValue != nativeValue) {
            row.nativeValue = nativeValue;
            notify = YES;
        }
        // Avoid creating an NSDate for every Easy Gating query. Updating every
        // 64 calls is sufficient for the developer UI while keeping the hook's
        // pass-through path inexpensive.
        if ((row.callCount & 63u) == 0u || notify) row.lastSeen = [NSDate date];
    }
    if (notify) snapshot = row;
    os_unfair_lock_unlock(&gRYGEasyGatingLock);

    if (snapshot) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGEasyGatingDidObserveNotification
                                                              object:nil
                                                            userInfo:@{RYGEasyGatingGateIDUserInfoKey:@(gateID)}];
        });
    }
}

static uint32_t RYGEasyGatingGetBooleanReplacement(uintptr_t context0,
                                                    uint32_t gateID,
                                                    uint32_t variant,
                                                    uintptr_t context3) {
    uint32_t native = gRYGOriginalEasyGatingGetBoolean
        ? gRYGOriginalEasyGatingGetBoolean(context0, gateID, variant, context3)
        : 0;
    RYGEasyGatingRecord(gateID, variant, native != 0);
    NSNumber *forced = RYGEasyGatingCachedOverride(gateID);
    return forced ? (forced.boolValue ? 1u : 0u) : native;
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

- (void)installIfNeeded {
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gRYGEasyGatingInstalled, &expected, true)) return;

    struct rebinding binding = {
        "EasyGatingGetBoolean_Internal_DoNotUseOrMock",
        (void *)RYGEasyGatingGetBooleanReplacement,
        (void **)&gRYGOriginalEasyGatingGetBoolean,
    };
    int result = rebind_symbols(&binding, 1);
    if (result != 0) atomic_store(&gRYGEasyGatingInstalled, false);
}

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

- (NSNumber *)overrideForGateID:(uint32_t)gateID {
    return RYGEasyGatingCachedOverride(gateID);
}

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

__attribute__((constructor(180))) static void RYGEasyGatingRuntimeBootstrap(void) {
    @autoreleasepool {
        [[RYGEasyGatingRuntime shared] installIfNeeded];
    }
}
