#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigNameMappingStore.h"
#import <math.h>
#include <stdlib.h>
#include <stdint.h>

static NSString *const kRYGMobileConfigNamesDidChangeNotification = @"RYGMobileConfigNamesDidChange";
static NSString *const kRYGMCQEOverridesKey = @"_qe_overrides_";
NSString *const RYGMCRuntimeSnapshotSchemaV1 = @"com.ryukgram.mobileconfig.runtime-snapshot.v1";

@interface RYGMobileConfig (RYGPrivateNativePath)
- (NSString *)mcDirectory;
@end

static NSError *RYGMCJSONError(NSString *message) {
    return [NSError errorWithDomain:@"com.ryukgram.mobileconfig.json"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey:message ?: @"MobileConfig JSON error"}];
}

static NSString *RYGMCCanonicalOverridesCachePath(void) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                             NSUserDomainMask,
                                                             YES).firstObject;
    if (!support.length) return nil;
    NSString *directory = [support stringByAppendingPathComponent:@"RyukGram"];
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

static id RYGMCParseNativeValue(NSString *text, RYGMCType type) {
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (type == RYGMCTypeBool) {
        NSString *lower = trim.lowercaseString;
        if ([lower isEqualToString:@"true"] || [lower isEqualToString:@"1"]) return @YES;
        if ([lower isEqualToString:@"false"] || [lower isEqualToString:@"0"]) return @NO;
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

static BOOL RYGMCValueMatchesType(id value, RYGMCType type) {
    if (type == RYGMCTypeString) return [value isKindOfClass:NSString.class];
    return (type == RYGMCTypeBool || type == RYGMCTypeInt || type == RYGMCTypeDouble) &&
           [value isKindOfClass:NSNumber.class];
}

static NSNumber *RYGMCRuntimeOverrideKey(unsigned int configNumber, unsigned int paramIndex) {
    return @(((uint64_t)configNumber << 32) | (uint64_t)paramIndex);
}

#pragma mark - Native JSON grammar

// Real FBMobileConfig overrides use:
//   "<configID>:<configName>" : ["<paramIndex>: <paramName>: <value>", ...]
// Values can themselves contain ':' (URLs, serialized strings), so only the
// first two separators are structural.
static BOOL RYGMCParseNativeConfigKey(NSString *key,
                                      unsigned int *configNumber,
                                      NSString **configName) {
    if (![key isKindOfClass:NSString.class] || !key.length) return NO;
    NSRange colon = [key rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0) return NO;
    unsigned long long number = 0;
    if (!RYGMCParseUnsigned([key substringToIndex:colon.location], UINT32_MAX, &number)) return NO;
    if (configNumber) *configNumber = (unsigned int)number;
    if (configName) *configName = [key substringFromIndex:NSMaxRange(colon)];
    return YES;
}

static BOOL RYGMCParseNativeOverrideLine(NSString *line,
                                         unsigned int *paramIndex,
                                         NSString **paramName,
                                         NSString **valueText) {
    if (![line isKindOfClass:NSString.class] || !line.length) return NO;
    NSRange first = [line rangeOfString:@":"];
    if (first.location == NSNotFound || first.location == 0) return NO;
    unsigned long long index = 0;
    if (!RYGMCParseUnsigned([line substringToIndex:first.location], UINT32_MAX, &index)) return NO;

    NSUInteger nameStart = NSMaxRange(first);
    while (nameStart < line.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:nameStart]]) nameStart++;
    NSRange rest = NSMakeRange(nameStart, line.length - nameStart);
    NSRange second = [line rangeOfString:@":" options:0 range:rest];
    if (second.location == NSNotFound) return NO;

    NSString *name = [[line substringWithRange:NSMakeRange(nameStart, second.location - nameStart)]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSUInteger valueStart = NSMaxRange(second);
    if (valueStart < line.length && [line characterAtIndex:valueStart] == ' ') valueStart++;

    if (paramIndex) *paramIndex = (unsigned int)index;
    if (paramName) *paramName = name ?: @"";
    if (valueText) *valueText = valueStart <= line.length ? [line substringFromIndex:valueStart] : @"";
    return YES;
}

static NSString *RYGMCNativeConfigKey(unsigned int number, NSString *name) {
    return [NSString stringWithFormat:@"%u:%@", number, name ?: @""];
}

static NSString *RYGMCNativeOverrideLine(RYGMCParam *param, NSString *fallbackName, id value) {
    NSString *name = param.name.length ? param.name : (fallbackName ?: @"");
    return [NSString stringWithFormat:@"%u: %@: %@",
            param.paramIndex,
            name,
            RYGMCJSONValueString(value, param.type) ?: @""];
}

static NSDictionary *RYGMCOverridesRootFromData(NSData *data) {
    if (!data.length) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [root isKindOfClass:NSDictionary.class] ? root : nil;
}

static NSString *RYGMCExistingConfigKey(NSDictionary *root, RYGMCConfig *config) {
    NSString *first = nil;
    for (id rawKey in root) {
        if (![rawKey isKindOfClass:NSString.class] || [rawKey isEqualToString:kRYGMCQEOverridesKey]) continue;
        unsigned int number = 0;
        NSString *name = nil;
        if (!RYGMCParseNativeConfigKey(rawKey, &number, &name) || number != config.number) continue;
        if (!first) first = rawKey;
        if (config.name.length && [name isEqualToString:config.name]) return rawKey;
    }
    return first;
}

#pragma mark - Name mapping

static NSDictionary<NSNumber *, NSDictionary *> *RYGMCNameCatalogFromNativeData(NSData *data, NSError **error) {
    if (!data.length) return nil;
    NSDictionary *catalog = RYGMCNameMappingCatalogFromData(data, NULL);
    if (catalog) return catalog;

    // Some diagnostics/fetch paths wrap the same canonical string array under
    // id_to_names. Accept that wrapper for discovery/import, but persist/export
    // the canonical native array representation.
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *rows = [root isKindOfClass:NSDictionary.class] && [root[@"id_to_names"] isKindOfClass:NSArray.class]
        ? root[@"id_to_names"] : nil;
    if (rows) {
        NSData *canonical = [NSJSONSerialization dataWithJSONObject:rows options:0 error:nil];
        catalog = RYGMCNameMappingCatalogFromData(canonical, error);
        if (catalog) return catalog;
    }
    if (error && !*error) *error = RYGMCJSONError(@"id_name_mapping.json is not a canonical MobileConfig names array.");
    return nil;
}

static NSDictionary<NSNumber *, NSDictionary *> *RYGMCCatalogFromCurrentModels(RYGMobileConfig *mobileConfig) {
    NSMutableDictionary<NSNumber *, NSDictionary *> *catalog = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in [mobileConfig allConfigsIncludingMappingOnly] ?: @[]) {
        NSMutableDictionary<NSNumber *, NSString *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *param in config.params ?: @[]) if (param.name.length) params[@(param.paramIndex)] = param.name;
        if (config.name.length || params.count)
            catalog[@(config.number)] = @{@"name":config.name ?: @"", @"params":params.copy};
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
        [NSNotificationCenter.defaultCenter postNotificationName:kRYGMobileConfigNamesDidChangeNotification object:mobileConfig];
    };
    if (NSThread.isMainThread) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

