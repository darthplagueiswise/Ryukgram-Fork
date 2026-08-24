#import "RYGDeveloperFeatureCatalog.h"
#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#include <stdlib.h>
#include <string.h>

NSNotificationName const RYGDeveloperFeatureCatalogDidUpdateNotification = @"RYGDeveloperFeatureCatalogDidUpdateNotification";
NSString *const RYGDeveloperFeatureCatalogSurfaceUserInfoKey = @"surface";

static atomic_uint_fast64_t gImageGeneration = 1;
static void RYGImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    atomic_fetch_add_explicit(&gImageGeneration, 1, memory_order_relaxed);
}

static const char *RYGSkipQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    char ret[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    const char *returnType = RYGSkipQualifiers(ret);
    if (!returnType || !strchr("BcC", *returnType)) return (RYGRuntimeArgumentKind)-1;

    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;

    char arg[64] = {0};
    method_getArgumentType(method, 2, arg, sizeof(arg));
    const char *argumentType = RYGSkipQualifiers(arg);
    if (argumentType && *argumentType == '@') return RYGRuntimeArgumentObject;
    if (argumentType && strchr("qQiIlLsScC", *argumentType)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static NSArray<NSString *> *RYGKnownOwners(RYGDeveloperRuntimeSurface surface) {
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism:
            return @[@"IGDSLauncherConfig", @"_TtC11BSLDSConfig11BSLDSConfig", @"BSLDSConfig.BSLDSConfig"];
        case RYGDeveloperRuntimeSurfaceLiquidGlass:
            return @[@"_TtC20IGLiquidGlassSwizzle26IGLiquidGlassSwizzleToggle",
                     @"_TtC29IGLiquidGlassExperimentHelper33IGThrowbackChromeExperimentHelper",
                     @"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper"];
        case RYGDeveloperRuntimeSurfaceStories:
            return @[@"_TtC27IGPersistentStoryTrayGating38IGPersistentStoryTrayGatingStaticFuncs",
                     @"_TtC18IGNavConfiguration25IGHomecomingConfiguration",
                     @"_TtC38IGStoryViewerRedesignExperimentHelpers38IGStoryViewerRedesignExperimentHelpers"];
        case RYGDeveloperRuntimeSurfaceConsumerSubs:
            return @[@"_TtC21IGConsumerSubsService21IGConsumerSubsService", @"IGConsumerSubsService.IGConsumerSubsService"];
        case RYGDeveloperRuntimeSurfaceBugReport:
            return @[@"_TtC17IGBugReporterMenu29IGBugReportMenuViewController"];
        case RYGDeveloperRuntimeSurfaceDirectDogfood:
            return @[@"_TtC20IGDogfoodingSettings20IGDogfoodingSettings", @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"];
        default:
            return @[];
    }
}

static NSArray<NSString *> *RYGClassTokens(RYGDeveloperRuntimeSurface surface) {
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism: return @[@"prism", @"igds", @"bslds", @"wordmark"];
        case RYGDeveloperRuntimeSurfaceLiquidGlass: return @[@"liquidglass", @"throwback", @"glass"];
        case RYGDeveloperRuntimeSurfaceStories: return @[@"storytray", @"storiestray", @"storygrid", @"storiesgrid", @"homecoming"];
        case RYGDeveloperRuntimeSurfaceConsumerSubs: return @[@"consumersubs", @"igplus", @"aura", @"subscription"];
        case RYGDeveloperRuntimeSurfaceInternalOnly: return @[@"internalonly", @"igonly", @"employee"];
        case RYGDeveloperRuntimeSurfaceDirectDogfood: return @[@"dogfood", @"dogfooding"];
        case RYGDeveloperRuntimeSurfaceBugReport: return @[@"bugreport", @"bugreporter", @"sandbox"];
        case RYGDeveloperRuntimeSurfaceSettingsRows: return @[@"settings", @"setting"];
    }
    return @[];
}

static NSArray<NSString *> *RYGSelectorTokens(RYGDeveloperRuntimeSurface surface) {
    switch (surface) {
        case RYGDeveloperRuntimeSurfacePrism: return @[@"prism", @"wordmark", @"redesign", @"design"];
        case RYGDeveloperRuntimeSurfaceLiquidGlass: return @[@"glass", @"throwback", @"chrome", @"navigation"];
        case RYGDeveloperRuntimeSurfaceStories: return @[@"story", @"tray", @"grid", @"homecoming"];
        case RYGDeveloperRuntimeSurfaceConsumerSubs: return @[@"aura", @"plus", @"subscription", @"benefit"];
        case RYGDeveloperRuntimeSurfaceInternalOnly: return @[@"internal", @"employee", @"hidden", @"debug"];
        case RYGDeveloperRuntimeSurfaceDirectDogfood: return @[@"dogfood", @"assistant", @"internal"];
        case RYGDeveloperRuntimeSurfaceBugReport: return @[@"bug", @"report", @"sandbox", @"loggedout", @"internal"];
        case RYGDeveloperRuntimeSurfaceSettingsRows: return @[@"hidden", @"hide", @"show", @"visible", @"available", @"display"];
    }
    return @[];
}

static BOOL RYGHasToken(NSString *value, NSArray<NSString *> *tokens) {
    NSString *lower = value.lowercaseString ?: @"";
    for (NSString *token in tokens) if ([lower containsString:token]) return YES;
    return NO;
}

static BOOL RYGStructuralNoise(NSString *selector) {
    if (!selector.length || [RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selector]) return YES;
    NSString *lower = selector.lowercaseString;
    static NSArray<NSString *> *fragments;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fragments = @[@"canrespond", @"respondstoselector", @"isequal", @"iskindofclass",
                      @"ismemberofclass", @"conformstoprotocol", @"methodforselector",
                      @"debugdescription", @"description", @"retaincount", @"copywithzone",
                      @"mutablecopywithzone", @"canperformaction"];
    });
    for (NSString *fragment in fragments) if ([lower containsString:fragment]) return YES;
    return NO;
}

