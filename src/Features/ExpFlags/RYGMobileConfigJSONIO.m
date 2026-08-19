#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import <math.h>
#include <stdlib.h>
#include <stdint.h>

static NSString *const kRYGMobileConfigNamesDidChangeNotification = @"RYGMobileConfigNamesDidChange";
static NSString *const kRYGMCQEOverridesKey = @"_qe_overrides_";
static NSString *const kRYGMCCanonicalSeparator = @": : ";

@interface RYGMobileConfig (RYGPrivateNativePath)
- (NSString *)mcDirectory;
@end

static NSError *RYGMCJSONError(NSString *message) {
    return [NSError errorWithDomain:@"com.ryukgram.mobileconfig.json"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey:message ?: @"MobileConfig JSON error"}];
}

static NSString *RYGMCCanonicalOverridesCachePath(void) {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                NSUserDomainMask,
                                                                YES).firstObject
        stringByAppendingPathComponent:@"RyukGram"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    return [directory stringByAppendingPathComponent:@"mc_overrides_canonical.json"];
}

static BOOL RYGMCParseUnsigned(NSString *text,
                               unsigned long long maximum,
                               unsigned long long *result) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const char *raw = trimmed.UTF8String;
    if (!raw || !*raw || *raw == '-') return NO;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 10);
    if (end == raw || *end != '\0' || value > maximum) return NO;
    if (result) *result = value;
    return YES;
}

static NSString *RYGMCJSONValueString(id value, RYGMCType type) {
    if (type == RYGMCTypeBool) return [value boolValue] ? @"true" : @"false";
    if (type == RYGMCTypeInt) return [NSString stringWithFormat:@"%lld", [value longLongValue]];
    if (type == RYGMCTypeDouble) return [NSString stringWithFormat:@"%.17g", [value doubleValue]];
    return [value isKindOfClass:NSString.class] ? value : [value description];
}

// Canonical native mc_overrides grammar is typed by the runtime parameter table:
// 1=bool, 2=int64, 3=string, 4=double. Unknown/mapping-only rows are preserved
// byte-semantically as strings but deliberately not interpreted or applied.
static id RYGMCParseCanonicalJSONValue(NSString *text, RYGMCType type) {
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (type == RYGMCTypeBool) {
        NSString *lower = trim.lowercaseString;
        if ([lower isEqualToString:@"true"]) return @YES;
        if ([lower isEqualToString:@"false"]) return @NO;
        return nil;
    }
    if (type == RYGMCTypeInt) {
        const char *raw = trim.UTF8String;
        if (!raw || !*raw) return nil;
        char *end = NULL;
        long long value = strtoll(raw, &end, 10);
        return end != raw && *end == '\0' ? @(value) : nil;
    }
    if (type == RYGMCTypeDouble) {
        const char *raw = trim.UTF8String;
        if (!raw || !*raw) return nil;
        char *end = NULL;
        double value = strtod(raw, &end);
        return end != raw && *end == '\0' && isfinite(value) ? @(value) : nil;
    }
    if (type == RYGMCTypeString) return text ?: @"";
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
            catalog[@(config.number)] = @{@"name":config.name ?: @"", @"params":params.copy};
        }
    }
    return catalog.copy;
}

