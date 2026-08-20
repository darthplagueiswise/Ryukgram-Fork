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

static NSMutableDictionary<NSString *, RYGRuntimeImageIndex *> *gRYGIndexes;
static uint32_t gRYGIndexDyldCount;

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

static BOOL RYGIndexClassBelongsToHeader(Class cls, const struct mach_header *target) {
    if (!cls || !target) return NO;
    const char *raw = class_getImageName(cls);
    if (!raw) return NO;
    NSString *runtimePath = [NSString stringWithUTF8String:raw];
    return RYGIndexHeaderForPath(runtimePath) == target;
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
    return type && *type == 'B';
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
    if (*type == 'q' || *type == 'Q') return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGIndexIMPBelongsToHeader(Method method, const struct mach_header *target) {
    IMP imp = method ? method_getImplementation(method) : NULL;
    if (!imp || !target) return NO;
    Dl_info info = {0};
    return dladdr((const void *)imp, &info) && info.dli_fbase == (const void *)target;
}

static RYGRuntimeBoolMethod *RYGIndexMethodRow(Class cls,
                                                Method method,
                                                BOOL classMethod,
                                                NSString *imagePath) {
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

    NSMutableArray<NSString *> *declaredNames = [NSMutableArray array];
    NSString *runtimeName = RYGIndexRuntimeNameForPath(imagePath) ?: imagePath;
    unsigned int imageClassCount = 0;
    const char **imageClassNames = objc_copyClassNamesForImage(runtimeName.fileSystemRepresentation, &imageClassCount);
    if (imageClassNames && imageClassCount > 0 && imageClassCount <= 500000) {
        for (unsigned int index = 0; index < imageClassCount; index++) {
            if (!imageClassNames[index] || !*imageClassNames[index]) continue;
            NSString *name = [NSString stringWithUTF8String:imageClassNames[index]];
            if (name.length) [declaredNames addObject:name];
        }
    }
    if (imageClassNames) free(imageClassNames);

    // Sideload paths can differ textually from dyld's registered image name.
    // If the direct API returns nothing, fall back to the runtime class list and
    // compare image headers rather than filesystem strings. This still runs only
    // on the serial utility queue.
    if (!declaredNames.count) {
        int total = objc_getClassList(NULL, 0);
        if (total <= 0 || total > 500000) return result;
        Class __unsafe_unretained *classes = (Class __unsafe_unretained *)calloc((size_t)total, sizeof(Class));
        if (!classes) return result;
        int filled = objc_getClassList(classes, total);
        for (int index = 0; index < filled; index++) {
            Class cls = classes[index];
            if (!RYGIndexClassBelongsToHeader(cls, target)) continue;
            const char *rawClass = class_getName(cls);
            if (!rawClass || !*rawClass) continue;
            NSString *name = [NSString stringWithUTF8String:rawClass];
            if (name.length) [declaredNames addObject:name];
        }
        free(classes);
    }

    if (!declaredNames.count) return result;
    NSOrderedSet<NSString *> *uniqueNames = [NSOrderedSet orderedSetWithArray:declaredNames];
    NSArray<NSString *> *orderedNames = [uniqueNames.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<RYGRuntimeClassRow *> *classRows = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *methodsByClass = [NSMutableDictionary dictionary];
    NSUInteger methodsScanned = 0;

    for (NSString *className in orderedNames) {
        @autoreleasepool {
            Class cls = objc_lookUpClass(className.UTF8String);
            if (!cls || !RYGIndexClassBelongsToHeader(cls, target)) continue;

            NSMutableArray<RYGRuntimeBoolMethod *> *rows = nil;
            NSUInteger instanceCount = 0;
            NSUInteger classCount = 0;
            for (NSUInteger pass = 0; pass < 2; pass++) {
                BOOL classMethod = pass == 1;
                Class owner = classMethod ? object_getClass(cls) : cls;
                unsigned int methodCount = 0;
                Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
                methodsScanned += methodCount;
                for (unsigned int methodIndex = 0; methods && methodIndex < methodCount; methodIndex++) {
                    Method method = methods[methodIndex];
                    if (!RYGIndexBoolReturn(method) || !RYGIndexIMPBelongsToHeader(method, target)) continue;
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
    [classRows sortUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    result.classes = classRows.copy;
    result.methodsByClass = methodsByClass.copy;
    result.classesScanned = orderedNames.count;
    result.methodsScanned = methodsScanned;
    result.buildDuration = -[started timeIntervalSinceNow];
    return result;
}

@implementation RYGRuntimeIndex

+ (void)requestIndexForImagePath:(NSString *)imagePath completion:(RYGRuntimeIndexCompletion)completion {
    NSString *requested = [imagePath copy] ?: @"";
    dispatch_async(RYGIndexQueue(), ^{
        uint32_t currentDyldCount = _dyld_image_count();
        if (!gRYGIndexes || gRYGIndexDyldCount != currentDyldCount) {
            gRYGIndexes = [NSMutableDictionary dictionary];
            gRYGIndexDyldCount = currentDyldCount;
        }
        NSString *key = RYGIndexCanonicalPath(requested);
        RYGRuntimeImageIndex *index = gRYGIndexes[key];
        if (!index) {
            index = RYGBuildIndex(requested);
            if (key.length && index) gRYGIndexes[key] = index;
        }
        RYGRuntimeImageIndex *snapshot = index ?: [RYGRuntimeImageIndex new];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(snapshot); });
    });
}

+ (RYGRuntimeImageIndex *)cachedIndexForImagePath:(NSString *)imagePath {
    __block RYGRuntimeImageIndex *index = nil;
    NSString *key = RYGIndexCanonicalPath(imagePath);
    dispatch_sync(RYGIndexQueue(), ^{
        if (gRYGIndexDyldCount == _dyld_image_count()) index = gRYGIndexes[key];
    });
    return index;
}

+ (void)invalidate {
    dispatch_async(RYGIndexQueue(), ^{
        [gRYGIndexes removeAllObjects];
        gRYGIndexDyldCount = _dyld_image_count();
    });
}

@end
