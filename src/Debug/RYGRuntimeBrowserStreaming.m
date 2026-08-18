#import "RYGRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>

static const void *kRYGStreamGenerationKey = &kRYGStreamGenerationKey;

@interface RYGRuntimeBrowserViewController (RYGStreamingInternals)
- (void)refreshRuntimeImages;
- (void)applySearchFilter;
- (void)ryg_stream_scanSelectedImage;
@end

static NSString *RYGStreamCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved : standard;
}

static BOOL RYGStreamPathsEqual(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    NSString *a = RYGStreamCanonicalPath(left);
    NSString *b = RYGStreamCanonicalPath(right);
    if ([a isEqualToString:b]) return YES;

    NSString *bundle = RYGStreamCanonicalPath(NSBundle.mainBundle.bundlePath);
    NSString *prefix = bundle.length ? [bundle stringByAppendingString:@"/"] : @"";
    return prefix.length && [a hasPrefix:prefix] && [b hasPrefix:prefix]
        && [a.lastPathComponent isEqualToString:b.lastPathComponent];
}

static const char *RYGStreamExactDyldImageName(NSString *requestedPath, NSString **resolvedPath) {
    if (resolvedPath) *resolvedPath = nil;
    if (!requestedPath.length) return NULL;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw || !*raw) continue;
        NSString *candidate = [NSString stringWithUTF8String:raw];
        if (!candidate.length || !RYGStreamPathsEqual(candidate, requestedPath)) continue;
        if (resolvedPath) *resolvedPath = candidate.stringByStandardizingPath;
        return raw;
    }
    return NULL;
}

static const char *RYGStreamSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGStreamArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;

    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGStreamSkipQualifiers(encoded);
    if (!type || !*type) return -1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *type)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGStreamSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGStreamSkipQualifiers(encoded);
    return type && *type == 'B' && RYGStreamArgumentKind(method) >= 0;
}

static BOOL RYGStreamClassInheritsFrom(Class cls, Class ancestor) {
    if (!cls || !ancestor) return NO;
    for (Class cursor = cls; cursor; cursor = class_getSuperclass(cursor)) {
        if (cursor == ancestor) return YES;
    }
    return NO;
}

