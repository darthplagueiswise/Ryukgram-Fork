#import "SCIMobileConfigIdNameMappingExporter.h"
#import "SCIMobileConfigMapping.h"
#import "SCIDexKitNameResolver.h"
#import <dlfcn.h>

NSString * const SCIMobileConfigIdNameMappingExporterDidUpdateNotification = @"SCIMobileConfigIdNameMappingExporterDidUpdateNotification";

static NSString * const kSCIIdMapExporterStatusKey = @"sci.mc.id_name_mapping_exporter.last_status";

static const char *kSCIIdMapSymbolTryGetNamedParamsList = "__ZN12mobileconfig23FBMobileConfigIdNameMap21tryGetNamedParamsListERKNSt3__110shared_ptrIKNS1_6vectorINS_13config_meta_tENS1_9allocatorIS4_EEEEEERKNS1_12basic_stringIcNS1_11char_traitsIcEENS5_IcEEEE";
static const char *kSCIIdMapSymbolGetFilePath = "__ZN12mobileconfig23FBMobileConfigIdNameMap19getIdToNameFilePathERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEE";
static const char *kSCIIdMapSymbolMakeConfigMetaList = "__ZN12mobileconfig25FBMobileConfigSchemaUtils18makeConfigMetaListEPKNS_15c_config_meta_tEi";
static const char *kSCIIdMapSymbolPersistExtraData = "__ZN12mobileconfig28FBMobileConfigStorageManager16persistExtraDataERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_";
static const char *kSCIIdMapSymbolTryUpdate = "IGMobileConfigTryUpdateConfigsWithCompletion";

static NSString *SCIIdMapString(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSString *SCIIdMapSafeComponent(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length) return @"unknown";
    NSMutableString *out = [NSMutableString stringWithCapacity:value.length];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"].invertedSet;
    for (NSString *part in [value componentsSeparatedByCharactersInSet:bad]) if (part.length) [out appendString:part];
    return out.length ? out : @"unknown";
}

static NSString *SCIIdMapTimestamp(void) {
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    return [fmt stringFromDate:[NSDate date]] ?: @"now";
}

static NSString *SCIIdMapISODate(NSDate *date) {
    if (![date isKindOfClass:NSDate.class]) return @"";
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    return [fmt stringFromDate:date] ?: @"";
}

static id SCIIdMapJSONObjectFromData(NSData *data) {
    if (!data.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

static NSUInteger SCIIdMapObjectCount(id object) {
    if ([object isKindOfClass:NSArray.class]) return [(NSArray *)object count];
    if (![object isKindOfClass:NSDictionary.class]) return 0;
    NSDictionary *dict = (NSDictionary *)object;
    id array = dict[@"id_to_names"] ?: dict[@"idToNames"] ?: dict[@"mappings"];
    if ([array isKindOfClass:NSArray.class]) return [(NSArray *)array count];
    if ([array isKindOfClass:NSDictionary.class]) return [(NSDictionary *)array count];
    return dict.count;
}

static BOOL SCIIdMapLooksUsable(id object) {
    if ([object isKindOfClass:NSArray.class]) return [(NSArray *)object count] > 0;
    if (![object isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *dict = (NSDictionary *)object;
    id array = dict[@"id_to_names"] ?: dict[@"idToNames"] ?: dict[@"mappings"];
    if ([array isKindOfClass:NSArray.class]) return [(NSArray *)array count] > 0;
    if ([array isKindOfClass:NSDictionary.class]) return [(NSDictionary *)array count] > 0;
    return dict.count > 0;
}

static NSDictionary *SCIIdMapCandidateInfo(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.length) return @{};
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDir] && !isDir;
    NSMutableDictionary *info = [@{@"path": path, @"exists": @(exists), @"valid": @NO, @"bytes": @0, @"count": @0, @"modified": @""} mutableCopy];
    if (!exists) return info;

    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil] ?: @{};
    NSNumber *size = [attrs[NSFileSize] respondsToSelector:@selector(unsignedLongLongValue)] ? attrs[NSFileSize] : @0;
    NSDate *modified = [attrs[NSFileModificationDate] isKindOfClass:NSDate.class] ? attrs[NSFileModificationDate] : nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    id json = SCIIdMapJSONObjectFromData(data);
    BOOL valid = SCIIdMapLooksUsable(json);
    NSUInteger count = SCIIdMapObjectCount(json);
    info[@"valid"] = @(valid);
    info[@"bytes"] = size;
    info[@"count"] = @(count);
    info[@"modified"] = SCIIdMapISODate(modified);
    return info;
}

static BOOL SCIIdMapWriteData(NSData *data, NSString *path, NSMutableArray<NSString *> *outputs, NSMutableArray<NSString *> *errors) {
    if (!data.length || !path.length) return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSError *dirError = nil;
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&dirError]) {
        [errors addObject:[NSString stringWithFormat:@"mkdir failed %@: %@", dir, dirError.localizedDescription ?: @"unknown"]];
        return NO;
    }
    NSError *writeError = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        [errors addObject:[NSString stringWithFormat:@"write failed %@: %@", path, writeError.localizedDescription ?: @"unknown"]];
        return NO;
    }
    [outputs addObject:path];
    return YES;
}

