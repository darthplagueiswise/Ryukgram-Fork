#import "SCIExpMobileConfigMapping.h"

extern NSData *SCIEmbeddedMobileConfigSchemaData(void);
extern NSString *SCIEmbeddedMobileConfigSchemaName(void);

static NSDictionary<NSString *, NSDictionary *> *gSCIMCMapping = nil;
static NSDictionary<NSNumber *, NSString *> *gSCIMCDirectSpecifierNames = nil;
static NSDictionary<NSString *, NSDictionary *> *gSCIMCNamedConfigs = nil;
static NSString *gSCIMCMappingSource = nil;
static NSArray<NSString *> *gSCIMCCheckedPaths = nil;
static NSArray<NSString *> *gSCIMCFoundPaths = nil;
static NSDictionary<NSString *, NSDictionary *> *gSCIMCFileReports = nil;
static NSUInteger gSCIMCVisitedNodes = 0;
static NSUInteger gSCIMCVisitedScalars = 0;
static BOOL gSCIMCLoadStarted = NO;

static dispatch_queue_t SCIMCMappingQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.expflags.mc.embedded_schema", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

static NSString *SCITrimString(id obj) {
    if (!obj || obj == (id)kCFNull) return nil;
    NSString *s = [obj isKindOfClass:[NSString class]] ? obj : ([obj respondsToSelector:@selector(description)] ? [obj description] : nil);
    if (!s.length) return nil;
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length || [s isEqualToString:@"(null)"] || [s isEqualToString:@"null"]) return nil;
    return s;
}

static NSString *SCIJSONStringObjectKind(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) return @"dictionary";
    if ([obj isKindOfClass:[NSArray class]]) return @"array";
    if ([obj isKindOfClass:[NSString class]]) return @"string";
    if ([obj isKindOfClass:[NSNumber class]]) return @"number";
    if (!obj || obj == (id)kCFNull) return @"nil";
    return NSStringFromClass([obj class]);
}

static BOOL SCIObjectToUInt64(id obj, unsigned long long *outValue) {
    if ([obj isKindOfClass:[NSNumber class]]) {
        if (outValue) *outValue = [(NSNumber *)obj unsignedLongLongValue];
        return YES;
    }
    NSString *trim = SCITrimString(obj);
    if (!trim.length) return NO;
    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:trim];
    if ([trim hasPrefix:@"0x"] || [trim hasPrefix:@"0X"]) {
        if (![scanner scanHexLongLong:&value]) return NO;
    } else {
        long long signedValue = 0;
        if (![scanner scanLongLong:&signedValue]) return NO;
        value = (unsigned long long)signedValue;
    }
    if (outValue) *outValue = value;
    return YES;
}

static id SCIFirstValueForKeys(NSDictionary *d, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id v = d[key];
        if (v && v != (id)kCFNull) return v;
    }
    return nil;
}

static NSString *SCIStringValueForKeys(NSDictionary *d, NSArray<NSString *> *keys) {
    return SCITrimString(SCIFirstValueForKeys(d, keys));
}

static NSString *SCILastNameFromPath(NSString *path) {
    if (!path.length) return nil;
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"."];
    for (NSString *part in [parts reverseObjectEnumerator]) {
        NSString *p = SCITrimString(part);
        if (!p.length) continue;
        NSRange bracket = [p rangeOfString:@"["];
        if (bracket.location != NSNotFound && bracket.location == 0) continue;
        return p;
    }
    return path;
}

static NSString *SCIPathAppend(NSString *path, id key) {
    NSString *k = SCITrimString(key) ?: @"?";
    if (!path.length) return k;
    return [path stringByAppendingFormat:@".%@", k];
}

static unsigned long long SCICombinedSpecifierFromFlagParam(id flagId, id paramId) {
    unsigned long long f = 0, p = 0;
    if (!SCIObjectToUInt64(flagId, &f) || !SCIObjectToUInt64(paramId, &p)) return 0;
    return ((f & 0xffffffffULL) << 32) | (p & 0xffffffffULL);
}

