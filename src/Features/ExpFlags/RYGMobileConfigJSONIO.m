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
    if (!data.length) { if (error) *error = RYGMCJSONError(@"The id_name_mapping.json file is empty."); return NO; }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSArray.class]) { if (error && !*error) *error = RYGMCJSONError(@"id_name_mapping.json must be an array of colon-delimited strings."); return NO; }
    for (id entry in (NSArray *)json) {
        if (![entry isKindOfClass:NSString.class]) { if (error) *error = RYGMCJSONError(@"id_name_mapping.json contains a non-string entry."); return NO; }
        NSArray *parts = [(NSString *)entry componentsSeparatedByString:@":"];
        if (parts.count < 2 || [parts.firstObject longLongValue] <= 0) { if (error) *error = RYGMCJSONError(@"id_name_mapping.json contains an invalid config entry."); return NO; }
    }
    NSString *path = [self ryg_nativeNameMappingPath];
    if (!path.length) { if (error) *error = RYGMCJSONError(@"Instagram has not exposed its active MobileConfig data directory yet. Open the app until MobileConfig is read, then retry."); return NO; }
    NSData *canonical = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
    if (!canonical || ![canonical writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    [self reloadFromRuntime];
    return YES;
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