@implementation RYGMobileConfig (RYGJSONIO)

- (NSString *)ryg_nativeDataDirectory {
    NSString *path = nil;
    @try { path = [self mcDirectory]; } @catch (__unused NSException *exception) {}
    if (![path isKindOfClass:NSString.class] || !path.length) return nil;
    path = path.stringByStandardizingPath;
    if (![path.pathExtension.lowercaseString isEqualToString:@"data"]) return nil;
    BOOL isDirectory = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory ? path : nil;
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
    NSDictionary<NSNumber *, NSDictionary *> *incoming = RYGMCNameCatalogFromNativeData(data, error);
    if (!incoming) return NO;

    NSMutableDictionary<NSNumber *, NSDictionary *> *result = [NSMutableDictionary dictionary];
    if (mode == RYGMCNameMappingImportModeMerge) {
        NSString *nativePath = [self ryg_nativeNameMappingPath];
        NSData *nativeData = nativePath.length ? [NSData dataWithContentsOfFile:nativePath options:0 error:nil] : nil;
        NSDictionary *native = RYGMCNameCatalogFromNativeData(nativeData, NULL);
        if (native.count) [result addEntriesFromDictionary:native];
        NSDictionary *cached = RYGMCLoadCachedNameMappingCatalog(NULL);
        if (cached.count) RYGMCMergeNameMappingCatalog(result, cached);
        if (!result.count) [result addEntriesFromDictionary:RYGMCCatalogFromCurrentModels(self) ?: @{}];
    }
    RYGMCMergeNameMappingCatalog(result, incoming);
    if (!RYGMCSaveNameMappingCatalog(result, error)) return NO;
    if (!RYGMCVerifyPersistedCatalog(result, error)) return NO;

    [self reloadFromRuntime];
    RYGMCPostNamesChanged(self);
    return YES;
}

