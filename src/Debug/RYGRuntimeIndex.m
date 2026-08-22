#import "RYGRuntimeIndex.h"
#import "RYGLoadedImageCatalog.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

@implementation RYGRuntimeImageIndex
- (NSArray<RYGRuntimeBoolMethod *> *)methodsForClassName:(NSString *)className {
    return self.methodsByClass[className] ?: @[];
}
@end

static dispatch_queue_t RYGIndexStateQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ queue = dispatch_queue_create("com.ryukgram.runtime-index.state", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static dispatch_queue_t RYGIndexWorkerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ queue = dispatch_queue_create("com.ryukgram.runtime-index.worker", DISPATCH_QUEUE_CONCURRENT); });
    return queue;
}

static NSMutableDictionary<NSString *, RYGRuntimeImageIndex *> *gRYGIndexes;
static NSMutableDictionary<NSString *, NSMutableArray<RYGRuntimeIndexCompletion> *> *gRYGIndexListeners;
static NSMutableSet<NSString *> *gRYGIndexInFlight;
static NSMutableSet<NSString *> *gRYGIndexComplete;
static NSMutableDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *gRYGMethodCache;
static NSMutableSet<NSString *> *gRYGMethodInFlight;
static NSMutableDictionary<NSString *, NSMutableArray<RYGRuntimeMethodsCompletion> *> *gRYGMethodListeners;
static atomic_uint_fast64_t gRYGIndexEpoch = 1;
static atomic_uint_fast64_t gRYGSearchEpoch = 1;

static NSString *RYGIndexKeyForPath(NSString *path) {
    RYGLoadedImageRecord *record = [RYGLoadedImageCatalog recordForPath:path];
    if (record.stableIdentifier.length) return record.stableIdentifier;
    return path.length ? path.stringByStandardizingPath : @"";
}

