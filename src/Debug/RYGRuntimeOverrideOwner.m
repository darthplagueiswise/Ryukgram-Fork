#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/lock.h>
#include <stdint.h>
#include <string.h>

static NSString *const kRYGOwnerMethodOverridesKey = @"ryg_runtime_method_overrides_v5";
static NSString *const kRYGOwnerCOverridesKey = @"ryg_runtime_c_overrides_v5";

static os_unfair_lock gRYGOwnerLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGOwnerOverrides;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGOwnerObserved;
static NSMutableSet<NSValue *> *gRYGOwnerInstalledIMPs;
static BOOL gRYGOwnerRestoreScheduled;

static const char *RYGOwnerSkipQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGOwnerBoolReturn(Method method) {
    if (!method) return NO;
    char encoded[64] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGOwnerSkipQualifiers(encoded);
    return type && strchr("BcC", *type) != NULL;
}

static RYGRuntimeArgumentKind RYGOwnerArgumentKind(Method method) {
    if (!method || !RYGOwnerBoolReturn(method)) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[96] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGOwnerSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@') return RYGRuntimeArgumentObject;
    if (*type == 'q' || *type == 'Q') return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGOwnerParseMethodKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
    if (key.length < 4) return NO;
    unichar prefix = [key characterAtIndex:0];
    if (prefix != '+' && prefix != '-') return NO;
    NSString *body = [key substringFromIndex:1];
    NSRange separator = [body rangeOfString:@"#"];
    if (separator.location == NSNotFound || separator.location == 0 || NSMaxRange(separator) >= body.length) return NO;
    if (className) *className = [body substringToIndex:separator.location];
    if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(separator)];
    if (classMethod) *classMethod = prefix == '+';
    return YES;
}

static NSDictionary<NSString *, NSNumber *> *RYGOwnerReadMethodOverrides(void) {
    id raw = [NSUserDefaults.standardUserDefaults objectForKey:kRYGOwnerMethodOverridesKey];
    if (![raw isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSNumber.class]) clean[key] = @([value boolValue]);
    }];
    return clean.copy;
}

static void RYGOwnerEnsureState(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gRYGOwnerOverrides = [RYGOwnerReadMethodOverrides() mutableCopy];
        gRYGOwnerObserved = [NSMutableDictionary dictionary];
        gRYGOwnerInstalledIMPs = [NSMutableSet set];
    });
}

static NSNumber *RYGOwnerForcedValue(NSString *key) {
    if (!key.length) return nil;
    RYGOwnerEnsureState();
    os_unfair_lock_lock(&gRYGOwnerLock);
    NSNumber *value = gRYGOwnerOverrides[key];
    os_unfair_lock_unlock(&gRYGOwnerLock);
    return value;
}

static void RYGOwnerRecordNative(NSString *key, BOOL nativeValue) {
    if (!key.length) return;
    RYGOwnerEnsureState();
    BOOL changed = NO;
    os_unfair_lock_lock(&gRYGOwnerLock);
    NSNumber *old = gRYGOwnerObserved[key];
    if (!old || old.boolValue != nativeValue) {
        gRYGOwnerObserved[key] = @(nativeValue);
        changed = YES;
    }
    os_unfair_lock_unlock(&gRYGOwnerLock);
    if (changed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification
                                                              object:nil
                                                            userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
        });
    }
}

static BOOL RYGOwnerIMPIsOurs(IMP implementation) {
    if (!implementation) return NO;
    RYGOwnerEnsureState();
    os_unfair_lock_lock(&gRYGOwnerLock);
    BOOL ours = [gRYGOwnerInstalledIMPs containsObject:[NSValue valueWithPointer:implementation]];
    os_unfair_lock_unlock(&gRYGOwnerLock);
    return ours;
}

static void RYGOwnerRememberIMP(IMP implementation) {
    if (!implementation) return;
    RYGOwnerEnsureState();
    os_unfair_lock_lock(&gRYGOwnerLock);
    [gRYGOwnerInstalledIMPs addObject:[NSValue valueWithPointer:implementation]];
    os_unfair_lock_unlock(&gRYGOwnerLock);
}

