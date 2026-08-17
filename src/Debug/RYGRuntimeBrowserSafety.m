#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <stdlib.h>
#include <string.h>

static NSString *RYGSafeNormalize(NSString *value) {
    if (!value.length) return @"";
    return value.lowercaseString;
}

static NSString *RYGSafeCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved : standard;
}

static BOOL RYGSafePathsEqual(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    NSString *a = RYGSafeCanonicalPath(left);
    NSString *b = RYGSafeCanonicalPath(right);
    if ([a isEqualToString:b]) return YES;

    NSString *bundle = RYGSafeCanonicalPath(NSBundle.mainBundle.bundlePath);
    NSString *bundlePrefix = bundle.length ? [bundle stringByAppendingString:@"/"] : @"";
    BOOL aOwned = bundlePrefix.length && [a hasPrefix:bundlePrefix];
    BOOL bOwned = bundlePrefix.length && [b hasPrefix:bundlePrefix];
    return aOwned && bOwned && [a.lastPathComponent isEqualToString:b.lastPathComponent];
}

/// objc_copyClassNamesForImage is image-scoped and fast, but it is deliberately
/// given dyld's exact registered path instead of a reconstructed Foundation path.
/// This avoids the empty scan seen with sideloaded bundles whose launch path and
/// canonical dyld path are not byte-identical.
static const char *RYGSafeExactDyldImageName(NSString *requestedPath, NSString **resolvedPath) {
    if (resolvedPath) *resolvedPath = nil;
    if (!requestedPath.length) return NULL;

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw || !*raw) continue;
        NSString *candidate = [NSString stringWithUTF8String:raw];
        if (!candidate.length || !RYGSafePathsEqual(candidate, requestedPath)) continue;
        if (resolvedPath) *resolvedPath = candidate.stringByStandardizingPath;
        return raw;
    }
    return NULL;
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
    // Current Instagram / FBSharedFramework BOOL getters verified in the shipped
    // Mach-O metadata use B (for example B16@0:8). Do not treat arbitrary chars
    // as Objective-C BOOL and accidentally expose unsafe methods as gates.
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

static BOOL RYGSafeMethodImplementedInImage(Method method, NSString *wanted) {
    if (!method || !wanted.length) return NO;
    IMP implementation = method_getImplementation(method);
    if (!implementation) return NO;
    Dl_info info = {0};
    if (!dladdr((const void *)implementation, &info) || !info.dli_fname) return NO;
    NSString *methodImage = [NSString stringWithUTF8String:info.dli_fname];
    return RYGSafePathsEqual(methodImage, wanted);
}

static void RYGSafeAppendMethodsForClass(NSMutableArray<RYGRuntimeBoolMethod *> *rows,
                                         NSMutableSet<NSString *> *dedupe,
                                         Class cls,
                                         NSString *wanted,
                                         RYGRuntimeBrowserScope scope) {
    if (!cls || !wanted.length) return;
    NSString *className = NSStringFromClass(cls);
    if (!className.length) return;

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
                || [RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]
                || RYGSafeStructuralState(cls, selectorName)
                || !RYGSafeSupportedBool(method)
                || !RYGSafeRelevant(className, selectorName, scope)) continue;

            // class_copyMethodList can include category additions to a class that
            // originated in this image. Attribute a row only when its live IMP
            // actually resolves back to the selected dyld image.
            if (!RYGSafeMethodImplementedInImage(method, wanted)) continue;

            RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
            row.imagePath = wanted;
            row.className = className;
            row.selectorName = selectorName;
            row.classMethod = classMethod;
            row.argumentKind = RYGSafeArgumentKind(method);
            const char *types = method_getTypeEncoding(method);
            row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
            NSString *key = row.overrideKey;
            if (!key.length || [dedupe containsObject:key]) continue;
            [dedupe addObject:key];
            [rows addObject:row];
        }
        if (methods) free(methods);
    }
}

@implementation RYGRuntimeBrowserEngine (RYGRuntimeBrowserSafety)

+ (NSArray<RYGRuntimeBoolMethod *> *)ryg_safeBoolMethodsForImagePath:(NSString *)imagePath
                                                               scope:(RYGRuntimeBrowserScope)scope {
    NSString *resolvedPath = nil;
    const char *rawImageName = RYGSafeExactDyldImageName(imagePath, &resolvedPath);
    if (!rawImageName || !resolvedPath.length) return @[];

    // The old implementation copied EVERY registered class in the Instagram
    // process and then made a second pass over every foreign class, including
    // instance + metaclass method lists and dladdr checks. That is quadratic-ish
    // work at Instagram scale and is why the Runtime Browser could spin forever.
    // Ask the Objective-C runtime for only the selected dyld image instead.
    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(rawImageName, &classCount);
    if (!classNames || !classCount) {
        if (classNames) free(classNames);
        return @[];
    }

    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
    for (unsigned int index = 0; index < classCount; index++) {
        const char *rawClassName = classNames[index];
        if (!rawClassName || !*rawClassName) continue;
        Class cls = objc_lookUpClass(rawClassName);
        if (!cls) continue;
        RYGSafeAppendMethodsForClass(rows, dedupe, cls, resolvedPath, scope);
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

// Single authoritative scanner replacement. Runtime Browser and developer
// surfaces now share the same image-scoped live enumeration path.
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
