#import "RYGDeveloperRuntimeScanner.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeClassBrowser.h"

static NSString *RYGDevScanNormalize(NSString *value) {
    if (!value.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:value.length];
    NSString *lower = value.lowercaseString;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        if ((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')) [result appendFormat:@"%C", character];
    }
    return result;
}
static BOOL RYGDevContainsAny(NSString *haystack, NSArray<NSString *> *needles) {
    NSString *normalizedHaystack = RYGDevScanNormalize(haystack);
    if (!normalizedHaystack.length) return NO;
    for (NSString *needle in needles) { NSString *normalized = RYGDevScanNormalize(needle); if (normalized.length && [normalizedHaystack containsString:normalized]) return YES; }
    return NO;
}
static BOOL RYGDevMatchesSurfaceText(NSString *className, NSString *selector, RYGDeveloperRuntimeSurface surface) {
    NSString *combined = [NSString stringWithFormat:@"%@ %@", className ?: @"", selector ?: @""];
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism:
            return RYGDevContainsAny(combined, @[@"prism", @"igdsprism", @"bdslprism"]);
        case RYGDeveloperRuntimeSurfaceLiquidGlass:
            return RYGDevContainsAny(combined, @[@"liquidglass", @"glasseffect", @"glassrendering", @"glassbutton", @"throwbackchrome"]);
        case RYGDeveloperRuntimeSurfaceStories:
            return RYGDevContainsAny(combined, @[@"storytray", @"storiestray", @"portablestorytray", @"storygrid", @"storiesgrid"]);
        case RYGDeveloperRuntimeSurfaceInternalOnly:
            return RYGDevContainsAny(combined, @[@"igonly", @"internalonly", @"internalsettings", @"internalmenu"]);
        case RYGDeveloperRuntimeSurfaceBugReport:
            return RYGDevContainsAny(combined, @[@"bugreport", @"rageshake", @"dogfoodingassistant", @"loggedout", @"sandbox"]);
        case RYGDeveloperRuntimeSurfaceSettingsRows:
            return RYGDevContainsAny(combined, @[@"settingsrow", @"settingrow", @"showinsettings", @"hiddensettings", @"settingsvisibility"]);
        case RYGDeveloperRuntimeSurfaceDirectDogfood:
            return RYGDevContainsAny(combined, @[@"dogfood", @"dogfooding", @"dogfooder", @"fishfood"]);
    }
    return NO;
}
static NSArray<RYGRuntimeBoolMethod *> *RYGDevSortedDedupedRows(NSArray<RYGRuntimeBoolMethod *> *source) {
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array]; NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (RYGRuntimeBoolMethod *row in source) { NSString *key = row.overrideKey; if (!key.length || [seen containsObject:key]) continue; [seen addObject:key]; [rows addObject:row]; }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) { NSComparisonResult image = [left.imagePath.lastPathComponent localizedCaseInsensitiveCompare:right.imagePath.lastPathComponent]; if (image != NSOrderedSame) return image; NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className]; return classOrder != NSOrderedSame ? classOrder : [left.selectorName localizedCaseInsensitiveCompare:right.selectorName]; }];
    return rows.copy;
}

@implementation RYGDeveloperRuntimeScanner
+ (NSArray<NSString *> *)primaryDeveloperImagePaths {
    NSArray<NSString *> *all = [RYGRuntimeBrowserEngine runtimeImagePaths]; NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath; NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    for (NSString *path in all) { NSString *standard = path.stringByStandardizingPath; if (main.length && ([standard isEqualToString:main] || [standard.stringByResolvingSymlinksInPath isEqualToString:main.stringByResolvingSymlinksInPath])) { [selected addObject:path]; break; } }
    for (NSString *path in all) if ([path.lastPathComponent rangeOfString:@"FBSharedFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) { [selected addObject:path]; break; }
    return selected.array;
}

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePaths:(NSArray<NSString *> *)imagePaths keywords:(NSArray<NSString *> *)keywords {
    NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
    for (NSString *imagePath in imagePaths) {
        for (RYGRuntimeClassRow *classRow in [RYGRuntimeClassBrowser classesForImagePath:imagePath]) {
            for (NSUInteger pass = 0; pass < 2; pass++) {
                for (RYGRuntimeMethodRow *method in [RYGRuntimeClassBrowser methodsForClass:classRow classMethods:(pass == 1)]) {
                    if (!method.hookableBool) continue;
                    NSString *text = [NSString stringWithFormat:@"%@ %@ %@", classRow.className ?: @"", method.selectorName ?: @"", imagePath.lastPathComponent ?: @""];
                    if (!keywords.count || RYGDevContainsAny(text, keywords)) { RYGRuntimeBoolMethod *descriptor = [RYGRuntimeClassBrowser boolDescriptorForMethod:method]; if (descriptor) [matches addObject:descriptor]; }
                }
            }
        }
    }
    return RYGDevSortedDedupedRows(matches);
}

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForSurface:(RYGDeveloperRuntimeSurface)surface {
    NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
    for (NSString *imagePath in [self primaryDeveloperImagePaths]) {
        for (RYGRuntimeClassRow *classRow in [RYGRuntimeClassBrowser classesForImagePath:imagePath]) {
            for (NSUInteger pass = 0; pass < 2; pass++) {
                for (RYGRuntimeMethodRow *method in [RYGRuntimeClassBrowser methodsForClass:classRow classMethods:(pass == 1)]) {
                    if (!method.hookableBool || !RYGDevMatchesSurfaceText(classRow.className, method.selectorName, surface)) continue;
                    RYGRuntimeBoolMethod *descriptor = [RYGRuntimeClassBrowser boolDescriptorForMethod:method]; if (descriptor) [matches addObject:descriptor];
                }
            }
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
