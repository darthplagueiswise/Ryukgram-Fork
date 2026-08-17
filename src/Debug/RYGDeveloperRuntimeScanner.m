#import "RYGDeveloperRuntimeScanner.h"
#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>
#include <string.h>

typedef NS_ENUM(NSInteger, RYGDevVerifiedSurface) {
    RYGDevVerifiedSurfaceGeneric = 0,
    RYGDevVerifiedSurfaceWordmark,
    RYGDevVerifiedSurfacePrism,
    RYGDevVerifiedSurfaceLiquidGlass,
    RYGDevVerifiedSurfaceThrowback,
};

static NSString *RYGDevScanNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) [result appendFormat:@"%C", c];
    }
    return result;
}

static BOOL RYGDevKeywordSetContains(NSArray<NSString *> *keywords, NSString *needle) {
    NSString *wanted = RYGDevScanNormalize(needle);
    for (NSString *keyword in keywords) {
        NSString *normalized = RYGDevScanNormalize(keyword);
        if (normalized.length && [normalized containsString:wanted]) return YES;
    }
    return NO;
}

static RYGDevVerifiedSurface RYGDevSurfaceForKeywords(NSArray<NSString *> *keywords) {
    if (RYGDevKeywordSetContains(keywords, @"wordmark")) return RYGDevVerifiedSurfaceWordmark;
    if (RYGDevKeywordSetContains(keywords, @"prism")) return RYGDevVerifiedSurfacePrism;
    if (RYGDevKeywordSetContains(keywords, @"throwback")) return RYGDevVerifiedSurfaceThrowback;
    if (RYGDevKeywordSetContains(keywords, @"liquidglass")
        || RYGDevKeywordSetContains(keywords, @"igdsglass")
        || RYGDevKeywordSetContains(keywords, @"glassbutton")
        || RYGDevKeywordSetContains(keywords, @"lucent")) return RYGDevVerifiedSurfaceLiquidGlass;
    return RYGDevVerifiedSurfaceGeneric;
}

static BOOL RYGDevMatchesKeywords(RYGRuntimeBoolMethod *row, NSArray<NSString *> *needles) {
    if (!needles.count) return YES;
    NSString *hay = RYGDevScanNormalize([NSString stringWithFormat:@"%@ %@ %@",
                                         row.className ?: @"",
                                         row.selectorName ?: @"",
                                         row.imagePath.lastPathComponent ?: @""]);
    for (NSString *needle in needles) {
        NSString *normalized = RYGDevScanNormalize(needle);
        if (normalized.length && [hay containsString:normalized]) return YES;
    }
    return NO;
}

static Class RYGDevResolveClass(NSString *className) {
    if (!className.length) return Nil;
    // NSStringFromClass() returns module-qualified names for Swift classes on
    // current runtimes. NSClassFromString resolves that form; objc_lookUpClass
    // remains the fallback for raw Objective-C/mangled runtime names.
    Class cls = NSClassFromString(className);
    if (!cls) cls = objc_lookUpClass(className.UTF8String);
    return cls;
}

// The two supplied binaries each contain a distinct Objective-C protocol object
// named IGDSLauncherConfigProtocol. Comparing Protocol pointers is therefore the
// wrong ownership test. Compare protocol names on the class hierarchy instead.
static BOOL RYGDevClassConformsToNamedProtocol(Class cls, const char *wantedName) {
    if (!cls || !wantedName || !*wantedName) return NO;
    for (Class cursor = cls; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int protocolCount = 0;
        Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cursor, &protocolCount);
        BOOL found = NO;
        for (unsigned int index = 0; index < protocolCount; index++) {
            Protocol *protocol = protocols[index];
            const char *name = protocol ? protocol_getName(protocol) : NULL;
            if (name && strcmp(name, wantedName) == 0) {
                found = YES;
                break;
            }
        }
        if (protocols) free(protocols);
        if (found) return YES;
    }
    return NO;
}

