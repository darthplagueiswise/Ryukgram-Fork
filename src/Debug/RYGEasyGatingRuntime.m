#import "RYGEasyGatingRuntime.h"
#import "../../modules/fishhook/fishhook.h"
#import <os/lock.h>
#import <stdatomic.h>
#import <stdint.h>
#include <stdlib.h>

NSString *const RYGEasyGatingDidObserveNotification = @"RYGEasyGatingDidObserveNotification";
NSString *const RYGEasyGatingGateIDUserInfoKey = @"gateID";

static NSString *const kRYGEasyGatingOverridesKey = @"ryg_easy_gating_platform_bool_overrides_v2";

// FBSharedFramework(20260819-042733), revalidated with LIEF + Capstone:
// EasyGatingGetBoolean_Internal_DoNotUseOrMock resolves the public selector/index
// to the final gate ID and reaches EasyGatingPlatformGetBoolean with
// x0=context, w1=final gate ID, w2=default Boolean, w3=exposure flag.
//
// IMPORTANT FOR SIDELOAD:
// Never inline-patch this function. On Instagram 443 the function is at
// FBSharedFramework + 0x50faf4, in the same 16 KiB signed __TEXT page as
// FBStashManagerGetStash. MSHookFunction made that page non-executable and iOS
// killed the process with CODESIGNING/Invalid Page. fishhook changes indirect
// symbol slots instead, leaving the framework's executable page untouched.
typedef uint32_t (*RYGEasyGatingPlatformGetBooleanFn)(uintptr_t context,
                                                       uint32_t gateID,
                                                       uint32_t defaultValue,
                                                       uint32_t exposureFlag);

static RYGEasyGatingPlatformGetBooleanFn gRYGOriginalEasyGatingPlatformGetBoolean;
static os_unfair_lock gRYGEasyGatingLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, RYGEasyGatingObservation *> *gRYGEasyGatingObservations;
static NSDictionary<NSString *, NSNumber *> *gRYGEasyGatingOverrideCache;
static atomic_bool gRYGEasyGatingRebindingRegistered = false;

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

static uint32_t RYGEasyGatingPlatformGetBooleanReplacement(uintptr_t context,
                                                            uint32_t gateID,
                                                            uint32_t defaultValue,
                                                            uint32_t exposureFlag) {
    RYGEasyGatingPlatformGetBooleanFn original = gRYGOriginalEasyGatingPlatformGetBoolean;
    uint32_t native = original ? original(context, gateID, defaultValue, exposureFlag)
                               : (defaultValue ? 1u : 0u);
    RYGEasyGatingRecord(gateID,
                        defaultValue != 0,
                        exposureFlag != 0,
                        native != 0);
    NSNumber *forced = RYGEasyGatingCachedOverride(gateID);
    return forced ? (forced.boolValue ? 1u : 0u) : native;
}

static BOOL RYGRegisterEasyGatingRebinding(void) {
    if (atomic_load(&gRYGEasyGatingRebindingRegistered)) return YES;

    bool expected = false;
    if (!atomic_compare_exchange_strong(&gRYGEasyGatingRebindingRegistered, &expected, true)) return YES;

    struct rebinding binding = {
        .name = "EasyGatingPlatformGetBoolean",
        .replacement = (void *)&RYGEasyGatingPlatformGetBooleanReplacement,
        .replaced = (void **)&gRYGOriginalEasyGatingPlatformGetBoolean,
    };
    if (rebind_symbols(&binding, 1) != 0) {
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

- (void)installIfNeeded {
    (void)RYGRegisterEasyGatingRebinding();
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
