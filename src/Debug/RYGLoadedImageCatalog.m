#import "RYGLoadedImageCatalog.h"
#import <mach-o/dyld.h>
#import <crt_externs.h>
#import <stdatomic.h>

@implementation RYGLoadedImageRecord
@end

static atomic_uint_fast64_t gRYGLoadedImageGeneration = 1;
static uint64_t gRYGLoadedImageCachedGeneration;
static NSArray<RYGLoadedImageRecord *> *gRYGLoadedImageSnapshot;
static NSDictionary<NSString *, RYGLoadedImageRecord *> *gRYGLoadedImageByPath;
static NSDictionary<NSString *, RYGLoadedImageRecord *> *gRYGLoadedImageByStableID;

static NSString *RYGLoadedImageCleanPath(NSString *path) {
    return path.length ? path.stringByStandardizingPath : @"";
}

static void RYGLoadedImageDidChange(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    // dyld callbacks can run while loader state is sensitive. Never allocate
    // Objective-C objects here; only invalidate the next ordinary snapshot.
    atomic_fetch_add_explicit(&gRYGLoadedImageGeneration, 1, memory_order_relaxed);
}

static NSString *RYGLoadedImageStableID(NSString *path, NSString *bundlePath, NSString *executablePath) {
    NSString *clean = RYGLoadedImageCleanPath(path);
    if (!clean.length) return @"";
    if ([clean isEqualToString:executablePath]) return @"@executable";
    NSString *prefix = [bundlePath stringByAppendingString:@"/"];
    if ([clean hasPrefix:prefix]) return [clean substringFromIndex:prefix.length];
    return clean.lastPathComponent ?: @"";
}

static NSArray<RYGLoadedImageRecord *> *RYGBuildLoadedImageSnapshot(void) {
    NSString *bundlePath = RYGLoadedImageCleanPath(NSBundle.mainBundle.bundlePath);
    NSString *executablePath = RYGLoadedImageCleanPath(NSBundle.mainBundle.executablePath);
    NSString *bundlePrefix = [bundlePath stringByAppendingString:@"/"];
    const struct mach_header *mainHeader = _NSGetMachExecuteHeader();

    NSMutableArray<RYGLoadedImageRecord *> *records = [NSMutableArray array];
    NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        const char *raw = _dyld_get_image_name(index);
        const struct mach_header *header = _dyld_get_image_header(index);
        if (!raw || !header) continue;
        NSString *path = RYGLoadedImageCleanPath([NSString stringWithUTF8String:raw]);
        if (!path.length || [seenPaths containsObject:path]) continue;

        BOOL main = header == mainHeader || [path isEqualToString:executablePath];
        BOOL bundled = [path hasPrefix:bundlePrefix];
        if (!main && !bundled) continue;

        [seenPaths addObject:path];
        RYGLoadedImageRecord *record = [RYGLoadedImageRecord new];
        record.path = path;
        record.header = header;
        record.slide = _dyld_get_image_vmaddr_slide(index);
        record.mainExecutable = main;
        record.stableIdentifier = RYGLoadedImageStableID(path, bundlePath, executablePath);
        record.displayName = main ? (NSBundle.mainBundle.executablePath.lastPathComponent ?: @"Executable")
                                  : (path.lastPathComponent ?: @"Image");
        [records addObject:record];
    }

    [records sortUsingComparator:^NSComparisonResult(RYGLoadedImageRecord *left, RYGLoadedImageRecord *right) {
        if (left.isMainExecutable != right.isMainExecutable) return left.isMainExecutable ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult byName = [left.displayName localizedCaseInsensitiveCompare:right.displayName];
        return byName == NSOrderedSame ? [left.stableIdentifier compare:right.stableIdentifier] : byName;
    }];
    return records.copy;
}

@implementation RYGLoadedImageCatalog

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _dyld_register_func_for_add_image(RYGLoadedImageDidChange);
        _dyld_register_func_for_remove_image(RYGLoadedImageDidChange);
    });
}

+ (NSArray<RYGLoadedImageRecord *> *)bundledImages {
    uint64_t generation = atomic_load_explicit(&gRYGLoadedImageGeneration, memory_order_relaxed);
    @synchronized(self) {
        if (gRYGLoadedImageSnapshot && gRYGLoadedImageCachedGeneration == generation) return gRYGLoadedImageSnapshot;

        NSArray<RYGLoadedImageRecord *> *snapshot = RYGBuildLoadedImageSnapshot();
        NSMutableDictionary *byPath = [NSMutableDictionary dictionaryWithCapacity:snapshot.count];
        NSMutableDictionary *byID = [NSMutableDictionary dictionaryWithCapacity:snapshot.count];
        for (RYGLoadedImageRecord *record in snapshot) {
            if (record.path.length) byPath[record.path] = record;
            if (record.stableIdentifier.length) byID[record.stableIdentifier.lowercaseString] = record;
        }
        gRYGLoadedImageSnapshot = snapshot;
        gRYGLoadedImageByPath = byPath.copy;
        gRYGLoadedImageByStableID = byID.copy;
        gRYGLoadedImageCachedGeneration = generation;
        return gRYGLoadedImageSnapshot;
    }
}

+ (RYGLoadedImageRecord *)recordForPath:(NSString *)path {
    NSString *clean = RYGLoadedImageCleanPath(path);
    if (!clean.length) return nil;
    (void)[self bundledImages];
    @synchronized(self) { return gRYGLoadedImageByPath[clean]; }
}

+ (RYGLoadedImageRecord *)recordForStableIdentifier:(NSString *)identifier {
    if (!identifier.length) return nil;
    (void)[self bundledImages];
    @synchronized(self) { return gRYGLoadedImageByStableID[identifier.lowercaseString]; }
}

+ (RYGLoadedImageRecord *)mainExecutableRecord {
    for (RYGLoadedImageRecord *record in [self bundledImages]) if (record.isMainExecutable) return record;
    return nil;
}

+ (NSString *)stableIdentifierForPath:(NSString *)path {
    RYGLoadedImageRecord *record = [self recordForPath:path];
    if (record.stableIdentifier.length) return record.stableIdentifier;
    NSString *bundlePath = RYGLoadedImageCleanPath(NSBundle.mainBundle.bundlePath);
    NSString *executablePath = RYGLoadedImageCleanPath(NSBundle.mainBundle.executablePath);
    return RYGLoadedImageStableID(path, bundlePath, executablePath);
}

+ (void)invalidate {
    atomic_fetch_add_explicit(&gRYGLoadedImageGeneration, 1, memory_order_relaxed);
}

@end
