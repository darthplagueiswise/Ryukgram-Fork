#import "RYGRuntimeIndex.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif

typedef struct {
    uintptr_t start;
    uintptr_t end;
} RYGExecutableRange;

static dispatch_queue_t RYGProgressiveIndexQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ryukgram.runtime-index.progressive", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static NSMutableDictionary<NSString *, RYGRuntimeImageIndex *> *gRYGProgressiveIndexCache;
static atomic_uint_fast64_t gRYGProgressiveIndexGeneration = 1;

static NSString *RYGProgressiveCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGProgressiveDyldInfo(NSString *path,
                                   const struct mach_header **headerOut,
                                   intptr_t *slideOut,
                                   NSString **runtimePathOut) {
    NSString *wanted = RYGProgressiveCanonicalPath(path);
    if (!wanted.length) return NO;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *runtimePath = [NSString stringWithUTF8String:raw] ?: @"";
        if (![RYGProgressiveCanonicalPath(runtimePath) isEqualToString:wanted]) continue;
        if (headerOut) *headerOut = _dyld_get_image_header(index);
        if (slideOut) *slideOut = _dyld_get_image_vmaddr_slide(index);
        if (runtimePathOut) *runtimePathOut = runtimePath;
        return YES;
    }
    return NO;
}

static NSUInteger RYGProgressiveExecutableRanges(const struct mach_header *rawHeader,
                                                 intptr_t slide,
                                                 RYGExecutableRange *ranges,
                                                 NSUInteger capacity) {
    if (!rawHeader || rawHeader->magic != MH_MAGIC_64 || !ranges || capacity == 0) return 0;
    const struct mach_header_64 *header = (const struct mach_header_64 *)rawHeader;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    NSUInteger count = 0;
    for (uint32_t index = 0; index < header->ncmds && count < capacity; index++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command)) break;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if ((segment->initprot & VM_PROT_EXECUTE) && segment->vmsize &&
                segment->vmaddr <= UINTPTR_MAX - (uintptr_t)slide) {
                uintptr_t start = (uintptr_t)slide + (uintptr_t)segment->vmaddr;
                if ((uintptr_t)segment->vmsize <= UINTPTR_MAX - start) {
                    ranges[count++] = (RYGExecutableRange){ start, start + (uintptr_t)segment->vmsize };
                }
            }
        }
        cursor += command->cmdsize;
    }
    return count;
}

static uintptr_t RYGProgressiveIMPAddress(IMP imp) {
    if (!imp) return 0;
#if __has_feature(ptrauth_calls) && __has_include(<ptrauth.h>)
    return (uintptr_t)ptrauth_strip(imp, ptrauth_key_function_pointer);
#else
    return (uintptr_t)imp;
#endif
}

static BOOL RYGProgressiveIMPInRanges(IMP imp, const RYGExecutableRange *ranges, NSUInteger count) {
    uintptr_t address = RYGProgressiveIMPAddress(imp);
    if (!address) return NO;
    for (NSUInteger index = 0; index < count; index++) {
        if (address >= ranges[index].start && address < ranges[index].end) return YES;
    }
    return NO;
}

static const char *RYGProgressiveSkipQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGProgressiveBoolReturn(Method method) {
    if (!method) return NO;
    char encoded[64] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGProgressiveSkipQualifiers(encoded);
    return type && strchr("BcC", *type) != NULL;
}

