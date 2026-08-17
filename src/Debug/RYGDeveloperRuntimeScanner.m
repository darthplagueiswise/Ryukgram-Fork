#import "RYGDeveloperRuntimeScanner.h"
#import "RYGRuntimeBrowserEngine.h"

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

    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
    for (NSString *imagePath in imagePaths) {
        // One source of truth: the same scanner used by Runtime Browser. This
        // prevents Prism / Liquid Glass / WordMark from disagreeing with the
        // runtime browser because of separate objc_copyClassNamesForImage logic.
        NSArray<RYGRuntimeBoolMethod *> *imageRows =
            [RYGRuntimeBrowserEngine boolMethodsForImagePath:imagePath scope:RYGRuntimeBrowserScopeAll];
        for (RYGRuntimeBoolMethod *row in imageRows) {
            if (!RYGDevMatchesKeywords(row, keywords)) continue;
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
