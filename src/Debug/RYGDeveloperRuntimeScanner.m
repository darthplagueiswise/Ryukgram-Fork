#import "RYGDeveloperRuntimeScanner.h"
#import "RYGRuntimeBrowserEngine.h"

static NSString *RYGDevScanNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        if ((character >= 'a' && character <= 'z') ||
            (character >= '0' && character <= '9')) {
            [result appendFormat:@"%C", character];
        }
    }
    return result;
}

static NSString *RYGDevRuntimeHaystack(RYGRuntimeBoolMethod *row) {
    return RYGDevScanNormalize([NSString stringWithFormat:@"%@ %@ %@",
        row.className ?: @"",
        row.selectorName ?: @"",
        row.imagePath.lastPathComponent ?: @""]);
}

static BOOL RYGDevHaystackContainsAny(NSString *haystack, NSArray<NSString *> *needles) {
    if (!haystack.length) return NO;
    for (NSString *needle in needles) {
        NSString *normalized = RYGDevScanNormalize(needle);
        if (normalized.length && [haystack containsString:normalized]) return YES;
    }
    return NO;
}

static BOOL RYGDevMatchesKeywords(RYGRuntimeBoolMethod *row, NSArray<NSString *> *needles) {
    if (!needles.count) return YES;
    return RYGDevHaystackContainsAny(RYGDevRuntimeHaystack(row), needles);
}

static BOOL RYGDevMatchesSurface(RYGRuntimeBoolMethod *row, RYGDeveloperRuntimeSurface surface) {
    NSString *haystack = RYGDevRuntimeHaystack(row);
    NSString *selector = RYGDevScanNormalize(row.selectorName);
    NSString *className = RYGDevScanNormalize(row.className);

    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism:
            // Current supplied Instagram / FBShared binaries expose the Prism
            // launcher/design BOOL family with "prism" in the selector, and
            // additionally contain the BDSL/IGDS design-system naming family.
            return RYGDevHaystackContainsAny(haystack, @[@"prism", @"bdslprism"]);

        case RYGDeveloperRuntimeSurfaceLiquidGlass:
            // Throwback chrome belongs here intentionally: it is the alternate
            // blue/header Liquid Glass experiment, not a separate Developer row.
            return RYGDevHaystackContainsAny(haystack, @[
                @"liquidglass", @"glassbackground", @"glasseffect",
                @"glassrendering", @"glassbutton", @"lucent", @"throwback"
            ]) || [className containsString:@"igliquidglass"]
               || [className containsString:@"igthrowbackchrome"];

        case RYGDeveloperRuntimeSurfaceStories:
            return RYGDevHaystackContainsAny(haystack, @[
                @"storytray", @"storiestray", @"portablestorytray",
                @"storygrid", @"storiesgrid", @"freshstoriestray"
            ]);

        case RYGDeveloperRuntimeSurfaceInternalOnly:
            return RYGDevHaystackContainsAny(haystack, @[
                @"igonly", @"internalonly", @"internalsettings",
                @"internalmenu", @"iginternalonly"
            ]);

        case RYGDeveloperRuntimeSurfaceBugReport:
            return RYGDevHaystackContainsAny(haystack, @[
                @"bugreport", @"rageshake", @"dogfoodingassistant",
                @"loggedoutinternalsettings", @"shaketoreport", @"sandboxcreatoragent"
            ]) || ([className containsString:@"bugreport"] &&
                    RYGDevHaystackContainsAny(selector, @[@"show", @"enable", @"allow", @"internal", @"sandbox"]));

        case RYGDeveloperRuntimeSurfaceSettingsRows: {
            if ([selector isEqualToString:@"showinsettings"] ||
                [selector containsString:@"settingsrow"] ||
                [selector containsString:@"settingrow"]) return YES;
            BOOL settingsFamily = [haystack containsString:@"settings"] || [haystack containsString:@"setting"];
            BOOL visibility = RYGDevHaystackContainsAny(selector, @[
                @"show", @"hide", @"visible", @"eligible", @"available",
                @"enabled", @"disabled", @"entrypoint", @"navigation", @"cansee"
            ]);
            return settingsFamily && visibility;
        }

        case RYGDeveloperRuntimeSurfaceDirectDogfood:
            return RYGDevHaystackContainsAny(haystack, @[
                @"dogfood", @"dogfooding", @"dogfooder", @"fishfood"
            ]);
    }
    return NO;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGDevSortedDedupedRows(NSArray<RYGRuntimeBoolMethod *> *source) {
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (RYGRuntimeBoolMethod *row in source) {
        NSString *key = row.overrideKey;
        if (!key.length || [seen containsObject:key]) continue;
        [seen addObject:key];
        [rows addObject:row];
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult image = [left.imagePath.lastPathComponent localizedCaseInsensitiveCompare:right.imagePath.lastPathComponent];
        if (image != NSOrderedSame) return image;
        NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className];
        if (classOrder != NSOrderedSame) return classOrder;
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return rows.copy;
}

@implementation RYGDeveloperRuntimeScanner

+ (NSArray<NSString *> *)primaryDeveloperImagePaths {
    NSArray<NSString *> *all = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];

    for (NSString *path in all) {
        NSString *standard = path.stringByStandardizingPath;
        if (main.length && ([standard isEqualToString:main] ||
            [standard.stringByResolvingSymlinksInPath isEqualToString:main.stringByResolvingSymlinksInPath])) {
            [selected addObject:path];
            break;
        }
    }
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
    NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
    for (NSString *imagePath in imagePaths) {
        for (RYGRuntimeBoolMethod *row in [RYGRuntimeBrowserEngine boolMethodsForImagePath:imagePath
                                                                                     scope:RYGRuntimeBrowserScopeAll]) {
            if (RYGDevMatchesKeywords(row, keywords)) [matches addObject:row];
        }
    }
    return RYGDevSortedDedupedRows(matches);
}

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForSurface:(RYGDeveloperRuntimeSurface)surface {
    NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
    for (NSString *imagePath in [self primaryDeveloperImagePaths]) {
        NSArray<RYGRuntimeBoolMethod *> *imageRows =
            [RYGRuntimeBrowserEngine boolMethodsForImagePath:imagePath scope:RYGRuntimeBrowserScopeAll];
        for (RYGRuntimeBoolMethod *row in imageRows) {
            if (RYGDevMatchesSurface(row, surface)) [matches addObject:row];
        }
    }
    return RYGDevSortedDedupedRows(matches);
}

+ (NSString *)titleForSurface:(RYGDeveloperRuntimeSurface)surface {
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism: return @"Prism UI";
        case RYGDeveloperRuntimeSurfaceLiquidGlass: return @"Liquid Glass";
        case RYGDeveloperRuntimeSurfaceStories: return @"Stories · Tray & Grid";
        case RYGDeveloperRuntimeSurfaceInternalOnly: return @"IG-only / Internal-only";
        case RYGDeveloperRuntimeSurfaceBugReport: return @"Bug Report";
        case RYGDeveloperRuntimeSurfaceSettingsRows: return @"Hidden Settings Rows";
        case RYGDeveloperRuntimeSurfaceDirectDogfood: return @"Direct Dogfooding";
    }
    return @"Developer";
}

@end
