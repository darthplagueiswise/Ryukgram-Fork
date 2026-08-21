#import "RYGRuntimeIndex.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <stdlib.h>
#include <string.h>

@implementation RYGRuntimeImageIndex
- (NSArray<RYGRuntimeBoolMethod *> *)methodsForClassName:(NSString *)className {
    return self.methodsByClass[className] ?: @[];
}
@end

static dispatch_queue_t RYGIndexQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ryukgram.runtime-index", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

// Discovery is intentionally snapshot-based. A loaded image is indexed once and
// reused until the user explicitly presses Refresh. Loading some unrelated dylib
// must not invalidate the selected image and trigger a full rescan.
static NSMutableDictionary<NSString *, RYGRuntimeImageIndex *> *gRYGIndexes;
static NSMutableDictionary<NSString *, NSValue *> *gRYGIndexHeaders;

static NSString *RYGIndexCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static const struct mach_header *RYGIndexHeaderForPath(NSString *path) {
    NSString *wanted = RYGIndexCanonicalPath(path);
    if (!wanted.length) return NULL;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *loaded = RYGIndexCanonicalPath([NSString stringWithUTF8String:raw]);
        if ([loaded isEqualToString:wanted]) return _dyld_get_image_header(index);
    }
    return NULL;
}

static NSString *RYGIndexRuntimeNameForPath(NSString *path) {
    NSString *wanted = RYGIndexCanonicalPath(path);
    if (!wanted.length) return nil;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *loaded = [NSString stringWithUTF8String:raw];
        if ([RYGIndexCanonicalPath(loaded) isEqualToString:wanted]) return loaded;
    }
    return nil;
}

static const char *RYGIndexSkipQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGIndexBoolReturn(Method method) {
    if (!method) return NO;
    char encoded[64] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGIndexSkipQualifiers(encoded);
    return type && (*type == 'B' || *type == 'c' || *type == 'C');
}

