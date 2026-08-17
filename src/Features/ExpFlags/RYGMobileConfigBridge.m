#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigViewController.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

@interface RYGMobileConfig (RYGBridgePrivate)
- (NSDictionary *)loadNameCatalog;
@end

static NSString *const kRYGMappingCacheFile = @"id_name_mapping.json";
static __thread BOOL gRYGEnteringMobileConfigBrowser;

static NSError *RYGBridgeError(NSString *message) {
    return [NSError errorWithDomain:@"com.ryukgram.mobileconfig.bridge"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey:message ?: @"MobileConfig bridge error"}];
}

static NSString *RYGBridgeSupportDirectory(void) {
    NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [root stringByAppendingPathComponent:@"RyukGram"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *RYGBridgeMappingCachePath(void) {
    return [RYGBridgeSupportDirectory() stringByAppendingPathComponent:kRYGMappingCacheFile];
}

static NSDictionary<NSNumber *, NSDictionary *> *RYGBridgeCatalogFromData(NSData *data, NSError **error) {
    if (!data.length) {
        if (error) *error = RYGBridgeError(@"The id_name_mapping.json file is empty.");
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSArray.class]) {
        if (error && !*error) *error = RYGBridgeError(@"id_name_mapping.json must be an array of colon-delimited strings.");
        return nil;
    }

    NSMutableDictionary<NSNumber *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];
    for (id raw in (NSArray *)json) {
        if (![raw isKindOfClass:NSString.class]) {
            if (error) *error = RYGBridgeError(@"id_name_mapping.json contains a non-string entry.");
            return nil;
        }
        NSArray<NSString *> *parts = [(NSString *)raw componentsSeparatedByString:@":"];
        if (parts.count < 2) {
            if (error) *error = RYGBridgeError(@"id_name_mapping.json contains an invalid config entry.");
            return nil;
        }
        unsigned long long configNumber = strtoull(parts[0].UTF8String, NULL, 10);
        if (!configNumber) {
            if (error) *error = RYGBridgeError(@"id_name_mapping.json contains an invalid config id.");
            return nil;
        }

        NSMutableDictionary<NSNumber *, NSString *> *params = [NSMutableDictionary dictionary];
        for (NSUInteger i = 2; i + 1 < parts.count; i += 2) {
            unsigned long long index = strtoull(parts[i].UTF8String, NULL, 10);
            NSString *name = parts[i + 1];
            if (name.length) params[@(index)] = name;
        }
        catalog[@(configNumber)] = @{
            @"name": parts[1] ?: @"",
            @"params": params.copy,
        };
    }
    return catalog.copy;
}

static NSData *RYGBridgeCanonicalMappingData(NSData *data, NSError **error) {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSArray.class]) return nil;
    return [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
}

static void RYGBridgeMergeCatalog(NSMutableDictionary *destination, NSDictionary<NSNumber *, NSDictionary *> *source) {
    [source enumerateKeysAndObjectsUsingBlock:^(NSNumber *configNumber, NSDictionary *info, BOOL *stop) {
        NSDictionary *old = [destination[configNumber] isKindOfClass:NSDictionary.class] ? destination[configNumber] : nil;
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        if ([old[@"params"] isKindOfClass:NSDictionary.class]) [params addEntriesFromDictionary:old[@"params"]];
        if ([info[@"params"] isKindOfClass:NSDictionary.class]) [params addEntriesFromDictionary:info[@"params"]];
        NSString *name = [info[@"name"] isKindOfClass:NSString.class] && [info[@"name"] length]
            ? info[@"name"] : (old[@"name"] ?: @"");
        destination[configNumber] = @{@"name":name ?: @"", @"params":params.copy};
    }];
}

static void RYGBridgeApplyCatalogToModels(RYGMobileConfig *mobileConfig, NSDictionary<NSNumber *, NSDictionary *> *catalog) {
    for (RYGMCConfig *config in mobileConfig.allConfigs) {
        NSDictionary *info = catalog[@(config.number)];
        if (![info isKindOfClass:NSDictionary.class]) continue;
        NSString *configName = info[@"name"];
        if ([configName isKindOfClass:NSString.class] && configName.length) config.name = configName;
        NSDictionary *params = info[@"params"];
        for (RYGMCParam *param in config.params) {
            NSString *name = params[@(param.paramIndex)];
            if ([name isKindOfClass:NSString.class] && name.length) param.name = name;
        }
    }
}