static NSArray<NSString *> *SCIIdMapOutputPaths(void) {
    NSString *home = NSHomeDirectory() ?: @"";
    NSString *docs = [home stringByAppendingPathComponent:@"Documents/RyukGram"];
    NSString *support = [[home stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:@"RyukGram/mobileconfig"];
    NSString *version = SCIIdMapSafeComponent([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown");
    NSString *build = SCIIdMapSafeComponent([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"");
    NSString *stamp = SCIIdMapTimestamp();
    NSString *versioned = build.length ? [NSString stringWithFormat:@"id_name_mapping_%@_%@_%@.json", version, build, stamp] : [NSString stringWithFormat:@"id_name_mapping_%@_%@.json", version, stamp];

    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    [paths addObject:[SCIMobileConfigMapping primaryIDNameMappingPath]];
    [paths addObject:[[SCIMobileConfigMapping legacyApplicationSupportMobileConfigDirectory] stringByAppendingPathComponent:@"id_name_mapping.json"]];
    [paths addObject:[support stringByAppendingPathComponent:@"id_name_mapping.json"]];
    [paths addObject:[docs stringByAppendingPathComponent:@"id_name_mapping.json"]];
    [paths addObject:[docs stringByAppendingPathComponent:versioned]];
    [paths addObject:[NSTemporaryDirectory() stringByAppendingPathComponent:@"id_name_mapping.json"]];
    return paths.array;
}

static void SCIIdMapSetStatus(NSString *status) {
    if (!status.length) return;
    [[NSUserDefaults standardUserDefaults] setObject:status forKey:kSCIIdMapExporterStatusKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSDictionary *SCIIdMapNativeSymbolProbe(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    struct Entry { NSString *label; const char *symbol; NSString *expectedVM; } entries[] = {
        {@"FBMobileConfigIdNameMap.tryGetNamedParamsList", kSCIIdMapSymbolTryGetNamedParamsList, @"0x1411598"},
        {@"FBMobileConfigIdNameMap.getIdToNameFilePath", kSCIIdMapSymbolGetFilePath, @"0x2a47e4"},
        {@"FBMobileConfigSchemaUtils.makeConfigMetaList", kSCIIdMapSymbolMakeConfigMetaList, @"0x28aefc"},
        {@"FBMobileConfigStorageManager.persistExtraData", kSCIIdMapSymbolPersistExtraData, @"0x15c33dc"},
        {@"IGMobileConfigTryUpdateConfigsWithCompletion", kSCIIdMapSymbolTryUpdate, @"0x702aa8"},
    };

    for (NSUInteger i = 0; i < sizeof(entries) / sizeof(entries[0]); i++) {
        void *target = dlsym(RTLD_DEFAULT, entries[i].symbol);
        out[entries[i].label] = @{
            @"loaded": @(target != NULL),
            @"address": target ? [NSString stringWithFormat:@"%p", target] : @"not-loaded",
            @"expectedVM": entries[i].expectedVM ?: @"",
            @"mode": @"probe-only"
        };
    }
    return out;
}

@implementation SCIMobileConfigIdNameMappingExporter

+ (NSArray<NSString *> *)candidateIDNameMappingPaths {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    NSString *home = NSHomeDirectory() ?: @"";
    for (NSString *path in @[
        [[home stringByAppendingPathComponent:@"mobileconfig"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"mobileconfig_spoof/mobileconfig"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"mobileconfig_spoof"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Documents/mobileconfig"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Documents/RyukGram"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Library/mobileconfig"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Library/Caches/mobileconfig"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Library/Application Support/mobileconfig"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Library/Application Support/RyukGram"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"Library/Application Support/RyukGram/mobileconfig"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [[home stringByAppendingPathComponent:@"tmp"] stringByAppendingPathComponent:@"id_name_mapping.json"],
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"id_name_mapping.json"]
    ]) if (path.length) [paths addObject:path];
    for (NSString *path in [SCIMobileConfigMapping mappingPaths]) if (path.length) [paths addObject:path];
    return paths.array;
}

+ (NSDictionary *)installNativePathObserver {
    NSDictionary *symbolProbe = SCIIdMapNativeSymbolProbe();
    NSString *primary = [SCIMobileConfigMapping primaryIDNameMappingPath] ?: @"";
    NSString *status = [NSString stringWithFormat:@"id_name_mapping scan only · native hooks disabled · primary=%@", primary];
    SCIIdMapSetStatus(status);
    return @{@"ok": @YES,
             @"mode": @"path-scan-only",
             @"primaryPath": primary,
             @"observerInstalled": @NO,
             @"passivePersistObserverInstalled": @NO,
             @"symbolProbe": symbolProbe ?: @{},
             @"status": status};
}

+ (NSDictionary *)exportIDNameMappingNow {
    NSDictionary *probe = [self installNativePathObserver];
    NSArray<NSString *> *candidates = [self candidateIDNameMappingPaths];
    NSMutableArray<NSDictionary *> *candidateInfo = [NSMutableArray array];
    NSDictionary *best = nil;

    for (NSString *path in candidates) {
        NSDictionary *info = SCIIdMapCandidateInfo(path);
        [candidateInfo addObject:info];
        if (![info[@"valid"] boolValue]) continue;
        if (!best) { best = info; continue; }
        NSUInteger bestCount = [best[@"count"] unsignedIntegerValue];
        NSUInteger count = [info[@"count"] unsignedIntegerValue];
        unsigned long long bestBytes = [best[@"bytes"] unsignedLongLongValue];
        unsigned long long bytes = [info[@"bytes"] unsignedLongLongValue];
        if (count > bestCount || (count == bestCount && bytes > bestBytes)) best = info;
    }

    NSMutableArray<NSDictionary *> *visibleCandidates = [NSMutableArray array];
    for (NSDictionary *info in candidateInfo) if ([info[@"exists"] boolValue] || visibleCandidates.count < 80) [visibleCandidates addObject:info];

    if (!best) {
        NSString *status = [NSString stringWithFormat:@"id_name_mapping not found · checked=%lu · primary=%@ · native hooks disabled", (unsigned long)candidates.count, [SCIMobileConfigMapping primaryIDNameMappingPath] ?: @""];
        SCIIdMapSetStatus(status);
        return @{@"ok": @NO,
                 @"mode": @"path-scan-only",
                 @"status": status,
                 @"probe": probe ?: @{},
                 @"symbolProbe": probe[@"symbolProbe"] ?: @{},
                 @"observerInstalled": probe[@"observerInstalled"] ?: @NO,
                 @"passivePersistObserverInstalled": probe[@"passivePersistObserverInstalled"] ?: @NO,
                 @"checked": @(candidates.count),
                 @"checkedPaths": @(candidates.count),
                 @"candidates": visibleCandidates,
                 @"count": @0,
                 @"source": @"",
                 @"outputs": @[],
                 @"errors": @[],
                 @"nativeImport": @{@"ok": @NO, @"mode": @"probe-only", @"reason": @"native hooks disabled; matching InstaFEL path-copy model"}};
    }

    NSString *source = SCIIdMapString(best[@"path"]);
    NSData *data = [NSData dataWithContentsOfFile:source options:0 error:nil];
    id json = SCIIdMapJSONObjectFromData(data);
    NSUInteger count = SCIIdMapObjectCount(json);
    NSMutableArray<NSString *> *outputs = [NSMutableArray array];
    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    for (NSString *output in SCIIdMapOutputPaths()) SCIIdMapWriteData(data, output, outputs, errors);

    NSString *manifestPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/RyukGram"] stringByAppendingPathComponent:@"id_name_mapping_export_manifest.json"];
    NSDictionary *manifest = @{@"ok": @(outputs.count > 0), @"mode": @"path-copy", @"source": source ?: @"", @"outputs": outputs, @"errors": errors, @"count": @(count), @"bytes": best[@"bytes"] ?: @0, @"modified": best[@"modified"] ?: @"", @"probe": probe ?: @{}, @"symbolProbe": probe[@"symbolProbe"] ?: @{}, @"observerInstalled": probe[@"observerInstalled"] ?: @NO, @"passivePersistObserverInstalled": probe[@"passivePersistObserverInstalled"] ?: @NO, @"bundleVersion": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"", @"bundleBuild": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"", @"exportedAt": SCIIdMapISODate([NSDate date])};
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
    if (manifestData.length) SCIIdMapWriteData(manifestData, manifestPath, outputs, errors);

    NSString *status = [NSString stringWithFormat:@"id_name_mapping exported · entries=%lu · source=%@ · primary=%@", (unsigned long)count, source, [SCIMobileConfigMapping primaryIDNameMappingPath] ?: @""];
    SCIIdMapSetStatus(status);
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIMobileConfigIdNameMappingExporterDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIDexKitNameResolverDidUpdateNotification object:nil];
    return @{@"ok": @(outputs.count > 0),
             @"mode": @"path-copy",
             @"status": status,
             @"source": source ?: @"",
             @"outputs": outputs,
             @"errors": errors,
             @"count": @(count),
             @"bytes": best[@"bytes"] ?: @0,
             @"modified": best[@"modified"] ?: @"",
             @"probe": probe ?: @{},
             @"symbolProbe": probe[@"symbolProbe"] ?: @{},
             @"observerInstalled": probe[@"observerInstalled"] ?: @NO,
             @"passivePersistObserverInstalled": probe[@"passivePersistObserverInstalled"] ?: @NO,
             @"checked": @(candidates.count),
             @"checkedPaths": @(candidates.count),
             @"manifest": manifestPath ?: @"",
             @"candidates": visibleCandidates};
}

+ (nullable NSString *)lastStatusLine {
    NSString *status = [[NSUserDefaults standardUserDefaults] stringForKey:kSCIIdMapExporterStatusKey];
    return status.length ? status : nil;
}

@end
