#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import <math.h>
#include <stdlib.h>

static NSString *const kRYGMobileConfigNamesDidChangeNotification = @"RYGMobileConfigNamesDidChange";
static NSString *const kRYGMCQEOverridesKey = @"_qe_overrides_";
static NSString *const kRYGMCOverrideSeparator = @": : ";

@interface RYGMobileConfig (RYGPrivateNativePath)
- (NSString *)mcDirectory;
@end

static NSError *RYGMCJSONError(NSString *message) {
    return [NSError errorWithDomain:@"com.ryukgram.mobileconfig.json"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey:message ?: @"MobileConfig JSON error"}];
}

static NSNumber *RYGMCJSONStrictUnsigned(NSString *text, BOOL allowZero) {
    if (![text isKindOfClass:NSString.class] || !text.length || [text hasPrefix:@"-"]) return nil;
    const char *raw = text.UTF8String;
    if (!raw || !*raw) return nil;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 10);
    if (end == raw || *end != '\0' || value > UINT32_MAX || (!allowZero && value == 0)) return nil;
    return @(value);
}

static NSString *RYGMCJSONValueString(id value, RYGMCType type) {
    if (type == RYGMCTypeBool) return [value boolValue] ? @"true" : @"false";
    if (type == RYGMCTypeInt) return [NSString stringWithFormat:@"%lld", [value longLongValue]];
    if (type == RYGMCTypeDouble) return [NSString stringWithFormat:@"%.17g", [value doubleValue]];
    return [value isKindOfClass:NSString.class] ? value : [value description];
}

static id RYGMCParseCanonicalJSONValue(NSString *text, RYGMCType type) {
    if (![text isKindOfClass:NSString.class]) return nil;
    switch (type) {
        case RYGMCTypeBool:
            if ([text isEqualToString:@"true"]) return @YES;
            if ([text isEqualToString:@"false"]) return @NO;
            return nil;
        case RYGMCTypeInt: {
            const char *raw = text.UTF8String;
            if (!raw || !*raw) return nil;
            char *end = NULL;
            long long value = strtoll(raw, &end, 10);
            return (end != raw && *end == '\0') ? @(value) : nil;
        }
        case RYGMCTypeDouble: {
            const char *raw = text.UTF8String;
            if (!raw || !*raw) return nil;
            char *end = NULL;
            double value = strtod(raw, &end);
            return (end != raw && *end == '\0' && isfinite(value)) ? @(value) : nil;
        }
        case RYGMCTypeString:
            // Canonical mc_overrides stores the raw string after ": : "; the
            // surrounding JSON string provides JSON escaping/quoting.
            return text;
        case RYGMCTypeUnknown:
            return nil;
    }
    return nil;
}

static NSDictionary<NSNumber *, NSDictionary *> *RYGMCCatalogFromCurrentModels(RYGMobileConfig *mobileConfig) {
    NSMutableDictionary<NSNumber *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in mobileConfig.allConfigs) {
        NSMutableDictionary<NSNumber *, NSString *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *param in config.params) {
            if (param.name.length) params[@(param.paramIndex)] = param.name;
        }
        if (config.name.length || params.count) {
            catalog[@(config.number)] = @{
                @"name": config.name ?: @"",
                @"params": params.copy,
            };
        }
    }
    return catalog.copy;
}

static BOOL RYGMCVerifyImportedCatalog(RYGMobileConfig *mobileConfig,
                                       NSDictionary<NSNumber *, NSDictionary *> *incoming,
                                       NSError **error) {
    NSMutableDictionary<NSNumber *, RYGMCConfig *> *configs = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in mobileConfig.allConfigs) configs[@(config.number)] = config;

    for (NSNumber *configNumber in incoming) {
        NSDictionary *info = incoming[configNumber];
        RYGMCConfig *config = configs[configNumber];
        if (!config) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                @"Imported config %@ did not materialize in the browser model.", configNumber]);
            return NO;
        }

        NSString *expectedConfigName = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : @"";
        if (expectedConfigName.length && ![config.name isEqualToString:expectedConfigName]) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                @"Imported config %@ was rebuilt with the wrong name.", configNumber]);
            return NO;
        }

        NSMutableDictionary<NSNumber *, RYGMCParam *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *param in config.params) params[@(param.paramIndex)] = param;
        NSDictionary<NSNumber *, NSString *> *expectedParams = [info[@"params"] isKindOfClass:NSDictionary.class]
            ? info[@"params"] : @{};
        for (NSNumber *paramIndex in expectedParams) {
            RYGMCParam *param = params[paramIndex];
            NSString *expectedName = expectedParams[paramIndex];
            if (!param || ![param.name isEqualToString:expectedName]) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                    @"Imported %@:%@ (%@) did not materialize in the browser model.",
                    configNumber, paramIndex, expectedName ?: @""]);
                return NO;
            }
        }
    }
    return YES;
}

