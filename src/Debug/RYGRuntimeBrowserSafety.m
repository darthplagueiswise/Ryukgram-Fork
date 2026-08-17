#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
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
    // dyld can report a canonical bundle path while Foundation still exposes
    // the launch path. Their basenames are only accepted as a last resort when
    // both paths are inside the current app bundle.
    NSString *bundle = RYGSafeCanonicalPath(NSBundle.mainBundle.bundlePath);
    BOOL aOwned = bundle.length && [a hasPrefix:[bundle stringByAppendingString:@"/"]];
    BOOL bOwned = bundle.length && [b hasPrefix:[bundle stringByAppendingString:@"/"]];
    return aOwned && bOwned && [a.lastPathComponent isEqualToString:b.lastPathComponent];
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
    // The uploaded Instagram / FBSharedFramework binaries use the modern
    // arm64 BOOL encoding B (for example B16@0:8 for the verified WordMark and
    // Prism gates). Do not silently treat arbitrary char-return methods as BOOL.
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

static BOOL RYGSafeClassDefinedInImage(Class cls, NSString *wanted) {
    const char *rawImage = cls ? class_getImageName(cls) : NULL;
    if (!rawImage || !*rawImage) return NO;
    NSString *classImage = [NSString stringWithUTF8String:rawImage];
    return RYGSafePathsEqual(classImage, wanted);
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
                                         RYGRuntimeBrowserScope scope,
                                         BOOL requireImplementationImage) {
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

            // Classes defined by the selected image are already authoritative.
            // For the fallback pass over foreign classes, require the actual IMP
            // to resolve to the selected image so category methods are included
            // without attributing inherited/foreign methods to the wrong binary.
            if (requireImplementationImage && !RYGSafeMethodImplementedInImage(method, wanted)) continue;

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
    NSString *wanted = RYGSafeCanonicalPath(imagePath);
    if (!wanted.length) return @[];

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes || !classCount) {
        if (classes) free(classes);
        return @[];
    }

    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];
    NSMutableIndexSet *foreignIndexes = [NSMutableIndexSet indexSet];

    // Pass 1: classes whose defining image is the selected executable/framework.
    // This is the common and cheap path and fixes objc_copyClassNamesForImage
    // returning an empty/incomplete view on current dyld/ObjC combinations.
    for (unsigned int index = 0; index < classCount; index++) {
        Class cls = classes[index];
        if (!cls) continue;
        if (RYGSafeClassDefinedInImage(cls, wanted)) {
            RYGSafeAppendMethodsForClass(rows, dedupe, cls, wanted, scope, NO);
        } else {
            [foreignIndexes addIndex:index];
        }
    }

    // Pass 2: category coverage. A category can be emitted by the selected image
    // while extending a class defined elsewhere. The class image is then wrong
    // for attribution; dladdr(method_getImplementation()) gives the real image.
    // Only foreign classes are visited here, and cheap signature/relevance tests
    // run before dladdr, keeping the scan practical even in Instagram's large runtime.
    [foreignIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        if (index >= classCount) return;
        RYGSafeAppendMethodsForClass(rows, dedupe, classes[index], wanted, scope, YES);
    }];

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

// This is the single scanner replacement. Older ABI compatibility files no
// longer swap boolMethodsForImagePath:scope:, so constructor order cannot form
// a chain of competing implementations.
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
