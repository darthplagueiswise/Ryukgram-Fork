#import "SCIMobileConfigMapping.h"

static NSString *const kDir = @"mobileconfig";
static NSString *const kMap = @"id_name_mapping.json";
static NSString *const kOvr = @"mc_overrides.json";

@implementation SCIMobileConfigMapping

+ (NSString *)primaryMobileConfigDirectory {
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:kDir];
}

+ (NSString *)primaryIDNameMappingPath { return [[self primaryMobileConfigDirectory] stringByAppendingPathComponent:kMap]; }
+ (NSString *)primaryOverridesPath { return [[self primaryMobileConfigDirectory] stringByAppendingPathComponent:kOvr]; }

+ (NSString *)bundleIGSchemaPath {
    NSString *root = [NSBundle mainBundle].bundlePath;
    NSArray *c = @[
        [root stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/igios-instagram-schema_client-persist.json"],
        [root stringByAppendingPathComponent:@"Frameworks/FBSharedModules.framework/igios-instagram-schema_client-persist.json"],
        [root stringByAppendingPathComponent:@"igios-instagram-schema_client-persist.json"]
    ];
    for (NSString *p in c) if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    return nil;
}

+ (id)jsonAtPath:(NSString *)p {
    NSData *d = p.length ? [NSData dataWithContentsOfFile:p] : nil;
    if (!d.length) return nil;
    return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
}

+ (void)addIDMapCandidatesForInstagramBundle:(NSString *)bundlePath toSet:(NSMutableOrderedSet<NSString *> *)paths {
    if (!bundlePath.length) return;
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"mobileconfig/id_name_mapping.json"]];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"id_name_mapping.json"]];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/mobileconfig/id_name_mapping.json"]];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/id_name_mapping.json"]];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedModules.framework/mobileconfig/id_name_mapping.json"]];
    [paths addObject:[bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedModules.framework/id_name_mapping.json"]];
}

+ (NSArray<NSString *> *)dynamicInstagramBundlePaths {
    NSMutableOrderedSet<NSString *> *bundles = [NSMutableOrderedSet orderedSet];
    NSString *current = [NSBundle mainBundle].bundlePath;
    if (current.length) [bundles addObject:current];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = @[
        @"/private/var/containers/Bundle/Application",
        @"/var/containers/Bundle/Application"
    ];

    for (NSString *root in roots) {
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *entry in entries) {
            if (!entry.length || [entry hasPrefix:@"."]) continue;
            NSString *candidate = [[root stringByAppendingPathComponent:entry] stringByAppendingPathComponent:@"Instagram.app"];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:candidate isDirectory:&isDir] && isDir) {
                [bundles addObject:candidate];
            }
        }
    }

    return bundles.array;
}

+ (NSArray *)mappingPaths {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    NSString *h = NSHomeDirectory();

    [paths addObject:[self primaryIDNameMappingPath]];
    if (h.length) {
        [paths addObject:[h stringByAppendingPathComponent:@"Documents/mobileconfig/id_name_mapping.json"]];
        [paths addObject:[h stringByAppendingPathComponent:@"Documents/id_name_mapping.json"]];
        [paths addObject:[h stringByAppendingPathComponent:@"Library/mobileconfig/id_name_mapping.json"]];
        [paths addObject:[h stringByAppendingPathComponent:@"Library/Application Support/mobileconfig/id_name_mapping.json"]];
        [paths addObject:[h stringByAppendingPathComponent:@"Library/Application Support/RyukGram/id_name_mapping.json"]];
        [paths addObject:[h stringByAppendingPathComponent:@"Library/Application Support/RyukGram/mobileconfig/id_name_mapping.json"]];
        [paths addObject:[h stringByAppendingPathComponent:@"tmp/id_name_mapping.json"]];
    }

    for (NSString *bundle in [self dynamicInstagramBundlePaths]) {
        [self addIDMapCandidatesForInstagramBundle:bundle toSet:paths];
    }

    return paths.array;
}

+ (NSString *)activeIDNameMappingPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in [self mappingPaths]) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir] && !isDir) return p;
    }
    return nil;
}

+ (NSDictionary<NSNumber *, NSDictionary *> *)parseMappingArray:(NSArray *)arr source:(NSString *)source {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id obj in arr) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *raw = obj;
        NSArray *parts = [raw componentsSeparatedByString:@":"];
        if (parts.count < 2) continue;
        unsigned long long pid = strtoull([parts[0] UTF8String], NULL, 0);
        NSString *name = parts[1];
        if (!pid || !name.length) continue;
        NSMutableDictionary *subs = [NSMutableDictionary dictionary];
        for (NSUInteger i = 2; i + 1 < parts.count; i += 2) {
            NSString *k = parts[i];
            NSString *v = parts[i + 1];
            if (k.length && v) subs[k] = v;
        }
        out[@(pid)] = @{@"config_name": name, @"subs": subs, @"source": source ?: kMap, @"raw": raw};
    }
    return out;
}

+ (NSDictionary<NSNumber *, NSDictionary *> *)parseMappingObject:(id)obj source:(NSString *)source {
    if ([obj isKindOfClass:[NSArray class]]) return [self parseMappingArray:obj source:source];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        id a = obj[@"id_to_names"] ?: obj[@"idToNames"] ?: obj[@"mappings"];
        if ([a isKindOfClass:[NSArray class]]) return [self parseMappingArray:a source:source];
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
            unsigned long long pid = strtoull([[key description] UTF8String], NULL, 0);
            NSString *name = [val isKindOfClass:[NSString class]] ? val : ([val isKindOfClass:[NSDictionary class]] ? (val[@"config_name"] ?: val[@"name"]) : nil);
            NSDictionary *subs = [val isKindOfClass:[NSDictionary class]] ? (val[@"subs"] ?: @{}) : @{};
            if (pid && name.length) out[@(pid)] = @{@"config_name": name, @"subs": subs, @"source": source ?: kMap};
        }];
        return out;
    }
    return @{};
}

