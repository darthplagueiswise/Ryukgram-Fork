#import "RYGDeveloperRuntimeScanner.h"
#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

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

static const char *RYGDevSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGDevArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;
    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGDevSkipQualifiers(encoded);
    if (!type || !*type) return -1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *type)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGDevSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGDevSkipQualifiers(encoded);
    return type && *type == 'B' && RYGDevArgumentKind(method) >= 0;
}

static BOOL RYGDevStructuralState(Class cls, NSString *selectorName) {
    if (!cls || !selectorName.length) return YES;
    BOOL viewLike = [cls isSubclassOfClass:UIView.class]
        || [cls isSubclassOfClass:UIViewController.class]
        || [cls isSubclassOfClass:NSClassFromString(@"CALayer")];
    if (!viewLike) return NO;
    static NSSet<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[
            @"isHidden", @"isSelected", @"isEnabled", @"isHighlighted",
            @"isOpaque", @"clipsToBounds", @"isUserInteractionEnabled",
            @"userInteractionEnabled", @"isFocused", @"canBecomeFocused",
            @"prefersStatusBarHidden", @"prefersHomeIndicatorAutoHidden",
            @"shouldAutorotate"
        ]];
    });
    return [names containsObject:selectorName];
}

static BOOL RYGDevMatchesKeywords(NSString *className, NSString *selectorName, NSString *imageName, NSArray<NSString *> *needles) {
    if (!needles.count) return YES;
    NSString *hay = RYGDevScanNormalize([NSString stringWithFormat:@"%@ %@ %@", className ?: @"", selectorName ?: @"", imageName ?: @""]);
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
        NSString *name = path.lastPathComponent.lowercaseString;
        if ([name containsString:@"fbsharedframework"]) {
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

    for (NSString *imagePath in imagePaths) {
        NSString *wanted = imagePath.stringByStandardizingPath;
        if (!wanted.length) continue;
        unsigned int classCount = 0;
        const char **classNames = objc_copyClassNamesForImage(wanted.fileSystemRepresentation, &classCount);
        if (!classNames) continue;

        for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
            const char *rawName = classNames[classIndex];
            if (!rawName) continue;
            Class cls = objc_lookUpClass(rawName);
            if (!cls) continue;
            NSString *className = [NSString stringWithUTF8String:rawName];
            if (!className.length) continue;

            for (NSInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    SEL selector = method_getName(method);
                    NSString *selectorName = selector ? NSStringFromSelector(selector) : nil;
                    if (!selectorName.length
                        || [selectorName hasPrefix:@"set"]
                        || [selectorName hasPrefix:@"init"]
                        || [RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]
                        || RYGDevStructuralState(cls, selectorName)
                        || !RYGDevSupportedBool(method)
                        || !RYGDevMatchesKeywords(className, selectorName, wanted.lastPathComponent, keywords)) continue;

                    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                    row.imagePath = wanted;
                    row.className = className;
                    row.selectorName = selectorName;
                    row.classMethod = classMethod;
                    row.argumentKind = RYGDevArgumentKind(method);
                    row.typeEncoding = [NSString stringWithUTF8String:method_getTypeEncoding(method) ?: ""];
                    [rows addObject:row];
                }
                if (methods) free(methods);
            }
        }
        free(classNames);
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult imageOrder = [left.imagePath.lastPathComponent localizedCaseInsensitiveCompare:right.imagePath.lastPathComponent];
        if (imageOrder != NSOrderedSame) return imageOrder;
        NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className];
        return classOrder == NSOrderedSame ? [left.selectorName localizedCaseInsensitiveCompare:right.selectorName] : classOrder;
    }];
    return rows.copy;
}

@end
