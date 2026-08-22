#import "RYGRuntimeHookManager.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <os/lock.h>
#include <string.h>

static NSString *const kRYGRuntimeSpecsV6Key = @"ryg_runtime_bool_hook_specs_v6";
static NSString *const kRYGRuntimeLegacyV5Key = @"ryg_runtime_method_overrides_v5";
static NSString *const kRYGRuntimeLegacyV4Key = @"ryg_runtime_method_overrides_v4";
static NSString *const kRYGRuntimeLegacyQuarantineKey = @"ryg_runtime_legacy_quarantine_v6";
static NSString *const kRYGRuntimeCSpecsV6Key = @"ryg_runtime_c_hook_specs_v6";
static NSString *const kRYGRuntimeCLegacyV5Key = @"ryg_runtime_c_overrides_v5";
static NSString *const kRYGRuntimeCLegacyV4Key = @"ryg_runtime_c_overrides_v4";
static const NSUInteger kRYGRuntimeMigrationLimit = 256;

@interface RYGRuntimeHookRecord : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) Class owner;
@property (nonatomic, assign) SEL selector;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, assign) RYGRuntimeArgumentKind kind;
@property (nonatomic, assign) IMP upstream;
@property (nonatomic, assign) IMP replacement;
@end
@implementation RYGRuntimeHookRecord @end

static os_unfair_lock gRYGRuntimeLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGRuntimeValues;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGRuntimeObserved;
static NSMutableDictionary<NSString *, RYGRuntimeHookRecord *> *gRYGRuntimeHooks;
static NSMutableDictionary<NSString *, NSDictionary *> *gRYGRuntimeSpecs;
static dispatch_once_t gRYGRuntimeStoreOnce;

static const char *RYGHookSkipQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGHookBoolReturn(Method method) {
    if (!method) return NO;
    char encoded[64] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGHookSkipQualifiers(encoded);
    return type && strchr("BcC", *type) != NULL;
}

static RYGRuntimeArgumentKind RYGHookArgumentKind(Method method) {
    if (!method || !RYGHookBoolReturn(method)) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[96] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGHookSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@') return RYGRuntimeArgumentObject;
    if (*type == 'q' || *type == 'Q') return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static Method RYGHookDirectMethod(Class owner, SEL selector) {
    if (!owner || !selector) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(owner, &count);
    Method found = NULL;
    for (unsigned int index = 0; methods && index < count; index++) {
        if (method_getName(methods[index]) == selector) {
            found = methods[index];
            break;
        }
    }
    if (methods) free(methods);
    return found;
}

static BOOL RYGHookParseLegacyKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
    if (![key isKindOfClass:NSString.class] || key.length < 4) return NO;
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

static NSString *RYGHookKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
}