+ (NSDictionary<NSNumber *, NSDictionary *> *)idNameMapping {
    static NSDictionary *cache;
    static NSString *loadedPath;
    static NSDate *loadedDate;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [self activeIDNameMappingPath];
    NSDate *date = nil;
    if (path.length) date = [fm attributesOfItemAtPath:path error:nil][NSFileModificationDate];
    if (cache && ((path == loadedPath) || [path isEqualToString:loadedPath]) && ((date == loadedDate) || [date isEqualToDate:loadedDate])) return cache;
    cache = [[self parseMappingObject:[self jsonAtPath:path] source:path ?: kMap] copy] ?: @{};
    loadedPath = [path copy];
    loadedDate = date;
    return cache;
}

+ (NSDictionary *)mappingForParamID:(unsigned long long)paramID { return [self idNameMapping][@(paramID)]; }
+ (NSString *)resolvedNameForParamID:(unsigned long long)paramID { NSString *s = [self mappingForParamID:paramID][@"config_name"]; return s.length ? s : nil; }
+ (NSString *)sourceForParamID:(unsigned long long)paramID { NSString *s = [self mappingForParamID:paramID][@"source"]; return s.length ? s : nil; }

+ (NSString *)mappingStatusLine {
    NSString *active = [self activeIDNameMappingPath];
    return [NSString stringWithFormat:@"id_name_mapping=%lu · active=%@ · primary=%@", (unsigned long)[self idNameMapping].count, active ?: @"none", [self primaryIDNameMappingPath]];
}

+ (NSDictionary *)allOverrides {
    id o = [self jsonAtPath:[self primaryOverridesPath]];
    if (![o isKindOfClass:[NSDictionary class]]) return @{};
    id backup = o[@"backup"];
    return [backup isKindOfClass:[NSDictionary class]] ? backup : o;
}

+ (BOOL)writeJSON:(id)obj path:(NSString *)path {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj ?: @{} options:NSJSONWritingPrettyPrinted error:nil];
    return d.length ? [d writeToFile:path atomically:YES] : NO;
}

+ (NSArray<NSNumber *> *)allOverriddenParamIDs {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *k in [self allOverrides]) { unsigned long long p = strtoull(k.UTF8String, NULL, 0); if (p) [out addObject:@(p)]; }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

+ (id)overrideObjectForParamID:(unsigned long long)paramID typeName:(NSString *)typeName {
    NSDictionary *d = [self allOverrides];
    id e = d[[NSString stringWithFormat:@"%llu", paramID]] ?: d[[NSString stringWithFormat:@"0x%llx", paramID]];
    if ([e isKindOfClass:[NSDictionary class]]) return e[@"value"] ?: e[@"override"] ?: e[typeName ?: @""];
    return e;
}

+ (void)setOverrideObject:(id)value forParamID:(unsigned long long)paramID typeName:(NSString *)typeName name:(NSString *)name {
    if (!value) return;
    NSMutableDictionary *d = [[self allOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    d[[NSString stringWithFormat:@"%llu", paramID]] = @{@"type": typeName ?: @"unknown", @"value": value, @"name": name ?: @""};
    [self writeJSON:d path:[self primaryOverridesPath]];
}

+ (void)removeOverrideForParamID:(unsigned long long)paramID {
    NSMutableDictionary *d = [[self allOverrides] mutableCopy] ?: [NSMutableDictionary dictionary];
    [d removeObjectForKey:[NSString stringWithFormat:@"%llu", paramID]];
    [d removeObjectForKey:[NSString stringWithFormat:@"0x%llx", paramID]];
    [self writeJSON:d path:[self primaryOverridesPath]];
}

+ (void)resetOverrides { [[NSFileManager defaultManager] removeItemAtPath:[self primaryOverridesPath] error:nil]; }

+ (void)collect:(id)o query:(NSString *)q limit:(NSUInteger)limit out:(NSMutableArray *)out path:(NSString *)path {
    if (out.count >= limit || !o) return;
    NSString *needle = q.lowercaseString ?: @"";
    if ([o isKindOfClass:[NSString class]]) {
        NSString *s = o;
        if (!needle.length || [s.lowercaseString containsString:needle]) [out addObject:@{@"path": path ?: @"schema", @"value": s}];
    } else if ([o isKindOfClass:[NSArray class]]) {
        NSArray *a = o;
        for (NSUInteger i = 0; i < a.count && out.count < limit; i++) [self collect:a[i] query:q limit:limit out:out path:[NSString stringWithFormat:@"%@[%lu]", path ?: @"schema", (unsigned long)i]];
    } else if ([o isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)o) {
            NSString *kp = [NSString stringWithFormat:@"%@.%@", path ?: @"schema", [k description]];
            if (needle.length && [[k description].lowercaseString containsString:needle]) [out addObject:@{@"path": kp, @"value": [[o objectForKey:k] description] ?: @""}];
            [self collect:[o objectForKey:k] query:q limit:limit out:out path:kp];
            if (out.count >= limit) break;
        }
    }
}

+ (NSArray<NSDictionary *> *)schemaMatchesForQuery:(NSString *)query limit:(NSUInteger)limit {
    NSMutableArray *out = [NSMutableArray array];
    [self collect:[self jsonAtPath:[self bundleIGSchemaPath]] query:query ?: @"" limit:limit ?: 100 out:out path:@"igios-schema"];
    return out;
}

@end
