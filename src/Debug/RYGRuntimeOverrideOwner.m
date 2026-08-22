#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import "RYGLoadedImageCatalog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdatomic.h>
#include <string.h>

static NSString *const kRYGOwnedMethodOverridesKey = @"ryg_runtime_method_overrides_v5";
static NSString *const kRYGLegacyMethodOverridesKey = @"ryg_runtime_method_overrides_v4";
static NSString *const kRYGOwnedCOverridesKey = @"ryg_runtime_c_overrides_v5";
static NSString *const kRYGLegacyCOverridesKey = @"ryg_runtime_c_overrides_v4";

@interface RYGOwnedRuntimeHook : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) Class owner;
@property (nonatomic, assign) SEL selector;
@property (nonatomic, assign) RYGRuntimeArgumentKind kind;
@property (nonatomic, assign) IMP upstream;
@property (nonatomic, assign) IMP replacement;
@end
@implementation RYGOwnedRuntimeHook @end

static NSMutableDictionary<NSString *, NSNumber *> *gRYGOwnedOverrides;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGOwnedObserved;
static NSMutableDictionary<NSString *, RYGOwnedRuntimeHook *> *gRYGOwnedHooks;
static atomic_uint_fast64_t gRYGOwnerRestoreGeneration = 1;
static atomic_bool gRYGOwnerRestoreScheduled = false;

static dispatch_queue_t RYGOwnerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ queue = dispatch_queue_create("com.ryukgram.runtime-owner", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

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

// Runtime rows are discovered with class_copyMethodList. Restore uses the same
// direct method semantics and never asks class_getInstanceMethod to invoke a
// private +resolveInstanceMethod: implementation.
static Method RYGOwnerDirectMethod(Class owner, SEL selector) {
    if (!owner || !selector) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(owner, &count);
    Method found = NULL;
    for (unsigned int index = 0; methods && index < count; index++) {
        if (method_getName(methods[index]) == selector) { found = methods[index]; break; }
    }
    if (methods) free(methods);
    return found;
}

static NSNumber *RYGOwnerOverride(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { return gRYGOwnedOverrides[key]; }
}

static void RYGOwnerRememberNative(NSString *key, BOOL value) {
    if (!key.length) return;
    BOOL changed = NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGOwnedObserved) gRYGOwnedObserved = [NSMutableDictionary dictionary];
        NSNumber *old = gRYGOwnedObserved[key];
        if (!old || old.boolValue != value) {
            gRYGOwnedObserved[key] = @(value);
            changed = YES;
        }
    }
    if (changed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification
                                                               object:nil
                                                             userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
        });
    }
}

static RYGOwnedRuntimeHook *RYGOwnerCreateHook(NSString *key,
                                                Class owner,
                                                SEL selector,
                                                RYGRuntimeArgumentKind kind,
                                                IMP upstream) {
    RYGOwnedRuntimeHook *record = [RYGOwnedRuntimeHook new];
    record.key = key;
    record.owner = owner;
    record.selector = selector;
    record.kind = kind;
    record.upstream = upstream;

    if (kind == RYGRuntimeArgumentNone) {
        __weak RYGOwnedRuntimeHook *weakRecord = record;
        record.replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            RYGOwnedRuntimeHook *strongRecord = weakRecord;
            if (!strongRecord) return NO;
            IMP nativeIMP = strongRecord.upstream;
            BOOL native = nativeIMP ? ((BOOL (*)(id, SEL))nativeIMP)(receiver, strongRecord.selector) : NO;
            RYGOwnerRememberNative(strongRecord.key, native);
            NSNumber *forced = RYGOwnerOverride(strongRecord.key);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentObject) {
        __weak RYGOwnedRuntimeHook *weakRecord = record;
        record.replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            RYGOwnedRuntimeHook *strongRecord = weakRecord;
            if (!strongRecord) return NO;
            IMP nativeIMP = strongRecord.upstream;
            BOOL native = nativeIMP ? ((BOOL (*)(id, SEL, id))nativeIMP)(receiver, strongRecord.selector, argument) : NO;
            RYGOwnerRememberNative(strongRecord.key, native);
            NSNumber *forced = RYGOwnerOverride(strongRecord.key);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentInteger) {
        __weak RYGOwnedRuntimeHook *weakRecord = record;
        record.replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            RYGOwnedRuntimeHook *strongRecord = weakRecord;
            if (!strongRecord) return NO;
            IMP nativeIMP = strongRecord.upstream;
            BOOL native = nativeIMP ? ((BOOL (*)(id, SEL, uint64_t))nativeIMP)(receiver, strongRecord.selector, argument) : NO;
            RYGOwnerRememberNative(strongRecord.key, native);
            NSNumber *forced = RYGOwnerOverride(strongRecord.key);
            return forced ? forced.boolValue : native;
        });
    }
    return record.replacement ? record : nil;
}