static NSString *RYGMethodCacheKey(NSString *imageKey, NSString *className) {
    return [NSString stringWithFormat:@"%@|%@", imageKey ?: @"", className ?: @""];
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
    return type && strchr("BcC", *type) != NULL;
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

static RYGRuntimeClassRow *RYGIndexClassRow(NSString *className,
                                             NSString *imagePath,
                                             NSUInteger instanceCount,
                                             NSUInteger classCount) {
    RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
    row.imagePath = imagePath ?: @"";
    row.className = className ?: @"";
    row.instanceMethodCount = instanceCount;
    row.classMethodCount = classCount;
    row.propertyCount = 0;
    return row;
}

static RYGRuntimeImageIndex *RYGIndexSnapshot(NSString *imagePath,
                                               NSArray<RYGRuntimeClassRow *> *classes,
                                               NSDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *methods,
                                               NSUInteger classesScanned,
                                               NSUInteger methodsScanned,
                                               NSTimeInterval duration) {
    RYGRuntimeImageIndex *snapshot = [RYGRuntimeImageIndex new];
    snapshot.imagePath = imagePath ?: @"";
    snapshot.classes = classes.copy ?: @[];
    snapshot.methodsByClass = methods.copy ?: @{};
    snapshot.classesScanned = classesScanned;
    snapshot.methodsScanned = methodsScanned;
    snapshot.buildDuration = duration;
    return snapshot;
}

static NSArray<NSString *> *RYGIndexQueryGroups(NSString *query) {
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    for (NSString *piece in [query.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (piece.length) [groups addObject:piece];
    }
    return groups.copy;
}

static BOOL RYGIndexTextMatchesGroups(NSString *text, NSArray<NSString *> *groups) {
    if (!groups.count) return YES;
    NSString *lower = text.lowercaseString ?: @"";
    NSString *compact = [[lower componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
    for (NSString *group in groups) {
        BOOL matched = NO;
        for (NSString *alternative in [group componentsSeparatedByString:@"|"]) {
            if (!alternative.length) continue;
            NSString *compactAlt = [[alternative componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
            if ([lower rangeOfString:alternative].location != NSNotFound ||
                (compactAlt.length && [compact rangeOfString:compactAlt].location != NSNotFound)) {
                matched = YES;
                break;
            }
        }
        if (!matched) return NO;
    }
    return YES;
}

static NSArray<RYGRuntimeBoolMethod *> *RYGScanMethodsForClass(NSString *className,
                                                                RYGLoadedImageRecord *record,
                                                                NSUInteger *scannedOut) {
    if (!className.length || !record.header) return @[];
    Class cls = objc_lookUpClass(className.UTF8String);
    if (!cls) return @[];

    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSUInteger scanned = 0;
    for (NSUInteger pass = 0; pass < 2; pass++) {
        BOOL classMethod = pass == 1;
        Class owner = classMethod ? object_getClass(cls) : cls;
        unsigned int count = 0;
        Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
        scanned += count;
        for (unsigned int index = 0; methods && index < count; index++) {
            Method method = methods[index];
            if (!RYGIndexBoolReturn(method)) continue;
            if (RYGIndexArgumentKind(method) < RYGRuntimeArgumentNone) continue;
            SEL selector = method_getName(method);
            NSString *name = selector ? NSStringFromSelector(selector) : @"";
            if ([RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:name]) continue;
            if (!RYGIndexIMPBelongsToHeader(method, record.header)) continue;
            RYGRuntimeBoolMethod *row = RYGIndexMethodRow(cls, method, classMethod, record.path);
            if (row) [rows addObject:row];
        }
        if (methods) free(methods);
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        if (left.classMethod != right.classMethod) return left.classMethod ? NSOrderedDescending : NSOrderedAscending;
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    if (scannedOut) *scannedOut = scanned;
    return rows.copy;
}

@implementation RYGRuntimeIndex

+ (void)requestIndexForImagePath:(NSString *)imagePath completion:(RYGRuntimeIndexCompletion)completion {
    NSString *path = [imagePath copy] ?: @"";
    NSString *key = RYGIndexKeyForPath(path);
    if (!key.length) {
        RYGRuntimeImageIndex *empty = RYGIndexSnapshot(@"", @[], @{}, 0, 0, 0);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(empty); });
        return;
    }

    uint64_t epoch = atomic_load_explicit(&gRYGIndexEpoch, memory_order_relaxed);
    dispatch_async(RYGIndexStateQueue(), ^{
        if (!gRYGIndexes) gRYGIndexes = [NSMutableDictionary dictionary];
        if (!gRYGIndexListeners) gRYGIndexListeners = [NSMutableDictionary dictionary];
        if (!gRYGIndexInFlight) gRYGIndexInFlight = [NSMutableSet set];
        if (!gRYGIndexComplete) gRYGIndexComplete = [NSMutableSet set];

        RYGRuntimeImageIndex *cached = gRYGIndexes[key];
        if (cached && completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        if ([gRYGIndexComplete containsObject:key]) return;

        if (completion) {
            NSMutableArray *listeners = gRYGIndexListeners[key];
            if (!listeners) { listeners = [NSMutableArray array]; gRYGIndexListeners[key] = listeners; }
            [listeners addObject:[completion copy]];
        }
        if ([gRYGIndexInFlight containsObject:key]) return;
        [gRYGIndexInFlight addObject:key];

        if (!cached) {
            RYGRuntimeImageIndex *bootstrap = RYGIndexSnapshot(path, @[], @{}, 0, 0, 0);
            gRYGIndexes[key] = bootstrap;
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(bootstrap); });
        }

        dispatch_async(RYGIndexWorkerQueue(), ^{
            @autoreleasepool {
                NSDate *started = NSDate.date;
                RYGLoadedImageRecord *record = [RYGLoadedImageCatalog recordForPath:path];
                NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray array];
                if (record) {
                    unsigned int count = 0;
                    const char **names = objc_copyClassNamesForImage(record.path.fileSystemRepresentation, &count);
                    if (names && count < 500000) {
                        NSMutableArray<NSString *> *classNames = [NSMutableArray arrayWithCapacity:count];
                        for (unsigned int index = 0; index < count; index++) {
                            const char *raw = names[index];
                            if (!raw || !*raw) continue;
                            NSString *name = [NSString stringWithUTF8String:raw];
                            if (name.length) [classNames addObject:name];
                        }
                        [classNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
                        for (NSString *name in classNames) [rows addObject:RYGIndexClassRow(name, record.path, 0, 0)];
                    }
                    if (names) free(names);
                }
                RYGRuntimeImageIndex *snapshot = RYGIndexSnapshot(record.path ?: path,
                                                                  rows,
                                                                  @{},
                                                                  rows.count,
                                                                  0,
                                                                  -started.timeIntervalSinceNow);
                dispatch_async(RYGIndexStateQueue(), ^{
                    if (atomic_load_explicit(&gRYGIndexEpoch, memory_order_relaxed) != epoch) return;
                    gRYGIndexes[key] = snapshot;
                    [gRYGIndexInFlight removeObject:key];
                    [gRYGIndexComplete addObject:key];
                    NSArray *listeners = [gRYGIndexListeners[key] copy] ?: @[];
                    [gRYGIndexListeners removeObjectForKey:key];
                    dispatch_async(dispatch_get_main_queue(), ^{ for (RYGRuntimeIndexCompletion block in listeners) if (block) block(snapshot); });
                });
            }
        });
    });
}

+ (void)requestMethodsForClassName:(NSString *)className
                         imagePath:(NSString *)imagePath
                        completion:(RYGRuntimeMethodsCompletion)completion {
    NSString *path = [imagePath copy] ?: @"";
    NSString *imageKey = RYGIndexKeyForPath(path);
    NSString *cacheKey = RYGMethodCacheKey(imageKey, className);
    if (!imageKey.length || !className.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[]); });
        return;
    }

    dispatch_async(RYGIndexStateQueue(), ^{
        if (!gRYGMethodCache) gRYGMethodCache = [NSMutableDictionary dictionary];
        if (!gRYGMethodInFlight) gRYGMethodInFlight = [NSMutableSet set];
        if (!gRYGMethodListeners) gRYGMethodListeners = [NSMutableDictionary dictionary];
        NSArray *cached = gRYGMethodCache[cacheKey];
        if (cached) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(cached); });
            return;
        }
        if (completion) {
            NSMutableArray *listeners = gRYGMethodListeners[cacheKey];
            if (!listeners) { listeners = [NSMutableArray array]; gRYGMethodListeners[cacheKey] = listeners; }
            [listeners addObject:[completion copy]];
        }
        if ([gRYGMethodInFlight containsObject:cacheKey]) return;
        [gRYGMethodInFlight addObject:cacheKey];

        dispatch_async(RYGIndexWorkerQueue(), ^{
            @autoreleasepool {
                RYGLoadedImageRecord *record = [RYGLoadedImageCatalog recordForPath:path];
                NSUInteger scanned = 0;
                NSArray *methods = record ? RYGScanMethodsForClass(className, record, &scanned) : @[];
                dispatch_async(RYGIndexStateQueue(), ^{
                    if (!gRYGMethodCache) gRYGMethodCache = [NSMutableDictionary dictionary];
                    gRYGMethodCache[cacheKey] = methods;
                    [gRYGMethodInFlight removeObject:cacheKey];
                    NSArray *listeners = [gRYGMethodListeners[cacheKey] copy] ?: @[];
                    [gRYGMethodListeners removeObjectForKey:cacheKey];

                    RYGRuntimeImageIndex *current = gRYGIndexes[imageKey];
                    if (current) {
                        NSMutableDictionary *byClass = [current.methodsByClass mutableCopy] ?: [NSMutableDictionary dictionary];
                        byClass[className] = methods;
                        NSMutableArray *classes = [current.classes mutableCopy] ?: [NSMutableArray array];
                        NSUInteger instanceCount = 0, classCount = 0;
                        for (RYGRuntimeBoolMethod *row in methods) {
                            if (row.classMethod) classCount++; else instanceCount++;
                        }
                        for (NSUInteger index = 0; index < classes.count; index++) {
                            RYGRuntimeClassRow *row = classes[index];
                            if ([row.className isEqualToString:className]) {
                                classes[index] = RYGIndexClassRow(className, current.imagePath, instanceCount, classCount);
                                break;
                            }
                        }
                        gRYGIndexes[imageKey] = RYGIndexSnapshot(current.imagePath, classes, byClass,
                                                                 current.classesScanned,
                                                                 current.methodsScanned + scanned,
                                                                 current.buildDuration);
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{ for (RYGRuntimeMethodsCompletion block in listeners) if (block) block(methods); });
                });
            }
        });
    });
}