static NSDictionary *RYGHookValidatedSpec(id raw, NSString *fallbackKey) {
    if (![raw isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *input = raw;
    NSString *className = [input[@"class"] isKindOfClass:NSString.class] ? input[@"class"] : nil;
    NSString *selectorName = [input[@"selector"] isKindOfClass:NSString.class] ? input[@"selector"] : nil;
    NSNumber *meta = [input[@"meta"] isKindOfClass:NSNumber.class] ? input[@"meta"] : nil;
    NSNumber *kind = [input[@"kind"] isKindOfClass:NSNumber.class] ? input[@"kind"] : nil;
    NSNumber *value = [input[@"value"] isKindOfClass:NSNumber.class] ? input[@"value"] : nil;
    if ((!className.length || !selectorName.length || !meta) && fallbackKey.length) {
        BOOL classMethod = NO;
        if (!RYGHookParseLegacyKey(fallbackKey, &className, &selectorName, &classMethod)) return nil;
        meta = @(classMethod);
    }
    if (!className.length || !selectorName.length || !meta || !value) return nil;
    NSInteger rawKind = kind ? kind.integerValue : -1;
    if (rawKind < RYGRuntimeArgumentNone || rawKind > RYGRuntimeArgumentInteger) {
        Class cls = objc_lookUpClass(className.UTF8String);
        Class owner = cls ? (meta.boolValue ? object_getClass(cls) : cls) : Nil;
        Method method = RYGHookDirectMethod(owner, NSSelectorFromString(selectorName));
        rawKind = RYGHookArgumentKind(method);
    }
    if (rawKind < RYGRuntimeArgumentNone || rawKind > RYGRuntimeArgumentInteger) return nil;
    return @{
        @"class": className,
        @"selector": selectorName,
        @"meta": @(meta.boolValue),
        @"kind": @(rawKind),
        @"value": @(value.boolValue),
    };
}

static void RYGHookWriteStoreLocked(void) {
    NSDictionary *snapshot = gRYGRuntimeSpecs.copy ?: @{};
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (snapshot.count) [defaults setObject:snapshot forKey:kRYGRuntimeSpecsV6Key];
    else [defaults removeObjectForKey:kRYGRuntimeSpecsV6Key];
    [defaults removeObjectForKey:kRYGRuntimeLegacyV5Key];
    [defaults removeObjectForKey:kRYGRuntimeLegacyV4Key];
    [defaults synchronize];
}

static void RYGHookLoadStore(void) {
    dispatch_once(&gRYGRuntimeStoreOnce, ^{
        gRYGRuntimeValues = [NSMutableDictionary dictionary];
        gRYGRuntimeObserved = [NSMutableDictionary dictionary];
        gRYGRuntimeHooks = [NSMutableDictionary dictionary];
        gRYGRuntimeSpecs = [NSMutableDictionary dictionary];

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *current = [defaults dictionaryForKey:kRYGRuntimeSpecsV6Key];
        if (current.count) {
            [current enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawSpec, BOOL *stop) {
                (void)stop;
                if (![rawKey isKindOfClass:NSString.class]) return;
                NSDictionary *spec = RYGHookValidatedSpec(rawSpec, rawKey);
                if (!spec) return;
                NSString *key = RYGHookKey(spec[@"class"], spec[@"selector"], [spec[@"meta"] boolValue]);
                gRYGRuntimeSpecs[key] = spec;
                gRYGRuntimeValues[key] = spec[@"value"];
            }];
            return;
        }

        NSDictionary *legacy = [defaults dictionaryForKey:kRYGRuntimeLegacyV5Key];
        if (!legacy.count) legacy = [defaults dictionaryForKey:kRYGRuntimeLegacyV4Key];
        if (!legacy.count) return;

        if (legacy.count > kRYGRuntimeMigrationLimit) {
            [defaults setObject:@{
                @"reason": @"legacy override set exceeded bounded exact-replay limit",
                @"count": @(legacy.count),
                @"captured": legacy,
            } forKey:kRYGRuntimeLegacyQuarantineKey];
            [defaults removeObjectForKey:kRYGRuntimeLegacyV5Key];
            [defaults removeObjectForKey:kRYGRuntimeLegacyV4Key];
            [defaults synchronize];
            return;
        }

        [legacy enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawValue, BOOL *stop) {
            (void)stop;
            if (![rawKey isKindOfClass:NSString.class] || ![rawValue isKindOfClass:NSNumber.class]) return;
            NSString *className = nil;
            NSString *selectorName = nil;
            BOOL classMethod = NO;
            if (!RYGHookParseLegacyKey(rawKey, &className, &selectorName, &classMethod)) return;
            Class cls = objc_lookUpClass(className.UTF8String);
            Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
            Method method = RYGHookDirectMethod(owner, NSSelectorFromString(selectorName));
            RYGRuntimeArgumentKind kind = RYGHookArgumentKind(method);
            if (kind < RYGRuntimeArgumentNone || kind > RYGRuntimeArgumentInteger) return;
            NSString *key = RYGHookKey(className, selectorName, classMethod);
            NSDictionary *spec = @{
                @"class": className,
                @"selector": selectorName,
                @"meta": @(classMethod),
                @"kind": @(kind),
                @"value": @([(NSNumber *)rawValue boolValue]),
            };
            gRYGRuntimeSpecs[key] = spec;
            gRYGRuntimeValues[key] = spec[@"value"];
        }];
        RYGHookWriteStoreLocked();
    });
}