static BOOL RYGOwnerEnsureHookForKey(NSString *key) {
    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGOwnerParseMethodKey(key, &className, &selectorName, &classMethod)) return NO;

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = RYGOwnerDirectMethod(owner, selector);
    RYGRuntimeArgumentKind kind = RYGOwnerArgumentKind(method);
    if (!cls || !owner || !method || kind < RYGRuntimeArgumentNone || kind > RYGRuntimeArgumentInteger) return NO;

    IMP current = method_getImplementation(method);
    if (!current) return NO;

    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGOwnedHooks) gRYGOwnedHooks = [NSMutableDictionary dictionary];
        RYGOwnedRuntimeHook *record = gRYGOwnedHooks[key];
        if (record) {
            // Never build a replacement->foreign replacement->our replacement
            // cycle. Once this process owns a method, another hook changing the
            // IMP is left alone until the next clean process launch.
            return current == record.replacement;
        }

        record = RYGOwnerCreateHook(key, owner, selector, kind, current);
        if (!record) return NO;
        (void)method_setImplementation(method, record.replacement);
        if (method_getImplementation(method) != record.replacement) {
            if (record.replacement) imp_removeBlock(record.replacement);
            return NO;
        }
        gRYGOwnedHooks[key] = record;
        return YES;
    }
}

static NSDictionary<NSString *, NSNumber *> *RYGOwnerStoredMethods(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *raw = [defaults dictionaryForKey:kRYGOwnedMethodOverridesKey];
    if (!raw.count) raw = [defaults dictionaryForKey:kRYGLegacyMethodOverridesKey];
    if (!raw.count) return @{};
    NSMutableDictionary<NSString *, NSNumber *> *clean = [NSMutableDictionary dictionary];
    [raw enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSNumber.class]) clean[key] = @([value boolValue]);
    }];
    return clean.copy;
}

static void RYGOwnerWriteMethods(void) {
    NSDictionary *snapshot = nil;
    @synchronized(RYGRuntimeBrowserEngine.class) { snapshot = gRYGOwnedOverrides.copy ?: @{}; }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (snapshot.count) [defaults setObject:snapshot forKey:kRYGOwnedMethodOverridesKey];
    else [defaults removeObjectForKey:kRYGOwnedMethodOverridesKey];
    [defaults removeObjectForKey:kRYGLegacyMethodOverridesKey];
}

static NSMutableDictionary *RYGOwnerStoredCMutable(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *raw = [defaults dictionaryForKey:kRYGOwnedCOverridesKey];
    if (!raw.count) raw = [defaults dictionaryForKey:kRYGLegacyCOverridesKey];
    return raw ? raw.mutableCopy : [NSMutableDictionary dictionary];
}

static void RYGOwnerWriteC(NSDictionary *records) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (records.count) [defaults setObject:records forKey:kRYGOwnedCOverridesKey];
    else [defaults removeObjectForKey:kRYGOwnedCOverridesKey];
    [defaults removeObjectForKey:kRYGLegacyCOverridesKey];
}