- (NSData *)ryg_exportNameMappingData:(NSError **)error {
    NSMutableDictionary<NSNumber *, NSDictionary *> *effective = [NSMutableDictionary dictionary];
    NSString *nativePath = [self ryg_nativeNameMappingPath];
    NSData *nativeData = nativePath.length ? [NSData dataWithContentsOfFile:nativePath options:0 error:nil] : nil;
    NSDictionary *native = RYGMCNameCatalogFromNativeData(nativeData, NULL);
    if (native.count) [effective addEntriesFromDictionary:native];
    NSDictionary *cached = RYGMCLoadCachedNameMappingCatalog(NULL);
    if (cached.count) RYGMCMergeNameMappingCatalog(effective, cached);
    if (!effective.count) [effective addEntriesFromDictionary:RYGMCCatalogFromCurrentModels(self) ?: @{}];
    if (!effective.count) {
        if (error) *error = RYGMCJSONError(@"No MobileConfig name mapping is available to export.");
        return nil;
    }
    return RYGMCNameMappingDataFromCatalog(effective, error);
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
        if (error && !*error) *error = RYGMCJSONError(@"mc_overrides.json must be a JSON object.");
        return NO;
    }
    NSDictionary *json = parsed;

    NSMutableDictionary<NSNumber *, RYGMCConfig *> *configs = [NSMutableDictionary dictionary];
    for (RYGMCConfig *config in [self allConfigsIncludingMappingOnly] ?: @[])
        if (config.hasRuntimeBacking) configs[@(config.number)] = config;

    NSMutableArray<NSDictionary *> *actions = [NSMutableArray array];
    NSMutableSet<NSNumber *> *desiredRuntimeKeys = [NSMutableSet set];
    for (id rawKey in json) {
        if (![rawKey isKindOfClass:NSString.class]) continue;
        NSString *key = rawKey;
        id rawLines = json[key];
        if ([key isEqualToString:kRYGMCQEOverridesKey]) continue;

        unsigned int configNumber = 0;
        if (!RYGMCParseNativeConfigKey(key, &configNumber, NULL) || ![rawLines isKindOfClass:NSArray.class])
            continue; // Unknown top-level material is passthrough, never destroyed.

        RYGMCConfig *config = configs[@(configNumber)];
        if (!config) continue;
        NSMutableDictionary<NSNumber *, RYGMCParam *> *params = [NSMutableDictionary dictionary];
        for (RYGMCParam *param in config.params ?: @[])
            if (param.isRuntimeBacked && RYGMCTypeIsRuntimeValue(param.type)) params[@(param.paramIndex)] = param;
        NSMutableSet<NSNumber *> *seenKnown = [NSMutableSet set];

        for (id rawLine in (NSArray *)rawLines) {
            if (![rawLine isKindOfClass:NSString.class]) continue;
            unsigned int paramIndex = 0;
            NSString *valueText = nil;
            if (!RYGMCParseNativeOverrideLine(rawLine, &paramIndex, NULL, &valueText)) continue;
            RYGMCParam *param = params[@(paramIndex)];
            if (!param) continue; // Mapping-only/unknown rows remain passthrough.
            NSNumber *runtimeKey = RYGMCRuntimeOverrideKey(param.configNumber, param.paramIndex);
            if ([seenKnown containsObject:runtimeKey]) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Duplicate typed override %u:%u.", configNumber, paramIndex]);
                return NO;
            }
            [seenKnown addObject:runtimeKey];
            id value = RYGMCParseNativeValue(valueText, param.type);
            if (!value) {
                if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Type mismatch for %u:%u (%@).",
                                                    configNumber, paramIndex, param.typeName ?: @"unknown"]);
                return NO;
            }
            [desiredRuntimeKeys addObject:runtimeKey];
            [actions addObject:@{@"param":param, @"value":value}];
        }
    }

    NSMutableArray<RYGMCParam *> *clearParams = [NSMutableArray array];
    for (RYGMCConfig *config in configs.allValues) for (RYGMCParam *param in config.params ?: @[]) {
        if (!param.isRuntimeBacked || !RYGMCTypeIsRuntimeValue(param.type)) continue;
        if ([self overrideStateFor:param] != RYGMCOverrideSet) continue;
        NSNumber *runtimeKey = RYGMCRuntimeOverrideKey(param.configNumber, param.paramIndex);
        if (![desiredRuntimeKeys containsObject:runtimeKey]) [clearParams addObject:param];
    }

    NSData *canonical = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
    if (!canonical) return NO;
    NSString *cachePath = RYGMCCanonicalOverridesCachePath();
    if (!cachePath.length) {
        if (error) *error = RYGMCJSONError(@"RyukGram overrides cache path is unavailable.");
        return NO;
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL cacheExisted = [fm fileExistsAtPath:cachePath];
    NSData *previousCache = cacheExisted ? [NSData dataWithContentsOfFile:cachePath options:0 error:nil] : nil;

    NSMutableArray<NSDictionary *> *previousOverrides = [NSMutableArray array];
    NSMutableSet<NSNumber *> *snapshotted = [NSMutableSet set];
    void (^snapshot)(RYGMCParam *) = ^(RYGMCParam *param) {
        NSNumber *key = RYGMCRuntimeOverrideKey(param.configNumber, param.paramIndex);
        if ([snapshotted containsObject:key]) return;
        [snapshotted addObject:key];
        BOOL had = [self overrideStateFor:param] == RYGMCOverrideSet;
        [previousOverrides addObject:@{@"param":param,
                                       @"had":@(had),
                                       @"value":had ? ([self overrideValueFor:param] ?: NSNull.null) : NSNull.null}];
    };
    for (RYGMCParam *param in clearParams) snapshot(param);
    for (NSDictionary *action in actions) snapshot(action[@"param"]);

    void (^rollback)(void) = ^{
        for (NSInteger i = (NSInteger)previousOverrides.count - 1; i >= 0; i--) {
            NSDictionary *old = previousOverrides[(NSUInteger)i];
            RYGMCParam *param = old[@"param"];
            if ([old[@"had"] boolValue] && old[@"value"] != NSNull.null)
                (void)[self setOverride:old[@"value"] for:param];
            else
                [self clearOverrideFor:param];
        }
        [self reapplyOverridesToNativeTable];
    };

    for (RYGMCParam *param in clearParams) [self clearOverrideFor:param];
    NSUInteger applied = 0;
    for (NSDictionary *action in actions) {
        if (![self setOverride:action[@"value"] for:action[@"param"]]) {
            rollback();
            if (error) *error = RYGMCJSONError(@"A typed override was rejected; previous RyukGram state was restored.");
            return NO;
        }
        applied++;
    }
    [self reapplyOverridesToNativeTable];

    NSError *writeError = nil;
    if (![canonical writeToFile:cachePath options:NSDataWritingAtomic error:&writeError]) {
        if (cacheExisted && previousCache) [previousCache writeToFile:cachePath options:NSDataWritingAtomic error:nil];
        else [fm removeItemAtPath:cachePath error:nil];
        rollback();
        if (error) *error = writeError ?: RYGMCJSONError(@"Could not persist canonical mc_overrides cache.");
        return NO;
    }
    if (appliedCount) *appliedCount = applied;
    return YES;
}

