#import "RYGMobileConfigJSONIO.h"
#import <math.h>
#include <stdlib.h>

@interface RYGMobileConfig (RYGPrivateNativePath)
- (NSString *)mcDirectory;
@end

static NSError *RYGMCJSONError(NSString *message) {
    return [NSError errorWithDomain:@"com.ryukgram.mobileconfig.json" code:1 userInfo:@{NSLocalizedDescriptionKey:message ?: @"MobileConfig JSON error"}];
}

static NSString *RYGMCJSONValueString(id value, RYGMCType type) {
    if (type == RYGMCTypeBool) return [value boolValue] ? @"true" : @"false";
    if (type == RYGMCTypeInt) return [NSString stringWithFormat:@"%lld", [value longLongValue]];
    if (type == RYGMCTypeDouble) return [NSString stringWithFormat:@"%.17g", [value doubleValue]];
    return [value isKindOfClass:NSString.class] ? value : [value description];
}

static id RYGMCParseJSONValue(NSString *text, RYGMCType type) {
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    switch (type) {
        case RYGMCTypeBool: {
            NSString *lower = trim.lowercaseString;
            if ([lower isEqualToString:@"true"] || [lower isEqualToString:@"1"] || [lower isEqualToString:@"yes"]) return @YES;
            if ([lower isEqualToString:@"false"] || [lower isEqualToString:@"0"] || [lower isEqualToString:@"no"]) return @NO;
            return nil;
        }
        case RYGMCTypeInt: {
            const char *raw = trim.UTF8String;
            if (!raw || !*raw) return nil;
            char *end = NULL;
            long long v = strtoll(raw, &end, 10);
            if (end == raw || *end != '\0') return nil;
            return @(v);
        }
        case RYGMCTypeDouble: {
            const char *raw = trim.UTF8String;
            if (!raw || !*raw) return nil;
            char *end = NULL;
            double v = strtod(raw, &end);
            if (end == raw || *end != '\0' || !isfinite(v)) return nil;
            return @(v);
        }
        case RYGMCTypeString: return text ?: @"";
    }
    return nil;
}

#pragma mark - id_name_mapping canonical model

static NSNumber *RYGMCStrictUnsignedNumber(NSString *text, BOOL allowZero) {
    if (![text isKindOfClass:NSString.class] || !text.length) return nil;
    const char *raw = text.UTF8String;
    if (!raw || !*raw || *raw == '-') return nil;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 10);
    if (end == raw || *end != '\0' || value > UINT32_MAX || (!allowZero && value == 0)) return nil;
    return @(value);
}

static NSDictionary<NSNumber *, NSDictionary *> *RYGMCNameCatalogFromJSONData(NSData *data, NSError **error) {
    if (!data.length) {
        if (error) *error = RYGMCJSONError(@"The id_name_mapping.json file is empty.");
        return nil;
    }

    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![json isKindOfClass:NSArray.class]) {
        if (error) *error = jsonError ?: RYGMCJSONError(@"id_name_mapping.json must be an array of colon-delimited strings.");
        return nil;
    }

    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *catalog = [NSMutableDictionary dictionary];
    for (id rawEntry in (NSArray *)json) {
        if (![rawEntry isKindOfClass:NSString.class]) {
            if (error) *error = RYGMCJSONError(@"id_name_mapping.json contains a non-string entry.");
            return nil;
        }

        NSArray<NSString *> *parts = [(NSString *)rawEntry componentsSeparatedByString:@":"];
        if (parts.count < 2) {
            if (error) *error = RYGMCJSONError(@"id_name_mapping.json contains an invalid config entry.");
            return nil;
        }

        NSNumber *configNumber = RYGMCStrictUnsignedNumber(parts[0], NO);
        if (!configNumber) {
            if (error) *error = RYGMCJSONError(@"id_name_mapping.json contains an invalid config id.");
            return nil;
        }

        NSMutableDictionary *record = catalog[configNumber];
        if (!record) {
            record = [@{
                @"name": @"",
                @"params": [NSMutableDictionary dictionary],
            } mutableCopy];
            catalog[configNumber] = record;
        }

        NSString *configName = parts[1];
        if (configName.length) record[@"name"] = configName;
        NSMutableDictionary<NSNumber *, NSString *> *params = record[@"params"];

        for (NSUInteger index = 2; index + 1 < parts.count; index += 2) {
            NSNumber *paramIndex = RYGMCStrictUnsignedNumber(parts[index], YES);
            NSString *paramName = parts[index + 1];
            if (!paramIndex || !paramName.length) continue;
            params[paramIndex] = paramName;
        }
    }

    NSMutableDictionary<NSNumber *, NSDictionary *> *immutable = [NSMutableDictionary dictionaryWithCapacity:catalog.count];
    [catalog enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSMutableDictionary *record, BOOL *stop) {
        NSDictionary *params = [record[@"params"] copy] ?: @{};
        immutable[key] = @{
            @"name": [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : @"",
            @"params": params,
        };
    }];
    return immutable.copy;
}