static NSNumber *RYGHookOverride(NSString *key) {
    RYGHookLoadStore();
    os_unfair_lock_lock(&gRYGRuntimeLock);
    NSNumber *value = gRYGRuntimeValues[key];
    os_unfair_lock_unlock(&gRYGRuntimeLock);
    return value;
}

static void RYGHookRememberNative(NSString *key, BOOL value) {
    if (!key.length) return;
    RYGHookLoadStore();
    BOOL changed = NO;
    os_unfair_lock_lock(&gRYGRuntimeLock);
    NSNumber *previous = gRYGRuntimeObserved[key];
    if (!previous || previous.boolValue != value) {
        gRYGRuntimeObserved[key] = @(value);
        changed = YES;
    }
    os_unfair_lock_unlock(&gRYGRuntimeLock);
    if (changed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification
                                                               object:nil
                                                             userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
        });
    }
}

static RYGRuntimeHookRecord *RYGHookCreateRecord(NSString *key,
                                                  Class owner,
                                                  SEL selector,
                                                  BOOL classMethod,
                                                  RYGRuntimeArgumentKind kind,
                                                  IMP upstream) {
    RYGRuntimeHookRecord *record = [RYGRuntimeHookRecord new];
    record.key = key;
    record.owner = owner;
    record.selector = selector;
    record.classMethod = classMethod;
    record.kind = kind;
    record.upstream = upstream;

    __weak RYGRuntimeHookRecord *weakRecord = record;
    if (kind == RYGRuntimeArgumentNone) {
        record.replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            RYGRuntimeHookRecord *strongRecord = weakRecord;
            if (!strongRecord) return NO;
            IMP nativeIMP = strongRecord.upstream;
            BOOL native = nativeIMP ? ((BOOL (*)(id, SEL))nativeIMP)(receiver, strongRecord.selector) : NO;
            RYGHookRememberNative(strongRecord.key, native);
            NSNumber *forced = RYGHookOverride(strongRecord.key);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentObject) {
        record.replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            RYGRuntimeHookRecord *strongRecord = weakRecord;
            if (!strongRecord) return NO;
            IMP nativeIMP = strongRecord.upstream;
            BOOL native = nativeIMP ? ((BOOL (*)(id, SEL, id))nativeIMP)(receiver, strongRecord.selector, argument) : NO;
            RYGHookRememberNative(strongRecord.key, native);
            NSNumber *forced = RYGHookOverride(strongRecord.key);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentInteger) {
        record.replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            RYGRuntimeHookRecord *strongRecord = weakRecord;
            if (!strongRecord) return NO;
            IMP nativeIMP = strongRecord.upstream;
            BOOL native = nativeIMP ? ((BOOL (*)(id, SEL, uint64_t))nativeIMP)(receiver, strongRecord.selector, argument) : NO;
            RYGHookRememberNative(strongRecord.key, native);
            NSNumber *forced = RYGHookOverride(strongRecord.key);
            return forced ? forced.boolValue : native;
        });
    }
    return record.replacement ? record : nil;
}

