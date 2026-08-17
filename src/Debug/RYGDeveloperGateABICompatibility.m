#import "RYGDeveloperGateViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static const void *kRYGDeveloperGateScanGenerationKey = &kRYGDeveloperGateScanGenerationKey;

static NSSet<NSString *> *RYGWordMarkSelectors(void) {
    return [NSSet setWithArray:@[@"isIGWordmark1aEnabled", @"isIGWordmark1aAltEnabled", @"isIGWordmark1bEnabled", @"isIGWordmark1bAltEnabled"]];
}

static BOOL RYGHaysContainsAny(NSString *haystack, NSArray<NSString *> *needles) {
    NSString *lower = haystack.lowercaseString ?: @"";
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static BOOL RYGCompatGateMatches(RYGRuntimeBoolMethod *row, RYGDeveloperGateSurface surface) {
    if (!row.selectorName.length) return NO;
    NSString *haystack = [NSString stringWithFormat:@"%@ %@", row.className ?: @"", row.selectorName ?: @""];
    NSString *lower = haystack.lowercaseString;
    switch (surface) {
        case RYGDeveloperGateSurfaceWordMark:
            return [RYGWordMarkSelectors() containsObject:row.selectorName];
        case RYGDeveloperGateSurfaceInternal:
            return RYGHaysContainsAny(haystack, @[@"employee", @"internal", @"dogfood", @"igonly", @"ig-only", @"metamate", @"staff"]);
        case RYGDeveloperGateSurfacePrism:
            return [lower containsString:@"prism"];
        case RYGDeveloperGateSurfaceLiquidGlass: {
            // Keep wearable/AI "glasses" features out of this UIKit surface.
            if (RYGHaysContainsAny(lower, @[@"glasses", @"rayban", @"wearable", @"smartglass"])) return NO;
            if ([lower containsString:@"throwbackchrome"]) return YES;
            return RYGHaysContainsAny(lower, @[@"liquidglass", @"liquid glass", @"glasseffect", @"igglass", @"igdsglass"]);
        }
    }
    return NO;
}

static NSArray<NSString *> *RYGCompatDeveloperImages(void) {
    NSArray<NSString *> *images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    if (main.length && [images containsObject:main]) [selected addObject:main];
    for (NSString *path in images) {
        if ([path.lastPathComponent rangeOfString:@"FBSharedFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [selected addObject:path];
            break;
        }
    }
    return selected.array;
}

@implementation RYGDeveloperGateViewController (RYGABICompatibility)

- (void)ryg_abi_refreshGates {
    NSInteger surfaceValue = 0;
    @try { surfaceValue = [[self valueForKey:@"surface"] integerValue]; } @catch (__unused id exception) {}
    RYGDeveloperGateSurface surface = (RYGDeveloperGateSurface)surfaceValue;
    NSUInteger generation = [objc_getAssociatedObject(self, kRYGDeveloperGateScanGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, kRYGDeveloperGateScanGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { [self setValue:@YES forKey:@"scanning"]; } @catch (__unused id exception) {}
    [self rebuildSections];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
        NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
        for (NSString *path in RYGCompatDeveloperImages()) {
            NSArray<RYGRuntimeBoolMethod *> *rows = [RYGRuntimeBrowserEngine boolMethodsForImagePath:path scope:RYGRuntimeBrowserScopeAll];
            for (RYGRuntimeBoolMethod *row in rows) {
                if (!RYGCompatGateMatches(row, surface) || [dedupe containsObject:row.overrideKey]) continue;
                [dedupe addObject:row.overrideKey];
                [matches addObject:row];
            }
        }
        [matches sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) {
            NSComparisonResult selectorOrder = [a.selectorName localizedCaseInsensitiveCompare:b.selectorName];
            if (selectorOrder != NSOrderedSame) return selectorOrder;
            return [a.className localizedCaseInsensitiveCompare:b.className];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger current = [objc_getAssociatedObject(self, kRYGDeveloperGateScanGenerationKey) unsignedIntegerValue];
            if (current != generation) return;
            @try {
                [self setValue:matches.copy forKey:@"gateRows"];
                [self setValue:@NO forKey:@"scanning"];
            } @catch (__unused id exception) {}
            [self rebuildSections];
        });
    });
}

@end

__attribute__((constructor(145))) static void RYGInstallDeveloperGateABICompatibility(void) {
    Class cls = RYGDeveloperGateViewController.class;
    Method original = class_getInstanceMethod(cls, NSSelectorFromString(@"refreshGates"));
    Method replacement = class_getInstanceMethod(cls, @selector(ryg_abi_refreshGates));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
