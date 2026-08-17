#import "RYGDeveloperGateViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>

static const void *kRYGDeveloperGateScanGenerationKey = &kRYGDeveloperGateScanGenerationKey;

static NSSet<NSString *> *RYGWordMarkSelectors(void) {
    static NSSet<NSString *> *selectors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        selectors = [NSSet setWithArray:@[
            @"isIGWordmark1aEnabled", @"isIGWordmark1aAltEnabled",
            @"isIGWordmark1bEnabled", @"isIGWordmark1bAltEnabled"
        ]];
    });
    return selectors;
}

static BOOL RYGHaysContainsAny(NSString *haystack, NSArray<NSString *> *needles) {
    NSString *lower = haystack.lowercaseString ?: @"";
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static BOOL RYGCompatGateMatches(NSString *className, NSString *selectorName, RYGDeveloperGateSurface surface) {
    if (!selectorName.length) return NO;
    NSString *haystack = [NSString stringWithFormat:@"%@ %@", className ?: @"", selectorName];
    NSString *lower = haystack.lowercaseString;
    switch (surface) {
        case RYGDeveloperGateSurfaceWordMark:
            return [RYGWordMarkSelectors() containsObject:selectorName];
        case RYGDeveloperGateSurfaceInternal:
            return RYGHaysContainsAny(lower, @[@"employee", @"internal", @"dogfood", @"igonly", @"ig-only", @"metamate", @"staff"]);
        case RYGDeveloperGateSurfacePrism:
            return [lower containsString:@"prism"];
        case RYGDeveloperGateSurfaceLiquidGlass:
            if (RYGHaysContainsAny(lower, @[@"glasses", @"rayban", @"wearable", @"smartglass"])) return NO;
            if ([lower containsString:@"throwbackchrome"]) return YES;
            return RYGHaysContainsAny(lower, @[@"liquidglass", @"liquid glass", @"glasseffect", @"igglass", @"igdsglass"]);
    }
    return NO;
}

static NSString *RYGCompatCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved : standard;
}

static BOOL RYGCompatPathsEqual(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    NSString *a = RYGCompatCanonicalPath(left);
    NSString *b = RYGCompatCanonicalPath(right);
    if ([a isEqualToString:b]) return YES;
    NSString *bundle = RYGCompatCanonicalPath(NSBundle.mainBundle.bundlePath);
    NSString *prefix = bundle.length ? [bundle stringByAppendingString:@"/"] : @"";
    return prefix.length && [a hasPrefix:prefix] && [b hasPrefix:prefix]
        && [a.lastPathComponent isEqualToString:b.lastPathComponent];
}

static const char *RYGCompatExactDyldImage(NSString *path, NSString **resolvedPath) {
    if (resolvedPath) *resolvedPath = nil;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw || !*raw) continue;
        NSString *candidate = [NSString stringWithUTF8String:raw];
        if (!candidate.length || !RYGCompatPathsEqual(candidate, path)) continue;
        if (resolvedPath) *resolvedPath = candidate.stringByStandardizingPath;
        return raw;
    }
    return NULL;
}

static const char *RYGCompatSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGCompatArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;
    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *arg = RYGCompatSkipQualifiers(encoded);
    if (!arg || !*arg) return -1;
    if (*arg == '@' || *arg == '#' || *arg == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *arg)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGCompatSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGCompatSkipQualifiers(encoded);
    return ret && *ret == 'B' && RYGCompatArgumentKind(method) >= 0;
}

static NSArray<NSString *> *RYGCompatDeveloperImages(void) {
    NSArray<NSString *> *images = [RYGRuntimeBrowserEngine runtimeImagePaths];
    NSString *main = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSMutableOrderedSet<NSString *> *selected = [NSMutableOrderedSet orderedSet];
    for (NSString *path in images) {
        if (main.length && RYGCompatPathsEqual(path, main)) [selected addObject:path];
        if ([path.lastPathComponent rangeOfString:@"FBSharedFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [selected addObject:path];
        }
    }
    return selected.array;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGCompatScanSurface(RYGDeveloperGateSurface surface) {
    NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];

    for (NSString *requestedPath in RYGCompatDeveloperImages()) {
        NSString *resolvedPath = nil;
        const char *rawImage = RYGCompatExactDyldImage(requestedPath, &resolvedPath);
        if (!rawImage || !resolvedPath.length) continue;

        unsigned int classCount = 0;
        const char **classNames = objc_copyClassNamesForImage(rawImage, &classCount);
        if (!classNames) continue;

        for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
            const char *rawClassName = classNames[classIndex];
            if (!rawClassName || !*rawClassName) continue;
            Class cls = objc_lookUpClass(rawClassName);
            if (!cls) continue;
            NSString *className = [NSString stringWithUTF8String:rawClassName];
            if (!className.length) continue;

            for (NSInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                if (!owner) continue;
                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList(owner, &methodCount);
                for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    SEL selector = method_getName(method);
                    if (!selector) continue;
                    NSString *selectorName = NSStringFromSelector(selector);

                    // Surface/name matching is intentionally first. Only the
                    // handful of relevant candidates pay the ABI decoding cost.
                    if (!RYGCompatGateMatches(className, selectorName, surface)
                        || !RYGCompatSupportedBool(method)) continue;

                    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                    row.imagePath = resolvedPath;
                    row.className = className;
                    row.selectorName = selectorName;
                    row.classMethod = classMethod;
                    row.argumentKind = RYGCompatArgumentKind(method);
                    const char *types = method_getTypeEncoding(method);
                    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                    NSString *key = row.overrideKey;
                    if (!key.length || [dedupe containsObject:key]) continue;
                    [dedupe addObject:key];
                    [matches addObject:row];
                }
                if (methods) free(methods);
            }
        }
        free(classNames);
    }

    [matches sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) {
        NSComparisonResult selectorOrder = [a.selectorName localizedCaseInsensitiveCompare:b.selectorName];
        if (selectorOrder != NSOrderedSame) return selectorOrder;
        return [a.className localizedCaseInsensitiveCompare:b.className];
    }];
    return matches.copy;
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
        NSArray<RYGRuntimeBoolMethod *> *matches = RYGCompatScanSurface(surface);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger current = [objc_getAssociatedObject(self, kRYGDeveloperGateScanGenerationKey) unsignedIntegerValue];
            if (current != generation) return;
            @try {
                [self setValue:matches ?: @[] forKey:@"gateRows"];
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