static BOOL RYGPathBelongsToApp(NSString *path) {
    if (!path.length) return NO;
    NSString *standard = path.stringByStandardizingPath;
    NSString *bundle = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    return [standard isEqualToString:executable] || [standard hasPrefix:[bundle stringByAppendingString:@"/"]];
}

static BOOL RYGAppClass(Class cls) {
    const char *raw = cls ? class_getImageName(cls) : NULL;
    if (!raw) return NO;
    return RYGPathBelongsToApp([NSString stringWithUTF8String:raw]);
}

static void RYGScanClass(Class cls, RYGDeveloperRuntimeSurface surface, NSMutableDictionary<NSString *, RYGRuntimeBoolMethod *> *out) {
    if (!RYGAppClass(cls)) return;
    NSString *className = NSStringFromClass(cls) ?: @"";
    BOOL classHit = RYGHasToken(className, RYGClassTokens(surface));

    for (NSUInteger pass = 0; pass < 2; pass++) {
        Class owner = pass ? object_getClass(cls) : cls;
        unsigned int count = 0;
        Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
        for (unsigned int i = 0; methods && i < count; i++) {
            RYGRuntimeArgumentKind kind = RYGArgumentKind(methods[i]);
            if (kind < 0) continue;
            NSString *selector = NSStringFromSelector(method_getName(methods[i])) ?: @"";
            if (RYGStructuralNoise(selector)) continue;
            BOOL selectorHit = RYGHasToken(selector, RYGSelectorTokens(surface));
            if (!selectorHit && !(classHit && RYGHasToken(selector, @[@"enabled", @"available", @"visible", @"hidden", @"show", @"internal", @"debug", @"experiment"]))) continue;

            RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
            row.className = className;
            row.selectorName = selector;
            row.classMethod = pass != 0;
            row.argumentKind = kind;
            const char *encoding = method_getTypeEncoding(methods[i]);
            row.typeEncoding = encoding ? [NSString stringWithUTF8String:encoding] : @"";
            const char *image = class_getImageName(cls);
            row.imagePath = image ? [NSString stringWithUTF8String:image] : @"";
            NSString *identity = [NSString stringWithFormat:@"%@|%@|%c|%@|%@", row.imagePath, row.className, row.classMethod ? '+' : '-', row.selectorName, row.typeEncoding];
            out[identity] = row;
        }
        if (methods) free(methods);
    }
}