#pragma mark - Signed App Group discovery

typedef CFTypeRef (*RYGSecTaskCreateFromSelfFn)(CFAllocatorRef allocator);
typedef CFTypeRef (*RYGSecTaskCopyValueForEntitlementFn)(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error);

static NSArray<NSString *> *RYGSignedApplicationGroups(void) {
    RYGSecTaskCreateFromSelfFn createTask = (RYGSecTaskCreateFromSelfFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    RYGSecTaskCopyValueForEntitlementFn copyEntitlement = (RYGSecTaskCopyValueForEntitlementFn)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyEntitlement) return @[];

    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) return @[];
    CFTypeRef raw = copyEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL);
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    if (raw && CFGetTypeID(raw) == CFArrayGetTypeID()) {
        NSArray *values = (__bridge NSArray *)raw;
        for (id value in values) if ([value isKindOfClass:NSString.class] && [value length]) [groups addObject:value];
    }
    if (raw) CFRelease(raw);
    CFRelease(task);
    return groups.copy;
}

static NSInteger RYGMobileConfigDataDirectoryScore(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) return NSIntegerMin;
    NSInteger score = 0;
    NSString *name = path.lastPathComponent.lowercaseString;
    if ([name hasSuffix:@".data"]) score += 20;
    if (![name isEqualToString:@"sessionless.data"]) score += 15;
    if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"id_name_mapping.json"]]) score += 100;
    if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"mc_overrides.json"]]) score += 80;
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
    NSDate *date = attributes[NSFileModificationDate];
    if (date) score += MIN(30, (NSInteger)MAX(0, 30.0 + [date timeIntervalSinceNow] / 86400.0));
    return score;
}

static NSString *RYGFallbackNativeMobileConfigDirectory(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *best = nil;
    NSInteger bestScore = NSIntegerMin;

    for (NSString *group in RYGSignedApplicationGroups()) {
        NSURL *container = [fm containerURLForSecurityApplicationGroupIdentifier:group];
        if (!container.path.length) continue;
        NSString *mobileConfig = [[container.path stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"mobileconfig"];
        NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:mobileConfig error:nil];
        for (NSString *child in children) {
            NSString *candidate = [mobileConfig stringByAppendingPathComponent:child];
            NSInteger score = RYGMobileConfigDataDirectoryScore(candidate);
            if (score > bestScore) {
                bestScore = score;
                best = candidate;
            }
        }
    }
    return bestScore == NSIntegerMin ? nil : best;
}

@implementation RYGMobileConfig (RYGMobileConfigBridge)

- (NSString *)ryg_bridgeNativeDataDirectory {
    NSString *native = [self ryg_bridgeNativeDataDirectory];
    if (native.length) return native;
    return RYGFallbackNativeMobileConfigDirectory();
}

- (BOOL)ryg_bridgeImportNameMappingData:(NSData *)data error:(NSError **)error {
    NSError *validationError = nil;
    NSDictionary *catalog = RYGBridgeCatalogFromData(data, &validationError);
    if (!catalog) {
        if (error) *error = validationError;
        return NO;
    }

    NSError *serializationError = nil;
    NSData *canonical = RYGBridgeCanonicalMappingData(data, &serializationError);
    if (!canonical) {
        if (error) *error = serializationError;
        return NO;
    }

    NSString *cachePath = RYGBridgeMappingCachePath();
    if (![canonical writeToFile:cachePath options:NSDataWritingAtomic error:error]) return NO;

    // The imported mapping is useful immediately. Do not invalidate and rescan
    // the private C++ MobileConfig table simply to rename rows.
    [self prepare];
    RYGBridgeApplyCatalogToModels(self, catalog);

    // Mirror into Instagram's current native *.data directory when one is
    // available. Failure to discover that directory no longer rejects a valid
    // mapping import; the signed-App-Group fallback above will find it later.
    NSString *nativePath = [self ryg_nativeNameMappingPath];
    if (nativePath.length) [canonical writeToFile:nativePath options:NSDataWritingAtomic error:nil];
    return YES;
}