static BOOL RYGOwnerInstallMethodKey(NSString *key) {
    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGOwnerParseMethodKey(key, &className, &selectorName, &classMethod)) return NO;

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
    RYGRuntimeArgumentKind kind = RYGOwnerArgumentKind(method);
    if (!cls || !owner || !selector || kind < RYGRuntimeArgumentNone || kind > RYGRuntimeArgumentInteger) return NO;

    IMP current = method_getImplementation(method);
    if (!current) return NO;
    if (RYGOwnerIMPIsOurs(current)) return YES;

    NSString *capturedKey = key.copy;
    SEL capturedSelector = selector;
    IMP displaced = current;
    IMP replacement = NULL;

    if (kind == RYGRuntimeArgumentNone) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL native = ((BOOL (*)(id, SEL))displaced)(receiver, capturedSelector);
            RYGOwnerRecordNative(capturedKey, native);
            NSNumber *forced = RYGOwnerForcedValue(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = ((BOOL (*)(id, SEL, id))displaced)(receiver, capturedSelector, argument);
            RYGOwnerRecordNative(capturedKey, native);
            NSNumber *forced = RYGOwnerForcedValue(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = ((BOOL (*)(id, SEL, uint64_t))displaced)(receiver, capturedSelector, argument);
            RYGOwnerRecordNative(capturedKey, native);
            NSNumber *forced = RYGOwnerForcedValue(capturedKey);
            return forced ? forced.boolValue : native;
        });
    }
    if (!replacement) return NO;

    RYGOwnerRememberIMP(replacement);
    method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static void RYGOwnerPersistMethods(void) {
    RYGOwnerEnsureState();
    NSDictionary *snapshot = nil;
    os_unfair_lock_lock(&gRYGOwnerLock);
    snapshot = gRYGOwnerOverrides.copy;
    os_unfair_lock_unlock(&gRYGOwnerLock);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (snapshot.count) [defaults setObject:snapshot forKey:kRYGOwnerMethodOverridesKey];
    else [defaults removeObjectForKey:kRYGOwnerMethodOverridesKey];
    [defaults synchronize];
}

static NSString *RYGOwnerImageID(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if ([standard isEqualToString:executable]) return @"@executable";
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static NSString *RYGOwnerLoadedPathForImageID(NSString *imageID) {
    if (!imageID.length) return nil;
    if ([imageID isEqualToString:@"@executable"]) return NSBundle.mainBundle.executablePath;
    for (NSString *path in [RYGRuntimeBrowserEngine runtimeImagePaths]) {
        if ([RYGOwnerImageID(path) isEqualToString:imageID]) return path;
    }
    return nil;
}

static NSMutableDictionary *RYGOwnerMutableCStore(void) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGOwnerCOverridesKey];
    return stored ? stored.mutableCopy : [NSMutableDictionary dictionary];
}

@implementation RYGRuntimeBrowserEngine (RYGRuntimeOverrideOwner)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RYGOwnerEnsureState();
        struct { SEL original; SEL owner; } swaps[] = {
            {@selector(setOverride:forMethod:), @selector(ryg_owner_setOverride:forMethod:)},
            {@selector(overrideForKey:), @selector(ryg_owner_overrideForKey:)},
            {@selector(observedNativeValueForKey:), @selector(ryg_owner_observedNativeValueForKey:)},
            {@selector(observeMethod:), @selector(ryg_owner_observeMethod:)},
            {@selector(reinstallPersistedOverrides), @selector(ryg_owner_reinstallPersistedOverrides)},
            {@selector(setCOverride:forSymbol:abi:), @selector(ryg_owner_setCOverride:forSymbol:abi:)},
        };
        for (NSUInteger index = 0; index < sizeof(swaps)/sizeof(swaps[0]); index++) {
            Method a = class_getClassMethod(self, swaps[index].original);
            Method b = class_getClassMethod(self, swaps[index].owner);
            if (a && b) method_exchangeImplementations(a, b);
        }
    });
}

+ (void)ryg_owner_setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return;
    NSString *key = method.overrideKey;
    if (value && !RYGOwnerInstallMethodKey(key)) return;
    RYGOwnerEnsureState();
    os_unfair_lock_lock(&gRYGOwnerLock);
    if (value) gRYGOwnerOverrides[key] = @(value.boolValue);
    else [gRYGOwnerOverrides removeObjectForKey:key];
    os_unfair_lock_unlock(&gRYGOwnerLock);
    RYGOwnerPersistMethods();
}