static void RYGScanLoadedAppClassesForSurface(RYGDeveloperRuntimeSurface surface, NSMutableDictionary *rows) {
    NSArray<NSString *> *tokens = RYGClassTokens(surface);
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const char *rawPath = _dyld_get_image_name(imageIndex);
        if (!rawPath) continue;
        NSString *path = [NSString stringWithUTF8String:rawPath];
        if (!RYGPathBelongsToApp(path)) continue;

        unsigned int classCount = 0;
        const char **names = objc_copyClassNamesForImage(rawPath, &classCount);
        for (unsigned int classIndex = 0; names && classIndex < classCount; classIndex++) {
            const char *name = names[classIndex];
            if (!name) continue;
            NSString *className = [NSString stringWithUTF8String:name];
            if (!RYGHasToken(className, tokens)) continue;
            Class cls = objc_lookUpClass(name);
            if (cls) RYGScanClass(cls, surface, rows);
        }
        if (names) free(names);
    }
}

@interface RYGDeveloperFeatureCatalog () {
    dispatch_queue_t _queue;
    BOOL _started;
    NSMutableDictionary<NSNumber *, NSArray *> *_snapshots;
    NSMutableDictionary<NSNumber *, NSNumber *> *_generations;
    NSMutableDictionary<NSNumber *, NSNumber *> *_fullGenerations;
    NSMutableSet<NSNumber *> *_busy;
}
@end

@implementation RYGDeveloperFeatureCatalog

+ (instancetype)sharedCatalog {
    static RYGDeveloperFeatureCatalog *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ catalog = [self new]; });
    return catalog;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.ryukgram.devcatalog", DISPATCH_QUEUE_SERIAL);
        _snapshots = [NSMutableDictionary dictionary];
        _generations = [NSMutableDictionary dictionary];
        _fullGenerations = [NSMutableDictionary dictionary];
        _busy = [NSMutableSet set];
    }
    return self;
}

- (void)startIfNeeded {
    @synchronized (self) {
        if (_started) return;
        _started = YES;
    }
    _dyld_register_func_for_add_image(RYGImageAdded);
}

- (void)prewarmKnownOwners {
    [self startIfNeeded];
    for (NSInteger value = RYGDeveloperRuntimeSurfacePrism; value <= RYGDeveloperRuntimeSurfaceSettingsRows; value++) {
        [self requestRefreshForSurface:(RYGDeveloperRuntimeSurface)value discoverAdditionalClasses:NO];
    }
}

- (NSArray<RYGRuntimeBoolMethod *> *)snapshotForSurface:(RYGDeveloperRuntimeSurface)surface {
    @synchronized (self) { return _snapshots[@(surface)] ?: @[]; }
}

- (BOOL)isRefreshingSurface:(RYGDeveloperRuntimeSurface)surface {
    @synchronized (self) { return [_busy containsObject:@(surface)]; }
}

- (void)requestRefreshForSurface:(RYGDeveloperRuntimeSurface)surface discoverAdditionalClasses:(BOOL)discover {
    [self startIfNeeded];
    NSNumber *key = @(surface);
    uint64_t generation = atomic_load_explicit(&gImageGeneration, memory_order_relaxed);
    @synchronized (self) {
        BOOL knownFresh = [_generations[key] unsignedLongLongValue] == generation;
        BOOL fullFresh = [_fullGenerations[key] unsignedLongLongValue] == generation;
        if ((discover ? fullFresh : knownFresh) || [_busy containsObject:key]) return;
        [_busy addObject:key];
    }

    dispatch_async(_queue, ^{
        NSMutableDictionary<NSString *, RYGRuntimeBoolMethod *> *rows = [NSMutableDictionary dictionary];
        for (NSString *name in RYGKnownOwners(surface)) {
            Class cls = objc_lookUpClass(name.UTF8String);
            if (cls) RYGScanClass(cls, surface, rows);
        }
        if (discover) RYGScanLoadedAppClassesForSurface(surface, rows);

        NSArray *sorted = [rows.allValues sortedArrayUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) {
            NSComparisonResult result = [a.className localizedCaseInsensitiveCompare:b.className];
            return result == NSOrderedSame ? [a.selectorName localizedCaseInsensitiveCompare:b.selectorName] : result;
        }];
        @synchronized (self) {
            _snapshots[key] = sorted ?: @[];
            _generations[key] = @(generation);
            if (discover) _fullGenerations[key] = @(generation);
            [_busy removeObject:key];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGDeveloperFeatureCatalogDidUpdateNotification object:self userInfo:@{RYGDeveloperFeatureCatalogSurfaceUserInfoKey:key}];
        });
    });
}

@end