static void SCIAddNamedConfig(NSMutableDictionary<NSString *, NSDictionary *> *named,
                              NSString *name,
                              NSString *path,
                              id lid,
                              id value,
                              NSString *sourceKind) {
    if (!name.length) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"name"] = name;
    if (path.length) entry[@"path"] = path;
    NSString *lidString = SCITrimString(lid);
    if (lidString.length) entry[@"lid"] = lidString;
    if (value && value != (id)kCFNull) entry[@"v"] = value;
    if (sourceKind.length) entry[@"sourceKind"] = sourceKind;
    named[name] = entry;
}

static void SCIAddFlagParam(NSMutableDictionary<NSString *, NSDictionary *> *flagMap,
                            NSMutableDictionary<NSNumber *, NSString *> *directMap,
                            id flagId,
                            NSString *flagName,
                            id paramId,
                            NSString *paramName) {
    NSString *f = SCITrimString(flagId);
    NSString *p = SCITrimString(paramId);
    if (!f.length && !p.length) return;
    if (!flagName.length && !paramName.length) return;
    if (!f.length) f = @"0";
    if (!p.length) p = @"0";

    NSMutableDictionary *flag = [flagMap[f] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (flagName.length && ![flag[@"name"] length]) flag[@"name"] = flagName;
    NSMutableDictionary *subs = [flag[@"subs"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (paramName.length) subs[p] = paramName;
    flag[@"subs"] = subs;
    flagMap[f] = flag;

    unsigned long long spec = SCICombinedSpecifierFromFlagParam(f, p);
    NSString *name = nil;
    if (flagName.length && paramName.length) name = [NSString stringWithFormat:@"%@ / %@", flagName, paramName];
    else name = flagName.length ? flagName : paramName;
    if (spec && name.length) directMap[@(spec)] = name;
}

static void SCIAddDirectSpecifier(NSMutableDictionary<NSNumber *, NSString *> *directMap,
                                  NSMutableDictionary<NSString *, NSDictionary *> *flagMap,
                                  id lid,
                                  NSString *name) {
    if (!name.length) return;
    unsigned long long spec = 0;
    if (!SCIObjectToUInt64(lid, &spec) || !spec) return;
    directMap[@(spec)] = name;

    uint32_t flagId32 = (uint32_t)(spec >> 32);
    uint32_t paramId32 = (uint32_t)(spec & 0xffffffffULL);
    NSString *flagId = [NSString stringWithFormat:@"%u", flagId32];
    NSString *paramId = [NSString stringWithFormat:@"%u", paramId32];
    NSString *flagName = name;
    NSString *paramName = name;
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound && dot.location > 0 && dot.location + 1 < name.length) {
        flagName = [name substringToIndex:dot.location];
        paramName = [name substringFromIndex:dot.location + 1];
    }
    SCIAddFlagParam(flagMap, directMap, flagId, flagName, paramId, paramName);
}

static NSDictionary *SCIParseMappingRawString(NSString *raw) {
    NSArray<NSString *> *parts = [raw componentsSeparatedByString:@":"];
    if (parts.count < 2) return nil;
    NSString *flagId = SCITrimString(parts[0]);
    NSString *flagName = SCITrimString(parts[1]);
    if (!flagId.length || !flagName.length) return nil;
    NSMutableDictionary *subs = [NSMutableDictionary dictionary];
    for (NSUInteger i = 2; i + 1 < parts.count; i += 2) {
        NSString *paramId = SCITrimString(parts[i]);
        NSString *paramName = SCITrimString(parts[i + 1]);
        if (paramId.length && paramName.length) subs[paramId] = paramName;
    }
    return @{@"flagId": flagId, @"name": flagName, @"subs": subs};
}

static void SCIVisitSchemaObject(id obj,
                                 NSString *path,
                                 NSString *inheritedFlagId,
                                 NSString *inheritedFlagName,
                                 NSMutableDictionary<NSString *, NSDictionary *> *flagMap,
                                 NSMutableDictionary<NSNumber *, NSString *> *directMap,
                                 NSMutableDictionary<NSString *, NSDictionary *> *named,
                                 NSUInteger depth) {
    if (!obj || obj == (id)kCFNull || depth > 64) return;
    gSCIMCVisitedNodes++;

    if ([obj isKindOfClass:[NSString class]]) {
        gSCIMCVisitedScalars++;
        NSDictionary *parsed = SCIParseMappingRawString((NSString *)obj);
        if (parsed) {
            NSString *flagId = parsed[@"flagId"];
            NSString *flagName = parsed[@"name"];
            NSDictionary *subs = [parsed[@"subs"] isKindOfClass:[NSDictionary class]] ? parsed[@"subs"] : @{};
            SCIAddNamedConfig(named, flagName, path, nil, obj, @"raw-mapping");
            if (!subs.count) SCIAddFlagParam(flagMap, directMap, flagId, flagName, @"0", flagName);
            for (NSString *paramId in subs) SCIAddFlagParam(flagMap, directMap, flagId, flagName, paramId, [subs[paramId] description]);
        }
        return;
    }

    if ([obj isKindOfClass:[NSNumber class]]) {
        gSCIMCVisitedScalars++;
        return;
    }

    if ([obj isKindOfClass:[NSArray class]]) {
        NSUInteger idx = 0;
        for (id item in (NSArray *)obj) {
            SCIVisitSchemaObject(item, [path stringByAppendingFormat:@"[%lu]", (unsigned long)idx], inheritedFlagId, inheritedFlagName, flagMap, directMap, named, depth + 1);
            idx++;
        }
        return;
    }

    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = (NSDictionary *)obj;

    NSString *explicitName = SCIStringValueForKeys(d, @[@"name", @"param_name", @"paramName", @"config_name", @"configName", @"stable_id", @"stableId", @"key", @"qe_name", @"universe_name"]);
    NSString *name = explicitName.length ? explicitName : SCILastNameFromPath(path);

    id lid = SCIFirstValueForKeys(d, @[@"lid", @"logging_id", @"loggingId", @"specifier", @"param_specifier", @"paramSpecifier", @"stable_id_lid"]);
    id value = SCIFirstValueForKeys(d, @[@"v", @"value", @"default", @"default_value", @"defaultValue", @"fallback", @"fallback_value"]);
    if (name.length && (lid || value || explicitName.length)) {
        SCIAddNamedConfig(named, name, path, lid, value, @"dict");
    }
    if (lid && name.length) SCIAddDirectSpecifier(directMap, flagMap, lid, name);

    NSString *flagId = SCIStringValueForKeys(d, @[@"flagId", @"flag_id", @"config_id", @"configId", @"universe_id", @"family", @"id"]);
    NSString *paramId = SCIStringValueForKeys(d, @[@"paramId", @"param_id", @"param", @"field", @"field_id", @"subId", @"sub_id"]);
    NSString *flagName = SCIStringValueForKeys(d, @[@"flagName", @"flag_name", @"configName", @"config_name", @"groupName", @"group_name", @"universeName", @"universe_name"]);
    NSString *paramName = SCIStringValueForKeys(d, @[@"paramName", @"param_name", @"fieldName", @"field_name", @"parameterName", @"parameter_name"]);

    if (!flagId.length) flagId = inheritedFlagId;
    if (!flagName.length) flagName = inheritedFlagName;
    if (!flagName.length && flagId.length && name.length && !paramId.length) flagName = name;
    if (!paramName.length && paramId.length && name.length) paramName = name;
    if ((flagId.length || paramId.length) && (flagName.length || paramName.length)) {
        SCIAddFlagParam(flagMap, directMap, flagId, flagName.length ? flagName : name, paramId.length ? paramId : @"0", paramName.length ? paramName : name);
    }

    NSString *nextFlagId = flagId.length ? flagId : inheritedFlagId;
    NSString *nextFlagName = flagName.length ? flagName : (name.length ? name : inheritedFlagName);

    id subs = d[@"subs"] ?: d[@"params"] ?: d[@"parameters"] ?: d[@"fields"] ?: d[@"param_map"] ?: d[@"paramMap"];
    if ([subs isKindOfClass:[NSDictionary class]]) {
        NSDictionary *sd = (NSDictionary *)subs;
        for (id rawSubKey in sd) {
            NSString *subKey = SCITrimString(rawSubKey);
            id subValue = sd[rawSubKey];
            if ([subValue isKindOfClass:[NSString class]] || [subValue isKindOfClass:[NSNumber class]]) {
                SCIAddFlagParam(flagMap, directMap, nextFlagId, nextFlagName, subKey, SCITrimString(subValue) ?: subKey);
            }
            SCIVisitSchemaObject(subValue, SCIPathAppend(path, subKey), nextFlagId, nextFlagName, flagMap, directMap, named, depth + 1);
        }
    }

    for (id rawKey in d) {
        NSString *childKey = SCITrimString(rawKey);
        if (!childKey.length) continue;
        id child = d[rawKey];
        if (child == subs) continue;
        SCIVisitSchemaObject(child, SCIPathAppend(path, childKey), nextFlagId, nextFlagName, flagMap, directMap, named, depth + 1);
    }
}

static NSDictionary *SCIReportForEmbeddedSchema(NSDictionary *mapping, NSDictionary *direct, NSDictionary *named, id obj, NSError *err, NSUInteger size) {
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"size"] = @(size);
    r[@"jsonKind"] = SCIJSONStringObjectKind(obj);
    r[@"ids"] = @((NSUInteger)mapping.count);
    r[@"direct"] = @((NSUInteger)direct.count);
    r[@"named"] = @((NSUInteger)named.count);
    r[@"nodes"] = @(gSCIMCVisitedNodes);
    r[@"scalars"] = @(gSCIMCVisitedScalars);
    if (err.localizedDescription.length) r[@"error"] = err.localizedDescription;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [[(NSDictionary *)obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger n = MIN((NSUInteger)12, keys.count);
        r[@"sampleKeys"] = n ? [keys subarrayWithRange:NSMakeRange(0, n)] : @[];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        r[@"arrayCount"] = @([(NSArray *)obj count]);
    }
    return r;
}

@implementation SCIExpMobileConfigMapping

+ (void)scheduleBackgroundLoadIfNeeded {
    __block BOOL shouldStart = NO;
    dispatch_barrier_sync(SCIMCMappingQueue(), ^{
        if (!gSCIMCLoadStarted && gSCIMCMapping == nil) {
            gSCIMCLoadStarted = YES;
            shouldStart = YES;
        }
    });
    if (!shouldStart) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [self loadMappingIfNeeded]; });
}