static RYGRuntimeArgumentKind RYGIndexArgumentKind(Method method) {
    if (!method || !RYGIndexBoolReturn(method)) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[96] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGIndexSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@') return RYGRuntimeArgumentObject;
    // Do not widen c/C/s/S/i/I/l/L to a uint64_t trampoline. The generic
    // runtime hook is only ABI-safe for an actual 64-bit integer register value.
    if (*type == 'q' || *type == 'Q') return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGIndexIMPBelongsToHeader(Method method, const struct mach_header *target) {
    IMP imp = method ? method_getImplementation(method) : NULL;
    if (!imp || !target) return NO;
    Dl_info info = {0};
    return dladdr((const void *)imp, &info) && info.dli_fbase == (const void *)target;
}

static RYGRuntimeBoolMethod *RYGIndexMethodRow(Class cls, Method method, BOOL classMethod, NSString *imagePath) {
    RYGRuntimeArgumentKind kind = RYGIndexArgumentKind(method);
    if (kind < RYGRuntimeArgumentNone || kind > RYGRuntimeArgumentInteger) return nil;
    SEL selector = method_getName(method);
    const char *rawClass = class_getName(cls);
    if (!selector || !rawClass || !*rawClass) return nil;
    NSString *selectorName = NSStringFromSelector(selector) ?: @"";
    if ([RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]) return nil;

    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.imagePath = imagePath ?: @"";
    row.className = [NSString stringWithUTF8String:rawClass] ?: @"";
    row.selectorName = selectorName;
    row.classMethod = classMethod;
    row.argumentKind = kind;
    const char *types = method_getTypeEncoding(method);
    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    return row;
}

static RYGRuntimeImageIndex *RYGBuildIndex(NSString *imagePath) {
    NSDate *started = NSDate.date;
    NSString *canonical = RYGIndexCanonicalPath(imagePath);
    const struct mach_header *target = RYGIndexHeaderForPath(canonical);
    RYGRuntimeImageIndex *result = [RYGRuntimeImageIndex new];
    result.imagePath = canonical ?: @"";
    result.classes = @[];
    result.methodsByClass = @{};
    if (!target) return result;

    NSString *runtimeName = RYGIndexRuntimeNameForPath(canonical) ?: canonical;
    unsigned int imageClassCount = 0;
    const char **imageClassNames = objc_copyClassNamesForImage(runtimeName.fileSystemRepresentation, &imageClassCount);
    if (!imageClassNames || imageClassCount == 0 || imageClassCount > 500000) {
        if (imageClassNames) free(imageClassNames);
        return result;
    }

    NSMutableArray<RYGRuntimeClassRow *> *classRows = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *methodsByClass = [NSMutableDictionary dictionary];
    NSUInteger methodsScanned = 0;

    for (unsigned int classIndex = 0; classIndex < imageClassCount; classIndex++) {
        @autoreleasepool {
            const char *declaredName = imageClassNames[classIndex];
            if (!declaredName || !*declaredName) continue;
            Class cls = objc_lookUpClass(declaredName);
            if (!cls) continue;
            NSString *className = NSStringFromClass(cls);
            if (!className.length) continue;

            NSMutableArray<RYGRuntimeBoolMethod *> *rows = nil;
            NSUInteger instanceCount = 0, classCount = 0;
            for (NSUInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                methodsScanned += methodCount;
                for (unsigned int methodIndex = 0; methods && methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    if (!RYGIndexIMPBelongsToHeader(method, target)) continue;
                    RYGRuntimeBoolMethod *row = RYGIndexMethodRow(cls, method, classMethod, canonical);
                    if (!row) continue;
                    if (!rows) rows = [NSMutableArray array];
                    [rows addObject:row];
                    if (classMethod) classCount++; else instanceCount++;
                }
                if (methods) free(methods);
            }
            if (!rows.count) continue;
            [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
                if (left.classMethod != right.classMethod) return left.classMethod ? NSOrderedDescending : NSOrderedAscending;
                return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
            }];
            methodsByClass[className] = rows.copy;
            RYGRuntimeClassRow *classRow = [RYGRuntimeClassRow new];
            classRow.imagePath = canonical;
            classRow.className = className;
            classRow.instanceMethodCount = instanceCount;
            classRow.classMethodCount = classCount;
            classRow.propertyCount = 0;
            [classRows addObject:classRow];
        }
    }
    free(imageClassNames);

    [classRows sortUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    result.classes = classRows.copy;
    result.methodsByClass = methodsByClass.copy;
    result.classesScanned = imageClassCount;
    result.methodsScanned = methodsScanned;
    result.buildDuration = -[started timeIntervalSinceNow];
    return result;
}

@implementation RYGRuntimeIndex

+ (void)requestIndexForImagePath:(NSString *)imagePath completion:(RYGRuntimeIndexCompletion)completion {
    NSString *requested = [imagePath copy] ?: @"";
    dispatch_async(RYGIndexQueue(), ^{
        if (!gRYGIndexes) gRYGIndexes = [NSMutableDictionary dictionary];
        if (!gRYGIndexHeaders) gRYGIndexHeaders = [NSMutableDictionary dictionary];
        NSString *key = RYGIndexCanonicalPath(requested);
        const struct mach_header *header = RYGIndexHeaderForPath(key);
        NSValue *headerValue = header ? [NSValue valueWithPointer:header] : nil;
        RYGRuntimeImageIndex *index = gRYGIndexes[key];
        if (!index || ![gRYGIndexHeaders[key] isEqual:headerValue]) {
            index = RYGBuildIndex(requested);
            if (key.length && index && headerValue) {
                gRYGIndexes[key] = index;
                gRYGIndexHeaders[key] = headerValue;
            }
        }
        RYGRuntimeImageIndex *snapshot = index ?: [RYGRuntimeImageIndex new];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(snapshot); });
    });
}

+ (RYGRuntimeImageIndex *)cachedIndexForImagePath:(NSString *)imagePath {
    __block RYGRuntimeImageIndex *index = nil;
    NSString *key = RYGIndexCanonicalPath(imagePath);
    dispatch_sync(RYGIndexQueue(), ^{
        const struct mach_header *header = RYGIndexHeaderForPath(key);
        NSValue *current = header ? [NSValue valueWithPointer:header] : nil;
        if (current && [gRYGIndexHeaders[key] isEqual:current]) index = gRYGIndexes[key];
    });
    return index;
}

+ (void)invalidate {
    dispatch_async(RYGIndexQueue(), ^{
        [gRYGIndexes removeAllObjects];
        [gRYGIndexHeaders removeAllObjects];
    });
}

@end