static void RYGOwnerLoadStoredMethodsIntoMemory(void) {
    NSDictionary *stored = RYGOwnerStoredMethods();
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGOwnedOverrides) gRYGOwnedOverrides = [NSMutableDictionary dictionary];
        [gRYGOwnedOverrides addEntriesFromDictionary:stored];
    }
}

static void RYGOwnerRestoreMethods(void) {
    NSDictionary *stored = nil;
    @synchronized(RYGRuntimeBrowserEngine.class) { stored = gRYGOwnedOverrides.copy ?: @{}; }
    for (NSString *key in stored) (void)RYGOwnerEnsureHookForKey(key);
}

static void RYGOwnerRestoreC(void) {
    NSDictionary *stored = RYGOwnerStoredCMutable().copy;
    [stored enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawRecord, BOOL *stop) {
        (void)rawKey; (void)stop;
        if (![rawRecord isKindOfClass:NSDictionary.class]) return;
        NSDictionary *record = rawRecord;
        NSString *imageID = [record[@"image"] isKindOfClass:NSString.class] ? record[@"image"] : nil;
        NSString *name = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
        NSNumber *abi = [record[@"abi"] isKindOfClass:NSNumber.class] ? record[@"abi"] : nil;
        NSNumber *value = [record[@"value"] isKindOfClass:NSNumber.class] ? record[@"value"] : nil;
        RYGLoadedImageRecord *image = imageID.length ? [RYGLoadedImageCatalog recordForStableIdentifier:imageID] : nil;
        if (!image.path.length || !name.length || !abi || !value) return;

        RYGMachOSymbol *symbol = [RYGMachOSymbol new];
        symbol.imagePath = image.path;
        symbol.name = name;
        symbol.external = YES;
        symbol.rebindableImport = YES;
        [RYGRuntimeBrowserEngine setCOverride:@(value.boolValue) forSymbol:symbol abi:(RYGCFunctionABI)abi.integerValue];
    }];
}

static void RYGOwnerRestoreAll(void) {
    RYGOwnerRestoreMethods();
    RYGOwnerRestoreC();
}

static void RYGOwnerDrainRestoreRequests(void) {
    for (;;) {
        uint64_t generation = atomic_load_explicit(&gRYGOwnerRestoreGeneration, memory_order_relaxed);
        @autoreleasepool { RYGOwnerRestoreAll(); }
        if (generation == atomic_load_explicit(&gRYGOwnerRestoreGeneration, memory_order_relaxed)) break;
    }
    atomic_store_explicit(&gRYGOwnerRestoreScheduled, false, memory_order_release);
    // Close the race where a request arrived after the last generation check but
    // before scheduled became false.
    uint64_t observed = atomic_load_explicit(&gRYGOwnerRestoreGeneration, memory_order_relaxed);
    (void)observed;
}

static void RYGScheduleRuntimeOwnerRestore(void) {
    atomic_fetch_add_explicit(&gRYGOwnerRestoreGeneration, 1, memory_order_relaxed);
    bool expected = false;
    if (!atomic_compare_exchange_strong_explicit(&gRYGOwnerRestoreScheduled, &expected, true,
                                                  memory_order_acq_rel, memory_order_acquire)) return;
    dispatch_async(RYGOwnerQueue(), ^{
        RYGOwnerDrainRestoreRequests();
        // If a dyld event landed exactly while the scheduled flag was being
        // released, one extra cheap exact-key pass closes that window.
        bool retryExpected = false;
        if (atomic_compare_exchange_strong_explicit(&gRYGOwnerRestoreScheduled, &retryExpected, true,
                                                     memory_order_acq_rel, memory_order_acquire)) {
            RYGOwnerDrainRestoreRequests();
        }
    });
}

static void RYGRuntimeOwnerImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    // No Runtime Browser/index lookup. The worker resolves only persisted exact
    // Class+SEL and stable-image import records.
    RYGScheduleRuntimeOwnerRestore();
}