static void RYGMCPostNamesChanged(RYGMobileConfig *mobileConfig) {
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:kRYGMobileConfigNamesDidChangeNotification
                                                          object:mobileConfig];
    };
    if (NSThread.isMainThread) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

@implementation RYGMobileConfig (RYGJSONIO)

- (NSString *)ryg_nativeDataDirectory {
    NSString *path = nil;
    @try { path = [self mcDirectory]; } @catch (__unused NSException *exception) {}
    if (![path isKindOfClass:NSString.class] || !path.length) return nil;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) return nil;
    return path;
}

- (NSString *)ryg_nativeNameMappingPath {
    NSString *directory = [self ryg_nativeDataDirectory];
    return directory.length ? [directory stringByAppendingPathComponent:@"id_name_mapping.json"] : nil;
}

- (NSString *)ryg_nativeOverridesJSONPath {
    NSString *directory = [self ryg_nativeDataDirectory];
    return directory.length ? [directory stringByAppendingPathComponent:@"mc_overrides.json"] : nil;
}

- (BOOL)ryg_importNameMappingData:(NSData *)data error:(NSError **)error {
    return [self ryg_importNameMappingData:data mode:RYGMCNameMappingImportModeReplace error:error];
}

- (BOOL)ryg_importNameMappingData:(NSData *)data
                             mode:(RYGMCNameMappingImportMode)mode
                            error:(NSError **)error {
    NSDictionary<NSNumber *, NSDictionary *> *incoming = RYGMCNameMappingCatalogFromData(data, error);
    if (!incoming) return NO;

    NSData *previousCache = RYGMCLoadCachedNameMappingData();
    NSMutableDictionary<NSNumber *, NSDictionary *> *result = [NSMutableDictionary dictionary];

    if (mode == RYGMCNameMappingImportModeMerge) {
        NSDictionary *existing = RYGMCLoadCachedNameMappingCatalog(NULL);
        if (!existing.count) existing = RYGMCCatalogFromCurrentModels(self);
        if (existing.count) [result addEntriesFromDictionary:existing];
    }
    RYGMCMergeNameMappingCatalog(result, incoming);

    if (!RYGMCSaveNameMappingCatalog(result, error)) return NO;

    NSData *canonical = RYGMCLoadCachedNameMappingData();
    NSString *nativePath = [self ryg_nativeNameMappingPath];
    if (nativePath.length && canonical.length &&
        ![canonical writeToFile:nativePath options:NSDataWritingAtomic error:error]) {
        if (previousCache.length) [previousCache writeToFile:RYGMCNameMappingCachePath() options:NSDataWritingAtomic error:nil];
        else [NSFileManager.defaultManager removeItemAtPath:RYGMCNameMappingCachePath() error:nil];
        return NO;
    }

    [self reloadFromRuntime];

    NSError *verificationError = nil;
    if (!RYGMCVerifyImportedCatalog(self, incoming, &verificationError)) {
        if (previousCache.length) {
            [previousCache writeToFile:RYGMCNameMappingCachePath() options:NSDataWritingAtomic error:nil];
        } else {
            [NSFileManager.defaultManager removeItemAtPath:RYGMCNameMappingCachePath() error:nil];
        }
        [self reloadFromRuntime];
        if (error) *error = verificationError;
        return NO;
    }

    RYGMCPostNamesChanged(self);
    return YES;
}

- (NSData *)ryg_exportNameMappingData:(NSError **)error {
    NSData *cached = RYGMCLoadCachedNameMappingData();
    if (cached.length) return cached;

    NSString *nativePath = [self ryg_nativeNameMappingPath];
    NSData *native = nativePath.length
        ? [NSData dataWithContentsOfFile:nativePath options:0 error:nil] : nil;
    if (native.length) return native;

    NSDictionary *catalog = RYGMCCatalogFromCurrentModels(self);
    if (!catalog.count) {
        if (error) *error = RYGMCJSONError(@"No MobileConfig name mapping is available to export.");
        return nil;
    }
    return RYGMCNameMappingDataFromCatalog(catalog, error);
}

- (NSArray *)ryg_existingQEOverrides {
    NSString *path = [self ryg_nativeOverridesJSONPath];
    NSData *data = path.length ? [NSData dataWithContentsOfFile:path options:0 error:nil] : nil;
    if (!data.length) return @[];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    id qe = [json isKindOfClass:NSDictionary.class] ? json[kRYGMCQEOverridesKey] : nil;
    return [qe isKindOfClass:NSArray.class] ? [qe copy] : @[];
}

