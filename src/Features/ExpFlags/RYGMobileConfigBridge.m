#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@interface RYGMobileConfig (RYGBridgePrivate)
- (NSDictionary *)loadNameCatalog;
@end

static NSString *const kRYGMappingCacheFile = @"id_name_mapping.json";
static NSString *const kRYGMobileConfigNamesDidChangeNotification = @"RYGMobileConfigNamesDidChange";

static NSError *RYGBridgeError(NSString *message) {
    return [NSError errorWithDomain:@"com.ryukgram.mobileconfig.bridge"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey:message ?: @"MobileConfig mapping error"}];
}

static NSString *RYGBridgeSupportDirectory(void) {
    NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    if (!root.length) root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *directory = [[root stringByAppendingPathComponent:@"RyukGram"] stringByAppendingPathComponent:@"MobileConfig"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

static NSString *RYGBridgeMappingCachePath(void) {
    return [RYGBridgeSupportDirectory() stringByAppendingPathComponent:kRYGMappingCacheFile];
}

static NSNumber *RYGBridgeStrictUnsigned(NSString *text, BOOL allowZero) {
    if (![text isKindOfClass:NSString.class] || !text.length) return nil;
    const char *raw = text.UTF8String;
    if (!raw || !*raw || *raw == '-') return nil;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 10);
    if (end == raw || *end != '\0' || value > UINT32_MAX || (!allowZero && value == 0)) return nil;
    return @(value);
}

static NSDictionary<NSNumber *, NSDictionary *> *RYGBridgeCatalogFromData(NSData *data, NSError **error) {
    if (!data.length) {
        if (error) *error = RYGBridgeError(@"The id_name_mapping.json file is empty.");
        return nil;
    }
    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![json isKindOfClass:NSArray.class]) {
        if (error) *error = jsonError ?: RYGBridgeError(@"id_name_mapping.json must be an array of colon-delimited strings.");
        return nil;
    }

    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *mutableCatalog = [NSMutableDictionary dictionary];
    for (id rawEntry in (NSArray *)json) {
        if (![rawEntry isKindOfClass:NSString.class]) {
            if (error) *error = RYGBridgeError(@"id_name_mapping.json contains a non-string entry.");
            return nil;
        }
        NSArray<NSString *> *parts = [(NSString *)rawEntry componentsSeparatedByString:@":"];
        if (parts.count < 2) {
            if (error) *error = RYGBridgeError(@"id_name_mapping.json contains an invalid config entry.");
            return nil;
        }
        NSNumber *configNumber = RYGBridgeStrictUnsigned(parts[0], NO);
        if (!configNumber) {
            if (error) *error = RYGBridgeError(@"id_name_mapping.json contains an invalid config id.");
            return nil;
        }

        NSMutableDictionary *record = mutableCatalog[configNumber];
        if (!record) {
            record = [@{@"name": @"", @"params": [NSMutableDictionary dictionary]} mutableCopy];
            mutableCatalog[configNumber] = record;
        }
        if (parts[1].length) record[@"name"] = parts[1];
        NSMutableDictionary *params = record[@"params"];
        for (NSUInteger index = 2; index + 1 < parts.count; index += 2) {
            NSNumber *paramIndex = RYGBridgeStrictUnsigned(parts[index], YES);
            NSString *paramName = parts[index + 1];
            if (paramIndex && paramName.length) params[paramIndex] = paramName;
        }
    }

    NSMutableDictionary *catalog = [NSMutableDictionary dictionaryWithCapacity:mutableCatalog.count];
    [mutableCatalog enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSDictionary *record, BOOL *stop) {
        catalog[key] = @{
            @"name": [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : @"",
            @"params": [record[@"params"] isKindOfClass:NSDictionary.class] ? [record[@"params"] copy] : @{},
        };
    }];
    return catalog.copy;
}

static NSData *RYGBridgeDataFromCatalog(NSDictionary<NSNumber *, NSDictionary *> *catalog, NSError **error) {
    NSArray<NSNumber *> *configNumbers = [catalog.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *entries = [NSMutableArray arrayWithCapacity:configNumbers.count];
    for (NSNumber *configNumber in configNumbers) {
        NSDictionary *info = catalog[configNumber];
        NSString *configName = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : @"";
        NSMutableString *line = [NSMutableString stringWithFormat:@"%@:%@", configNumber, configName];
        NSDictionary<NSNumber *, NSString *> *params = [info[@"params"] isKindOfClass:NSDictionary.class] ? info[@"params"] : @{};
        for (NSNumber *paramIndex in [params.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *name = [params[paramIndex] isKindOfClass:NSString.class] ? params[paramIndex] : @"";
            if (name.length) [line appendFormat:@":%@:%@", paramIndex, name];
        }
        [entries addObject:line];
    }
    return [NSJSONSerialization dataWithJSONObject:entries options:0 error:error];
}

static NSUInteger RYGBridgeResolvedNameCount(RYGMobileConfig *mobileConfig) {
    NSUInteger count = 0;
    for (RYGMCConfig *config in mobileConfig.allConfigs) {
        if (config.name.length) count++;
        for (RYGMCParam *param in config.params) if (param.name.length) count++;
    }
    return count;
}

static void RYGBridgePostNamesDidChange(RYGMobileConfig *mobileConfig) {
    NSDictionary *info = @{@"resolvedCount": @(RYGBridgeResolvedNameCount(mobileConfig))};
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:kRYGMobileConfigNamesDidChangeNotification
                                                          object:mobileConfig
                                                        userInfo:info];
    };
    if (NSThread.isMainThread) post(); else dispatch_async(dispatch_get_main_queue(), post);
}

#pragma mark - Signed App Group discovery