- (NSData *)ryg_exportOverridesData:(NSError **)error {
    NSDictionary *base = nil;
    BOOL usingNativeBase = NO;
    NSString *nativePath = [self ryg_nativeOverridesJSONPath];
    if (nativePath.length) {
        base = RYGMCOverridesRootFromData([NSData dataWithContentsOfFile:nativePath options:0 error:nil]);
        usingNativeBase = base != nil;
    }
    if (!base) base = RYGMCOverridesRootFromData([NSData dataWithContentsOfFile:RYGMCCanonicalOverridesCachePath() options:0 error:nil]);

    NSMutableDictionary<NSString *, id> *root = base ? [base mutableCopy] : [NSMutableDictionary dictionary];

    for (RYGMCConfig *config in [self allConfigsIncludingMappingOnly] ?: @[]) {
        if (!config.hasRuntimeBacking) continue;
        NSString *existingKey = RYGMCExistingConfigKey(root, config);
        NSString *configKey = existingKey ?: RYGMCNativeConfigKey(config.number, config.name);
        NSArray *existing = [root[configKey] isKindOfClass:NSArray.class] ? root[configKey] : @[];
        NSMutableDictionary<NSNumber *, NSString *> *knownLines = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSNumber *, NSString *> *knownNames = [NSMutableDictionary dictionary];
        NSMutableArray<NSString *> *passthrough = [NSMutableArray array];

        for (id rawLine in existing) {
            if (![rawLine isKindOfClass:NSString.class]) { continue; }
            unsigned int index = 0;
            NSString *name = nil;
            if (RYGMCParseNativeOverrideLine(rawLine, &index, &name, NULL)) {
                knownLines[@(index)] = rawLine;
                if (name.length) knownNames[@(index)] = name;
            } else {
                [passthrough addObject:rawLine];
            }
        }

        for (RYGMCParam *param in config.params ?: @[]) {
            if (!param.isRuntimeBacked || !RYGMCTypeIsRuntimeValue(param.type)) continue;
            NSNumber *indexKey = @(param.paramIndex);
            if ([self overrideStateFor:param] == RYGMCOverrideSet) {
                id value = [self overrideValueFor:param];
                if (RYGMCValueMatchesType(value, param.type))
                    knownLines[indexKey] = RYGMCNativeOverrideLine(param, knownNames[indexKey], value);
            } else if (!usingNativeBase) {
                // A local canonical cache is RyukGram-owned; removing an active
                // local override must remove its old serialized row. A REAL native
                // baseline is different: no local override means preserve exactly
                // what Instagram already wrote.
                [knownLines removeObjectForKey:indexKey];
            }
        }

        NSArray<NSNumber *> *indices = [knownLines.allKeys sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:passthrough.count + indices.count];
        [lines addObjectsFromArray:passthrough];
        for (NSNumber *index in indices) [lines addObject:knownLines[index]];
        if (lines.count) root[configKey] = lines;
        else if (!usingNativeBase) [root removeObjectForKey:configKey];
    }

    return [NSJSONSerialization dataWithJSONObject:root options:0 error:error];
}

