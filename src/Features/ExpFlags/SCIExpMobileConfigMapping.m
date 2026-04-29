#import "SCIExpMobileConfigMapping.h"

static NSDictionary<NSString *, NSDictionary *> *gSCIMCMapping = nil;
static NSDictionary<NSNumber *, NSString *> *gSCIMCDirectSpecifierNames = nil;
static NSDictionary<NSString *, NSDictionary *> *gSCIMCNamedConfigs = nil;
static NSString *gSCIMCMappingSource = nil;
static NSArray<NSString *> *gSCIMCCheckedPaths = nil;
static NSArray<NSString *> *gSCIMCFoundPaths = nil;
static NSDictionary<NSString *, NSDictionary *> *gSCIMCFileReports = nil;

static dispatch_queue_t SCIMCMappingQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.expflags.mc.schemaimport", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

static void SCIAddUniquePath(NSMutableArray<NSString *> *paths, NSString *path) {
    if (!path.length) return;
    NSString *standardized = [path stringByStandardizingPath];
    if (standardized.length && ![paths containsObject:standardized]) [paths addObject:standardized];
}

static NSString *SCITrimString(id obj) {
    if (!obj) return nil;
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
    if (!obj) return @"nil";
    return NSStringFromClass([obj class]);
}

static BOOL SCINameLooksLikeMCName(NSString *name) {
    if (name.length < 3) return NO;
    NSString *n = name.lowercaseString;
    if ([n hasPrefix:@"ig_"] || [n hasPrefix:@"fb_"] || [n hasPrefix:@"mc_"] || [n hasPrefix:@"qe_"] || [n hasPrefix:@"p92_"] || [n hasPrefix:@"bsl_"] || [n hasPrefix:@"bcn_"]) return YES;
    if ([n containsString:@"."] && ([n containsString:@"ig"] || [n containsString:@"fb"] || [n containsString:@"mobileconfig"])) return YES;
    if ([n containsString:@"quick_snap"] || [n containsString:@"quicksnap"] || [n containsString:@"instants"] || [n containsString:@"employee"] || [n containsString:@"dogfood"] || [n containsString:@"internal"] || [n containsString:@"prism"] || [n containsString:@"homecoming"] || [n containsString:@"liquid_glass"] || [n containsString:@"liquidglass"]) return YES;
    return NO;
}

static BOOL SCIStringToUInt64(NSString *s, unsigned long long *outValue) {
    if (!s.length) return NO;
    NSString *trim = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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

static NSString *SCIStringValueForKeys(NSDictionary *d, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id v = d[key];
        NSString *s = SCITrimString(v);
        if (s.length) return s;
    }
    return nil;
}

static unsigned long long SCICombinedSpecifierFromFlagParam(NSString *flagId, NSString *paramId) {
    unsigned long long f = 0, p = 0;
    if (!SCIStringToUInt64(flagId, &f) || !SCIStringToUInt64(paramId, &p)) return 0;
    return ((f & 0xffffffffULL) << 32) | (p & 0xffffffffULL);
}

