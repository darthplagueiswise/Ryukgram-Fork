#import "SCINativeMobileConfigOverride.h"
#import "SCIMobileConfigRuntime.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

#define NLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] NativeMC " fmt, ##__VA_ARGS__)

// IGMobileConfigForceUpdateConfigs is a C function imported by Instagram and
// defined in FBSharedFramework. We resolve it lazily via dlsym so a missing
// symbol never breaks the build or the launch.
#import <dlfcn.h>

typedef void (*SCIForceUpdateFn)(void);

@implementation SCINativeMobileConfigOverride

+ (Class)startupConfigsClass {
    return NSClassFromString(@"FBMobileConfigStartupConfigs");
}

+ (nullable id)instance {
    Class cls = [self startupConfigsClass];
    if (!cls) return nil;
    SEL getInstance = NSSelectorFromString(@"getInstance");
    if (![cls respondsToSelector:getInstance]) return nil;
    id (*fn)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    @try {
        return fn(cls, getInstance);
    } @catch (id e) {
        NLOG("getInstance threw: %{public}@", e);
        return nil;
    }
}

+ (BOOL)available {
    id inst = [self instance];
    if (!inst) return NO;
    SEL setSel = NSSelectorFromString(@"setOverrideForParam:andValue:");
    return [inst respondsToSelector:setSel];
}

+ (BOOL)applyNativeOverrideForParamID:(unsigned long long)paramID
                                 type:(NSString *)type
                                value:(id)value {
    id inst = [self instance];
    if (!inst) return NO;

    // Wrap the raw value into the object the setter expects. setOverrideForParam:
    // takes (uint64 paramID, id value). For bool/int/double we pass an NSNumber;
    // for string an NSString. removeOverrideForParam: is used when value is nil.
    if (value == nil) {
        SEL rm = NSSelectorFromString(@"removeOverrideForParam:");
        if (![inst respondsToSelector:rm]) return NO;
        void (*fn)(id, SEL, unsigned long long) = (void (*)(id, SEL, unsigned long long))objc_msgSend;
        @try {
            fn(inst, rm, paramID);
            NLOG("removed override pid=%llu", paramID);
            return YES;
        } @catch (id e) {
            NLOG("removeOverrideForParam threw pid=%llu: %{public}@", paramID, e);
            return NO;
        }
    }

    SEL setSel = NSSelectorFromString(@"setOverrideForParam:andValue:");
    if (![inst respondsToSelector:setSel]) return NO;
    void (*fn)(id, SEL, unsigned long long, id) = (void (*)(id, SEL, unsigned long long, id))objc_msgSend;
    @try {
        fn(inst, setSel, paramID, value);
        NLOG("set override pid=%llu type=%{public}@", paramID, type);
        return YES;
    } @catch (id e) {
        NLOG("setOverrideForParam threw pid=%llu: %{public}@", paramID, e);
        return NO;
    }
}

+ (void)forceUpdateConfigs {
    static SCIForceUpdateFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (SCIForceUpdateFn)dlsym(RTLD_DEFAULT, "IGMobileConfigForceUpdateConfigs");
        NLOG("IGMobileConfigForceUpdateConfigs resolved=%d", fn != NULL);
    });
    if (!fn) return;
    @try {
        fn();
        NLOG("forceUpdateConfigs called");
    } @catch (id e) {
        NLOG("forceUpdateConfigs threw: %{public}@", e);
    }
}

+ (NSUInteger)applyAllPersistedNativeOverrides {
    if (![self available]) {
        NLOG("native path unavailable; skipping persisted apply");
        return 0;
    }
    // Reuse the runtime's persisted overrides dict: keys are "type:paramID".
    NSDictionary *overrides = [SCIMobileConfigRuntime manualOverrides];
    if (overrides.count == 0) return 0;

    NSUInteger applied = 0;
    for (NSString *key in overrides) {
        NSRange r = [key rangeOfString:@":"];
        if (r.location == NSNotFound) continue;
        NSString *type = [key substringToIndex:r.location];
        unsigned long long pid = strtoull([key substringFromIndex:r.location + 1].UTF8String, NULL, 10);
        id value = overrides[key];
        if ([self applyNativeOverrideForParamID:pid type:type value:value]) applied++;
    }
    if (applied > 0) [self forceUpdateConfigs];
    NLOG("applied %lu persisted native overrides", (unsigned long)applied);
    return applied;
}

@end