+ (void)requestSearchForImagePath:(NSString *)imagePath
                            query:(NSString *)query
                       completion:(RYGRuntimeSearchCompletion)completion {
    NSString *path = [imagePath copy] ?: @"";
    NSArray<NSString *> *groups = RYGIndexQueryGroups(query ?: @"");
    uint64_t searchEpoch = atomic_fetch_add_explicit(&gRYGSearchEpoch, 1, memory_order_relaxed) + 1;
    if (!path.length || !groups.count) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[], 0, 0, YES); });
        return;
    }

    dispatch_async(RYGIndexWorkerQueue(), ^{
        @autoreleasepool {
            RYGLoadedImageRecord *record = [RYGLoadedImageCatalog recordForPath:path];
            if (!record) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[], 0, 0, YES); });
                return;
            }
            unsigned int classCount = 0;
            const char **names = objc_copyClassNamesForImage(record.path.fileSystemRepresentation, &classCount);
            if (!names || classCount >= 500000) {
                if (names) free(names);
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(@[], 0, 0, YES); });
                return;
            }

            NSMutableArray<RYGRuntimeBoolMethod *> *matches = [NSMutableArray array];
            NSUInteger classesScanned = 0, methodsScanned = 0;
            const NSUInteger publishEvery = 96;
            for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
                if (atomic_load_explicit(&gRYGSearchEpoch, memory_order_relaxed) != searchEpoch) break;
                @autoreleasepool {
                    const char *raw = names[classIndex];
                    if (!raw || !*raw) { classesScanned++; continue; }
                    Class cls = objc_lookUpClass(raw);
                    if (!cls) { classesScanned++; continue; }
                    for (NSUInteger pass = 0; pass < 2; pass++) {
                        BOOL classMethod = pass == 1;
                        Class owner = classMethod ? object_getClass(cls) : cls;
                        unsigned int count = 0;
                        Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
                        methodsScanned += count;
                        for (unsigned int methodIndex = 0; methods && methodIndex < count; methodIndex++) {
                            Method method = methods[methodIndex];
                            if (!RYGIndexBoolReturn(method) || RYGIndexArgumentKind(method) < RYGRuntimeArgumentNone) continue;
                            SEL selector = method_getName(method);
                            NSString *selectorName = selector ? NSStringFromSelector(selector) : @"";
                            if ([RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]) continue;
                            NSString *className = [NSString stringWithUTF8String:raw] ?: @"";
                            NSString *haystack = [NSString stringWithFormat:@"%@ %@", className, selectorName];
                            if (!RYGIndexTextMatchesGroups(haystack, groups)) continue;
                            if (!RYGIndexIMPBelongsToHeader(method, record.header)) continue;
                            RYGRuntimeBoolMethod *row = RYGIndexMethodRow(cls, method, classMethod, record.path);
                            if (row) [matches addObject:row];
                        }
                        if (methods) free(methods);
                    }
                    classesScanned++;
                }
                if ((classesScanned % publishEvery) == 0 && completion) {
                    NSArray *snapshot = matches.copy;
                    NSUInteger c = classesScanned, m = methodsScanned;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (atomic_load_explicit(&gRYGSearchEpoch, memory_order_relaxed) == searchEpoch) completion(snapshot, c, m, NO);
                    });
                }
            }
            free(names);
            if (atomic_load_explicit(&gRYGSearchEpoch, memory_order_relaxed) != searchEpoch) return;
            [matches sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
                NSComparisonResult byClass = [left.className localizedCaseInsensitiveCompare:right.className];
                if (byClass != NSOrderedSame) return byClass;
                if (left.classMethod != right.classMethod) return left.classMethod ? NSOrderedDescending : NSOrderedAscending;
                return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
            }];
            NSArray *finalMatches = matches.copy;
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(finalMatches, classesScanned, methodsScanned, YES); });
        }
    });
}

+ (void)cancelActiveSearch {
    atomic_fetch_add_explicit(&gRYGSearchEpoch, 1, memory_order_relaxed);
}

+ (RYGRuntimeImageIndex *)cachedIndexForImagePath:(NSString *)imagePath {
    __block RYGRuntimeImageIndex *index = nil;
    NSString *key = RYGIndexKeyForPath(imagePath);
    dispatch_sync(RYGIndexStateQueue(), ^{ index = gRYGIndexes[key]; });
    return index;
}

+ (void)invalidate {
    atomic_fetch_add_explicit(&gRYGIndexEpoch, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&gRYGSearchEpoch, 1, memory_order_relaxed);
    dispatch_async(RYGIndexStateQueue(), ^{
        [gRYGIndexes removeAllObjects];
        [gRYGIndexListeners removeAllObjects];
        [gRYGIndexInFlight removeAllObjects];
        [gRYGIndexComplete removeAllObjects];
        [gRYGMethodCache removeAllObjects];
        [gRYGMethodInFlight removeAllObjects];
        [gRYGMethodListeners removeAllObjects];
    });
}

@end