static void SCIAddFlagParam(NSMutableDictionary<NSString *, NSDictionary *> *flagMap,
                            NSMutableDictionary<NSNumber *, NSString *> *directMap,
                            NSString *flagId,
                            NSString *flagName,
                            NSString *paramId,
                            NSString *paramName) {
    if (!flagId.length && !paramId.length) return;
    if (!flagName.length && !paramName.length) return;

    NSString *f = flagId.length ? flagId : @"0";
    NSString *p = paramId.length ? paramId : @"0";
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
                                  NSString *lidString,
                                  NSString *name) {
    if (!lidString.length || !name.length) return;
    unsigned long long spec = 0;
    if (!SCIStringToUInt64(lidString, &spec) || !spec) return;
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

static NSDictionary *SCIReportForPath(NSString *path, NSDictionary *mapping, NSDictionary *direct, NSDictionary *named, id obj, NSError *err, unsigned long long size) {
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"size"] = @(size);
    r[@"jsonKind"] = SCIJSONStringObjectKind(obj);
    r[@"ids"] = @((NSUInteger)mapping.count);
    r[@"direct"] = @((NSUInteger)direct.count);
    r[@"named"] = @((NSUInteger)named.count);
    if (err.localizedDescription.length) r[@"error"] = err.localizedDescription;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [[(NSDictionary *)obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger n = MIN((NSUInteger)8, keys.count);
        r[@"sampleKeys"] = n ? [keys subarrayWithRange:NSMakeRange(0, n)] : @[];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        r[@"arrayCount"] = @([(NSArray *)obj count]);
    }
    return r;
}

@implementation SCIExpMobileConfigMapping

+ (NSArray<NSString *> *)exactCandidateMappingPaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;

    NSArray<NSString *> *baseDirs = @[
        [bundle stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework"] ?: @"",
        [bundle stringByAppendingPathComponent:@"Frameworks/FBSharedModules.framework"] ?: @"",
        [bundle stringByAppendingPathComponent:@"Frameworks"] ?: @"",
        [bundle stringByAppendingPathComponent:@"RyukGram.bundle"] ?: @"",
        bundle ?: @"",
        docs ?: @"",
        appSupport ?: @"",
        lib ?: @""
    ];

    NSArray<NSString *> *names = @[
        @"igios-instagram-schema_client-persist.json",
        @"igios-facebook-schema_client-persist.json",
        @"id_name_mapping.json",
        @"id_mapping.json",
        @"name_mapping.json",
        @"mc_startup_configs.json",
        @"startup_configs.json"
    ];

    for (NSString *base in baseDirs) {
        if (!base.length) continue;
        for (NSString *name in names) SCIAddUniquePath(paths, [base stringByAppendingPathComponent:name]);
    }

    for (NSBundle *b in [NSBundle allBundles]) {
        for (NSString *name in names) {
            NSString *p = [b pathForResource:[name stringByDeletingPathExtension] ofType:@"json"];
            if (p.length) SCIAddUniquePath(paths, p);
        }
    }
    return paths;
}

+ (NSArray<NSString *> *)candidateMappingPaths { return [self exactCandidateMappingPaths]; }

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

+ (NSDictionary *)parseMappingRawString:(NSString *)raw {
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

+ (void)scanObject:(id)obj
              key:(NSString *)key
          flagMap:(NSMutableDictionary<NSString *, NSDictionary *> *)flagMap
        directMap:(NSMutableDictionary<NSNumber *, NSString *> *)directMap
            named:(NSMutableDictionary<NSString *, NSDictionary *> *)named
            depth:(NSUInteger)depth {
    if (!obj || depth > 10) return;

    if ([obj isKindOfClass:[NSString class]]) {
        NSDictionary *parsed = [self parseMappingRawString:(NSString *)obj];
        if (parsed) {
            NSString *flagId = parsed[@"flagId"];
            NSString *flagName = parsed[@"name"];
            NSDictionary *subs = parsed[@"subs"] ?: @{};
            if (!subs.count) SCIAddFlagParam(flagMap, directMap, flagId, flagName, @"0", flagName);
            for (NSString *paramId in subs) SCIAddFlagParam(flagMap, directMap, flagId, flagName, paramId, [subs[paramId] description]);
        }
        return;
    }

    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) [self scanObject:item key:key flagMap:flagMap directMap:directMap named:named depth:depth + 1];
        return;
    }

    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = (NSDictionary *)obj;

    NSString *name = SCIStringValueForKeys(d, @[@"name", @"param_name", @"paramName", @"config_name", @"configName", @"stable_id", @"stableId", @"key"]);
    if (!name.length && SCINameLooksLikeMCName(key)) name = key;

    NSString *lid = SCIStringValueForKeys(d, @[@"lid", @"logging_id", @"loggingId", @"specifier", @"param_specifier", @"paramSpecifier"]);
    if (lid.length && name.length) {
        named[name] = @{ @"name": name, @"lid": lid, @"v": d[@"v"] ?: d[@"value"] ?: d[@"default"] ?: @"" };
        SCIAddDirectSpecifier(directMap, flagMap, lid, name);
    }

    NSString *flagId = SCIStringValueForKeys(d, @[@"flagId", @"flag_id", @"config_id", @"configId", @"family", @"id"]);
    NSString *paramId = SCIStringValueForKeys(d, @[@"paramId", @"param_id", @"param", @"field", @"subId", @"sub_id"]);
    NSString *flagName = SCIStringValueForKeys(d, @[@"flagName", @"flag_name", @"configName", @"config_name", @"groupName", @"group_name"]);
    NSString *paramName = SCIStringValueForKeys(d, @[@"paramName", @"param_name", @"fieldName", @"field_name"]);
    if (!flagName.length && name.length && !paramName.length) flagName = name;
    if (!paramName.length && name.length && flagName.length && ![name isEqualToString:flagName]) paramName = name;
    if ((flagId.length || paramId.length) && (flagName.length || paramName.length)) {
        SCIAddFlagParam(flagMap, directMap, flagId, flagName, paramId.length ? paramId : @"0", paramName.length ? paramName : flagName);
    }

    id subs = d[@"subs"] ?: d[@"params"] ?: d[@"parameters"] ?: d[@"fields"];
    if ([subs isKindOfClass:[NSDictionary class]]) {
        NSDictionary *sd = (NSDictionary *)subs;
        for (id rawSubKey in sd) {
            NSString *subKey = SCITrimString(rawSubKey);
            id subValue = sd[rawSubKey];
            if ([subValue isKindOfClass:[NSString class]]) {
                SCIAddFlagParam(flagMap, directMap, flagId, flagName.length ? flagName : name, subKey, (NSString *)subValue);
            } else {
                [self scanObject:subValue key:subKey flagMap:flagMap directMap:directMap named:named depth:depth + 1];
            }
        }
    } else if ([subs isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)subs) [self scanObject:item key:name flagMap:flagMap directMap:directMap named:named depth:depth + 1];
    }

    for (id rawKey in d) {
        NSString *childKey = SCITrimString(rawKey);
        if (!childKey.length) continue;
        id child = d[rawKey];
        if (child == subs) continue;
        if ([child isKindOfClass:[NSDictionary class]] || [child isKindOfClass:[NSArray class]] || [child isKindOfClass:[NSString class]]) {
            [self scanObject:child key:childKey flagMap:flagMap directMap:directMap named:named depth:depth + 1];
        }
    }
}

