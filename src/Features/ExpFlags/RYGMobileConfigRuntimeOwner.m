#import "RYGMobileConfig.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/lock.h>
#include <stdint.h>
#include <string.h>

// This is the outer MobileConfig getter owner.  It deliberately does not depend
// on ryg_metaconfig_enabled: the Developer/MobileConfig UI is always reachable,
// so an override selected there must have a runtime consumer on the next launch.
//
// Instagram/FB bootstrap is allowed to swizzle the same getters after us.  On
// every real lifecycle/image event we inspect the CURRENT IMP.  If our wrapper
// is no longer outermost, a fresh wrapper is installed around whatever displaced
// it.  This avoids the old one-shot "orig != NULL means installed" failure.

static os_unfair_lock gRYGMCOwnerLock = OS_UNFAIR_LOCK_INIT;
static NSMutableSet<NSValue *> *gRYGMCOwnerIMPs;
static NSMutableDictionary<NSNumber *, RYGMCParam *> *gRYGMCOwnerParams;
static BOOL gRYGMCOwnerRestoreScheduled;

static void RYGMCOwnerEnsureState(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gRYGMCOwnerIMPs = [NSMutableSet set];
        gRYGMCOwnerParams = [NSMutableDictionary dictionary];
        // Force persisted mc_overrides.plist to be loaded even if the legacy
        // MobileConfig ctor preference is disabled.
        (void)RYGMobileConfig.shared;
    });
}