static BOOL RYGMCVerifyPersistedCatalog(NSDictionary<NSNumber *, NSDictionary *> *expected, NSError **error) {
    NSDictionary<NSNumber *, NSDictionary *> *actual = RYGMCLoadCachedNameMappingCatalog(error);
    if (!actual) return NO;
    for (NSNumber *configNumber in expected) {
        NSDictionary *wanted = expected[configNumber];
        NSDictionary *got = actual[configNumber];
        if (!got) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Config %@ was not persisted.", configNumber]);
            return NO;
        }
        NSString *wantedName = [wanted[@"name"] isKindOfClass:NSString.class] ? wanted[@"name"] : @"";
        NSString *gotName = [got[@"name"] isKindOfClass:NSString.class] ? got[@"name"] : @"";
        if (wantedName.length && ![wantedName isEqualToString:gotName]) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Config %@ name did not round-trip.", configNumber]);
            return NO;
        }
        NSDictionary *wantedParams = [wanted[@"params"] isKindOfClass:NSDictionary.class] ? wanted[@"params"] : @{};
        NSDictionary *gotParams = [got[@"params"] isKindOfClass:NSDictionary.class] ? got[@"params"] : @{};
        for (NSNumber *paramIndex in wantedParams) {
            if (![wantedParams[paramIndex] isEqual:gotParams[paramIndex]]) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Param %@:%@ did not round-trip.", configNumber, paramIndex]);
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

static NSDictionary *RYGMCOverridesRootFromData(NSData *data) {
    if (!data.length) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [root isKindOfClass:NSDictionary.class] ? root : nil;
}

static BOOL RYGMCParseCanonicalLine(NSString *line,
                                    unsigned int *paramIndex,
                                    NSString **valueText) {
    if (![line isKindOfClass:NSString.class]) return NO;
    NSRange separator = [line rangeOfString:kRYGMCCanonicalSeparator];
    if (separator.location == NSNotFound) return NO;
    NSString *indexText = [line substringToIndex:separator.location];
    unsigned long long parsedIndex = 0;
    if (!RYGMCParseUnsigned(indexText, UINT32_MAX, &parsedIndex)) return NO;
    if (paramIndex) *paramIndex = (unsigned int)parsedIndex;
    if (valueText) *valueText = [line substringFromIndex:NSMaxRange(separator)];
    return YES;
}

@implementation RYGMobileConfig (RYGJSONIO)

- (NSString *)ryg_nativeDataDirectory {
    NSString *path = nil;
    @try { path = [self mcDirectory]; } @catch (__unused NSException *exception) {}
    if (![path isKindOfClass:NSString.class] || !path.length) return nil;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) return nil;
    // Instagram's native MobileConfig unit lives under Documents/mobileconfig/<user>.data/.
    if (![path.pathExtension.lowercaseString isEqualToString:@"data"]) return nil;
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

    NSMutableDictionary<NSNumber *, NSDictionary *> *result = [NSMutableDictionary dictionary];
    if (mode == RYGMCNameMappingImportModeMerge) {
        NSDictionary *existing = RYGMCLoadCachedNameMappingCatalog(NULL);
        if (!existing.count) existing = RYGMCCatalogFromCurrentModels(self);
        if (existing.count) [result addEntriesFromDictionary:existing];
    }
    RYGMCMergeNameMappingCatalog(result, incoming);
    if (!RYGMCSaveNameMappingCatalog(result, error)) return NO;
    if (!RYGMCVerifyPersistedCatalog(result, error)) return NO;

    NSData *canonical = RYGMCLoadCachedNameMappingData();
    NSString *nativePath = [self ryg_nativeNameMappingPath];
    if (nativePath.length && canonical.length &&
        ![canonical writeToFile:nativePath options:NSDataWritingAtomic error:error]) return NO;

    [self reloadFromRuntime];
    RYGMCPostNamesChanged(self);
    return YES;
}

- (NSData *)ryg_exportNameMappingData:(NSError **)error {
    NSData *cached = RYGMCLoadCachedNameMappingData();
    if (cached.length) return cached;
    NSString *nativePath = [self ryg_nativeNameMappingPath];
    NSData *native = nativePath.length ? [NSData dataWithContentsOfFile:nativePath options:0 error:nil] : nil;
    if (native.length) return native;
    NSDictionary *catalog = RYGMCCatalogFromCurrentModels(self);
    if (!catalog.count) {
        if (error) *error = RYGMCJSONError(@"No MobileConfig name mapping is available to export.");
        return nil;
    }
    return RYGMCNameMappingDataFromCatalog(catalog, error);
}

