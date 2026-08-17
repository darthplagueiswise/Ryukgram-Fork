#import "RYGMobileConfigJSONIO.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSInteger RYGDataDirectoryScore(NSString *path) {
    if (!path.length || ![path.lastPathComponent.lowercaseString hasSuffix:@".data"]) return NSIntegerMin;
    BOOL isDir = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) return NSIntegerMin;
    NSInteger score = 20;
    NSString *name = path.lastPathComponent.lowercaseString;
    if (![name isEqualToString:@"sessionless.data"]) score += 30;
    if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"id_name_mapping.json"]]) score += 120;
    if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"mc_overrides.json"]]) score += 100;
    NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    if (modified) {
        NSTimeInterval age = -modified.timeIntervalSinceNow;
        if (age < 3600.0) score += 25;
        else if (age < 86400.0) score += 15;
        else if (age < 604800.0) score += 5;
    }
    return score;
}

static NSString *RYGResolveActualDataDirectory(NSString *candidate) {
    if (![candidate isKindOfClass:NSString.class] || !candidate.length) return nil;
    NSString *path = candidate.stringByStandardizingPath;
    BOOL isDir = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) return nil;

    if ([path.lastPathComponent.lowercaseString hasSuffix:@".data"]) return path;

    NSString *best = nil;
    NSInteger bestScore = NSIntegerMin;
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:path error:nil];
    for (NSString *child in children) {
        NSString *childPath = [path stringByAppendingPathComponent:child];
        NSInteger score = RYGDataDirectoryScore(childPath);
        if (score > bestScore) { bestScore = score; best = childPath; }
    }
    if (best.length) return best;

    NSString *cursor = path;
    while (cursor.length > 1) {
        if ([cursor.lastPathComponent.lowercaseString hasSuffix:@".data"] &&
            [fm fileExistsAtPath:cursor isDirectory:&isDir] && isDir) return cursor;
        NSString *parent = cursor.stringByDeletingLastPathComponent;
        if ([parent isEqualToString:cursor]) break;
        cursor = parent;
    }
    return nil;
}

static BOOL RYGWriteIfChanged(NSData *data, NSString *path) {
    if (!data.length || !path.length) return NO;
    NSData *existing = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if ([existing isEqualToData:data]) return YES;
    return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static void RYGMirrorCachedArtifacts(RYGMobileConfig *mc, NSString *dataDirectory) {
    if (!mc || !dataDirectory.length) return;
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *cacheRoot = [support stringByAppendingPathComponent:@"RyukGram"];
    NSData *mapping = [NSData dataWithContentsOfFile:[cacheRoot stringByAppendingPathComponent:@"id_name_mapping.json"] options:0 error:nil];
    if (mapping.length) RYGWriteIfChanged(mapping, [dataDirectory stringByAppendingPathComponent:@"id_name_mapping.json"]);

    if (mc.overrideCount) {
        NSError *error = nil;
        NSData *overrides = [mc ryg_exportOverridesData:&error];
        if (overrides.length) RYGWriteIfChanged(overrides, [dataDirectory stringByAppendingPathComponent:@"mc_overrides.json"]);
    }
}

@implementation RYGMobileConfig (RYGDataDirectoryCompatibility)

- (NSString *)ryg_dataDirectory_nativeDataDirectory {
    // After method exchange this invokes the complete bridge chain first:
    // getOverridesTablePath plus the signed-App-Group fallback. We then enforce
    // the contract required by Instagram persistence: the result must be the
    // actual Documents/mobileconfig/*.data directory, never its parent.
    NSString *candidate = [self ryg_dataDirectory_nativeDataDirectory];
    NSString *dataDirectory = RYGResolveActualDataDirectory(candidate);
    if (dataDirectory.length) RYGMirrorCachedArtifacts(self, dataDirectory);
    return dataDirectory;
}

@end

__attribute__((constructor(65490))) static void RYGInstallMobileConfigDataDirectoryCompatibility(void) {
    Class cls = RYGMobileConfig.class;
    Method original = class_getInstanceMethod(cls, @selector(ryg_nativeDataDirectory));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_dataDirectory_nativeDataDirectory));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
