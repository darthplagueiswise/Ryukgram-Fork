#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static NSString *RYGSafeNormalize(NSString *value) {
    if (!value.length) return @"";
    return value.lowercaseString;
}

static const char *RYGSafeSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGSafeArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;

    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGSafeSkipQualifiers(encoded);
    if (!type || !*type) return -1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *type)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGSafeSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGSafeSkipQualifiers(encoded);
    return type && *type == 'B' && RYGSafeArgumentKind(method) >= 0;
}

static BOOL RYGSafeClassInheritsFrom(Class cls, Class ancestor) {
    if (!cls || !ancestor) return NO;
    for (Class cursor = cls; cursor; cursor = class_getSuperclass(cursor)) {
        if (cursor == ancestor) return YES;
    }
    return NO;
}

static BOOL RYGSafeStructuralState(Class cls, NSString *selectorName) {
    if (!cls || !selectorName.length) return YES;
    Class view = objc_lookUpClass("UIView");
    Class controller = objc_lookUpClass("UIViewController");
    Class layer = objc_lookUpClass("CALayer");
    BOOL viewLike = (view && RYGSafeClassInheritsFrom(cls, view))
        || (controller && RYGSafeClassInheritsFrom(cls, controller))
        || (layer && RYGSafeClassInheritsFrom(cls, layer));
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

static BOOL RYGSafeRelevant(NSString *className, NSString *selectorName, RYGRuntimeBrowserScope scope) {
    if (scope == RYGRuntimeBrowserScopeAll) return YES;
    NSString *hay = RYGSafeNormalize([NSString stringWithFormat:@"%@ %@", className ?: @"", selectorName ?: @""]);
    for (NSString *needle in @[@"employee", @"dogfood", @"internal", @"launcher", @"staff", @"metamate"]) {
        if ([hay containsString:needle]) return YES;
    }
    if (scope == RYGRuntimeBrowserScopeEmployee) return NO;
    for (NSString *needle in @[@"experiment", @"feature", @"gate", @"gating", @"enable", @"available",
                                @"allow", @"support", @"test", @"debug", @"rollout", @"treatment",
                                @"variant", @"config", @"prism", @"glass", @"wordmark"]) {
        if ([hay containsString:needle]) return YES;
    }
    return NO;
}

@implementation RYGRuntimeBrowserEngine (RYGRuntimeBrowserSafety)

+ (NSArray<RYGRuntimeBoolMethod *> *)ryg_safeBoolMethodsForImagePath:(NSString *)imagePath
                                                               scope:(RYGRuntimeBrowserScope)scope {
    NSString *wanted = imagePath.stringByStandardizingPath;
    if (!wanted.length) return @[];

    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(wanted.fileSystemRepresentation, &classCount);
    if (!classNames || !classCount) {
        if (classNames) free(classNames);
        return @[];
    }

    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
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
                if (!selectorName.length
                    || [selectorName hasPrefix:@"set"]
                    || [selectorName hasPrefix:@"init"]
                    || [self isStructuralNoiseSelectorName:selectorName]
                    || RYGSafeStructuralState(cls, selectorName)
                    || !RYGSafeSupportedBool(method)
                    || !RYGSafeRelevant(className, selectorName, scope)) continue;

                RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                row.imagePath = wanted;
                row.className = className;
                row.selectorName = selectorName;
                row.classMethod = classMethod;
                row.argumentKind = RYGSafeArgumentKind(method);
                const char *types = method_getTypeEncoding(method);
                row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                [rows addObject:row];
            }
            if (methods) free(methods);
        }
    }
    free(classNames);

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className];
        if (classOrder != NSOrderedSame) return classOrder;
        NSComparisonResult selectorOrder = [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
        if (selectorOrder != NSOrderedSame) return selectorOrder;
        if (left.classMethod == right.classMethod) return NSOrderedSame;
        return left.classMethod ? NSOrderedAscending : NSOrderedDescending;
    }];
    return rows.copy;
}

@end

__attribute__((constructor(65480))) static void RYGInstallRuntimeBrowserSafety(void) {
    @autoreleasepool {
        Class meta = object_getClass(RYGRuntimeBrowserEngine.class);
        SEL originalSelector = @selector(boolMethodsForImagePath:scope:);
        SEL replacementSelector = @selector(ryg_safeBoolMethodsForImagePath:scope:);
        Method original = class_getInstanceMethod(meta, originalSelector);
        Method replacement = class_getInstanceMethod(meta, replacementSelector);
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
