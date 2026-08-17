#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static NSString *const kRYGSafeRuntimeOverridesKey = @"ryg_runtime_bool_overrides";
static NSMutableSet<NSString *> *gRYGSafeInstalledKeys;
static NSLock *gRYGSafeOverrideLock;
// Process-local only. For helpers that expose an official override setter, keep
// the value observed immediately before the first override so "Use native" can
// restore it without installing a getter hook.
static NSMutableDictionary<NSString *, NSNumber *> *gRYGNativeHelperOriginalValues;

static void RYGSafeOverrideEnsureStorage(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gRYGSafeInstalledKeys = [NSMutableSet set];
        gRYGSafeOverrideLock = [NSLock new];
        gRYGNativeHelperOriginalValues = [NSMutableDictionary dictionary];
    });
}

static NSDictionary<NSString *, NSNumber *> *RYGSafePersistedOverrides(void) {
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:kRYGSafeRuntimeOverridesKey];
    if (![raw isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary<NSString *, NSNumber *> *clean = [NSMutableDictionary dictionary];
    [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSNumber.class]) clean[key] = @([value boolValue]);
    }];
    return clean.copy;
}

static NSNumber *RYGSafeOverrideForKey(NSString *key) {
    return key.length ? RYGSafePersistedOverrides()[key] : nil;
}

static BOOL RYGSafeParseKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
    if (key.length < 4) return NO;
    unichar prefix = [key characterAtIndex:0];
    if (prefix != '+' && prefix != '-') return NO;
    NSString *body = [key substringFromIndex:1];
    NSRange split = [body rangeOfString:@"#"];
    if (split.location == NSNotFound || split.location == 0 || NSMaxRange(split) >= body.length) return NO;
    if (className) *className = [body substringToIndex:split.location];
    if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(split)];
    if (classMethod) *classMethod = prefix == '+';
    return YES;
}

static Method RYGSafeDeclaredMethodInHierarchy(Class owner, SEL selector) {
    if (!owner || !selector) return NULL;
    for (Class cursor = owner; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int index = 0; index < count; index++) {
            if (method_getName(methods[index]) == selector) {
                found = methods[index];
                break;
            }
        }
        if (methods) free(methods);
        if (found) return found;
    }
    return NULL;
}

static const char *RYGSafeOverrideSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGSafeOverrideArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;
    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *arg = RYGSafeOverrideSkipQualifiers(encoded);
    if (!arg || !*arg) return -1;
    if (*arg == '@' || *arg == '#' || *arg == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *arg)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGSafeOverrideMethodMatches(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGSafeOverrideSkipQualifiers(encoded);
    return ret && *ret == 'B' && RYGSafeOverrideArgumentKind(method) >= 0;
}

#pragma mark - Verified native helper overrides

// The supplied FBSharedFramework exposes these exact BOOL getter/setter pairs on
// IGLiquidGlassNavigationExperimentHelper and IGThrowbackChromeExperimentHelper.
// Prefer their native override API; hooking the getter is unnecessary and loses
// the framework's own state-management path.
static NSString *RYGNativeHelperSetterFor(NSString *className, NSString *selectorName) {
    if (!className.length || !selectorName.length) return nil;
    BOOL navigation = [className hasSuffix:@"IGLiquidGlassNavigationExperimentHelper"];
    BOOL throwback = [className hasSuffix:@"IGThrowbackChromeExperimentHelper"];
    if (throwback && [selectorName isEqualToString:@"isEnabled"]) return @"overrideIsEnabled:";
    if (!navigation) return nil;

    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"isEnabled": @"overrideIsEnabled:",
            @"isGlassRenderingOptimizationEnabled": @"overrideIsGlassRenderingOptimizationEnabled:",
            @"isProfileSegmentedTabsGlassDisabled": @"overrideIsProfileSegmentedTabsGlassDisabled:",
            @"isProfileOtherNavBarHeightMatchSelf": @"overrideIsProfileOtherNavBarHeightMatchSelf:",
            @"isLegibilityBlurEnabled": @"overrideIsLegibilityBlurEnabled:",
        };
    });
    return map[selectorName];
}

