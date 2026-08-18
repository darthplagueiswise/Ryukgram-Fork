#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <stdlib.h>
#include <string.h>

static NSString *RYGSafeNormalize(NSString *value) {
    return value.length ? value.lowercaseString : @"";
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

    // Sideload signing can relocate an otherwise identical bundle image. Only
    // relax the comparison when both paths still belong to the current bundle.
    NSString *bundle = RYGSafeCanonicalPath(NSBundle.mainBundle.bundlePath);
    NSString *prefix = bundle.length ? [bundle stringByAppendingString:@"/"] : @"";
    BOOL aOwned = prefix.length && [a hasPrefix:prefix];
    BOOL bOwned = prefix.length && [b hasPrefix:prefix];
    return aOwned && bOwned && [a.lastPathComponent isEqualToString:b.lastPathComponent];
}

static NSString *RYGSafeExactDyldImagePath(NSString *requestedPath) {
    if (!requestedPath.length) return nil;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw || !*raw) continue;
        NSString *candidate = [NSString stringWithUTF8String:raw];
        if (candidate.length && RYGSafePathsEqual(candidate, requestedPath)) {
            return candidate.stringByStandardizingPath;
        }
    }
    return nil;
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

static BOOL RYGSafeLooksBooleanSelector(NSString *selectorName) {
    NSString *lower = selectorName.lowercaseString ?: @"";
    for (NSString *prefix in @[@"is", @"has", @"can", @"should", @"supports", @"allows", @"allow", @"enable", @"enabled", @"use", @"uses", @"needs", @"requires", @"prefers"]) {
        if ([lower hasPrefix:prefix]) return YES;
    }
    return NO;
}

static BOOL RYGSafeSupportedBool(Method method, NSString *selectorName) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGSafeSkipQualifiers(encoded);
    if (!type || !*type || RYGSafeArgumentKind(method) < 0) return NO;

    // The supplied Instagram/FBShared build uses B16@0:8 for the verified
    // IGDSLauncherConfig Prism/LiquidGlass/Wordmark getters. Keep c/C support
    // only for boolean-shaped legacy selectors so plain character accessors do
    // not pollute the runtime browser.
    if (*type == 'B') return YES;
    return (*type == 'c' || *type == 'C') && RYGSafeLooksBooleanSelector(selectorName);
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

static BOOL RYGSafeMethodIMPBelongsToImage(Method method, NSString *wanted) {
    if (!method || !wanted.length) return NO;
    IMP imp = method_getImplementation(method);
    if (!imp) return NO;
    Dl_info info = {0};
    if (!dladdr((const void *)imp, &info) || !info.dli_fname) return NO;
    NSString *implementationImage = [NSString stringWithUTF8String:info.dli_fname];
    return implementationImage.length && RYGSafePathsEqual(implementationImage, wanted);
}

static BOOL RYGSafeClassBelongsToImage(Class cls, NSString *wanted) {
    if (!cls || !wanted.length) return NO;
    const char *raw = class_getImageName(cls);
    if (!raw || !*raw) return NO;
    NSString *classImage = [NSString stringWithUTF8String:raw];
    return classImage.length && RYGSafePathsEqual(classImage, wanted);
}

static void RYGSafeAppendMethodsForClass(NSMutableArray<RYGRuntimeBoolMethod *> *rows,
                                         NSMutableSet<NSString *> *dedupe,
                                         Class cls,
                                         NSString *wanted,
                                         RYGRuntimeBrowserScope scope) {
    if (!cls || !wanted.length) return;
    const char *rawClassName = class_getName(cls);
    if (!rawClassName || !*rawClassName) return;
    NSString *className = [NSString stringWithUTF8String:rawClassName];
    if (!className.length) return;

    BOOL classOwned = RYGSafeClassBelongsToImage(cls, wanted);
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
                || !RYGSafeSupportedBool(method, selectorName)
                || !RYGSafeRelevant(className, selectorName, scope)) continue;

            // Objective-C categories are merged into the host class at runtime.
            // class_getImageName(host) therefore cannot tell which image owns a
            // category method. Keep a method when either the host class belongs
            // to the selected image or the current IMP resolves into it. The IMP
            // test is what recovers FBShared/Instagram category methods that the
            // previous objc_copyClassNamesForImage scanner silently dropped.
            if (!classOwned && !RYGSafeMethodIMPBelongsToImage(method, wanted)) continue;

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
    NSString *wanted = RYGSafeExactDyldImagePath(imagePath);
    if (!wanted.length) return @[];

    // Use C runtime storage only. Do not retain Class objects in NSArray and do
    // not invoke private getters while scanning. This also lets category IMP
    // ownership participate in the image match.
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes || !classCount) {
        if (classes) free(classes);
        return @[];
    }

    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
    for (unsigned int index = 0; index < classCount; index++) {
        RYGSafeAppendMethodsForClass(rows, dedupe, classes[index], wanted, scope);
    }
    free(classes);

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

// Single authoritative scanner replacement. Runtime Browser and every developer
// feature surface consume this same real-time image scanner.
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