- (NSData *)ryg_bridgeExportNameMappingData:(NSError **)error {
    NSData *cached = [NSData dataWithContentsOfFile:RYGBridgeMappingCachePath() options:0 error:nil];
    if (cached.length) return cached;
    return [self ryg_bridgeExportNameMappingData:error];
}

- (NSDictionary *)ryg_bridgeLoadNameCatalog {
    NSDictionary *native = [self ryg_bridgeLoadNameCatalog];
    NSMutableDictionary *merged = [native isKindOfClass:NSDictionary.class] ? [native mutableCopy] : [NSMutableDictionary dictionary];
    NSData *cached = [NSData dataWithContentsOfFile:RYGBridgeMappingCachePath() options:0 error:nil];
    NSDictionary *catalog = cached.length ? RYGBridgeCatalogFromData(cached, NULL) : nil;
    if (catalog.count) RYGBridgeMergeCatalog(merged, catalog);
    return merged.copy;
}

- (void)ryg_bridgeReloadFromRuntime {
    if (gRYGEnteringMobileConfigBrowser) {
        // The tools page has already prepared a stable snapshot. The former
        // browser viewDidLoad invalidated it and immediately re-read private C++
        // globals during a navigation transition, which is unnecessary and was
        // the remaining entry-crash path.
        [self prepare];
        return;
    }
    [self ryg_bridgeReloadFromRuntime];
}

@end

@implementation RYGMobileConfigViewController (RYGMobileConfigBridge)

- (void)ryg_bridgeViewDidLoad {
    BOOL previous = gRYGEnteringMobileConfigBrowser;
    gRYGEnteringMobileConfigBrowser = YES;
    [self ryg_bridgeViewDidLoad];
    gRYGEnteringMobileConfigBrowser = previous;
}

- (void)ryg_bridgeRefreshRuntime {
    [[RYGMobileConfig shared] prepare];
    if ([self respondsToSelector:NSSelectorFromString(@"reload")]) {
        ((void (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"reload"));
    }
    if ([self isKindOfClass:UITableViewController.class]) {
        [((UITableViewController *)self).tableView.refreshControl endRefreshing];
    }
}

@end

static void RYGBridgeSwapInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

// Must precede the Logos MobileConfig %ctor: the current Developer menu exposes
// MobileConfig directly, so a clean install needs its context-manager capture
// hooks without depending on a removed legacy settings switch. An explicit user
// value is always respected.
__attribute__((constructor(100))) static void RYGMobileConfigEnableCaptureByDefault(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if ([defaults objectForKey:@"ryg_metaconfig_enabled"] == nil) {
            [defaults setBool:YES forKey:@"ryg_metaconfig_enabled"];
        }
    }
}

__attribute__((constructor(65460))) static void RYGInstallMobileConfigBridge(void) {
    @autoreleasepool {
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class,
                                    @selector(ryg_nativeDataDirectory),
                                    @selector(ryg_bridgeNativeDataDirectory));
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class,
                                    @selector(ryg_importNameMappingData:error:),
                                    @selector(ryg_bridgeImportNameMappingData:error:));
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class,
                                    @selector(ryg_exportNameMappingData:),
                                    @selector(ryg_bridgeExportNameMappingData:));
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class,
                                    @selector(loadNameCatalog),
                                    @selector(ryg_bridgeLoadNameCatalog));
        RYGBridgeSwapInstanceMethod(RYGMobileConfig.class,
                                    @selector(reloadFromRuntime),
                                    @selector(ryg_bridgeReloadFromRuntime));

        RYGBridgeSwapInstanceMethod(RYGMobileConfigViewController.class,
                                    @selector(viewDidLoad),
                                    @selector(ryg_bridgeViewDidLoad));
        RYGBridgeSwapInstanceMethod(RYGMobileConfigViewController.class,
                                    NSSelectorFromString(@"refreshRuntime"),
                                    @selector(ryg_bridgeRefreshRuntime));
    }
}
