#import "RYGDeveloperRuntimeScanner.h"
#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>

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

static BOOL RYGDevClassNameContains(NSString *className, NSString *needle) {
    return className.length && needle.length
        && [className rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL RYGDevMatchesVerifiedSurface(RYGRuntimeBoolMethod *row, RYGDevVerifiedSurface surface) {
    NSString *selector = row.selectorName.lowercaseString ?: @"";
    NSString *className = row.className ?: @"";

    switch (surface) {
        case RYGDevVerifiedSurfaceWordmark:
            // Verified directly in the supplied FBSharedFramework with radare2
            // and Capstone: IGDSLauncherConfig implements all four no-argument
            // BOOL getters isIGWordmark1a/1aAlt/1b/1bAltEnabled.
            return [selector hasPrefix:@"isigwordmark"];

        case RYGDevVerifiedSurfacePrism:
            // Do not require runtime protocol metadata. The current binary puts
            // dozens of Prism BOOL getters directly on IGDSLauncherConfig and
            // other IGDS classes; the selector itself is the stable surface key.
            return [selector containsString:@"prism"];

        case RYGDevVerifiedSurfaceLiquidGlass:
            if ([selector containsString:@"liquidglass"]
                || [selector containsString:@"glassrendering"]
                || [selector isEqualToString:@"canuseinternalliquidglassdebugger"])
                return YES;
            return RYGDevClassNameContains(className, @"IGLiquidGlassNavigationExperimentHelper")
                || RYGDevClassNameContains(className, @"IGLiquidGlassSwizzleToggle");

        case RYGDevVerifiedSurfaceThrowback:
            return RYGDevClassNameContains(className, @"IGThrowbackChromeExperimentHelper")
                || [selector containsString:@"throwback"];

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