static RYGRuntimeArgumentKind RYGProgressiveArgumentKind(Method method) {
    if (!method || !RYGProgressiveBoolReturn(method)) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[96] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGProgressiveSkipQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@') return RYGRuntimeArgumentObject;
    if (*type == 'q' || *type == 'Q') return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static RYGRuntimeBoolMethod *RYGProgressiveMethodRow(Class cls,
                                                     Method method,
                                                     BOOL classMethod,
                                                     NSString *imagePath) {
    RYGRuntimeArgumentKind kind = RYGProgressiveArgumentKind(method);
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

static RYGRuntimeImageIndex *RYGProgressiveSnapshot(NSString *path,
                                                    NSArray<RYGRuntimeClassRow *> *classes,
                                                    NSDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *methods,
                                                    NSUInteger classesScanned,
                                                    NSUInteger methodsScanned,
                                                    NSDate *started) {
    RYGRuntimeImageIndex *snapshot = [RYGRuntimeImageIndex new];
    snapshot.imagePath = path ?: @"";
    snapshot.classes = classes ?: @[];
    snapshot.methodsByClass = methods ?: @{};
    snapshot.classesScanned = classesScanned;
    snapshot.methodsScanned = methodsScanned;
    snapshot.buildDuration = started ? -[started timeIntervalSinceNow] : 0;
    return snapshot;
}

static void RYGProgressiveDeliver(RYGRuntimeIndexCompletion completion,
                                  RYGRuntimeImageIndex *snapshot,
                                  uint64_t token) {
    if (!completion || !snapshot) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (atomic_load_explicit(&gRYGProgressiveIndexGeneration, memory_order_relaxed) != token) return;
        completion(snapshot);
    });
}

static void RYGBuildProgressiveIndex(NSString *requested,
                                     uint64_t token,
                                     RYGRuntimeIndexCompletion completion) {
    NSString *canonical = RYGProgressiveCanonicalPath(requested);
    const struct mach_header *header = NULL;
    intptr_t slide = 0;
    NSString *runtimePath = nil;
    NSDate *started = NSDate.date;
    if (!RYGProgressiveDyldInfo(canonical, &header, &slide, &runtimePath) || !header) {
        RYGProgressiveDeliver(completion, RYGProgressiveSnapshot(canonical, @[], @{}, 0, 0, started), token);
        return;
    }

    RYGExecutableRange ranges[16] = {0};
    NSUInteger rangeCount = RYGProgressiveExecutableRanges(header, slide, ranges, 16);
    if (!rangeCount) {
        RYGProgressiveDeliver(completion, RYGProgressiveSnapshot(canonical, @[], @{}, 0, 0, started), token);
        return;
    }

    unsigned int imageClassCount = 0;
    const char **imageClassNames = objc_copyClassNamesForImage(runtimePath.fileSystemRepresentation, &imageClassCount);
    if (!imageClassNames || imageClassCount == 0 || imageClassCount > 500000) {
        if (imageClassNames) free(imageClassNames);
        RYGProgressiveDeliver(completion, RYGProgressiveSnapshot(canonical, @[], @{}, 0, 0, started), token);
        return;
    }

    NSMutableArray<RYGRuntimeClassRow *> *classRows = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *methodsByClass = [NSMutableDictionary dictionary];
    NSUInteger methodsScanned = 0;
    NSUInteger sincePublish = 0;
    CFAbsoluteTime lastPublish = CFAbsoluteTimeGetCurrent();

    for (unsigned int classIndex = 0; classIndex < imageClassCount; classIndex++) {
        if (atomic_load_explicit(&gRYGProgressiveIndexGeneration, memory_order_relaxed) != token) break;
        @autoreleasepool {
            const char *declaredName = imageClassNames[classIndex];
            if (!declaredName || !*declaredName) continue;
            Class cls = objc_lookUpClass(declaredName);
            if (!cls) continue;
            const char *rawClass = class_getName(cls);
            if (!rawClass || !*rawClass) continue;
            NSString *className = [NSString stringWithUTF8String:rawClass];
            if (!className.length) continue;

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
                    if (!RYGProgressiveBoolReturn(method)) continue;
                    if (!RYGProgressiveIMPInRanges(method_getImplementation(method), ranges, rangeCount)) continue;
                    RYGRuntimeBoolMethod *row = RYGProgressiveMethodRow(cls, method, classMethod, canonical);
                    if (!row) continue;
                    if (!rows) rows = [NSMutableArray array];
                    [rows addObject:row];
                    if (classMethod) classCount++; else instanceCount++;
                }
                if (methods) free(methods);
            }
            if (rows.count) {
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

        sincePublish++;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        BOOL firstChunk = classIndex >= 31 && lastPublish == 0;
        BOOL timedChunk = sincePublish >= 96 && (now - lastPublish) >= 0.10;
        if (classIndex == 31 || timedChunk) {
            NSArray *classes = [classRows sortedArrayUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
                return [left.className localizedCaseInsensitiveCompare:right.className];
            }];
            RYGRuntimeImageIndex *partial = RYGProgressiveSnapshot(canonical, classes, methodsByClass.copy, classIndex + 1, methodsScanned, started);
            RYGProgressiveDeliver(completion, partial, token);
            sincePublish = 0;
            lastPublish = now;
            (void)firstChunk;
        }
    }
    free(imageClassNames);

    if (atomic_load_explicit(&gRYGProgressiveIndexGeneration, memory_order_relaxed) != token) return;
    NSArray *classes = [classRows sortedArrayUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    RYGRuntimeImageIndex *finalIndex = RYGProgressiveSnapshot(canonical, classes, methodsByClass.copy, imageClassCount, methodsScanned, started);
    @synchronized(RYGRuntimeIndex.class) {
        if (!gRYGProgressiveIndexCache) gRYGProgressiveIndexCache = [NSMutableDictionary dictionary];
        if (canonical.length) gRYGProgressiveIndexCache[canonical] = finalIndex;
    }
    RYGProgressiveDeliver(completion, finalIndex, token);
}

