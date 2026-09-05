#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"

static NSDictionary<NSNumber *, NSDictionary *> *RYGMCUnionCatalog(RYGMobileConfig *mobileConfig) {
    NSMutableDictionary<NSNumber *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];

    // Native mapping is the baseline when present.
    NSString *nativePath = [mobileConfig ryg_nativeNameMappingPath];
    NSData *nativeData = nativePath.length ? [NSData dataWithContentsOfFile:nativePath options:0 error:nil] : nil;
    NSDictionary *nativeCatalog = nativeData.length ? RYGMCNameMappingCatalogFromData(nativeData, NULL) : nil;
    if (nativeCatalog.count) [catalog addEntriesFromDictionary:nativeCatalog];

    // Imported mapping is an explicit RyukGram overlay. Merge is deterministic:
    // imported config/parameter names win, native rows absent from the import are
    // retained. This lets an Android/newer mapping expand discovery without ever
    // fabricating an iOS PID/type.
    NSDictionary *cached = RYGMCLoadCachedNameMappingCatalog(NULL);
    if (cached.count) RYGMCMergeNameMappingCatalog(catalog, cached);
    return catalog.copy;
}

static RYGMCParam *RYGMCCloneParam(RYGMCParam *source) {
    RYGMCParam *param = [RYGMCParam new];
    param.paramID = source.paramID;
    param.ordinal = source.ordinal;
    param.configNumber = source.configNumber;
    param.paramIndex = source.paramIndex;
    param.type = source.type;
    param.runtimeBacked = source.isRuntimeBacked;
    param.name = source.name;
    return param;
}

@implementation RYGMobileConfig (RYGMappingRuntimeUnion)

- (NSArray<RYGMCConfig *> *)allConfigsIncludingMappingOnly {
    [self prepare];

    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, RYGMCParam *> *> *paramsByConfig = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSString *> *runtimeConfigNames = [NSMutableDictionary dictionary];

    for (RYGMCConfig *config in self.allConfigs ?: @[]) {
        NSNumber *configKey = @(config.number);
        NSMutableDictionary<NSNumber *, RYGMCParam *> *bucket = [NSMutableDictionary dictionary];
        for (RYGMCParam *source in config.params ?: @[]) bucket[@(source.paramIndex)] = RYGMCCloneParam(source);
        paramsByConfig[configKey] = bucket;
        if (config.name.length) runtimeConfigNames[configKey] = config.name;
    }

    NSDictionary<NSNumber *, NSDictionary *> *catalog = RYGMCUnionCatalog(self);
    [catalog enumerateKeysAndObjectsUsingBlock:^(NSNumber *configKey, NSDictionary *info, BOOL *stop) {
        (void)stop;
        NSMutableDictionary<NSNumber *, RYGMCParam *> *bucket = paramsByConfig[configKey];
        if (!bucket) {
            bucket = [NSMutableDictionary dictionary];
            paramsByConfig[configKey] = bucket;
        }
        NSDictionary<NSNumber *, NSString *> *mapped = [info[@"params"] isKindOfClass:NSDictionary.class] ? info[@"params"] : @{};
        [mapped enumerateKeysAndObjectsUsingBlock:^(NSNumber *indexKey, NSString *name, BOOL *innerStop) {
            (void)innerStop;
            RYGMCParam *param = bucket[indexKey];
            if (!param) {
                param = [RYGMCParam new];
                param.configNumber = configKey.unsignedIntValue;
                param.paramIndex = indexKey.unsignedIntValue;
                param.paramID = 0;
                param.ordinal = 0;
                param.type = RYGMCTypeUnknown;
                param.runtimeBacked = NO;
                bucket[indexKey] = param;
            }
            if (name.length) param.name = name;
        }];
    }];

    NSMutableArray<RYGMCConfig *> *configs = [NSMutableArray arrayWithCapacity:paramsByConfig.count];
    [paramsByConfig enumerateKeysAndObjectsUsingBlock:^(NSNumber *configKey, NSMutableDictionary<NSNumber *, RYGMCParam *> *bucket, BOOL *stop) {
        (void)stop;
        RYGMCConfig *config = [RYGMCConfig new];
        config.number = configKey.unsignedIntValue;
        NSDictionary *info = catalog[configKey];
        NSString *mappedName = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : nil;
        config.name = mappedName.length ? mappedName : runtimeConfigNames[configKey];
        config.params = [bucket.allValues sortedArrayUsingComparator:^NSComparisonResult(RYGMCParam *left, RYGMCParam *right) {
            if (left.paramIndex < right.paramIndex) return NSOrderedAscending;
            if (left.paramIndex > right.paramIndex) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        [configs addObject:config];
    }];

    [configs sortUsingComparator:^NSComparisonResult(RYGMCConfig *left, RYGMCConfig *right) {
        BOOL leftNamed = left.name.length, rightNamed = right.name.length;
        if (leftNamed != rightNamed) return leftNamed ? NSOrderedAscending : NSOrderedDescending;
        if (leftNamed) {
            NSComparisonResult byName = [left.name localizedCaseInsensitiveCompare:right.name];
            if (byName != NSOrderedSame) return byName;
        }
        if (left.number < right.number) return NSOrderedAscending;
        if (left.number > right.number) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return configs.copy;
}

@end