static BOOL RYGHookInstallExact(NSString *className,
                                NSString *selectorName,
                                BOOL classMethod,
                                RYGRuntimeArgumentKind expectedKind,
                                NSString *key) {
    if (!className.length || !selectorName.length || !key.length) return NO;
    Class cls = objc_lookUpClass(className.UTF8String);
    if (!cls) return NO;
    Class owner = classMethod ? object_getClass(cls) : cls;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = RYGHookDirectMethod(owner, selector);
    RYGRuntimeArgumentKind runtimeKind = RYGHookArgumentKind(method);
    if (!owner || !method || runtimeKind < RYGRuntimeArgumentNone || runtimeKind > RYGRuntimeArgumentInteger) return NO;
    if (expectedKind >= RYGRuntimeArgumentNone && expectedKind <= RYGRuntimeArgumentInteger && runtimeKind != expectedKind) return NO;

    IMP current = method_getImplementation(method);
    if (!current) return NO;

    RYGHookLoadStore();
    os_unfair_lock_lock(&gRYGRuntimeLock);
    RYGRuntimeHookRecord *record = gRYGRuntimeHooks[key];
    if (record && current == record.replacement) {
        os_unfair_lock_unlock(&gRYGRuntimeLock);
        return YES;
    }
    if (!record || record.owner != owner || record.selector != selector || record.kind != runtimeKind) {
        record = RYGHookCreateRecord(key, owner, selector, classMethod, runtimeKind, current);
        if (!record) {
            os_unfair_lock_unlock(&gRYGRuntimeLock);
            return NO;
        }
        gRYGRuntimeHooks[key] = record;
    } else {
        // Another hook may have legitimately replaced the method after us.
        // Chain to the current owner before reinstalling our exact trampoline.
        record.upstream = current;
    }
    IMP replacement = record.replacement;
    os_unfair_lock_unlock(&gRYGRuntimeLock);

    (void)method_setImplementation(method, replacement);
    return method_getImplementation(method) == replacement;
}

static BOOL RYGHookInstallMethod(RYGRuntimeBoolMethod *method) {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.className.length || !method.selectorName.length) return NO;
    NSString *key = method.overrideKey;
    return RYGHookInstallExact(method.className, method.selectorName, method.classMethod, method.argumentKind, key);
}

static NSString *RYGCImageID(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if ([standard isEqualToString:executable]) return @"@executable";
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static NSString *RYGCLoadedPath(NSString *imageID) {
    if (!imageID.length) return nil;
    if ([imageID isEqualToString:@"@executable"]) return NSBundle.mainBundle.executablePath;
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
        NSString *candidate = RYGCImageID(path);
        if ([candidate caseInsensitiveCompare:imageID] == NSOrderedSame) return path;
        if ([path hasPrefix:[root stringByAppendingString:@"/"]] &&
            [path.lastPathComponent caseInsensitiveCompare:imageID.lastPathComponent] == NSOrderedSame) return path;
    }
    return nil;
}

static NSMutableDictionary *RYGCStoredMutable(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *current = [defaults dictionaryForKey:kRYGRuntimeCSpecsV6Key];
    if (current.count) return current.mutableCopy;
    NSDictionary *legacy = [defaults dictionaryForKey:kRYGRuntimeCLegacyV5Key];
    if (!legacy.count) legacy = [defaults dictionaryForKey:kRYGRuntimeCLegacyV4Key];
    if (legacy.count && legacy.count <= 8) {
        [defaults setObject:legacy forKey:kRYGRuntimeCSpecsV6Key];
        [defaults removeObjectForKey:kRYGRuntimeCLegacyV5Key];
        [defaults removeObjectForKey:kRYGRuntimeCLegacyV4Key];
        [defaults synchronize];
        return legacy.mutableCopy;
    }
    return [NSMutableDictionary dictionary];
}

static void RYGCWrite(NSDictionary *records) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (records.count) [defaults setObject:records forKey:kRYGRuntimeCSpecsV6Key];
    else [defaults removeObjectForKey:kRYGRuntimeCSpecsV6Key];
    [defaults removeObjectForKey:kRYGRuntimeCLegacyV5Key];
    [defaults removeObjectForKey:kRYGRuntimeCLegacyV4Key];
    [defaults synchronize];
}

@implementation RYGRuntimeHookManager

+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method {
    RYGHookLoadStore();
    return RYGHookInstallMethod(method);
}