@implementation RYGRuntimeIndex (RYGRuntimeIndexCompat)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method request = class_getClassMethod(self, @selector(requestIndexForImagePath:completion:));
        Method fastRequest = class_getClassMethod(self, @selector(ryg_progressive_requestIndexForImagePath:completion:));
        if (request && fastRequest) method_exchangeImplementations(request, fastRequest);

        Method cached = class_getClassMethod(self, @selector(cachedIndexForImagePath:));
        Method fastCached = class_getClassMethod(self, @selector(ryg_progressive_cachedIndexForImagePath:));
        if (cached && fastCached) method_exchangeImplementations(cached, fastCached);

        Method invalidate = class_getClassMethod(self, @selector(invalidate));
        Method fastInvalidate = class_getClassMethod(self, @selector(ryg_progressive_invalidate));
        if (invalidate && fastInvalidate) method_exchangeImplementations(invalidate, fastInvalidate);
    });
}

+ (void)ryg_progressive_requestIndexForImagePath:(NSString *)imagePath completion:(RYGRuntimeIndexCompletion)completion {
    NSString *canonical = RYGProgressiveCanonicalPath(imagePath ?: @"");
    RYGRuntimeImageIndex *cached = nil;
    @synchronized(self) { cached = gRYGProgressiveIndexCache[canonical]; }
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(cached); });
        return;
    }

    uint64_t token = atomic_fetch_add_explicit(&gRYGProgressiveIndexGeneration, 1, memory_order_relaxed) + 1;
    NSString *requested = [imagePath copy] ?: @"";
    RYGRuntimeIndexCompletion copiedCompletion = [completion copy];
    dispatch_async(RYGProgressiveIndexQueue(), ^{
        RYGBuildProgressiveIndex(requested, token, copiedCompletion);
    });
}

+ (RYGRuntimeImageIndex *)ryg_progressive_cachedIndexForImagePath:(NSString *)imagePath {
    NSString *canonical = RYGProgressiveCanonicalPath(imagePath ?: @"");
    RYGRuntimeImageIndex *index = nil;
    @synchronized(self) { index = gRYGProgressiveIndexCache[canonical]; }
    return index ?: [self ryg_progressive_cachedIndexForImagePath:imagePath];
}

+ (void)ryg_progressive_invalidate {
    atomic_fetch_add_explicit(&gRYGProgressiveIndexGeneration, 1, memory_order_relaxed);
    @synchronized(self) { [gRYGProgressiveIndexCache removeAllObjects]; }
    [self ryg_progressive_invalidate];
}

@end