static void RYGMCMergeNameCatalog(NSMutableDictionary<NSNumber *, NSDictionary *> *base,
                                  NSDictionary<NSNumber *, NSDictionary *> *incoming) {
    [incoming enumerateKeysAndObjectsUsingBlock:^(NSNumber *configNumber, NSDictionary *incomingInfo, BOOL *stop) {
        NSDictionary *existingInfo = [base[configNumber] isKindOfClass:NSDictionary.class] ? base[configNumber] : nil;
        NSMutableDictionary<NSNumber *, NSString *> *params = [NSMutableDictionary dictionary];
        NSDictionary *existingParams = [existingInfo[@"params"] isKindOfClass:NSDictionary.class] ? existingInfo[@"params"] : nil;
        NSDictionary *incomingParams = [incomingInfo[@"params"] isKindOfClass:NSDictionary.class] ? incomingInfo[@"params"] : nil;
        if (existingParams.count) [params addEntriesFromDictionary:existingParams];
        if (incomingParams.count) [params addEntriesFromDictionary:incomingParams];

        NSString *existingName = [existingInfo[@"name"] isKindOfClass:NSString.class] ? existingInfo[@"name"] : @"";
        NSString *incomingName = [incomingInfo[@"name"] isKindOfClass:NSString.class] ? incomingInfo[@"name"] : @"";
        base[configNumber] = @{
            @"name": incomingName.length ? incomingName : existingName,
            @"params": params.copy,
        };
    }];
}

static NSData *RYGMCNameCatalogJSONData(NSDictionary<NSNumber *, NSDictionary *> *catalog, NSError **error) {
    NSArray<NSNumber *> *configNumbers = [catalog.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *entries = [NSMutableArray arrayWithCapacity:configNumbers.count];

    for (NSNumber *configNumber in configNumbers) {
        NSDictionary *info = catalog[configNumber];
        NSString *name = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : @"";
        NSMutableString *line = [NSMutableString stringWithFormat:@"%@:%@", configNumber, name];
        NSDictionary<NSNumber *, NSString *> *params = [info[@"params"] isKindOfClass:NSDictionary.class] ? info[@"params"] : @{};
        NSArray<NSNumber *> *indices = [params.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (NSNumber *index in indices) {
            NSString *paramName = [params[index] isKindOfClass:NSString.class] ? params[index] : @"";
            if (paramName.length) [line appendFormat:@":%@:%@", index, paramName];
        }
        [entries addObject:line];
    }

    return [NSJSONSerialization dataWithJSONObject:entries options:0 error:error];
}

@implementation RYGMobileConfig (RYGJSONIO)

- (NSString *)ryg_nativeDataDirectory {
    NSString *path = nil;
    @try { path = [self mcDirectory]; } @catch (__unused NSException *exception) {}
    if (![path isKindOfClass:NSString.class] || !path.length) return nil;
    BOOL isDir = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] || !isDir) return nil;
    return path;
}

- (NSString *)ryg_nativeNameMappingPath {
    NSString *dir = [self ryg_nativeDataDirectory];
    return dir.length ? [dir stringByAppendingPathComponent:@"id_name_mapping.json"] : nil;
}

- (NSString *)ryg_nativeOverridesJSONPath {
    NSString *dir = [self ryg_nativeDataDirectory];
    return dir.length ? [dir stringByAppendingPathComponent:@"mc_overrides.json"] : nil;
}

