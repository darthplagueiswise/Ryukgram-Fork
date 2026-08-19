#import "RYGMobileConfigNameMappingStore.h"
#include <stdlib.h>

static NSString *const kRYGMCNameMappingFileName = @"id_name_mapping.json";

static NSError *RYGMCNameMappingError(NSString *message) {
    return [NSError errorWithDomain:@"com.ryukgram.mobileconfig.names"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"id_name_mapping error"}];
}

NSString *RYGMCNameMappingCachePath(void) {
    NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                          NSUserDomainMask,
                                                          YES).firstObject;
    if (!root.length) {
        root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    }
    NSString *directory = [[root stringByAppendingPathComponent:@"RyukGram"]
        stringByAppendingPathComponent:@"MobileConfig"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    return [directory stringByAppendingPathComponent:kRYGMCNameMappingFileName];
}

static NSNumber *RYGMCStrictUnsigned(NSString *text, BOOL allowZero) {
    if (![text isKindOfClass:NSString.class] || !text.length) return nil;
    const char *raw = text.UTF8String;
    if (!raw || !*raw || *raw == '-') return nil;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 10);
    if (end == raw || *end != '\0' || value > UINT32_MAX || (!allowZero && value == 0)) return nil;
    return @(value);
}

NSDictionary<NSNumber *, NSDictionary *> *RYGMCNameMappingCatalogFromData(NSData *data,
                                                                           NSError **error) {
    if (!data.length) {
        if (error) *error = RYGMCNameMappingError(@"The id_name_mapping.json file is empty.");
        return nil;
    }

    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![json isKindOfClass:NSArray.class]) {
        if (error) *error = jsonError ?: RYGMCNameMappingError(
            @"id_name_mapping.json must be an array of colon-delimited strings.");
        return nil;
    }

    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *catalog = [NSMutableDictionary dictionary];
    for (id rawEntry in (NSArray *)json) {
        if (![rawEntry isKindOfClass:NSString.class]) {
            if (error) *error = RYGMCNameMappingError(
                @"id_name_mapping.json contains a non-string entry.");
            return nil;
        }

        NSArray<NSString *> *parts = [(NSString *)rawEntry componentsSeparatedByString:@":"];
        if (parts.count < 2) {
            if (error) *error = RYGMCNameMappingError(
                @"id_name_mapping.json contains an invalid config entry.");
            return nil;
        }

        NSNumber *configNumber = RYGMCStrictUnsigned(parts[0], NO);
        if (!configNumber) {
            if (error) *error = RYGMCNameMappingError(
                @"id_name_mapping.json contains an invalid config id.");
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
            NSNumber *paramIndex = RYGMCStrictUnsigned(parts[index], YES);
            NSString *paramName = parts[index + 1];
            if (!paramIndex || !paramName.length) continue;
            params[paramIndex] = paramName;
        }
    }

    NSMutableDictionary<NSNumber *, NSDictionary *> *immutable =
        [NSMutableDictionary dictionaryWithCapacity:catalog.count];
    [catalog enumerateKeysAndObjectsUsingBlock:^(NSNumber *configNumber,
                                                 NSMutableDictionary *record,
                                                 BOOL *stop) {
        (void)stop;
        immutable[configNumber] = @{
            @"name": [record[@"name"] isKindOfClass:NSString.class] ? record[@"name"] : @"",
            @"params": [record[@"params"] isKindOfClass:NSDictionary.class]
                ? [record[@"params"] copy] : @{},
        };
    }];
    return immutable.copy;
}

NSData *RYGMCNameMappingDataFromCatalog(NSDictionary<NSNumber *, NSDictionary *> *catalog,
                                        NSError **error) {
    NSArray<NSNumber *> *configNumbers = [catalog.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *entries = [NSMutableArray arrayWithCapacity:configNumbers.count];

    for (NSNumber *configNumber in configNumbers) {
        NSDictionary *info = [catalog[configNumber] isKindOfClass:NSDictionary.class]
            ? catalog[configNumber] : @{};
        NSString *configName = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : @"";
        NSMutableString *line = [NSMutableString stringWithFormat:@"%@:%@", configNumber, configName];
        NSDictionary<NSNumber *, NSString *> *params = [info[@"params"] isKindOfClass:NSDictionary.class]
            ? info[@"params"] : @{};
        for (NSNumber *paramIndex in [params.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *name = [params[paramIndex] isKindOfClass:NSString.class] ? params[paramIndex] : @"";
            if (name.length) [line appendFormat:@":%@:%@", paramIndex, name];
        }
        [entries addObject:line];
    }

    return [NSJSONSerialization dataWithJSONObject:entries options:0 error:error];
}

NSData *RYGMCLoadCachedNameMappingData(void) {
    NSData *data = [NSData dataWithContentsOfFile:RYGMCNameMappingCachePath()
                                          options:0
                                            error:nil];
    return data.length ? data : nil;
}

NSDictionary<NSNumber *, NSDictionary *> *RYGMCLoadCachedNameMappingCatalog(NSError **error) {
    NSData *data = RYGMCLoadCachedNameMappingData();
    if (!data.length) return nil;
    return RYGMCNameMappingCatalogFromData(data, error);
}

BOOL RYGMCSaveNameMappingCatalog(NSDictionary<NSNumber *, NSDictionary *> *catalog,
                                 NSError **error) {
    NSData *data = RYGMCNameMappingDataFromCatalog(catalog ?: @{}, error);
    if (!data) return NO;
    return [data writeToFile:RYGMCNameMappingCachePath()
                     options:NSDataWritingAtomic
                       error:error];
}

void RYGMCMergeNameMappingCatalog(NSMutableDictionary<NSNumber *, NSDictionary *> *base,
                                  NSDictionary<NSNumber *, NSDictionary *> *incoming) {
    [incoming enumerateKeysAndObjectsUsingBlock:^(NSNumber *configNumber,
                                                  NSDictionary *incomingInfo,
                                                  BOOL *stop) {
        (void)stop;
        NSDictionary *existingInfo = [base[configNumber] isKindOfClass:NSDictionary.class]
            ? base[configNumber] : nil;
        NSMutableDictionary<NSNumber *, NSString *> *params = [NSMutableDictionary dictionary];
        NSDictionary *existingParams = [existingInfo[@"params"] isKindOfClass:NSDictionary.class]
            ? existingInfo[@"params"] : nil;
        NSDictionary *incomingParams = [incomingInfo[@"params"] isKindOfClass:NSDictionary.class]
            ? incomingInfo[@"params"] : nil;
        if (existingParams.count) [params addEntriesFromDictionary:existingParams];
        if (incomingParams.count) [params addEntriesFromDictionary:incomingParams];

        NSString *existingName = [existingInfo[@"name"] isKindOfClass:NSString.class]
            ? existingInfo[@"name"] : @"";
        NSString *incomingName = [incomingInfo[@"name"] isKindOfClass:NSString.class]
            ? incomingInfo[@"name"] : @"";
        base[configNumber] = @{
            @"name": incomingName.length ? incomingName : existingName,
            @"params": params.copy,
        };
    }];
}