static const char *RYGMCOuterUnqualifiedType(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGMCOwnerTypeMatches(const char *raw, char expected) {
    const char *type = RYGMCOuterUnqualifiedType(raw);
    if (!type || !*type) return NO;
    switch (expected) {
        case 'P':
            return *type == 'Q' || *type == 'q' ||
                   (*type == '{' && (strstr(type, "=Q}") || strstr(type, "=q}")));
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

static BOOL RYGMCOwnerIMPIsOurs(IMP implementation) {
    if (!implementation) return NO;
    RYGMCOwnerEnsureState();
    os_unfair_lock_lock(&gRYGMCOwnerLock);
    BOOL ours = [gRYGMCOwnerIMPs containsObject:[NSValue valueWithPointer:implementation]];
    os_unfair_lock_unlock(&gRYGMCOwnerLock);
    return ours;
}

static void RYGMCOwnerRememberIMP(IMP implementation) {
    if (!implementation) return;
    RYGMCOwnerEnsureState();
    os_unfair_lock_lock(&gRYGMCOwnerLock);
    [gRYGMCOwnerIMPs addObject:[NSValue valueWithPointer:implementation]];
    os_unfair_lock_unlock(&gRYGMCOwnerLock);
}

static RYGMCParam *RYGMCOwnerParam(unsigned long long pid, RYGMCType type) {
    if (!pid) return nil;
    RYGMCOwnerEnsureState();
    NSNumber *key = @(pid);
    os_unfair_lock_lock(&gRYGMCOwnerLock);
    RYGMCParam *param = gRYGMCOwnerParams[key];
    if (!param) {
        param = [RYGMCParam new];
        param.paramID = pid;
        param.type = type;
        param.runtimeBacked = YES;
        gRYGMCOwnerParams[key] = param;
    }
    os_unfair_lock_unlock(&gRYGMCOwnerLock);
    return param;
}

static id RYGMCOwnerOverride(unsigned long long pid, RYGMCType type) {
    RYGMCParam *param = RYGMCOwnerParam(pid, type);
    return param ? [RYGMobileConfig.shared overrideValueFor:param] : nil;
}

static BOOL RYGMCOwnerInstallBool0(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'B', "P")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current;
    SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver, unsigned long long pid) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeBool);
        return forced ? [forced boolValue] : ((BOOL (*)(id, SEL, unsigned long long))displaced)(receiver, captured, pid);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement);
    method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallBoolDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'B', "PB")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver, unsigned long long pid, BOOL defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeBool);
        return forced ? [forced boolValue] : ((BOOL (*)(id, SEL, unsigned long long, BOOL))displaced)(receiver, captured, pid, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallBoolOptions(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'B', "P@")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver, unsigned long long pid, id options) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeBool);
        return forced ? [forced boolValue] : ((BOOL (*)(id, SEL, unsigned long long, id))displaced)(receiver, captured, pid, options);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallBoolOptionsDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'B', "P@B")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^BOOL(id receiver, unsigned long long pid, id options, BOOL defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeBool);
        return forced ? [forced boolValue] : ((BOOL (*)(id, SEL, unsigned long long, id, BOOL))displaced)(receiver, captured, pid, options, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallInt0(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'Q', "P")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^long long(id receiver, unsigned long long pid) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeInt);
        return forced ? [forced longLongValue] : ((long long (*)(id, SEL, unsigned long long))displaced)(receiver, captured, pid);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallIntDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'Q', "PQ")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^long long(id receiver, unsigned long long pid, long long defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeInt);
        return forced ? [forced longLongValue] : ((long long (*)(id, SEL, unsigned long long, long long))displaced)(receiver, captured, pid, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallIntOptions(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'Q', "P@")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^long long(id receiver, unsigned long long pid, id options) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeInt);
        return forced ? [forced longLongValue] : ((long long (*)(id, SEL, unsigned long long, id))displaced)(receiver, captured, pid, options);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallIntOptionsDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'Q', "P@Q")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^long long(id receiver, unsigned long long pid, id options, long long defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeInt);
        return forced ? [forced longLongValue] : ((long long (*)(id, SEL, unsigned long long, id, long long))displaced)(receiver, captured, pid, options, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallDouble0(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'D', "P")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^double(id receiver, unsigned long long pid) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeDouble);
        return forced ? [forced doubleValue] : ((double (*)(id, SEL, unsigned long long))displaced)(receiver, captured, pid);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallDoubleDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'D', "PD")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^double(id receiver, unsigned long long pid, double defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeDouble);
        return forced ? [forced doubleValue] : ((double (*)(id, SEL, unsigned long long, double))displaced)(receiver, captured, pid, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallDoubleOptions(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'D', "P@")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^double(id receiver, unsigned long long pid, id options) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeDouble);
        return forced ? [forced doubleValue] : ((double (*)(id, SEL, unsigned long long, id))displaced)(receiver, captured, pid, options);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallDoubleOptionsDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, 'D', "P@D")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^double(id receiver, unsigned long long pid, id options, double defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeDouble);
        return forced ? [forced doubleValue] : ((double (*)(id, SEL, unsigned long long, id, double))displaced)(receiver, captured, pid, options, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallString0(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, '@', "P")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^id(id receiver, unsigned long long pid) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeString);
        return [forced isKindOfClass:NSString.class] ? forced : ((id (*)(id, SEL, unsigned long long))displaced)(receiver, captured, pid);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallStringDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, '@', "P@")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^id(id receiver, unsigned long long pid, id defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeString);
        return [forced isKindOfClass:NSString.class] ? forced : ((id (*)(id, SEL, unsigned long long, id))displaced)(receiver, captured, pid, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGMCOwnerInstallStringOptions(Class cls, SEL selector) {
    // getString:withOptions: has the same Objective-C ABI as withDefault:.
    return RYGMCOwnerInstallStringDefault(cls, selector);
}

static BOOL RYGMCOwnerInstallStringOptionsDefault(Class cls, SEL selector) {
    Method method = cls && selector ? class_getInstanceMethod(cls, selector) : NULL;
    if (!RYGMCOwnerMethodMatches(method, '@', "P@@")) return NO;
    IMP current = method_getImplementation(method);
    if (!current || RYGMCOwnerIMPIsOurs(current)) return current != NULL;
    IMP displaced = current; SEL captured = selector;
    IMP replacement = imp_implementationWithBlock(^id(id receiver, unsigned long long pid, id options, id defaultValue) {
        id forced = RYGMCOwnerOverride(pid, RYGMCTypeString);
        return [forced isKindOfClass:NSString.class] ? forced : ((id (*)(id, SEL, unsigned long long, id, id))displaced)(receiver, captured, pid, options, defaultValue);
    });
    if (!replacement) return NO;
    RYGMCOwnerRememberIMP(replacement); method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static void RYGMCOwnerInstallForClass(Class cls) {
    if (!cls) return;
    (void)RYGMCOwnerInstallBool0(cls, NSSelectorFromString(@"getBool:"));
    (void)RYGMCOwnerInstallBoolDefault(cls, NSSelectorFromString(@"getBool:withDefault:"));
    (void)RYGMCOwnerInstallBoolOptions(cls, NSSelectorFromString(@"getBool:withOptions:"));
    (void)RYGMCOwnerInstallBoolOptionsDefault(cls, NSSelectorFromString(@"getBool:withOptions:withDefault:"));

    (void)RYGMCOwnerInstallInt0(cls, NSSelectorFromString(@"getInt64:"));
    (void)RYGMCOwnerInstallIntDefault(cls, NSSelectorFromString(@"getInt64:withDefault:"));
    (void)RYGMCOwnerInstallIntOptions(cls, NSSelectorFromString(@"getInt64:withOptions:"));
    (void)RYGMCOwnerInstallIntOptionsDefault(cls, NSSelectorFromString(@"getInt64:withOptions:withDefault:"));

    (void)RYGMCOwnerInstallDouble0(cls, NSSelectorFromString(@"getDouble:"));
    (void)RYGMCOwnerInstallDoubleDefault(cls, NSSelectorFromString(@"getDouble:withDefault:"));
    (void)RYGMCOwnerInstallDoubleOptions(cls, NSSelectorFromString(@"getDouble:withOptions:"));
    (void)RYGMCOwnerInstallDoubleOptionsDefault(cls, NSSelectorFromString(@"getDouble:withOptions:withDefault:"));

    (void)RYGMCOwnerInstallString0(cls, NSSelectorFromString(@"getString:"));
    (void)RYGMCOwnerInstallStringDefault(cls, NSSelectorFromString(@"getString:withDefault:"));
    (void)RYGMCOwnerInstallStringOptions(cls, NSSelectorFromString(@"getString:withOptions:"));
    (void)RYGMCOwnerInstallStringOptionsDefault(cls, NSSelectorFromString(@"getString:withOptions:withDefault:"));
}

static void RYGMCOwnerRestore(void) {
    RYGMCOwnerEnsureState();
    RYGMCOwnerInstallForClass(objc_lookUpClass("FBMobileConfigContextManager"));
    RYGMCOwnerInstallForClass(objc_lookUpClass("IGMobileConfigContextManager"));

    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    if (mobileConfig.overrideCount) [mobileConfig reapplyOverridesToNativeTable];
}

static void RYGMCOwnerScheduleRestore(void) {
    @synchronized(RYGMobileConfig.class) {
        if (gRYGMCOwnerRestoreScheduled) return;
        gRYGMCOwnerRestoreScheduled = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(RYGMobileConfig.class) { gRYGMCOwnerRestoreScheduled = NO; }
        RYGMCOwnerRestore();
    });
}

static void RYGMCOwnerImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    RYGMCOwnerScheduleRestore();
}

__attribute__((constructor)) static void RYGInstallMobileConfigRuntimeOwner(void) {
    RYGMCOwnerEnsureState();
    RYGMCOwnerRestore();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) { RYGMCOwnerScheduleRestore(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) { RYGMCOwnerScheduleRestore(); }];
    });
    _dyld_register_func_for_add_image(RYGMCOwnerImageDidLoad);
}