- (BOOL)ryg_isRuntimeSnapshotData:(NSData *)data {
    if (!data.length) return NO;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [root isKindOfClass:NSDictionary.class] &&
           [root[@"schema"] isEqualToString:RYGMCRuntimeSnapshotSchemaV1] &&
           [root[@"entries"] isKindOfClass:NSArray.class];
}

- (NSData *)ryg_exportRuntimeSnapshotData:(NSError **)error {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSUInteger effectiveCount = 0;
    NSUInteger overrideCount = 0;
    for (RYGMCConfig *config in [self allConfigsIncludingMappingOnly] ?: @[]) {
        for (RYGMCParam *param in config.params ?: @[]) {
            if (!param.isRuntimeBacked || !param.paramID || !RYGMCTypeIsRuntimeValue(param.type)) continue;
            NSMutableDictionary *row = [@{
                @"pid":[NSString stringWithFormat:@"%llu", param.paramID],
                @"config":@(param.configNumber),
                @"param":@(param.paramIndex),
                @"ordinal":@(param.ordinal),
                @"type":param.typeName ?: @"unknown",
                @"override_present":@([self overrideStateFor:param] == RYGMCOverrideSet),
            } mutableCopy];
            if (config.name.length) row[@"config_name"] = config.name;
            if (param.name.length) row[@"name"] = param.name;
            id effective = [self liveValueFor:param];
            if (RYGMCValueMatchesType(effective, param.type)) {
                row[@"effective_present"] = @YES;
                row[@"effective_value"] = effective;
                effectiveCount++;
            } else row[@"effective_present"] = @NO;
            if ([row[@"override_present"] boolValue]) {
                id value = [self overrideValueFor:param];
                if (RYGMCValueMatchesType(value, param.type)) {
                    row[@"override_value"] = value;
                    overrideCount++;
                } else row[@"override_present"] = @NO;
            }
            [entries addObject:row.copy];
        }
    }
    if (!entries.count) {
        if (error) *error = RYGMCJSONError(@"Instagram's typed MobileConfig table is unavailable.");
        return nil;
    }
    NSDictionary *document = @{
        @"schema":RYGMCRuntimeSnapshotSchemaV1,
        @"created_at":@([[NSDate date] timeIntervalSince1970]),
        @"bundle_version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
        @"runtime_parameter_count":@(entries.count),
        @"effective_value_count":@(effectiveCount),
        @"override_count":@(overrideCount),
        @"import_policy":@"restore_explicit_overrides_only",
        @"entries":entries,
    };
    return [NSJSONSerialization dataWithJSONObject:document options:0 error:error];
}

