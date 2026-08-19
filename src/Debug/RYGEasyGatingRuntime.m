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

// Re-validated against the current supplied Instagram executable. Calls to the
// FBSharedFramework export materialize the gate id in w1, the variant in w2,
// preserve opaque contexts in x0/x3 and consume the Boolean result from w0.
// The opaque arguments are forwarded bit-for-bit; only the proven integer
// fields and Boolean return are interpreted.
typedef uint32_t (*RYGEasyGatingGetBooleanFn)(uintptr_t context0,
                                              uint32_t gateID,
                                              uint32_t variant,
                                              uintptr_t context3);

static RYGEasyGatingGetBooleanFn gRYGOriginalEasyGatingGetBoolean;
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

static void RYGEasyGatingRecord(uint32_t gateID, uint32_t variant, BOOL nativeValue) {
    BOOL notify = NO;
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
        row.lastSeen = NSDate.date;
        gRYGEasyGatingObservations[key] = row;
        notify = YES;
    } else {
        row.callCount += 1;
        row.variant = variant;
        if (row.nativeValue != nativeValue) {
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

static BOOL RYGInstallEasyGatingExportHook(void) {
    if (atomic_load(&gRYGEasyGatingInstalled)) return YES;
    void *function = dlsym(RTLD_DEFAULT, "EasyGatingGetBoolean_Internal_DoNotUseOrMock");
    if (!function) return NO;

    bool expected = false;
    if (!atomic_compare_exchange_strong(&gRYGEasyGatingInstalled, &expected, true)) return YES;
    MSHookFunction(function,
                   (void *)&RYGEasyGatingGetBooleanReplacement,
                   (void **)&gRYGOriginalEasyGatingGetBoolean);
    if (!gRYGOriginalEasyGatingGetBoolean) {
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
        RYGInstallEasyGatingExportHook();
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
    if (!RYGInstallEasyGatingExportHook()) RYGScheduleEasyGatingInstall();
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
        RYGInstallEasyGatingExportHook();
        _dyld_register_func_for_add_image(RYGEasyGatingImageLoaded);
    }
}