static BOOL RYGDevRowOwnedByLauncherProtocol(RYGRuntimeBoolMethod *row) {
    Class cls = RYGDevResolveClass(row.className);
    return RYGDevClassConformsToNamedProtocol(cls, "IGDSLauncherConfigProtocol");
}

static BOOL RYGDevClassNameHasSuffix(NSString *className, NSString *suffix) {
    return className.length && suffix.length && [className hasSuffix:suffix];
}

static BOOL RYGDevMatchesVerifiedSurface(RYGRuntimeBoolMethod *row, RYGDevVerifiedSurface surface) {
    NSString *selector = row.selectorName.lowercaseString ?: @"";
    NSString *className = row.className ?: @"";
    BOOL launcher = RYGDevRowOwnedByLauncherProtocol(row);

    switch (surface) {
        case RYGDevVerifiedSurfaceWordmark:
            // Verified in both supplied Mach-O files as B16@0:8 members of
            // IGDSLauncherConfigProtocol, implemented by IGDSLauncherConfig and
            // _TtC11BSLDSConfig11BSLDSConfig.
            return launcher && [selector hasPrefix:@"isigwordmark"];

        case RYGDevVerifiedSurfacePrism:
            return launcher && [selector containsString:@"prism"];

        case RYGDevVerifiedSurfaceLiquidGlass: {
            if (launcher && ([selector containsString:@"liquidglass"]
                             || [selector isEqualToString:@"canuseinternalliquidglassdebugger"])) return YES;
            // These exact helpers and BOOL signatures are present in the supplied
            // FBSharedFramework. They are not launcher-protocol implementations.
            return RYGDevClassNameHasSuffix(className, @"IGLiquidGlassNavigationExperimentHelper")
                || RYGDevClassNameHasSuffix(className, @"IGLiquidGlassSwizzleToggle");
        }

        case RYGDevVerifiedSurfaceThrowback:
            return RYGDevClassNameHasSuffix(className, @"IGThrowbackChromeExperimentHelper");

        case RYGDevVerifiedSurfaceGeneric:
            return YES;
    }
    return NO;
}

@implementation RYGDeveloperRuntimeScanner

+ (NSArray<NSString *> *)primaryDeveloperImagePaths {
    NSArray<NSString *> *all = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    if (main.length && [all containsObject:main]) [selected addObject:main];
    for (NSString *path in all) {
        if ([path.lastPathComponent rangeOfString:@"FBSharedFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [selected addObject:path];
            break;
        }
    }
    return selected.array;
}

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePaths:(NSArray<NSString *> *)imagePaths
                                                    keywords:(NSArray<NSString *> *)keywords {
    if (!imagePaths.count) return @[];

    RYGDevVerifiedSurface surface = RYGDevSurfaceForKeywords(keywords);
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
    for (NSString *imagePath in imagePaths) {
        NSArray<RYGRuntimeBoolMethod *> *imageRows =
            [RYGRuntimeBrowserEngine boolMethodsForImagePath:imagePath scope:RYGRuntimeBrowserScopeAll];
        for (RYGRuntimeBoolMethod *row in imageRows) {
            BOOL matches = surface == RYGDevVerifiedSurfaceGeneric
                ? RYGDevMatchesKeywords(row, keywords)
                : RYGDevMatchesVerifiedSurface(row, surface);
            if (!matches) continue;
            NSString *key = row.overrideKey;
            if (!key.length || [dedupe containsObject:key]) continue;
            [dedupe addObject:key];
            [rows addObject:row];
        }
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult imageOrder = [left.imagePath.lastPathComponent localizedCaseInsensitiveCompare:right.imagePath.lastPathComponent];
        if (imageOrder != NSOrderedSame) return imageOrder;
        NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className];
        return classOrder == NSOrderedSame
            ? [left.selectorName localizedCaseInsensitiveCompare:right.selectorName]
            : classOrder;
    }];
    return rows.copy;
}

@end
