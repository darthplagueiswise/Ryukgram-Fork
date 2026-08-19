#import "RYGEasyGatingRuntime.h"
#import <substrate.h>
#import <os/lock.h>
#import <stdatomic.h>
#import <stdint.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

NSString *const RYGEasyGatingDidObserveNotification = @"RYGEasyGatingDidObserveNotification";
NSString *const RYGEasyGatingGateIDUserInfoKey = @"gateID";

static NSString *const kRYGEasyGatingOverridesKey = @"ryg_easy_gating_bool_overrides";

// ABI re-validated against FBSharedFramework(20260819-042733):
//
// EasyGatingGetBoolean_Internal_DoNotUseOrMock saves incoming x3/x2, maps the
// incoming w1 selector/index through its internal jump table, then tail-calls
// EasyGatingPlatformGetBoolean after restoring:
//   x0 = original context
//   w1 = FINAL mapped gate ID
//   w2 = original Boolean/default value
//   w3 = (original w3 == 1)
//
// EasyGatingPlatformGetBoolean itself immediately preserves x2 as its fallback
// result, which independently confirms the default-value role. We therefore hook
// the platform function, not the pre-map public wrapper.
typedef uint32_t (*RYGEasyGatingPlatformGetBooleanFn)(uintptr_t context,
                                                       uint32_t gateID,
                                                       uint32_t defaultValue,
                                                       uint32_t exposureFlag);

static RYGEasyGatingPlatformGetBooleanFn gRYGOriginalEasyGatingPlatformGetBoolean;
static os_unfair_lock gRYGEasyGatingLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber *, RYGEasyGatingObservation *> *gRYGEasyGatingObservations;
static NSDictionary<NSString *, NSNumber *> *gRYGEasyGatingOverrideCache;
static atomic_bool gRYGEasyGatingInstalled = false;
static atomic_bool gRYGEasyGatingRetryScheduled = false;

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
    uint32_t native = gRYGOriginalEasyGatingPlatformGetBoolean
        ? gRYGOriginalEasyGatingPlatformGetBoolean(context, gateID, defaultValue, exposureFlag)
        : (defaultValue != 0 ? 1u : 0u);
    RYGEasyGatingRecord(gateID,
                        defaultValue != 0,
                        exposureFlag != 0,
                        native != 0);
    NSNumber *forced = RYGEasyGatingCachedOverride(gateID);
    return forced ? (forced.boolValue ? 1u : 0u) : native;
}

static BOOL RYGInstallEasyGatingPlatformHook(void) {
    if (atomic_load(&gRYGEasyGatingInstalled)) return YES;
    void *function = dlsym(RTLD_DEFAULT, "EasyGatingPlatformGetBoolean");
    if (!function) return NO;

    bool expected = false;
    if (!atomic_compare_exchange_strong(&gRYGEasyGatingInstalled, &expected, true)) return YES;
    MSHookFunction(function,
                   (void *)&RYGEasyGatingPlatformGetBooleanReplacement,
                   (void **)&gRYGOriginalEasyGatingPlatformGetBoolean);
    if (!gRYGOriginalEasyGatingPlatformGetBoolean) {
        atomic_store(&gRYGEasyGatingInstalled, false);
        return NO;
    }
    return YES;
}

static void RYGScheduleEasyGatingInstall(void) {
    if (atomic_load(&gRYGEasyGatingInstalled)) return;
    bool expected = false;
    if (!atomic_compare_exchange_strong(&gRYGEasyGatingRetryScheduled, &expected, true)) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        atomic_store(&gRYGEasyGatingRetryScheduled, false);
        RYGInstallEasyGatingPlatformHook();
    });
}

static void RYGEasyGatingImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    RYGScheduleEasyGatingInstall();
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
    if (!RYGInstallEasyGatingPlatformHook()) RYGScheduleEasyGatingInstall();
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
        RYGEasyGatingRefreshOverrideCache();
        RYGInstallEasyGatingPlatformHook();
        _dyld_register_func_for_add_image(RYGEasyGatingImageLoaded);
    }
}