- (BOOL)ryg_importAndApplyOverridesData:(NSData *)data
                           appliedCount:(NSUInteger *)appliedCount
                                  error:(NSError **)error {
    if (appliedCount) *appliedCount = 0;
    if (!data.length) {
        if (error) *error = RYGMCJSONError(@"The mc_overrides.json file is empty.");
        return NO;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = RYGMCJSONError(
            @"mc_overrides.json must be a JSON object keyed by \"<config>:\" plus optional _qe_overrides_.");
        return NO;
    }

    NSMutableDictionary<NSNumber *, RYGMCConfig *> *configs = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in self.allConfigs) configs[@(config.number)] = config;

    // Validate the entire file before changing one live value. The supplied
    // canonical file uses only:
    //   "<configId>:": ["<paramIndex>: : <value>", ...]
    // plus the special _qe_overrides_ array. Unsupported runtime params are
    // preserved in the file but are not guessed/applied.
    NSMutableArray<NSDictionary *> *actions = [NSMutableArray array];
    for (id rawKey in (NSDictionary *)json) {
        if (![rawKey isKindOfClass:NSString.class]) {
            if (error) *error = RYGMCJSONError(@"mc_overrides.json contains a non-string key.");
            return NO;
        }
        NSString *key = (NSString *)rawKey;
        id rawLines = ((NSDictionary *)json)[key];

        if ([key isEqualToString:kRYGMCQEOverridesKey]) {
            if (![rawLines isKindOfClass:NSArray.class]) {
                if (error) *error = RYGMCJSONError(@"_qe_overrides_ must be a JSON array.");
                return NO;
            }
            continue;
        }

        if (![key hasSuffix:@":"] || key.length < 2) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                @"Invalid MobileConfig key %@; expected <configId>:.", key]);
            return NO;
        }
        NSString *configText = [key substringToIndex:key.length - 1];
        NSNumber *configNumber = RYGMCJSONStrictUnsigned(configText, NO);
        if (!configNumber) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                @"Invalid MobileConfig config id in key %@.", key]);
            return NO;
        }
        if (![rawLines isKindOfClass:NSArray.class]) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                @"MobileConfig key %@ must contain an array of override strings.", key]);
            return NO;
        }

        RYGMCConfig *config = configs[configNumber];
        NSMutableDictionary<NSNumber *, RYGMCParam *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *param in config.params) params[@(param.paramIndex)] = param;

        for (id rawLine in (NSArray *)rawLines) {
            if (![rawLine isKindOfClass:NSString.class]) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                    @"MobileConfig key %@ contains a non-string override entry.", key]);
                return NO;
            }
            NSString *line = (NSString *)rawLine;
            NSRange separator = [line rangeOfString:kRYGMCOverrideSeparator];
            if (separator.location == NSNotFound || separator.location == 0) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                    @"Invalid override line %@; expected <paramIndex>: : <value>.", line]);
                return NO;
            }

            NSString *indexText = [line substringToIndex:separator.location];
            NSNumber *paramIndex = RYGMCJSONStrictUnsigned(indexText, YES);
            if (!paramIndex) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                    @"Invalid parameter index in override line %@.", line]);
                return NO;
            }

            // Syntax is validated for every row. Applicability is separate: a
            // full mapping can legitimately contain a config/param not backed by
            // the currently loaded iOS metadata table.
            RYGMCParam *param = params[paramIndex];
            if (!param || !param.isRuntimeBacked || param.type == RYGMCTypeUnknown) continue;

            NSString *valueText = [line substringFromIndex:NSMaxRange(separator)];
            id value = RYGMCParseCanonicalJSONValue(valueText, param.type);
            if (!value) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:
                    @"Invalid %@ value in override line %@.", param.typeName ?: @"MobileConfig", line]);
                return NO;
            }
            [actions addObject:@{@"param":param, @"value":value}];
        }
    }

    // Serialize/write only after the complete grammar has been validated. This
    // preserves _qe_overrides_ and the exact string-line representation while
    // keeping JSON compact (no pretty-print line breaks).
    NSData *canonical = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
    if (!canonical) return NO;
    NSString *nativePath = [self ryg_nativeOverridesJSONPath];
    if (nativePath.length &&
        ![canonical writeToFile:nativePath options:NSDataWritingAtomic error:error]) return NO;

    NSUInteger applied = 0;
    for (NSDictionary *action in actions) {
        RYGMCParam *param = action[@"param"];
        id value = action[@"value"];
        if ([self setOverride:value for:param]) applied++;
    }
    [self reapplyOverridesToNativeTable];
    if (appliedCount) *appliedCount = applied;
    return YES;
}

- (NSData *)ryg_exportOverridesData:(NSError **)error {
    NSMutableDictionary<NSString *, id> *root = [NSMutableDictionary dictionary];
    root[kRYGMCQEOverridesKey] = [self ryg_existingQEOverrides] ?: @[];

    for (RYGMCConfig *config in self.allConfigs) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (RYGMCParam *param in config.params) {
            if (!param.isRuntimeBacked || param.type == RYGMCTypeUnknown) continue;
            if ([self overrideStateFor:param] != RYGMCOverrideSet) continue;
            id value = [self overrideValueFor:param];
            if (value) {
                [lines addObject:[NSString stringWithFormat:@"%u%@%@",
                    param.paramIndex, kRYGMCOverrideSeparator, RYGMCJSONValueString(value, param.type)]];
            }
        }
        if (lines.count) root[[NSString stringWithFormat:@"%u:", config.number]] = lines;
    }
    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
}

@end