+ (NSArray<NSString *> *)candidateMappingPaths {
    NSString *name = SCIEmbeddedMobileConfigSchemaName();
    return name.length ? @[[NSString stringWithFormat:@"embedded:%@", name]] : @[];
}

+ (NSArray<NSString *> *)checkedMappingPaths {
    [self loadMappingIfNeeded];
    __block NSArray<NSString *> *paths = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{ paths = [gSCIMCCheckedPaths copy] ?: @[]; });
    return paths ?: @[];
}

+ (NSArray<NSString *> *)foundMappingPaths {
    [self loadMappingIfNeeded];
    __block NSArray<NSString *> *paths = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{ paths = [gSCIMCFoundPaths copy] ?: @[]; });
    return paths ?: @[];
}

+ (void)loadMappingIfNeeded {
    __block BOOL loaded = NO;
    dispatch_sync(SCIMCMappingQueue(), ^{ loaded = (gSCIMCMapping != nil); });
    if (loaded) return;

    NSData *data = SCIEmbeddedMobileConfigSchemaData();
    NSString *schemaName = SCIEmbeddedMobileConfigSchemaName() ?: @"embedded schema";
    NSMutableDictionary *allMapping = [NSMutableDictionary dictionary];
    NSMutableDictionary *allDirect = [NSMutableDictionary dictionary];
    NSMutableDictionary *allNamed = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *reports = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *checked = [NSMutableArray array];
    NSMutableArray<NSString *> *found = [NSMutableArray array];

    NSString *sourceKey = [NSString stringWithFormat:@"embedded:%@", schemaName];
    if (schemaName.length) [checked addObject:sourceKey];

    NSError *err = nil;
    id obj = nil;
    gSCIMCVisitedNodes = 0;
    gSCIMCVisitedScalars = 0;

    if (data.length) {
        [found addObject:sourceKey];
        obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (obj && !err) {
            SCIVisitSchemaObject(obj, @"root", nil, nil, allMapping, allDirect, allNamed, 0);
        }
    }

    reports[sourceKey.length ? sourceKey : @"embedded:none"] = SCIReportForEmbeddedSchema(allMapping, allDirect, allNamed, obj, err, data.length);

    dispatch_barrier_sync(SCIMCMappingQueue(), ^{
        if (gSCIMCMapping) return;
        gSCIMCMapping = [allMapping copy] ?: @{};
        gSCIMCDirectSpecifierNames = [allDirect copy] ?: @{};
        gSCIMCNamedConfigs = [allNamed copy] ?: @{};
        gSCIMCCheckedPaths = [checked copy] ?: @[];
        gSCIMCFoundPaths = [found copy] ?: @[];
        gSCIMCFileReports = [reports copy] ?: @{};
        if (!data.length) {
            gSCIMCMappingSource = @"no embedded schema; put igios-instagram-schema_client-persist.json in resources/ or pass SCHEMA_JSON=/path/file.json at build time";
        } else if (err || !obj) {
            gSCIMCMappingSource = [NSString stringWithFormat:@"%@ parse-error: %@", schemaName, err.localizedDescription ?: @"unknown"];
        } else {
            gSCIMCMappingSource = [NSString stringWithFormat:@"%@ · FULL import nodes=%lu scalars=%lu ids=%lu direct=%lu named=%lu", schemaName, (unsigned long)gSCIMCVisitedNodes, (unsigned long)gSCIMCVisitedScalars, (unsigned long)allMapping.count, (unsigned long)allDirect.count, (unsigned long)allNamed.count];
        }
        NSLog(@"[RyukGram][MCMapping] %@", gSCIMCMappingSource);
    });
}