+ (void)loadMappingIfNeeded {
    __block BOOL loaded = NO;
    dispatch_sync(SCIMCMappingQueue(), ^{ loaded = (gSCIMCMapping != nil); });
    if (loaded) return;

    dispatch_barrier_sync(SCIMCMappingQueue(), ^{
        if (gSCIMCMapping) return;
        NSMutableDictionary *allMapping = [NSMutableDictionary dictionary];
        NSMutableDictionary *allDirect = [NSMutableDictionary dictionary];
        NSMutableDictionary *allNamed = [NSMutableDictionary dictionary];
        NSMutableArray<NSString *> *sources = [NSMutableArray array];
        NSMutableArray<NSString *> *checked = [NSMutableArray array];
        NSMutableArray<NSString *> *found = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSDictionary *> *reports = [NSMutableDictionary dictionary];
        NSFileManager *fm = [NSFileManager defaultManager];

        NSArray<NSString *> *toInspect = [self exactCandidateMappingPaths];
        for (NSString *path in toInspect) {
            SCIAddUniquePath(checked, path);
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) continue;
            SCIAddUniquePath(found, path);

            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
            NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
            if (!data.length) {
                reports[path] = SCIReportForPath(path, @{}, @{}, @{}, nil, nil, size);
                [sources addObject:[NSString stringWithFormat:@"%@ empty", path.lastPathComponent]];
                continue;
            }

            NSError *err = nil;
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
            if (!obj || err) {
                reports[path] = SCIReportForPath(path, @{}, @{}, @{}, nil, err, size);
                [sources addObject:[NSString stringWithFormat:@"%@ parse-error", path.lastPathComponent]];
                continue;
            }

            NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
            NSMutableDictionary *direct = [NSMutableDictionary dictionary];
            NSMutableDictionary *named = [NSMutableDictionary dictionary];
            [self scanObject:obj key:path.lastPathComponent flagMap:parsed directMap:direct named:named depth:0];

            reports[path] = SCIReportForPath(path, parsed, direct, named, obj, nil, size);
            if (parsed.count || direct.count || named.count) {
                [allMapping addEntriesFromDictionary:parsed];
                [allDirect addEntriesFromDictionary:direct];
                [allNamed addEntriesFromDictionary:named];
                [sources addObject:[NSString stringWithFormat:@"%@ (%lu ids/%lu direct/%lu named)", path.lastPathComponent, (unsigned long)parsed.count, (unsigned long)direct.count, (unsigned long)named.count]];
            } else {
                [sources addObject:[NSString stringWithFormat:@"%@ parsed-empty", path.lastPathComponent]];
            }
        }

        gSCIMCMapping = [allMapping copy] ?: @{};
        gSCIMCDirectSpecifierNames = [allDirect copy] ?: @{};
        gSCIMCNamedConfigs = [allNamed copy] ?: @{};
        gSCIMCCheckedPaths = [checked copy] ?: @[];
        gSCIMCFoundPaths = [found copy] ?: @[];
        gSCIMCFileReports = [reports copy] ?: @{};
        gSCIMCMappingSource = sources.count ? [sources componentsJoinedByString:@", "] : @"none";
        NSLog(@"[RyukGram][MCMapping] import %@", gSCIMCMappingSource);
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
    __block NSString *message = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"Mapping: %@", [self mappingSourceDescription]]];
        [lines addObject:@"Found schema/import JSON files:"];
        if (gSCIMCFoundPaths.count) {
            for (NSString *p in gSCIMCFoundPaths) {
                NSDictionary *r = gSCIMCFileReports[p] ?: @{};
                [lines addObject:[NSString stringWithFormat:@"  + %@ size=%@ kind=%@ ids=%@ direct=%@ named=%@", p, r[@"size"] ?: @0, r[@"jsonKind"] ?: @"?", r[@"ids"] ?: @0, r[@"direct"] ?: @0, r[@"named"] ?: @0]];
                NSArray *sample = [r[@"sampleKeys"] isKindOfClass:[NSArray class]] ? r[@"sampleKeys"] : nil;
                if (sample.count) [lines addObject:[NSString stringWithFormat:@"    sample=%@", sample]];
                if (r[@"arrayCount"]) [lines addObject:[NSString stringWithFormat:@"    arrayCount=%@", r[@"arrayCount"]]];
                if (r[@"error"]) [lines addObject:[NSString stringWithFormat:@"    error=%@", r[@"error"]]];
            }
        } else {
            [lines addObject:@"  none"];
        }
        [lines addObject:@"Checked exact paths:"];
        for (NSString *p in gSCIMCCheckedPaths) [lines addObject:[NSString stringWithFormat:@"  - %@", p]];

        [lines addObject:@"Sample direct specifiers:"];
        NSArray<NSNumber *> *directKeys = [[gSCIMCDirectSpecifierNames allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger directCount = MIN((NSUInteger)12, directKeys.count);
        for (NSUInteger i = 0; i < directCount; i++) {
            NSNumber *n = directKeys[i];
            [lines addObject:[NSString stringWithFormat:@"  0x%016llx -> %@", n.unsignedLongLongValue, gSCIMCDirectSpecifierNames[n]]];
        }
        if (!directCount) [lines addObject:@"  none"];
        message = [lines componentsJoinedByString:@"\n"];
    });
    return message ?: @"Mapping: none";
}

+ (NSString *)resolvedNameForSpecifier:(unsigned long long)specifier {
    [self loadMappingIfNeeded];

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