static BOOL RYGNativeHelperKeyInfo(NSString *key,
                                   NSString **classNameOut,
                                   NSString **getterNameOut,
                                   NSString **setterNameOut) {
    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGSafeParseKey(key, &className, &selectorName, &classMethod) || classMethod) return NO;
    NSString *setter = RYGNativeHelperSetterFor(className, selectorName);
    if (!setter.length) return NO;
    if (classNameOut) *classNameOut = className;
    if (getterNameOut) *getterNameOut = selectorName;
    if (setterNameOut) *setterNameOut = setter;
    return YES;
}

static id RYGNativeHelperSharedInstance(Class cls) {
    if (!cls) return nil;
    SEL sharedSelector = NSSelectorFromString(@"shared");
    Class meta = object_getClass(cls);
    Method sharedMethod = meta ? RYGSafeDeclaredMethodInHierarchy(meta, sharedSelector) : NULL;
    if (!sharedMethod) return nil;
    return ((id (*)(id, SEL))objc_msgSend)((id)cls, sharedSelector);
}

static BOOL RYGApplyNativeHelperValueForKey(NSString *key, NSNumber *forced, BOOL restoring) {
    NSString *className = nil;
    NSString *getterName = nil;
    NSString *setterName = nil;
    if (!RYGNativeHelperKeyInfo(key, &className, &getterName, &setterName)) return NO;

    Class cls = objc_lookUpClass(className.UTF8String);
    if (!cls) return NO; // persisted value will be retried by the dyld callback
    id instance = RYGNativeHelperSharedInstance(cls);
    if (!instance) return NO;

    SEL getter = NSSelectorFromString(getterName);
    SEL setter = NSSelectorFromString(setterName);
    Method getterMethod = RYGSafeDeclaredMethodInHierarchy(cls, getter);
    Method setterMethod = RYGSafeDeclaredMethodInHierarchy(cls, setter);
    if (!getterMethod || !setterMethod) return NO;

    if (!restoring) {
        [gRYGSafeOverrideLock lock];
        BOOL hasOriginal = gRYGNativeHelperOriginalValues[key] != nil;
        [gRYGSafeOverrideLock unlock];
        if (!hasOriginal) {
            BOOL native = ((BOOL (*)(id, SEL))objc_msgSend)(instance, getter);
            [gRYGSafeOverrideLock lock];
            if (!gRYGNativeHelperOriginalValues[key]) gRYGNativeHelperOriginalValues[key] = @(native);
            [gRYGSafeOverrideLock unlock];
        }
    }

    NSNumber *value = forced;
    if (restoring) {
        [gRYGSafeOverrideLock lock];
        value = gRYGNativeHelperOriginalValues[key];
        [gRYGSafeOverrideLock unlock];
        if (!value) return NO;
    }

    ((void (*)(id, SEL, BOOL))objc_msgSend)(instance, setter, value.boolValue);
    if (restoring) {
        [gRYGSafeOverrideLock lock];
        [gRYGNativeHelperOriginalValues removeObjectForKey:key];
        [gRYGSafeOverrideLock unlock];
    }
    return YES;
}

#pragma mark - Generic BOOL method override