- (BOOL)ryg_importNameMappingData:(NSData *)data error:(NSError **)error {
    NSDictionary *catalog = RYGMCNameCatalogFromJSONData(data, error);
    if (!catalog) return NO;

    NSData *canonical = RYGMCNameCatalogJSONData(catalog, error);
    if (!canonical) return NO;

    NSString *path = [self ryg_nativeNameMappingPath];
    if (!path.length) {
        if (error) *error = RYGMCJSONError(@"Instagram has not exposed its active MobileConfig data directory yet. Open the app until MobileConfig is read, then retry.");
        return NO;
    }
    if (![canonical writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    [self reloadFromRuntime];
    return YES;
}

- (BOOL)ryg_importNameMappingData:(NSData *)data
                             mode:(RYGMCNameMappingImportMode)mode
                            error:(NSError **)error {
    NSDictionary<NSNumber *, NSDictionary *> *incoming = RYGMCNameCatalogFromJSONData(data, error);
    if (!incoming) return NO;

    NSMutableDictionary<NSNumber *, NSDictionary *> *result = [NSMutableDictionary dictionary];
    if (mode == RYGMCNameMappingImportModeMerge) {
        NSError *existingError = nil;
        NSData *existingData = [self ryg_exportNameMappingData:&existingError];
        if (existingData.length) {
            NSDictionary *existing = RYGMCNameCatalogFromJSONData(existingData, &existingError);
            if (!existing && existingError) {
                if (error) *error = existingError;
                return NO;
            }
            if (existing.count) [result addEntriesFromDictionary:existing];
        }
    }

    // Incoming entries deliberately win conflicts in both modes. Replace starts
    // with an empty result; Merge starts from the currently persisted/effective
    // mapping and preserves entries the import does not mention.
    RYGMCMergeNameCatalog(result, incoming);
    NSData *canonical = RYGMCNameCatalogJSONData(result, error);
    if (!canonical) return NO;

    // Call the established import selector so the bridge remains the single
    // owner of cache persistence, native *.data mirroring, model refresh and
    // RYGMobileConfigNamesDidChange notifications.
    return [self ryg_importNameMappingData:canonical error:error];
}

- (NSData *)ryg_exportNameMappingData:(NSError **)error {
    NSString *path = [self ryg_nativeNameMappingPath];
    NSData *disk = path.length ? [NSData dataWithContentsOfFile:path options:0 error:nil] : nil;
    if (disk.length) return disk;
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    for (RYGMCConfig *config in self.allConfigs) {
        if (!config.name.length) continue;
        NSMutableString *line = [NSMutableString stringWithFormat:@"%u:%@", config.number, config.name];
        for (RYGMCParam *param in config.params) if (param.name.length) [line appendFormat:@":%u:%@", param.paramIndex, param.name];
        [entries addObject:line];
    }
    if (!entries.count) { if (error) *error = RYGMCJSONError(@"No live MobileConfig name mapping is available to export."); return nil; }
    return [NSJSONSerialization dataWithJSONObject:entries options:0 error:error];
}

- (BOOL)ryg_importAndApplyOverridesData:(NSData *)data appliedCount:(NSUInteger *)appliedCount error:(NSError **)error {
    if (appliedCount) *appliedCount = 0;
    if (!data.length) { if (error) *error = RYGMCJSONError(@"The mc_overrides.json file is empty."); return NO; }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class]) { if (error && !*error) *error = RYGMCJSONError(@"mc_overrides.json must be a JSON object keyed by \"<config>:\"."); return NO; }

    NSMutableDictionary<NSNumber *, RYGMCConfig *> *configs = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in self.allConfigs) configs[@(config.number)] = config;
    NSUInteger applied = 0;
    for (id rawKey in (NSDictionary *)json) {
        if (![rawKey isKindOfClass:NSString.class]) continue;
        NSString *configKey = [(NSString *)rawKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([configKey hasSuffix:@":"]) configKey = [configKey substringToIndex:configKey.length - 1];
        unsigned long long configNumber = strtoull(configKey.UTF8String, NULL, 10);
        RYGMCConfig *config = configs[@(configNumber)];
        id lines = ((NSDictionary *)json)[rawKey];
        if (![lines isKindOfClass:NSArray.class] || !config) continue;

        NSMutableDictionary<NSNumber *, RYGMCParam *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *param in config.params) params[@(param.paramIndex)] = param;
        for (id rawLine in (NSArray *)lines) {
            if (![rawLine isKindOfClass:NSString.class]) continue;
            NSString *line = rawLine;
            NSRange separator = [line rangeOfString:@": : "];
            if (separator.location == NSNotFound) separator = [line rangeOfString:@"::"];
            if (separator.location == NSNotFound) continue;
            NSString *indexText = [[line substringToIndex:separator.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *valueText = [line substringFromIndex:NSMaxRange(separator)];
            unsigned long long index = strtoull(indexText.UTF8String, NULL, 10);
            RYGMCParam *param = params[@(index)];
            if (!param) continue;
            id value = RYGMCParseJSONValue(valueText, param.type);
            if (value && [self setOverride:value for:param]) applied++;
        }
    }
    [self reapplyOverridesToNativeTable];

    NSString *nativePath = [self ryg_nativeOverridesJSONPath];
    if (nativePath.length) {
        NSData *canonical = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
        if (!canonical || ![canonical writeToFile:nativePath options:NSDataWritingAtomic error:error]) return NO;
    }
    if (appliedCount) *appliedCount = applied;
    return YES;
}

- (NSData *)ryg_exportOverridesData:(NSError **)error {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *root = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in self.allConfigs) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (RYGMCParam *param in config.params) {
            if ([self overrideStateFor:param] != RYGMCOverrideSet) continue;
            id value = [self overrideValueFor:param];
            if (value) [lines addObject:[NSString stringWithFormat:@"%u: : %@", param.paramIndex, RYGMCJSONValueString(value, param.type)]];
        }
        if (lines.count) root[[NSString stringWithFormat:@"%u:", config.number]] = lines;
    }
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
}

@end