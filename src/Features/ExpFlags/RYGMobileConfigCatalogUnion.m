#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import "RYGMobileConfigStaticRuntimeCatalog.h"

static NSDictionary<NSNumber *, NSDictionary *> *RYGMCUnionCatalog(RYGMobileConfig *mobileConfig) {
    NSMutableDictionary<NSNumber *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];

    // The active Instagram holder is authoritative when its native mapping is
    // already present. Path discovery is read-only and never creates a fake
    // AppGroup/mobileconfig tree.
    NSString *nativePath = [mobileConfig ryg_nativeNameMappingPath];
    NSData *nativeData = nativePath.length ? [NSData dataWithContentsOfFile:nativePath options:0 error:nil] : nil;
    NSDictionary *nativeCatalog = nativeData.length ? RYGMCNameMappingCatalogFromData(nativeData, NULL) : nil;
    if (nativeCatalog.count) [catalog addEntriesFromDictionary:nativeCatalog];

    // Imported mapping is a RyukGram overlay. It contributes names and rows, not
    // ABI. An imported mapping can therefore expose a candidate immediately but
    // cannot turn it into an editable value by itself.
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

static void RYGMCMergeRuntimeConfig(RYGMCConfig *config,
                                    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, RYGMCParam *> *> *paramsByConfig,
                                    NSMutableDictionary<NSNumber *, NSString *> *runtimeConfigNames) {
    if (!config) return;
    NSNumber *configKey = @(config.number);
    NSMutableDictionary<NSNumber *, RYGMCParam *> *bucket = paramsByConfig[configKey];
    if (!bucket) {
        bucket = [NSMutableDictionary dictionary];
        paramsByConfig[configKey] = bucket;
    }
    if (config.name.length) runtimeConfigNames[configKey] = config.name;

    for (RYGMCParam *source in config.params ?: @[]) {
        if (!source.isRuntimeBacked || !source.paramID || !RYGMCTypeIsRuntimeValue(source.type)) continue;
        NSNumber *indexKey = @(source.paramIndex);
        RYGMCParam *existing = bucket[indexKey];
        if (!existing || !existing.isRuntimeBacked) {
            bucket[indexKey] = RYGMCCloneParam(source);
        } else if (!existing.name.length && source.name.length) {
            existing.name = source.name;
        }
    }
}

@implementation RYGMobileConfig (RYGMappingRuntimeUnion)

- (NSArray<RYGMCConfig *> *)allConfigsIncludingMappingOnly {
    [self prepare];

    NSDictionary<NSNumber *, NSDictionary *> *catalog = RYGMCUnionCatalog(self);
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, RYGMCParam *> *> *paramsByConfig = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSString *> *runtimeConfigNames = [NSMutableDictionary dictionary];

    // First take whatever the canonical MobileConfig owner already resolved.
    for (RYGMCConfig *config in self.allConfigs ?: @[])
        RYGMCMergeRuntimeConfig(config, paramsByConfig, runtimeConfigNames);

    // Then resolve the same compiled iOS parameter descriptor table without
    // waiting for a getter to be observed. The resolver tries exported symbols
    // and then the loaded Mach-O symbol table. This is the source of BOOL/INT64/
    // STRING/DOUBLE identity; names are never used to infer type.
    for (RYGMCConfig *config in RYGMCStaticRuntimeConfigs(catalog))
        RYGMCMergeRuntimeConfig(config, paramsByConfig, runtimeConfigNames);

    // Finally materialize every id_name_mapping row that is absent from the
    // compiled iOS table. Such rows are intentionally mapping-only/read-only:
    // paramID=0 and type=Unknown. This makes the entire mapping searchable while
    // preserving the no-type-guessing invariant.
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