+ (void)reloadMapping {
    dispatch_barrier_sync(SCIMCMappingQueue(), ^{
        gSCIMCMapping = nil;
        gSCIMCDirectSpecifierNames = nil;
        gSCIMCNamedConfigs = nil;
        gSCIMCMappingSource = nil;
        gSCIMCCheckedPaths = nil;
        gSCIMCFoundPaths = nil;
        gSCIMCFileReports = nil;
        gSCIMCVisitedNodes = 0;
        gSCIMCVisitedScalars = 0;
        gSCIMCLoadStarted = NO;
    });
    [self loadMappingIfNeeded];
}

+ (NSString *)mappingSourceDescription {
    [self loadMappingIfNeeded];
    __block NSString *s = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        s = [NSString stringWithFormat:@"%@ · ids=%lu direct=%lu named=%lu · checked=%lu found=%lu", gSCIMCMappingSource ?: @"none", (unsigned long)gSCIMCMapping.count, (unsigned long)gSCIMCDirectSpecifierNames.count, (unsigned long)gSCIMCNamedConfigs.count, (unsigned long)gSCIMCCheckedPaths.count, (unsigned long)gSCIMCFoundPaths.count];
    });
    return s ?: @"none";
}

+ (NSString *)mappingDebugDescription {
    [self loadMappingIfNeeded];
    __block NSString *source = nil;
    __block NSArray *found = nil;
    __block NSArray *checked = nil;
    __block NSDictionary *reports = nil;
    __block NSDictionary *directMap = nil;
    __block NSDictionary *namedMap = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        source = gSCIMCMappingSource ?: @"none";
        found = [gSCIMCFoundPaths copy] ?: @[];
        checked = [gSCIMCCheckedPaths copy] ?: @[];
        reports = [gSCIMCFileReports copy] ?: @{};
        directMap = [gSCIMCDirectSpecifierNames copy] ?: @{};
        namedMap = [gSCIMCNamedConfigs copy] ?: @{};
    });

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"Mapping: %@", source]];
    [lines addObject:@"Embedded schema files:"];
    if (found.count) {
        for (NSString *p in found) {
            NSDictionary *r = reports[p] ?: @{};
            [lines addObject:[NSString stringWithFormat:@"  + %@ size=%@ kind=%@ ids=%@ direct=%@ named=%@ nodes=%@ scalars=%@", p, r[@"size"] ?: @0, r[@"jsonKind"] ?: @"?", r[@"ids"] ?: @0, r[@"direct"] ?: @0, r[@"named"] ?: @0, r[@"nodes"] ?: @0, r[@"scalars"] ?: @0]];
            NSArray *sample = [r[@"sampleKeys"] isKindOfClass:[NSArray class]] ? r[@"sampleKeys"] : nil;
            if (sample.count) [lines addObject:[NSString stringWithFormat:@"    sample=%@", sample]];
            if (r[@"arrayCount"]) [lines addObject:[NSString stringWithFormat:@"    arrayCount=%@", r[@"arrayCount"]]];
            if (r[@"error"]) [lines addObject:[NSString stringWithFormat:@"    error=%@", r[@"error"]]];
        }
    } else {
        [lines addObject:@"  none"];
    }
    [lines addObject:@"Checked sources:"];
    for (NSString *p in checked) [lines addObject:[NSString stringWithFormat:@"  - %@", p]];

    [lines addObject:@"Sample direct specifiers:"];
    NSArray<NSNumber *> *directKeys = [[directMap allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger directCount = MIN((NSUInteger)16, directKeys.count);
    for (NSUInteger i = 0; i < directCount; i++) {
        NSNumber *n = directKeys[i];
        [lines addObject:[NSString stringWithFormat:@"  0x%016llx -> %@", n.unsignedLongLongValue, directMap[n]]];
    }
    if (!directCount) [lines addObject:@"  none"];

    [lines addObject:@"Sample named configs:"];
    NSArray<NSString *> *namedKeys = [[namedMap allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger namedCount = MIN((NSUInteger)16, namedKeys.count);
    for (NSUInteger i = 0; i < namedCount; i++) {
        NSString *key = namedKeys[i];
        NSDictionary *entry = namedMap[key];
        [lines addObject:[NSString stringWithFormat:@"  %@ path=%@ lid=%@", key, entry[@"path"] ?: @"", entry[@"lid"] ?: @""]];
    }
    if (!namedCount) [lines addObject:@"  none"];
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)resolvedNameForSpecifier:(unsigned long long)specifier {
    __block BOOL loaded = NO;
    dispatch_sync(SCIMCMappingQueue(), ^{ loaded = (gSCIMCMapping != nil); });
    if (!loaded) {
        [self scheduleBackgroundLoadIfNeeded];
        return nil;
    }

    __block NSString *direct = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{ direct = gSCIMCDirectSpecifierNames[@(specifier)]; });
    if (direct.length) return direct;

    uint32_t flagId32 = (uint32_t)(specifier >> 32);
    uint32_t paramId32 = (uint32_t)(specifier & 0xffffffffULL);
    NSString *flagDec = [NSString stringWithFormat:@"%u", flagId32];
    NSString *paramDec = [NSString stringWithFormat:@"%u", paramId32];
    NSString *flagHex = [NSString stringWithFormat:@"0x%08x", flagId32];
    NSString *paramHex = [NSString stringWithFormat:@"0x%08x", paramId32];

    __block NSDictionary *flag = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{ flag = gSCIMCMapping[flagDec] ?: gSCIMCMapping[flagHex] ?: gSCIMCMapping[[flagHex uppercaseString]]; });
    if (![flag isKindOfClass:[NSDictionary class]]) return nil;

    NSString *flagName = [flag[@"name"] isKindOfClass:[NSString class]] ? flag[@"name"] : @"";
    NSDictionary *subs = [flag[@"subs"] isKindOfClass:[NSDictionary class]] ? flag[@"subs"] : @{};
    id p = subs[paramDec] ?: subs[paramHex] ?: subs[[paramHex uppercaseString]];
    NSString *paramName = p ? [p description] : nil;
    if (flagName.length && paramName.length) return [NSString stringWithFormat:@"%@ / %@", flagName, paramName];
    if (flagName.length) return [NSString stringWithFormat:@"%@ / param %@", flagName, paramDec];
    if (paramName.length) return [NSString stringWithFormat:@"flag %@ / %@", flagDec, paramName];
    return nil;
}

@end