- (BOOL)ryg_importRuntimeSnapshotOverridesData:(NSData *)data
                                   appliedCount:(NSUInteger *)appliedCount
                                          error:(NSError **)error {
    if (appliedCount) *appliedCount = 0;
    id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
    if (![parsed isKindOfClass:NSDictionary.class] ||
        ![parsed[@"schema"] isEqualToString:RYGMCRuntimeSnapshotSchemaV1] ||
        ![parsed[@"entries"] isKindOfClass:NSArray.class]) {
        if (error && !*error) *error = RYGMCJSONError(@"This is not a RyukGram typed runtime snapshot.");
        return NO;
    }

    NSMutableDictionary<NSString *, RYGMCParam *> *paramsByPID = [NSMutableDictionary dictionary];
    NSMutableArray<RYGMCParam *> *allRuntimeParams = [NSMutableArray array];
    for (RYGMCConfig *config in [self allConfigsIncludingMappingOnly] ?: @[]) for (RYGMCParam *param in config.params ?: @[]) {
        if (!param.isRuntimeBacked || !param.paramID || !RYGMCTypeIsRuntimeValue(param.type)) continue;
        paramsByPID[[NSString stringWithFormat:@"%llu", param.paramID]] = param;
        [allRuntimeParams addObject:param];
    }

    NSMutableArray<NSDictionary *> *actions = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id candidate in parsed[@"entries"]) {
        if (![candidate isKindOfClass:NSDictionary.class]) {
            if (error) *error = RYGMCJSONError(@"Runtime snapshot contains a non-object entry.");
            return NO;
        }
        NSDictionary *row = candidate;
        NSString *pid = [row[@"pid"] isKindOfClass:NSString.class] ? row[@"pid"] : nil;
        NSNumber *present = [row[@"override_present"] isKindOfClass:NSNumber.class] ? row[@"override_present"] : nil;
        NSNumber *configNumber = [row[@"config"] isKindOfClass:NSNumber.class] ? row[@"config"] : nil;
        NSNumber *paramIndex = [row[@"param"] isKindOfClass:NSNumber.class] ? row[@"param"] : nil;
        NSNumber *ordinal = [row[@"ordinal"] isKindOfClass:NSNumber.class] ? row[@"ordinal"] : nil;
        unsigned long long parsedPID = 0;
        NSString *canonicalPID = nil;
        if (RYGMCParseUnsigned(pid, UINT64_MAX, &parsedPID) && parsedPID)
            canonicalPID = [NSString stringWithFormat:@"%llu", parsedPID];
        if (!canonicalPID.length || ![pid isEqualToString:canonicalPID] || !present || !configNumber || !paramIndex || !ordinal || [seen containsObject:canonicalPID]) {
            if (error) *error = RYGMCJSONError(@"Runtime snapshot contains an invalid or duplicate PID.");
            return NO;
        }
        [seen addObject:canonicalPID];
        if (!present.boolValue) continue;
        RYGMCParam *param = paramsByPID[canonicalPID];
        if (!param) continue;
        NSString *type = [row[@"type"] isKindOfClass:NSString.class] ? row[@"type"] : nil;
        id value = row[@"override_value"];
        BOOL identityMatches = configNumber.unsignedLongLongValue == param.configNumber &&
                               paramIndex.unsignedLongLongValue == param.paramIndex &&
                               ordinal.unsignedLongLongValue == param.ordinal;
        if (!identityMatches || ![type isEqualToString:param.typeName] || !RYGMCValueMatchesType(value, param.type)) {
            if (error) *error = RYGMCJSONError([NSString stringWithFormat:@"Identity/type mismatch for runtime PID %@.", canonicalPID]);
            return NO;
        }
        [actions addObject:@{@"param":param, @"value":value}];
    }

    NSMutableArray<NSDictionary *> *previous = [NSMutableArray array];
    for (RYGMCParam *param in allRuntimeParams) {
        if ([self overrideStateFor:param] != RYGMCOverrideSet) continue;
        id value = [self overrideValueFor:param];
        if (RYGMCValueMatchesType(value, param.type)) [previous addObject:@{@"param":param, @"value":value}];
    }

    [self resetAllOverrides];
    NSUInteger applied = 0;
    for (NSDictionary *action in actions) {
        if (![self setOverride:action[@"value"] for:action[@"param"]]) {
            [self resetAllOverrides];
            for (NSDictionary *old in previous) (void)[self setOverride:old[@"value"] for:old[@"param"]];
            [self reapplyOverridesToNativeTable];
            if (error) *error = RYGMCJSONError(@"Could not apply the snapshot; the previous override set was restored.");
            return NO;
        }
        applied++;
    }
    [self reapplyOverridesToNativeTable];
    if (appliedCount) *appliedCount = applied;
    return YES;
}

@end