+ (NSNumber *)observedNativeValueForKey:(NSString *)overrideKey {
    if (!overrideKey.length) return nil;
    RYGHookLoadStore();
    os_unfair_lock_lock(&gRYGRuntimeLock);
    NSNumber *value = gRYGRuntimeObserved[overrideKey];
    os_unfair_lock_unlock(&gRYGRuntimeLock);
    return value;
}

+ (NSNumber *)overrideForKey:(NSString *)overrideKey {
    if (!overrideKey.length) return nil;
    return RYGHookOverride(overrideKey);
}

+ (BOOL)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return NO;
    if (value && !RYGHookInstallMethod(method)) return NO;
    RYGHookLoadStore();
    NSString *key = method.overrideKey;
    os_unfair_lock_lock(&gRYGRuntimeLock);
    if (value) {
        NSNumber *normalized = @(value.boolValue);
        gRYGRuntimeValues[key] = normalized;
        gRYGRuntimeSpecs[key] = @{
            @"class": method.className ?: @"",
            @"selector": method.selectorName ?: @"",
            @"meta": @(method.classMethod),
            @"kind": @(method.argumentKind),
            @"value": normalized,
        };
    } else {
        [gRYGRuntimeValues removeObjectForKey:key];
        [gRYGRuntimeSpecs removeObjectForKey:key];
    }
    RYGHookWriteStoreLocked();
    os_unfair_lock_unlock(&gRYGRuntimeLock);
    return YES;
}

+ (void)restorePersistedOverrides {
    RYGHookLoadStore();
    os_unfair_lock_lock(&gRYGRuntimeLock);
    NSDictionary<NSString *, NSDictionary *> *snapshot = gRYGRuntimeSpecs.copy ?: @{};
    os_unfair_lock_unlock(&gRYGRuntimeLock);
    [snapshot enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *spec, BOOL *stop) {
        (void)stop;
        NSString *className = spec[@"class"];
        NSString *selectorName = spec[@"selector"];
        BOOL meta = [spec[@"meta"] boolValue];
        RYGRuntimeArgumentKind kind = (RYGRuntimeArgumentKind)[spec[@"kind"] integerValue];
        (void)RYGHookInstallExact(className, selectorName, meta, kind, key);
    }];
}

+ (NSUInteger)persistedOverrideCount {
    RYGHookLoadStore();
    os_unfair_lock_lock(&gRYGRuntimeLock);
    NSUInteger count = gRYGRuntimeSpecs.count;
    os_unfair_lock_unlock(&gRYGRuntimeLock);
    return count;
}

@end

@interface RYGRuntimeBrowserEngine (RYGRuntimeHookManagerBridge)
+ (BOOL)ryg_manager_observeMethod:(RYGRuntimeBoolMethod *)method;
+ (NSNumber *)ryg_manager_observedNativeValueForKey:(NSString *)overrideKey;
+ (NSNumber *)ryg_manager_overrideForKey:(NSString *)overrideKey;
+ (void)ryg_manager_setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method;
+ (void)ryg_manager_reinstallPersistedOverrides;
+ (BOOL)ryg_manager_setCOverride:(NSNumber *)value forSymbol:(RYGMachOSymbol *)symbol abi:(RYGCFunctionABI)abi;
@end

@implementation RYGRuntimeBrowserEngine (RYGRuntimeHookManagerBridge)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct { SEL original; SEL replacement; } swaps[] = {
            {@selector(observeMethod:), @selector(ryg_manager_observeMethod:)},
            {@selector(observedNativeValueForKey:), @selector(ryg_manager_observedNativeValueForKey:)},
            {@selector(overrideForKey:), @selector(ryg_manager_overrideForKey:)},
            {@selector(setOverride:forMethod:), @selector(ryg_manager_setOverride:forMethod:)},
            {@selector(reinstallPersistedOverrides), @selector(ryg_manager_reinstallPersistedOverrides)},
            {@selector(setCOverride:forSymbol:abi:), @selector(ryg_manager_setCOverride:forSymbol:abi:)},
        };
        for (NSUInteger index = 0; index < sizeof(swaps) / sizeof(swaps[0]); index++) {
            Method original = class_getClassMethod(self, swaps[index].original);
            Method replacement = class_getClassMethod(self, swaps[index].replacement);
            if (original && replacement) method_exchangeImplementations(original, replacement);
        }
    });
}

