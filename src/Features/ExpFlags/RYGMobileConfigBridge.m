#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface RYGMobileConfig (RYGBridgePrivate)
- (NSDictionary *)loadNameCatalog;
@end

static BOOL RYGBridgeDirectoryExists(NSString *path) {
    if (!path.length) return NO;
    BOOL directory = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && directory;
}

static NSString *RYGBridgeResolveDataDirectoryFromCandidate(NSString *candidate) {
    if (![candidate isKindOfClass:NSString.class] || !candidate.length) return nil;
    NSString *path = candidate.stringByResolvingSymlinksInPath.stringByStandardizingPath;
    if (![path.lastPathComponent.lowercaseString hasSuffix:@".data"]) return nil;
    return RYGBridgeDirectoryExists(path) ? path : nil;
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
    // Accept only its exact Documents/mobileconfig/*.data result. Selecting a
    // recently modified directory from another App Group/account can apply an
    // override to the wrong user, so there is deliberately no guessed fallback.
    NSString *candidate = [self ryg_bridgeNativeDataDirectory];
    NSString *resolved = RYGBridgeResolveDataDirectoryFromCandidate(candidate);
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
