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

    // getOverridesTablePath can also resolve to a file inside the active .data
    // directory. Walk upward until the first *.data container is found.
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

@implementation RYGMobileConfig (RYGDataDirectoryCompatibility)

- (NSString *)ryg_dataDirectory_nativeDataDirectory {
    // After method exchange this invokes the complete bridge chain first:
    // getOverridesTablePath plus the signed-App-Group fallback. We then enforce
    // the contract required by Instagram persistence: the result must be the
    // actual Documents/mobileconfig/*.data directory, never its parent.
    NSString *candidate = [self ryg_dataDirectory_nativeDataDirectory];
    return RYGResolveActualDataDirectory(candidate);
}

@end

__attribute__((constructor(65490))) static void RYGInstallMobileConfigDataDirectoryCompatibility(void) {
    Class cls = RYGMobileConfig.class;
    Method original = class_getInstanceMethod(cls, @selector(ryg_nativeDataDirectory));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_dataDirectory_nativeDataDirectory));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