static BOOL RYGStreamStructuralState(Class cls, NSString *selectorName) {
    if (!cls || !selectorName.length) return YES;
    Class view = objc_lookUpClass("UIView");
    Class controller = objc_lookUpClass("UIViewController");
    Class layer = objc_lookUpClass("CALayer");
    BOOL viewLike = (view && RYGStreamClassInheritsFrom(cls, view))
        || (controller && RYGStreamClassInheritsFrom(cls, controller))
        || (layer && RYGStreamClassInheritsFrom(cls, layer));
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

static BOOL RYGStreamContainsAny(NSString *haystack, NSArray<NSString *> *needles) {
    NSString *lower = haystack.lowercaseString ?: @"";
    for (NSString *needle in needles) if ([lower containsString:needle]) return YES;
    return NO;
}

static BOOL RYGStreamRelevant(NSString *className, NSString *selectorName, RYGRuntimeBrowserScope scope) {
    if (scope == RYGRuntimeBrowserScopeAll) return YES;
    NSString *hay = [NSString stringWithFormat:@"%@ %@", className ?: @"", selectorName ?: @""];
    if (RYGStreamContainsAny(hay, @[@"employee", @"dogfood", @"internal", @"launcher", @"staff", @"metamate"])) return YES;
    if (scope == RYGRuntimeBrowserScopeEmployee) return NO;
    return RYGStreamContainsAny(hay, @[
        @"experiment", @"feature", @"gate", @"gating", @"enable", @"available",
        @"allow", @"support", @"test", @"debug", @"rollout", @"treatment",
        @"variant", @"config", @"prism", @"glass", @"wordmark"
    ]);
}

static void RYGStreamAppendClassMethods(NSMutableArray<RYGRuntimeBoolMethod *> *rows,
                                        NSMutableSet<NSString *> *dedupe,
                                        Class cls,
                                        NSString *resolvedPath,
                                        RYGRuntimeBrowserScope scope) {
    if (!cls || !resolvedPath.length) return;
    NSString *className = NSStringFromClass(cls);
    if (!className.length) return;

    for (NSInteger pass = 0; pass < 2; pass++) {
        BOOL classMethod = pass == 1;
        Class owner = classMethod ? object_getClass(cls) : cls;
        if (!owner) continue;

        unsigned int count = 0;
        Method *methods = class_copyMethodList(owner, &count);
        for (unsigned int index = 0; index < count; index++) {
            Method method = methods[index];
            SEL selector = method_getName(method);
            if (!selector) continue;
            NSString *selectorName = NSStringFromSelector(selector);
            if (!selectorName.length
                || [selectorName hasPrefix:@"set"]
                || [selectorName hasPrefix:@"init"]
                || [RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]
                || RYGStreamStructuralState(cls, selectorName)) continue;

            // Name/scope filtering is intentionally BEFORE ABI decoding. The
            // normal browser scope rejects most methods by name, avoiding tens
            // of thousands of method_getReturnType/argument decoding calls.
            if (!RYGStreamRelevant(className, selectorName, scope)) continue;
            if (!RYGStreamSupportedBool(method)) continue;

            RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
            row.imagePath = resolvedPath;
            row.className = className;
            row.selectorName = selectorName;
            row.classMethod = classMethod;
            row.argumentKind = RYGStreamArgumentKind(method);
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

static void RYGStreamBoolMethods(NSString *requestedPath,
                                 RYGRuntimeBrowserScope scope,
                                 BOOL (^cancelled)(void),
                                 void (^batchHandler)(NSArray<RYGRuntimeBoolMethod *> *batch),
                                 void (^completion)(NSArray<RYGRuntimeBoolMethod *> *allRows)) {
    NSString *resolvedPath = nil;
    const char *rawImage = RYGStreamExactDyldImageName(requestedPath, &resolvedPath);
    if (!rawImage || !resolvedPath.length) {
        if (completion) completion(@[]);
        return;
    }

    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(rawImage, &classCount);
    if (!classNames || !classCount) {
        if (classNames) free(classNames);
        if (completion) completion(@[]);
        return;
    }

    NSMutableArray<RYGRuntimeBoolMethod *> *all = [NSMutableArray array];
    NSMutableArray<RYGRuntimeBoolMethod *> *pending = [NSMutableArray array];
    NSMutableSet<NSString *> *dedupe = [NSMutableSet set];

    // 128 classes per yield keeps a 40k+ class executable responsive while the
    // browser progressively fills. There is no pre-rendered table and no full
    // process scan: every row still comes from the currently loaded image.
    const unsigned int classBatch = 128;
    for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
        if (cancelled && cancelled()) break;
        @autoreleasepool {
            const char *rawClassName = classNames[classIndex];
            if (rawClassName && *rawClassName) {
                Class cls = objc_lookUpClass(rawClassName);
                if (cls) {
                    NSUInteger before = pending.count;
                    RYGStreamAppendClassMethods(pending, dedupe, cls, resolvedPath, scope);
                    if (pending.count > before) {
                        NSRange newRange = NSMakeRange(before, pending.count - before);
                        [all addObjectsFromArray:[pending subarrayWithRange:newRange]];
                    }
                }
            }
        }

        BOOL shouldFlush = pending.count >= 96 || ((classIndex + 1) % classBatch == 0);
        if (shouldFlush && pending.count) {
            NSArray *batch = pending.copy;
            [pending removeAllObjects];
            if (batchHandler) batchHandler(batch);
        }
    }
    if (pending.count && (!cancelled || !cancelled())) {
        if (batchHandler) batchHandler(pending.copy);
    }
    free(classNames);

    [all sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult classOrder = [left.className localizedCaseInsensitiveCompare:right.className];
        if (classOrder != NSOrderedSame) return classOrder;
        NSComparisonResult selectorOrder = [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
        if (selectorOrder != NSOrderedSame) return selectorOrder;
        if (left.classMethod == right.classMethod) return NSOrderedSame;
        return left.classMethod ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (completion) completion(all.copy);
}

@implementation RYGRuntimeBrowserViewController (RYGRuntimeBrowserStreaming)

- (void)ryg_stream_scanSelectedImage {
    UISegmentedControl *modeControl = nil;
    @try { modeControl = [self valueForKey:@"modeControl"]; } @catch (__unused id exception) {}
    if (!modeControl || modeControl.selectedSegmentIndex != 0) {
        // Mach-O symbol mode already walks LC_SYMTAB directly and doesn't have
        // the Objective-C class explosion. Preserve its existing implementation.
        [self ryg_stream_scanSelectedImage];
        return;
    }

    [self refreshRuntimeImages];
    NSString *path = nil;
    NSNumber *scopeNumber = nil;
    @try {
        path = [[self valueForKey:@"selectedImagePath"] copy];
        scopeNumber = [self valueForKey:@"scope"];
    } @catch (__unused id exception) {}
    if (!path.length) {
        @try {
            [self setValue:@[] forKey:@"boolRows"];
            [self setValue:@NO forKey:@"scanning"];
        } @catch (__unused id exception) {}
        [self applySearchFilter];
        return;
    }

    RYGRuntimeBrowserScope scope = (RYGRuntimeBrowserScope)scopeNumber.integerValue;
    NSUInteger generation = [objc_getAssociatedObject(self, kRYGStreamGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, kRYGStreamGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {
        [self setValue:@[] forKey:@"boolRows"];
        [self setValue:@YES forKey:@"scanning"];
    } @catch (__unused id exception) {}
    self.navigationItem.rightBarButtonItems.firstObject.enabled = NO;
    [self applySearchFilter];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        RYGStreamBoolMethods(path, scope, ^BOOL{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return YES;
            return [objc_getAssociatedObject(self, kRYGStreamGenerationKey) unsignedIntegerValue] != generation;
        }, ^(NSArray<RYGRuntimeBoolMethod *> *batch) {
            if (!batch.count) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || [objc_getAssociatedObject(self, kRYGStreamGenerationKey) unsignedIntegerValue] != generation) return;
                NSArray *current = nil;
                @try { current = [self valueForKey:@"boolRows"]; } @catch (__unused id exception) {}
                NSMutableArray *next = current ? [current mutableCopy] : [NSMutableArray array];
                [next addObjectsFromArray:batch];
                @try { [self setValue:next.copy forKey:@"boolRows"]; } @catch (__unused id exception) {}
                [self applySearchFilter];
            });
        }, ^(NSArray<RYGRuntimeBoolMethod *> *allRows) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || [objc_getAssociatedObject(self, kRYGStreamGenerationKey) unsignedIntegerValue] != generation) return;
                @try {
                    [self setValue:allRows ?: @[] forKey:@"boolRows"];
                    [self setValue:@NO forKey:@"scanning"];
                } @catch (__unused id exception) {}
                self.navigationItem.rightBarButtonItems.firstObject.enabled = YES;
                [self applySearchFilter];
            });
        });
    });
}

@end

__attribute__((constructor(65520))) static void RYGInstallRuntimeBrowserStreaming(void) {
    @autoreleasepool {
        Class cls = RYGRuntimeBrowserViewController.class;
        SEL originalSelector = NSSelectorFromString(@"scanSelectedImage");
        SEL replacementSelector = @selector(ryg_stream_scanSelectedImage);
        Method original = class_getInstanceMethod(cls, originalSelector);
        Method replacement = class_getInstanceMethod(cls, replacementSelector);
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