@implementation RYGRuntimeBrowserEngine (RYGRuntimeOverrideOwner)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RYGOwnerLoadStoredMethodsIntoMemory();
        struct { SEL original; SEL owned; } swaps[] = {
            {@selector(observeMethod:), @selector(ryg_owner_observeMethod:)},
            {@selector(observedNativeValueForKey:), @selector(ryg_owner_observedNativeValueForKey:)},
            {@selector(overrideForKey:), @selector(ryg_owner_overrideForKey:)},
            {@selector(setOverride:forMethod:), @selector(ryg_owner_setOverride:forMethod:)},
            {@selector(reinstallPersistedOverrides), @selector(ryg_owner_reinstallPersistedOverrides)},
            {@selector(setCOverride:forSymbol:abi:), @selector(ryg_owner_setCOverride:forSymbol:abi:)},
        };
        for (NSUInteger index = 0; index < sizeof(swaps) / sizeof(swaps[0]); index++) {
            Method original = class_getClassMethod(self, swaps[index].original);
            Method owned = class_getClassMethod(self, swaps[index].owned);
            if (original && owned) method_exchangeImplementations(original, owned);
        }
    });
}

+ (BOOL)ryg_owner_observeMethod:(RYGRuntimeBoolMethod *)method {
    return [method isKindOfClass:RYGRuntimeBoolMethod.class] && method.overrideKey.length && RYGOwnerEnsureHookForKey(method.overrideKey);
}

+ (NSNumber *)ryg_owner_observedNativeValueForKey:(NSString *)overrideKey {
    @synchronized(self) { return gRYGOwnedObserved[overrideKey]; }
}

+ (NSNumber *)ryg_owner_overrideForKey:(NSString *)overrideKey {
    return RYGOwnerOverride(overrideKey);
}

+ (void)ryg_owner_setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return;
    if (value && !RYGOwnerEnsureHookForKey(method.overrideKey)) return;
    @synchronized(self) {
        if (!gRYGOwnedOverrides) gRYGOwnedOverrides = [NSMutableDictionary dictionary];
        if (value) gRYGOwnedOverrides[method.overrideKey] = @(value.boolValue);
        else [gRYGOwnedOverrides removeObjectForKey:method.overrideKey];
    }
    RYGOwnerWriteMethods();
}

+ (void)ryg_owner_reinstallPersistedOverrides {
    RYGScheduleRuntimeOwnerRestore();
}

+ (BOOL)ryg_owner_setCOverride:(NSNumber *)value forSymbol:(RYGMachOSymbol *)symbol abi:(RYGCFunctionABI)abi {
    // After exchange this selector invokes the engine's exact per-image fishhook
    // implementation. No symbol browser or global Mach-O scan is required.
    BOOL success = [self ryg_owner_setCOverride:value forSymbol:symbol abi:abi];
    NSString *imageID = [RYGLoadedImageCatalog stableIdentifierForPath:symbol.imagePath];
    NSString *name = symbol.name ?: @"";
    if (!imageID.length || !name.length) return success;

    NSMutableDictionary *stored = RYGOwnerStoredCMutable();
    NSString *recordKey = [NSString stringWithFormat:@"%@|%@", imageID, name];
    if (!value) [stored removeObjectForKey:recordKey];
    else if (success) stored[recordKey] = @{@"image":imageID, @"name":name, @"abi":@(abi), @"value":@(value.boolValue)};
    RYGOwnerWriteC(stored);
    return success;
}

@end

__attribute__((constructor)) static void RYGInstallRuntimeOverrideOwner(void) {
    // Restore is independent of Runtime Browser construction. Registering the
    // image callback also gives us one callback for already-loaded images; all
    // requests are coalesced onto the exact-key owner queue.
    _dyld_register_func_for_add_image(RYGRuntimeOwnerImageDidLoad);
    RYGScheduleRuntimeOwnerRestore();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) {
            RYGScheduleRuntimeOwnerRestore();
        }];
    });
}