static BOOL RYGSafeInstallOverrideKey(NSString *key) {
    if (!key.length) return NO;
    RYGSafeOverrideEnsureStorage();

    // Native helper override setters are authoritative. If the owning image is
    // not loaded yet, keep the persisted key and retry from the dyld callback;
    // do not fall through to a competing MSHookMessageEx getter hook.
    if (RYGNativeHelperKeyInfo(key, NULL, NULL, NULL)) {
        NSNumber *value = RYGSafeOverrideForKey(key);
        return value ? RYGApplyNativeHelperValueForKey(key, value, NO) : YES;
    }

    [gRYGSafeOverrideLock lock];
    BOOL installed = [gRYGSafeInstalledKeys containsObject:key];
    if (!installed) [gRYGSafeInstalledKeys addObject:key];
    [gRYGSafeOverrideLock unlock];
    if (installed) return YES;

    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGSafeParseKey(key, &className, &selectorName, &classMethod)
        || [RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]) {
        [gRYGSafeOverrideLock lock];
        [gRYGSafeInstalledKeys removeObject:key];
        [gRYGSafeOverrideLock unlock];
        return NO;
    }

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = NSSelectorFromString(selectorName);
    Class owner = classMethod ? object_getClass(cls) : cls;
    Method method = owner ? RYGSafeDeclaredMethodInHierarchy(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGSafeOverrideMethodMatches(method)) {
        [gRYGSafeOverrideLock lock];
        [gRYGSafeInstalledKeys removeObject:key];
        [gRYGSafeOverrideLock unlock];
        return NO;
    }

    RYGRuntimeArgumentKind kind = RYGSafeOverrideArgumentKind(method);
    NSString *capturedKey = key.copy;
    SEL capturedSelector = selector;
    IMP *original = calloc(1, sizeof(IMP));
    if (!original) return NO;

    IMP replacement = NULL;
    if (kind == RYGRuntimeArgumentNone) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
            NSNumber *forced = RYGSafeOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
            NSNumber *forced = RYGSafeOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
            NSNumber *forced = RYGSafeOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    }

    if (!replacement) {
        free(original);
        [gRYGSafeOverrideLock lock];
        [gRYGSafeInstalledKeys removeObject:key];
        [gRYGSafeOverrideLock unlock];
        return NO;
    }

    MSHookMessageEx(owner, selector, replacement, original);
    if (!*original) {
        imp_removeBlock(replacement);
        free(original);
        [gRYGSafeOverrideLock lock];
        [gRYGSafeInstalledKeys removeObject:key];
        [gRYGSafeOverrideLock unlock];
        return NO;
    }
    return YES;
}

@implementation RYGRuntimeBrowserEngine (RYGRuntimeOverrideSafety)

+ (NSNumber *)ryg_safeOverrideForKey:(NSString *)overrideKey {
    return RYGSafeOverrideForKey(overrideKey);
}

+ (void)ryg_safeSetOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    NSString *key = method.overrideKey;
    if (!key.length) return;

    BOOL nativeHelper = RYGNativeHelperKeyInfo(key, NULL, NULL, NULL);
    if (nativeHelper && !value) {
        // Restore while the persisted forced value is still available and before
        // removing the key. This uses the original captured before the setter.
        RYGApplyNativeHelperValueForKey(key, nil, YES);
    }

    NSMutableDictionary<NSString *, NSNumber *> *overrides = [RYGSafePersistedOverrides() mutableCopy];
    if (value) overrides[key] = @([value boolValue]);
    else [overrides removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults setObject:overrides.copy forKey:kRYGSafeRuntimeOverridesKey];

    if (value) RYGSafeInstallOverrideKey(key);
}

+ (void)ryg_safeReinstallPersistedOverrides {
    NSDictionary<NSString *, NSNumber *> *overrides = RYGSafePersistedOverrides();
    for (NSString *key in overrides) RYGSafeInstallOverrideKey(key);
}

@end

static void RYGSwapClassMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Class meta = object_getClass(cls);
    Method original = class_getInstanceMethod(meta, originalSelector);
    Method replacement = class_getInstanceMethod(meta, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

__attribute__((constructor(65470))) static void RYGInstallRuntimeOverrideSafety(void) {
    @autoreleasepool {
        RYGSafeOverrideEnsureStorage();
        RYGSwapClassMethod(RYGRuntimeBrowserEngine.class, @selector(overrideForKey:), @selector(ryg_safeOverrideForKey:));
        RYGSwapClassMethod(RYGRuntimeBrowserEngine.class, @selector(setOverride:forMethod:), @selector(ryg_safeSetOverride:forMethod:));
        RYGSwapClassMethod(RYGRuntimeBrowserEngine.class, @selector(reinstallPersistedOverrides), @selector(ryg_safeReinstallPersistedOverrides));
    }
}