+ (NSNumber *)ryg_owner_overrideForKey:(NSString *)overrideKey {
    return RYGOwnerForcedValue(overrideKey);
}

+ (NSNumber *)ryg_owner_observedNativeValueForKey:(NSString *)overrideKey {
    if (!overrideKey.length) return nil;
    RYGOwnerEnsureState();
    os_unfair_lock_lock(&gRYGOwnerLock);
    NSNumber *value = gRYGOwnerObserved[overrideKey];
    os_unfair_lock_unlock(&gRYGOwnerLock);
    return value;
}

+ (BOOL)ryg_owner_observeMethod:(RYGRuntimeBoolMethod *)method {
    return [method isKindOfClass:RYGRuntimeBoolMethod.class] && RYGOwnerInstallMethodKey(method.overrideKey);
}

+ (BOOL)ryg_owner_setCOverride:(NSNumber *)value forSymbol:(RYGMachOSymbol *)symbol abi:(RYGCFunctionABI)abi {
    BOOL success = [self ryg_owner_setCOverride:value forSymbol:symbol abi:abi];
    NSString *imageID = RYGOwnerImageID(symbol.imagePath);
    NSString *name = symbol.name ?: @"";
    if (!imageID.length || !name.length) return success;

    NSString *recordKey = [NSString stringWithFormat:@"%@|%@", imageID, name];
    NSMutableDictionary *stored = RYGOwnerMutableCStore();
    if (!value) {
        [stored removeObjectForKey:recordKey];
    } else if (success) {
        stored[recordKey] = @{@"image":imageID, @"name":name, @"abi":@(abi), @"value":@(value.boolValue)};
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (stored.count) [defaults setObject:stored forKey:kRYGOwnerCOverridesKey];
    else [defaults removeObjectForKey:kRYGOwnerCOverridesKey];
    [defaults synchronize];
    return success;
}

+ (void)ryg_owner_reinstallPersistedOverrides {
    RYGOwnerEnsureState();
    NSArray<NSString *> *keys = nil;
    os_unfair_lock_lock(&gRYGOwnerLock);
    keys = gRYGOwnerOverrides.allKeys.copy;
    os_unfair_lock_unlock(&gRYGOwnerLock);
    for (NSString *key in keys) (void)RYGOwnerInstallMethodKey(key);

    NSDictionary *cStored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGOwnerCOverridesKey];
    [cStored enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawRecord, BOOL *stop) {
        (void)rawKey; (void)stop;
        if (![rawRecord isKindOfClass:NSDictionary.class]) return;
        NSDictionary *record = rawRecord;
        NSString *imageID = [record[@"image"] isKindOfClass:NSString.class] ? record[@"image"] : nil;
        NSString *name = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
        NSNumber *abi = [record[@"abi"] isKindOfClass:NSNumber.class] ? record[@"abi"] : nil;
        NSNumber *value = [record[@"value"] isKindOfClass:NSNumber.class] ? record[@"value"] : nil;
        NSString *path = RYGOwnerLoadedPathForImageID(imageID);
        if (!path.length || !name.length || !abi || !value) return;
        RYGMachOSymbol *symbol = [RYGMachOSymbol new];
        symbol.imagePath = path;
        symbol.name = name;
        symbol.external = YES;
        symbol.rebindableImport = YES;
        (void)[self ryg_owner_setCOverride:@(value.boolValue) forSymbol:symbol abi:(RYGCFunctionABI)abi.integerValue];
    }];
}

@end

static void RYGOwnerScheduleRestore(void) {
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (gRYGOwnerRestoreScheduled) return;
        gRYGOwnerRestoreScheduled = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(RYGRuntimeBrowserEngine.class) { gRYGOwnerRestoreScheduled = NO; }
        [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
    });
}

static void RYGOwnerImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    RYGOwnerScheduleRestore();
}

__attribute__((constructor)) static void RYGInstallRuntimeOverrideOwner(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) { RYGOwnerScheduleRestore(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) { RYGOwnerScheduleRestore(); }];
        RYGOwnerScheduleRestore();
    });
    _dyld_register_func_for_add_image(RYGOwnerImageDidLoad);
}