- (BOOL)ryg_importAndApplyOverridesData:(NSData *)data
                           appliedCount:(NSUInteger *)appliedCount
                                  error:(NSError **)error {
    if (appliedCount) *appliedCount = 0;
    if (!data.length) {
        if (error) *error = RYGMCJSONError(@"The mc_overrides.json file is empty.");
        return NO;
    }

    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![parsed isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = RYGMCJSONError(@"mc_overrides.json must be an object keyed by <config>:. ");
        return NO;
    }
    NSDictionary *json = parsed;

    [self prepare];
    NSMutableDictionary<NSNumber *, RYGMCConfig *> *configs = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in self.allConfigs) configs[@(config.number)] = config;

    // Validate the entire canonical document first. Nothing is applied until
    // every structural field and every known runtime-backed value is valid.
    NSMutableArray<NSDictionary *> *actions = [NSMutableArray array];
    for (id rawKey in json) {
        if (![rawKey isKindOfClass:NSString.class]) {
            if (error) *error = RYGMCJSONError(@"Every mc_overrides key must be a string.");
            return NO;
        }
        NSString *key = rawKey;
        id rawLines = json[key];

        if ([key isEqualToString:kRYGMCQEOverridesKey]) {
            if (![rawLines isKindOfClass:NSArray.class]) {
                if (error) *error = RYGMCJSONError(@"_qe_overrides_ must be an array.");
                return NO;
            }
            for (id item in (NSArray *)rawLines) {
                if (![item isKindOfClass:NSString.class]) {
                    if (error) *error = RYGMCJSONError(@"Every _qe_overrides_ entry must be a string.");
                    return NO;
                }
            }
            continue;
        }

        if (![key hasSuffix:@":"] || key.length < 2 || ![rawLines isKindOfClass:NSArray.class]) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Invalid canonical config entry: %@", key]);
            return NO;
        }
        unsigned long long configNumber = 0;
        if (!RYGMCParseUnsigned([key substringToIndex:key.length - 1], UINT32_MAX, &configNumber)) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Invalid config id: %@", key]);
            return NO;
        }

        RYGMCConfig *config = configs[@(configNumber)];
        NSMutableDictionary<NSNumber *, RYGMCParam *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *param in config.params) params[@(param.paramIndex)] = param;
        NSMutableSet<NSNumber *> *seenIndices = [NSMutableSet set];

        for (id rawLine in (NSArray *)rawLines) {
            if (![rawLine isKindOfClass:NSString.class]) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Config %@ contains a non-string override row.", key]);
                return NO;
            }
            unsigned int paramIndex = 0;
            NSString *valueText = nil;
            if (!RYGMCParseCanonicalLine(rawLine, &paramIndex, &valueText)) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Invalid override row in %@: %@", key, rawLine]);
                return NO;
            }
            NSNumber *indexKey = @(paramIndex);
            if ([seenIndices containsObject:indexKey]) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Duplicate override %@:%u", key, paramIndex]);
                return NO;
            }
            [seenIndices addObject:indexKey];

            RYGMCParam *param = params[indexKey];
            if (!param || !param.isRuntimeBacked || !RYGMCTypeIsRuntimeValue(param.type)) {
                // Valid canonical row whose current iOS binary has no typed
                // runtime backing. Preserve it exactly; never invent a PID/type.
                continue;
            }
            id value = RYGMCParseCanonicalJSONValue(valueText, param.type);
            if (!value) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Type mismatch for %@:%u (%@).",
                                                    key, paramIndex, param.typeName ?: @"unknown"]);
                return NO;
            }
            [actions addObject:@{@"param":param, @"value":value}];
        }
    }

    NSData *canonical = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
    if (!canonical) return NO;

    // Persist the complete canonical document before applying its supported
    // rows. This sidecar is the round-trip source for mapping-only / unknown
    // rows and _qe_overrides_ even when the native *.data path is not available
    // yet during early app startup.
    if (![canonical writeToFile:RYGMCCanonicalOverridesCachePath()
                        options:NSDataWritingAtomic
                          error:error]) return NO;
    NSString *nativePath = [self ryg_nativeOverridesJSONPath];
    if (nativePath.length &&
        ![canonical writeToFile:nativePath options:NSDataWritingAtomic error:error]) return NO;

    NSUInteger applied = 0;
    for (NSDictionary *action in actions) {
        RYGMCParam *param = action[@"param"];
        id value = action[@"value"];
        if (![self setOverride:value for:param]) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Could not apply %@:%u.",
                                                [NSString stringWithFormat:@"%u", param.configNumber],
                                                param.paramIndex]);
            return NO;
        }
        applied++;
    }
    [self reapplyOverridesToNativeTable];
    if (appliedCount) *appliedCount = applied;
    return YES;
}

- (NSData *)ryg_exportOverridesData:(NSError **)error {
    NSDictionary *base = nil;
    NSString *nativePath = [self ryg_nativeOverridesJSONPath];
    if (nativePath.length) {
        base = RYGMCOverridesRootFromData([NSData dataWithContentsOfFile:nativePath options:0 error:nil]);
    }
    if (!base) {
        base = RYGMCOverridesRootFromData([NSData dataWithContentsOfFile:RYGMCCanonicalOverridesCachePath()
                                                                 options:0
                                                                   error:nil]);
    }

    NSMutableDictionary<NSString *, id> *root = [NSMutableDictionary dictionary];
    if (base) [root addEntriesFromDictionary:base];
    if (![root[kRYGMCQEOverridesKey] isKindOfClass:NSArray.class]) root[kRYGMCQEOverridesKey] = @[];

    for (RYGMCConfig *config in self.allConfigs) {
        NSString *configKey = [NSString stringWithFormat:@"%u:", config.number];
        NSArray *existing = [root[configKey] isKindOfClass:NSArray.class] ? root[configKey] : @[];
        NSMutableDictionary<NSNumber *, NSString *> *knownLines = [NSMutableDictionary dictionary];
        NSMutableArray<NSString *> *passthrough = [NSMutableArray array];

        for (id rawLine in existing) {
            if (![rawLine isKindOfClass:NSString.class]) continue;
            unsigned int index = 0;
            if (RYGMCParseCanonicalLine(rawLine, &index, NULL)) knownLines[@(index)] = rawLine;
            else [passthrough addObject:rawLine];
        }

        for (RYGMCParam *param in config.params) {
            if (!param.isRuntimeBacked || !RYGMCTypeIsRuntimeValue(param.type)) continue;
            NSNumber *indexKey = @(param.paramIndex);
            if ([self overrideStateFor:param] == RYGMCOverrideSet) {
                id value = [self overrideValueFor:param];
                if (value) {
                    knownLines[indexKey] = [NSString stringWithFormat:@"%u: : %@",
                                            param.paramIndex,
                                            RYGMCJSONValueString(value, param.type)];
                }
            } else {
                // Clearing a supported live override must also remove its old
                // imported row instead of resurrecting it during export.
                [knownLines removeObjectForKey:indexKey];
            }
        }

        NSArray<NSNumber *> *indices = [knownLines.allKeys sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:passthrough.count + indices.count];
        [lines addObjectsFromArray:passthrough];
        for (NSNumber *index in indices) [lines addObject:knownLines[index]];
        if (lines.count) root[configKey] = lines;
        else [root removeObjectForKey:configKey];
    }

    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
}

@end