typedef CFTypeRef (*RYGSecTaskCreateFromSelfFn)(CFAllocatorRef allocator);
typedef CFTypeRef (*RYGSecTaskCopyValueForEntitlementFn)(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error);

static NSArray<NSString *> *RYGSignedApplicationGroups(void) {
    RYGSecTaskCreateFromSelfFn createTask = (RYGSecTaskCreateFromSelfFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    RYGSecTaskCopyValueForEntitlementFn copyValue = (RYGSecTaskCopyValueForEntitlementFn)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyValue) return @[];
    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) return @[];
    CFTypeRef raw = copyValue(task, CFSTR("com.apple.security.application-groups"), NULL);
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    if (raw && CFGetTypeID(raw) == CFArrayGetTypeID()) {
        for (id value in (__bridge NSArray *)raw) if ([value isKindOfClass:NSString.class] && [value length]) [groups addObject:value];
    }
    if (raw) CFRelease(raw);
    CFRelease(task);
    return groups.copy;
}

static NSInteger RYGBridgeDataDirectoryScore(NSString *path) {
    BOOL directory = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path isDirectory:&directory] || !directory) return NSIntegerMin;
    NSInteger score = 0;
    NSString *name = path.lastPathComponent.lowercaseString;
    if ([name hasSuffix:@".data"]) score += 30;
    if (![name isEqualToString:@"sessionless.data"]) score += 20;
    if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"mc_overrides.json"]]) score += 80;
    if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"id_name_mapping.json"]]) score += 100;
    return score;
}

static NSString *RYGFallbackNativeMobileConfigDirectory(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *bestPath = nil;
    NSInteger bestScore = NSIntegerMin;
    for (NSString *group in RYGSignedApplicationGroups()) {
        NSURL *container = [fm containerURLForSecurityApplicationGroupIdentifier:group];
        if (!container.path.length) continue;
        NSString *root = [[container.path stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"mobileconfig"];
        for (NSString *child in [fm contentsOfDirectoryAtPath:root error:nil]) {
            NSString *candidate = [root stringByAppendingPathComponent:child];
            NSInteger score = RYGBridgeDataDirectoryScore(candidate);
            if (score > bestScore) { bestScore = score; bestPath = candidate; }
        }
    }
    return bestScore == NSIntegerMin ? nil : bestPath;
}

static void RYGBridgeMirrorCache(NSString *nativeDirectory) {
    if (!nativeDirectory.length) return;
    NSData *cache = [NSData dataWithContentsOfFile:RYGBridgeMappingCachePath() options:0 error:nil];
    if (!cache.length) return;
    NSString *destination = [nativeDirectory stringByAppendingPathComponent:kRYGMappingCacheFile];
    NSData *existing = [NSData dataWithContentsOfFile:destination options:0 error:nil];
    if (![existing isEqualToData:cache]) [cache writeToFile:destination options:NSDataWritingAtomic error:nil];
}

@implementation RYGMobileConfig (RYGMobileConfigBridge)

- (NSString *)ryg_bridgeNativeDataDirectory {
    NSString *directory = [self ryg_bridgeNativeDataDirectory];
    if (!directory.length) directory = RYGFallbackNativeMobileConfigDirectory();
    if (directory.length) RYGBridgeMirrorCache(directory);
    return directory;
}

- (BOOL)ryg_bridgeImportNameMappingData:(NSData *)data error:(NSError **)error {
    NSDictionary *catalog = RYGBridgeCatalogFromData(data, error);
    if (!catalog) return NO;
    NSData *canonical = RYGBridgeDataFromCatalog(catalog, error);
    if (!canonical) return NO;

    // This selector represents REPLACE semantics. Merge is resolved by
    // RYGMobileConfigJSONIO before it reaches here. The cache is authoritative:
    // names absent from a replacement import must not be resurrected from an old
    // native file on the next reload.
    if (![canonical writeToFile:RYGBridgeMappingCachePath() options:NSDataWritingAtomic error:error]) return NO;
    NSString *nativeDirectory = [self ryg_nativeDataDirectory];
    if (nativeDirectory.length) RYGBridgeMirrorCache(nativeDirectory);

    [self reloadFromRuntime];
    RYGBridgePostNamesDidChange(self);
    return YES;
}

- (NSData *)ryg_bridgeExportNameMappingData:(NSError **)error {
    NSData *cache = [NSData dataWithContentsOfFile:RYGBridgeMappingCachePath() options:0 error:nil];
    if (cache.length) return cache;
    return [self ryg_bridgeExportNameMappingData:error];
}

- (NSDictionary *)ryg_bridgeLoadNameCatalog {
    NSData *cache = [NSData dataWithContentsOfFile:RYGBridgeMappingCachePath() options:0 error:nil];
    NSDictionary *catalog = cache.length ? RYGBridgeCatalogFromData(cache, NULL) : nil;
    if (catalog) return catalog;
    return [self ryg_bridgeLoadNameCatalog];
}

@end

static void RYGBridgeSwapInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

__attribute__((constructor(100))) static void RYGMobileConfigEnableCaptureByDefault(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if ([defaults objectForKey:@"ryg_metaconfig_enabled"] == nil) [defaults setBool:YES forKey:@"ryg_metaconfig_enabled"];
    }
}

__attribute__((constructor(65460))) static void RYGInstallMobileConfigBridge(void) {
    @autoreleasepool {
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class, @selector(ryg_nativeDataDirectory), @selector(ryg_bridgeNativeDataDirectory));
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class, @selector(ryg_importNameMappingData:error:), @selector(ryg_bridgeImportNameMappingData:error:));
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class, @selector(ryg_exportNameMappingData:), @selector(ryg_bridgeExportNameMappingData:));
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class, @selector(loadNameCatalog), @selector(ryg_bridgeLoadNameCatalog));
    }
}