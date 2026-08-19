#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@interface RYGMobileConfig (RYGBridgePrivate)
- (NSDictionary *)loadNameCatalog;
@end

static BOOL RYGBridgeDirectoryExists(NSString *path) {
    if (!path.length) return NO;
    BOOL directory = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && directory;
}

static NSInteger RYGBridgeDataDirectoryScore(NSString *path) {
    if (!RYGBridgeDirectoryExists(path)) return NSIntegerMin;
    NSString *name = path.lastPathComponent.lowercaseString;
    if (![name hasSuffix:@".data"]) return NSIntegerMin;

    NSInteger score = 100;
    if (![name isEqualToString:@"sessionless.data"]) score += 40;
    if ([NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingPathComponent:@"mc_overrides.json"]]) score += 30;
    if ([NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingPathComponent:@"id_name_mapping.json"]]) score += 20;

    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    if (modified && -modified.timeIntervalSinceNow < 86400.0) score += 10;
    return score;
}

static NSString *RYGBridgeResolveDataDirectoryFromCandidate(NSString *candidate) {
    if (![candidate isKindOfClass:NSString.class] || !candidate.length) return nil;
    NSString *path = candidate.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    if (!RYGBridgeDirectoryExists(path)) return nil;
    if ([path.lastPathComponent.lowercaseString hasSuffix:@".data"]) return path;

    NSString *best = nil;
    NSInteger bestScore = NSIntegerMin;
    for (NSString *child in [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil]) {
        NSString *childPath = [path stringByAppendingPathComponent:child];
        NSInteger score = RYGBridgeDataDirectoryScore(childPath);
        if (score > bestScore) {
            bestScore = score;
            best = childPath;
        }
    }
    if (best.length) return best;

    NSString *cursor = path;
    while (cursor.length > 1) {
        if ([cursor.lastPathComponent.lowercaseString hasSuffix:@".data"] && RYGBridgeDirectoryExists(cursor)) return cursor;
        NSString *parent = cursor.stringByDeletingLastPathComponent;
        if ([parent isEqualToString:cursor]) break;
        cursor = parent;
    }
    return nil;
}

typedef CFTypeRef (*RYGSecTaskCreateFromSelfFn)(CFAllocatorRef allocator);
typedef CFTypeRef (*RYGSecTaskCopyValueForEntitlementFn)(CFTypeRef task,
                                                         CFStringRef entitlement,
                                                         CFErrorRef *error);

static NSArray<NSString *> *RYGBridgeSignedApplicationGroups(void) {
    RYGSecTaskCreateFromSelfFn createTask = (RYGSecTaskCreateFromSelfFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    RYGSecTaskCopyValueForEntitlementFn copyValue = (RYGSecTaskCopyValueForEntitlementFn)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyValue) return @[];

    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) return @[];
    CFTypeRef raw = copyValue(task, CFSTR("com.apple.security.application-groups"), NULL);
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    if (raw && CFGetTypeID(raw) == CFArrayGetTypeID()) {
        for (id value in (__bridge NSArray *)raw) {
            if ([value isKindOfClass:NSString.class] && [value length]) [groups addObject:value];
        }
    }
    if (raw) CFRelease(raw);
    CFRelease(task);
    return groups.copy;
}

static NSString *RYGBridgeResolveSignedAppGroupDataDirectory(void) {
    NSString *best = nil;
    NSInteger bestScore = NSIntegerMin;
    NSFileManager *fm = NSFileManager.defaultManager;

    for (NSString *group in RYGBridgeSignedApplicationGroups()) {
        NSURL *container = [fm containerURLForSecurityApplicationGroupIdentifier:group];
        if (!container.path.length) continue;
        NSString *mobileConfig = [[container.path stringByAppendingPathComponent:@"Documents"]
            stringByAppendingPathComponent:@"mobileconfig"];
        if (!RYGBridgeDirectoryExists(mobileConfig)) continue;

        for (NSString *child in [fm contentsOfDirectoryAtPath:mobileConfig error:nil]) {
            NSString *candidate = [mobileConfig stringByAppendingPathComponent:child];
            NSInteger score = RYGBridgeDataDirectoryScore(candidate);
            if (score > bestScore) {
                bestScore = score;
                best = candidate;
            }
        }
    }
    return best;
}

static void RYGBridgeMirrorMappingCache(NSString *dataDirectory) {
    if (!dataDirectory.length) return;
    NSData *mapping = RYGMCLoadCachedNameMappingData();
    if (!mapping.length) return;

    NSString *destination = [dataDirectory stringByAppendingPathComponent:@"id_name_mapping.json"];
    NSData *existing = [NSData dataWithContentsOfFile:destination options:0 error:nil];
    if (![existing isEqualToData:mapping]) {
        [mapping writeToFile:destination options:NSDataWritingAtomic error:nil];
    }
}

@implementation RYGMobileConfig (RYGMobileConfigBridge)

- (NSString *)ryg_bridgeNativeDataDirectory {
    // After exchange this invokes the original JSONIO implementation first.
    // Normalize that result to the actual Documents/mobileconfig/*.data folder;
    // only if Instagram has not exposed one do we inspect the app groups that
    // are actually present in this signed process.
    NSString *candidate = [self ryg_bridgeNativeDataDirectory];
    NSString *resolved = RYGBridgeResolveDataDirectoryFromCandidate(candidate);
    if (!resolved.length) resolved = RYGBridgeResolveSignedAppGroupDataDirectory();
    if (resolved.length) RYGBridgeMirrorMappingCache(resolved);
    return resolved;
}

- (NSDictionary *)ryg_bridgeLoadNameCatalog {
    // An imported mapping is authoritative for names. It intentionally can
    // contain configs that do not exist in the current iOS parameter table;
    // RYGMobileConfig.prepare builds the union and marks those rows mapping-only.
    NSDictionary *cached = RYGMCLoadCachedNameMappingCatalog(NULL);
    if (cached) return cached;
    return [self ryg_bridgeLoadNameCatalog];
}

@end

static void RYGBridgeExchange(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

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
        Class cls = RYGMobileConfig.class;
        RYGBridgeExchange(cls,
                          @selector(ryg_nativeDataDirectory),
                          @selector(ryg_bridgeNativeDataDirectory));
        RYGBridgeExchange(cls,
                          @selector(loadNameCatalog),
                          @selector(ryg_bridgeLoadNameCatalog));
    }
}