+ (BOOL)ryg_manager_observeMethod:(RYGRuntimeBoolMethod *)method {
    return [RYGRuntimeHookManager observeMethod:method];
}

+ (NSNumber *)ryg_manager_observedNativeValueForKey:(NSString *)overrideKey {
    return [RYGRuntimeHookManager observedNativeValueForKey:overrideKey];
}

+ (NSNumber *)ryg_manager_overrideForKey:(NSString *)overrideKey {
    return [RYGRuntimeHookManager overrideForKey:overrideKey];
}

+ (void)ryg_manager_setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    (void)[RYGRuntimeHookManager setOverride:value forMethod:method];
}

+ (void)ryg_manager_reinstallPersistedOverrides {
    [RYGRuntimeHookManager restorePersistedOverrides];

    NSDictionary *stored = RYGCStoredMutable().copy;
    [stored enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawRecord, BOOL *stop) {
        (void)rawKey; (void)stop;
        if (![rawRecord isKindOfClass:NSDictionary.class]) return;
        NSDictionary *record = rawRecord;
        NSString *imageID = [record[@"image"] isKindOfClass:NSString.class] ? record[@"image"] : nil;
        NSString *name = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
        NSNumber *abi = [record[@"abi"] isKindOfClass:NSNumber.class] ? record[@"abi"] : nil;
        NSNumber *value = [record[@"value"] isKindOfClass:NSNumber.class] ? record[@"value"] : nil;
        NSString *path = RYGCLoadedPath(imageID);
        if (!path.length || !name.length || !abi || !value) return;
        RYGMachOSymbol *symbol = [RYGMachOSymbol new];
        symbol.imagePath = path;
        symbol.name = name;
        symbol.external = YES;
        symbol.rebindableImport = YES;
        (void)[self ryg_manager_setCOverride:value forSymbol:symbol abi:(RYGCFunctionABI)abi.integerValue];
    }];
}

+ (BOOL)ryg_manager_setCOverride:(NSNumber *)value forSymbol:(RYGMachOSymbol *)symbol abi:(RYGCFunctionABI)abi {
    // After exchange, this selector calls the engine's original fishhook path.
    BOOL success = [self ryg_manager_setCOverride:value forSymbol:symbol abi:abi];
    NSString *imageID = RYGCImageID(symbol.imagePath);
    NSString *name = symbol.name ?: @"";
    if (!imageID.length || !name.length) return success;

    NSMutableDictionary *stored = RYGCStoredMutable();
    NSString *recordKey = [NSString stringWithFormat:@"%@|%@", imageID, name];
    if (!value) {
        [stored removeObjectForKey:recordKey];
    } else if (success) {
        stored[recordKey] = @{
            @"image": imageID,
            @"name": name,
            @"abi": @(abi),
            @"value": @(value.boolValue),
        };
    }
    RYGCWrite(stored);
    return success;
}

@end

static void RYGRuntimeRestoreOnceAfterLaunch(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
    });
}

__attribute__((constructor(205))) static void RYGRuntimeHookManagerBootstrap(void) {
    @autoreleasepool {
        // Exact replay only: no class catalogue, no method discovery, no dyld
        // add-image callback. Try once now and once after application launch so
        // late UIKit/framework initialization does not require global scanning.
        [RYGRuntimeHookManager restorePersistedOverrides];
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                            object:nil
                                                             queue:NSOperationQueue.mainQueue
                                                        usingBlock:^(__unused NSNotification *note) {
                RYGRuntimeRestoreOnceAfterLaunch();
            }];
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateInactive) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC)),
                               dispatch_get_main_queue(), ^{ RYGRuntimeRestoreOnceAfterLaunch(); });
            }
        });
    }
}
