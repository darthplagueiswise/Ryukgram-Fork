#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

static NSString *const kRYGPersistedMethodOverridesKey = @"ryg_runtime_method_overrides_v4";
static NSString *const kRYGPersistedCOverridesKey = @"ryg_runtime_c_overrides_v4";
static BOOL gRYGRuntimeRestoreScheduled;

static NSString *RYGPersistenceImageID(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    if ([standard isEqualToString:executable]) return @"@executable";
    NSString *root = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if ([standard hasPrefix:prefix]) return [standard substringFromIndex:prefix.length];
    return standard.lastPathComponent ?: @"";
}

static NSString *RYGLoadedPathForImageID(NSString *imageID) {
    if (!imageID.length) return nil;
    if ([imageID isEqualToString:@"@executable"]) return NSBundle.mainBundle.executablePath;
    for (NSString *path in [RYGRuntimeBrowserEngine runtimeImagePaths]) {
        if ([RYGPersistenceImageID(path) isEqualToString:imageID]) return path;
    }
    return nil;
}

static NSMutableDictionary *RYGMutableDefaultsDictionary(NSString *key) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:key];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

static void RYGPersistDefaultsDictionary(NSMutableDictionary *dictionary, NSString *key) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (dictionary.count) [defaults setObject:dictionary.copy forKey:key];
    else [defaults removeObjectForKey:key];
    // A runtime override is an explicit user action. Flush it before returning
    // so a force-quit immediately afterwards does not silently lose the choice.
    [defaults synchronize];
}

static BOOL RYGParseMethodKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
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

static RYGRuntimeBoolMethod *RYGMethodFromPersistedKey(NSString *key) {
    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGParseMethodKey(key, &className, &selectorName, &classMethod)) return nil;
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
    if (!method) return nil;

    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.className = className;
    row.selectorName = selectorName;
    row.classMethod = classMethod;
    const char *types = method_getTypeEncoding(method);
    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    const char *image = class_getImageName(cls);
    row.imagePath = image ? [NSString stringWithUTF8String:image] : @"";
    return row;
}

static void RYGRestoreMethodOverrides(void) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGPersistedMethodOverridesKey];
    [stored enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawValue, BOOL *stop) {
        (void)stop;
        if (![rawKey isKindOfClass:NSString.class] || ![rawValue isKindOfClass:NSNumber.class]) return;
        RYGRuntimeBoolMethod *method = RYGMethodFromPersistedKey(rawKey);
        if (method) [RYGRuntimeBrowserEngine setOverride:@([(NSNumber *)rawValue boolValue]) forMethod:method];
    }];
}

static void RYGRestoreCOverrides(void) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGPersistedCOverridesKey];
    [stored enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawRecord, BOOL *stop) {
        (void)rawKey; (void)stop;
        if (![rawRecord isKindOfClass:NSDictionary.class]) return;
        NSDictionary *record = rawRecord;
        NSString *imageID = [record[@"image"] isKindOfClass:NSString.class] ? record[@"image"] : nil;
        NSString *name = [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : nil;
        NSNumber *abi = [record[@"abi"] isKindOfClass:NSNumber.class] ? record[@"abi"] : nil;
        NSNumber *value = [record[@"value"] isKindOfClass:NSNumber.class] ? record[@"value"] : nil;
        NSString *path = RYGLoadedPathForImageID(imageID);
        if (!path.length || !name.length || !abi || !value) return;

        RYGMachOSymbol *symbol = [RYGMachOSymbol new];
        symbol.imagePath = path;
        symbol.name = name;
        symbol.external = YES;
        symbol.rebindableImport = YES;
        [RYGRuntimeBrowserEngine setCOverride:@(value.boolValue) forSymbol:symbol abi:(RYGCFunctionABI)abi.integerValue];
    }];
}

static void RYGRestorePersistedRuntimeOverrides(void) {
    [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
}

static void RYGScheduleRuntimeRestore(void) {
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (gRYGRuntimeRestoreScheduled) return;
        gRYGRuntimeRestoreScheduled = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(RYGRuntimeBrowserEngine.class) { gRYGRuntimeRestoreScheduled = NO; }
        RYGRestorePersistedRuntimeOverrides();
    });
}

static void RYGRuntimePersistenceImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    // dyld invokes this for existing images at registration and for genuinely
    // late-loaded frameworks. Coalescing onto the main queue makes restore
    // deterministic without clock-based retries.
    RYGScheduleRuntimeRestore();
}

@implementation RYGRuntimeBrowserEngine (RYGRuntimePersistenceCompat)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method setMethod = class_getClassMethod(self, @selector(setOverride:forMethod:));
        Method persistedSetMethod = class_getClassMethod(self, @selector(ryg_persist_setOverride:forMethod:));
        if (setMethod && persistedSetMethod) method_exchangeImplementations(setMethod, persistedSetMethod);

        Method cMethod = class_getClassMethod(self, @selector(setCOverride:forSymbol:abi:));
        Method persistedCMethod = class_getClassMethod(self, @selector(ryg_persist_setCOverride:forSymbol:abi:));
        if (cMethod && persistedCMethod) method_exchangeImplementations(cMethod, persistedCMethod);

        Method reinstallMethod = class_getClassMethod(self, @selector(reinstallPersistedOverrides));
        Method compatReinstallMethod = class_getClassMethod(self, @selector(ryg_persist_reinstallPersistedOverrides));
        if (reinstallMethod && compatReinstallMethod) method_exchangeImplementations(reinstallMethod, compatReinstallMethod);
    });
}

+ (void)ryg_persist_setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    [self ryg_persist_setOverride:value forMethod:method];
    NSString *key = method.overrideKey;
    if (!key.length) return;

    NSMutableDictionary *stored = RYGMutableDefaultsDictionary(kRYGPersistedMethodOverridesKey);
    if (!value) {
        [stored removeObjectForKey:key];
    } else {
        NSNumber *installed = [self overrideForKey:key];
        if (installed) stored[key] = @(installed.boolValue);
    }
    RYGPersistDefaultsDictionary(stored, kRYGPersistedMethodOverridesKey);
}

+ (BOOL)ryg_persist_setCOverride:(NSNumber *)value forSymbol:(RYGMachOSymbol *)symbol abi:(RYGCFunctionABI)abi {
    BOOL success = [self ryg_persist_setCOverride:value forSymbol:symbol abi:abi];
    NSString *imageID = RYGPersistenceImageID(symbol.imagePath);
    NSString *name = symbol.name ?: @"";
    if (!imageID.length || !name.length) return success;

    NSString *recordKey = [NSString stringWithFormat:@"%@|%@", imageID, name];
    NSMutableDictionary *stored = RYGMutableDefaultsDictionary(kRYGPersistedCOverridesKey);
    if (!value) {
        [stored removeObjectForKey:recordKey];
    } else if (success) {
        stored[recordKey] = @{@"image": imageID, @"name": name, @"abi": @(abi), @"value": @(value.boolValue)};
    }
    RYGPersistDefaultsDictionary(stored, kRYGPersistedCOverridesKey);
    return success;
}

+ (void)ryg_persist_reinstallPersistedOverrides {
    [self ryg_persist_reinstallPersistedOverrides];
    RYGRestoreMethodOverrides();
    RYGRestoreCOverrides();
}

@end

__attribute__((constructor)) static void RYGInstallRuntimePersistenceCompat(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) {
            RYGScheduleRuntimeRestore();
        }];
        RYGScheduleRuntimeRestore();
    });
    _dyld_register_func_for_add_image(RYGRuntimePersistenceImageDidLoad);
}
