#import "SCIExpMobileConfigMapping.h"

static NSDictionary<NSString *, NSDictionary *> *gSCIMCMapping = nil;
static NSDictionary<NSString *, NSDictionary *> *gSCIMCNamedConfigs = nil;
static NSString *gSCIMCMappingSource = nil;
static NSArray<NSString *> *gSCIMCCheckedPaths = nil;
static NSArray<NSString *> *gSCIMCFoundPaths = nil;
static NSArray<NSString *> *gSCIMCRoots = nil;
static NSDictionary<NSString *, NSDictionary *> *gSCIMCFileReports = nil;

static dispatch_queue_t SCIMCMappingQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("sci.expflags.mc.mapping", DISPATCH_QUEUE_CONCURRENT); });
    return q;
}

static void SCIAddUniquePath(NSMutableArray<NSString *> *paths, NSString *path) {
    if (!path.length) return;
    NSString *standardized = [path stringByStandardizingPath];
    if (!standardized.length) return;
    if (![paths containsObject:standardized]) [paths addObject:standardized];
}

static BOOL SCIPathExistsDirectory(NSString *path, BOOL *isDirOut) {
    if (!path.length) return NO;
    BOOL isDir = NO;
    BOOL ok = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (isDirOut) *isDirOut = isDir;
    return ok;
}

static BOOL SCIFileNameLooksLikeMobileConfigMapping(NSString *path) {
    NSString *name = path.lastPathComponent.lowercaseString ?: @"";
    NSString *ext = path.pathExtension.lowercaseString ?: @"";
    if (![ext isEqualToString:@"json"]) return NO;

    if ([name isEqualToString:@"id_name_mapping.json"]) return YES;
    if ([name isEqualToString:@"id_mapping.json"]) return YES;
    if ([name isEqualToString:@"name_mapping.json"]) return YES;
    if ([name isEqualToString:@"example_mapping.json"]) return YES;
    if ([name isEqualToString:@"mc_startup_configs.json"]) return YES;
    if ([name isEqualToString:@"startup_configs.json"]) return YES;

    if ([name containsString:@"mapping"]) return YES;
    if ([name containsString:@"mobileconfig"]) return YES;
    if ([name containsString:@"startup"] && [name containsString:@"config"]) return YES;
    if ([name containsString:@"client"] && [name containsString:@"persist"]) return YES;
    if ([name containsString:@"distillery"]) return YES;
    return NO;
}

static NSString *SCIJSONStringObjectKind(id obj) {
    if ([obj isKindOfClass:[NSDictionary class]]) return @"dictionary";
    if ([obj isKindOfClass:[NSArray class]]) return @"array";
    if ([obj isKindOfClass:[NSString class]]) return @"string";
    if ([obj isKindOfClass:[NSNumber class]]) return @"number";
    if (!obj) return @"nil";
    return NSStringFromClass([obj class]);
}

@implementation SCIExpMobileConfigMapping

+ (NSArray<NSString *> *)recursiveSearchRoots {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tmp = NSTemporaryDirectory();
    NSString *bundle = [[NSBundle mainBundle] bundlePath];

    SCIAddUniquePath(roots, bundle);
    SCIAddUniquePath(roots, [bundle stringByAppendingPathComponent:@"Frameworks"]);
    SCIAddUniquePath(roots, [bundle stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework"]);
    SCIAddUniquePath(roots, [bundle stringByAppendingPathComponent:@"RyukGram.bundle"]);
    SCIAddUniquePath(roots, home);
    SCIAddUniquePath(roots, docs);
    SCIAddUniquePath(roots, lib);
    SCIAddUniquePath(roots, appSupport);
    SCIAddUniquePath(roots, caches);
    SCIAddUniquePath(roots, tmp);

    for (NSBundle *b in [NSBundle allBundles]) {
        SCIAddUniquePath(roots, b.bundlePath);
    }

    NSMutableArray<NSString *> *existing = [NSMutableArray array];
    for (NSString *root in roots) {
        BOOL isDir = NO;
        if (SCIPathExistsDirectory(root, &isDir) && isDir) [existing addObject:root];
    }
    return existing;
}

+ (NSArray<NSString *> *)exactCandidateMappingPaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tmp = NSTemporaryDirectory();
    NSString *bundle = [[NSBundle mainBundle] bundlePath];

    NSArray<NSString *> *baseDirs = @[
        home ?: @"",
        docs ?: @"",
        lib ?: @"",
        appSupport ?: @"",
        caches ?: @"",
        tmp ?: @"",
        bundle ?: @"",
        [bundle stringByAppendingPathComponent:@"Frameworks"] ?: @"",
        [bundle stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework"] ?: @"",
        [bundle stringByAppendingPathComponent:@"RyukGram.bundle"] ?: @"",
    ];

    NSArray<NSString *> *names = @[
        @"id_name_mapping.json",
        @"id_mapping.json",
        @"name_mapping.json",
        @"example_mapping.json",
        @"mc_startup_configs.json",
        @"startup_configs.json",
    ];
    NSArray<NSString *> *subdirs = @[@"", @"mobileconfig", @"MobileConfig", @"Config", @"configs", @"Resources"];

    for (NSString *base in baseDirs) {
        if (!base.length) continue;
        for (NSString *subdir in subdirs) {
            NSString *dir = subdir.length ? [base stringByAppendingPathComponent:subdir] : base;
            for (NSString *name in names) SCIAddUniquePath(paths, [dir stringByAppendingPathComponent:name]);
        }
    }

    for (NSBundle *b in [NSBundle allBundles]) {
        for (NSString *name in @[@"id_name_mapping", @"id_mapping", @"name_mapping", @"example_mapping", @"mc_startup_configs", @"startup_configs"]) {
            NSString *p = [b pathForResource:name ofType:@"json"];
            if (p.length) SCIAddUniquePath(paths, p);
        }
    }

    return paths;
}

+ (NSArray<NSString *> *)recursiveCandidateMappingPathsWithChecked:(NSMutableArray<NSString *> *)checked roots:(NSMutableArray<NSString *> *)rootsOut {
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = [self recursiveSearchRoots];
    [rootsOut addObjectsFromArray:roots];

    for (NSString *root in roots) {
        NSDirectoryEnumerator<NSURL *> *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:root]
                                      includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLFileSizeKey]
                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                    errorHandler:^BOOL(NSURL *url, NSError *error) {
            NSLog(@"[RyukGram][MCMapping] recursive scan error %@: %@", url.path, error.localizedDescription);
            return YES;
        }];

        NSUInteger visited = 0;
        for (NSURL *url in en) {
            if (++visited > 20000) {
                NSLog(@"[RyukGram][MCMapping] recursive scan cap hit at root %@", root);
                break;
            }
            NSString *path = url.path;
            if (!path.length) continue;

            NSNumber *isDirNum = nil;
            [url getResourceValue:&isDirNum forKey:NSURLIsDirectoryKey error:nil];
            if (isDirNum.boolValue) {
                NSString *name = path.lastPathComponent.lowercaseString ?: @"";
                if ([name isEqualToString:@".git"] || [name isEqualToString:@"_codesignature"]) [en skipDescendants];
                continue;
            }

            NSString *ext = path.pathExtension.lowercaseString ?: @"";
            if ([ext isEqualToString:@"json"]) SCIAddUniquePath(checked, path);
            if (SCIFileNameLooksLikeMobileConfigMapping(path)) SCIAddUniquePath(found, path);
        }
    }

    return found;
}

+ (NSArray<NSString *> *)candidateMappingPaths {
    NSMutableArray<NSString *> *checked = [NSMutableArray array];
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    for (NSString *p in [self exactCandidateMappingPaths]) SCIAddUniquePath(checked, p);
    NSArray<NSString *> *recursive = [self recursiveCandidateMappingPathsWithChecked:checked roots:roots];
    NSMutableArray<NSString *> *all = [checked mutableCopy] ?: [NSMutableArray array];
    for (NSString *p in recursive) SCIAddUniquePath(all, p);
    return all;
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

+ (NSDictionary *)parseMappingRawString:(NSString *)raw {
    NSArray<NSString *> *parts = [raw componentsSeparatedByString:@":"];
    if (parts.count < 2) return nil;
    NSString *flagId = parts[0];
    NSString *flagName = parts[1];
    if (!flagId.length || !flagName.length) return nil;

    NSMutableDictionary *subs = [NSMutableDictionary dictionary];
    for (NSUInteger i = 2; i + 1 < parts.count; i += 2) {
        NSString *paramId = parts[i];
        NSString *paramName = parts[i + 1];
        if (paramId.length && paramName.length) subs[paramId] = paramName;
    }

    return @{@"flagId": flagId, @"name": flagName, @"subs": subs};
}

+ (void)addNamedConfigKey:(NSString *)key value:(id)value toMap:(NSMutableDictionary<NSString *, NSDictionary *> *)out named:(NSMutableDictionary<NSString *, NSDictionary *> *)named {
    if (![key isKindOfClass:[NSString class]] || !key.length) return;
    if (![value isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = (NSDictionary *)value;
    if (![key containsString:@"."] && ![key hasPrefix:@"ig_"] && ![key hasPrefix:@"mc_"] && ![key hasPrefix:@"qe_"] && ![key hasPrefix:@"p92_"] && ![key hasPrefix:@"bsl_"] && ![key hasPrefix:@"bcn_"]) return;

    id rawLid = d[@"lid"];
    NSString *lid = [rawLid isKindOfClass:[NSString class]] ? rawLid : (rawLid ? [rawLid description] : @"");
    id v = d[@"v"];
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"name"] = key;
    if (lid.length) entry[@"lid"] = lid;
    if (v) entry[@"v"] = v;
    named[key] = entry;

    if (!lid.length) return;

    unsigned long long spec = 0;
    NSScanner *scanner = [NSScanner scannerWithString:lid];
    if ([lid hasPrefix:@"0x"] || [lid hasPrefix:@"0X"]) {
        [scanner scanHexLongLong:&spec];
    } else {
        long long signedSpec = 0;
        if ([scanner scanLongLong:&signedSpec]) spec = (unsigned long long)signedSpec;
    }
    if (!spec) return;

    uint32_t flagId32 = (uint32_t)(spec >> 32);
    uint32_t paramId32 = (uint32_t)(spec & 0xffffffffULL);
    NSString *flagId = [NSString stringWithFormat:@"%u", flagId32];
    NSString *paramId = [NSString stringWithFormat:@"%u", paramId32];

    NSString *flagName = key;
    NSString *paramName = key;
    NSRange dot = [key rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound && dot.location > 0 && dot.location + 1 < key.length) {
        flagName = [key substringToIndex:dot.location];
        paramName = [key substringFromIndex:dot.location + 1];
    }

    NSMutableDictionary *flag = [out[flagId] mutableCopy] ?: [NSMutableDictionary dictionary];
    flag[@"name"] = flag[@"name"] ?: flagName;
    NSMutableDictionary *subs = [flag[@"subs"] mutableCopy] ?: [NSMutableDictionary dictionary];
    subs[paramId] = paramName;
    flag[@"subs"] = subs;
    out[flagId] = flag;
}

+ (NSDictionary<NSString *, NSDictionary *> *)parseMappingObject:(id)obj named:(NSMutableDictionary<NSString *, NSDictionary *> *)namedOut {
    NSMutableDictionary<NSString *, NSDictionary *> *out = [NSMutableDictionary dictionary];

    if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)obj) {
            if ([item isKindOfClass:[NSString class]]) {
                NSDictionary *parsed = [self parseMappingRawString:item];
                NSString *flagId = parsed[@"flagId"];
                if (flagId.length) out[flagId] = @{@"name": parsed[@"name"] ?: @"", @"subs": parsed[@"subs"] ?: @{}};
            } else if ([item isKindOfClass:[NSDictionary class]]) {
                NSDictionary *d = item;
                NSString *flagId = d[@"flagId"] ? [d[@"flagId"] description] : (d[@"id"] ? [d[@"id"] description] : (d[@"key"] ? [d[@"key"] description] : @""));
                NSString *name = d[@"name"] ? [d[@"name"] description] : (d[@"flagName"] ? [d[@"flagName"] description] : @"");
                NSDictionary *subs = [d[@"subs"] isKindOfClass:[NSDictionary class]] ? d[@"subs"] : @{};
                if (flagId.length) out[flagId] = @{@"name": name ?: @"", @"subs": subs ?: @{}};
            }
        }
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        for (id rawKey in dict.allKeys) {
            NSString *flagId = [rawKey description];
            id value = dict[rawKey];
            if ([value isKindOfClass:[NSString class]]) {
                NSDictionary *parsed = [self parseMappingRawString:value];
                NSString *realId = parsed[@"flagId"] ?: flagId;
                if (realId.length) out[realId] = @{@"name": parsed[@"name"] ?: @"", @"subs": parsed[@"subs"] ?: @{}};
            } else if ([value isKindOfClass:[NSDictionary class]]) {
                NSDictionary *d = value;
                NSString *name = d[@"name"] ? [d[@"name"] description] : (d[@"flagName"] ? [d[@"flagName"] description] : @"");
                NSDictionary *subs = [d[@"subs"] isKindOfClass:[NSDictionary class]] ? d[@"subs"] : nil;
                if (subs || name.length) {
                    out[flagId] = @{@"name": name ?: @"", @"subs": subs ?: @{}};
                } else {
                    [self addNamedConfigKey:flagId value:value toMap:out named:namedOut];
                }
            }
        }
    }

    return out;
}

+ (NSDictionary *)reportForPath:(NSString *)path mapping:(NSDictionary *)mapping named:(NSDictionary *)named json:(id)obj error:(NSError *)err size:(unsigned long long)size {
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"size"] = @(size);
    r[@"jsonKind"] = SCIJSONStringObjectKind(obj);
    r[@"ids"] = @((NSUInteger)mapping.count);
    r[@"named"] = @((NSUInteger)named.count);
    if (err.localizedDescription.length) r[@"error"] = err.localizedDescription;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [[(NSDictionary *)obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger n = MIN((NSUInteger)6, keys.count);
        r[@"sampleKeys"] = n ? [keys subarrayWithRange:NSMakeRange(0, n)] : @[];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        r[@"arrayCount"] = @([(NSArray *)obj count]);
    }
    return r;
}

+ (void)loadMappingIfNeeded {
    __block BOOL loaded = NO;
    dispatch_sync(SCIMCMappingQueue(), ^{ loaded = (gSCIMCMapping != nil); });
    if (loaded) return;

    dispatch_barrier_sync(SCIMCMappingQueue(), ^{
        if (gSCIMCMapping) return;
        NSMutableDictionary *allMapping = [NSMutableDictionary dictionary];
        NSMutableDictionary *allNamed = [NSMutableDictionary dictionary];
        NSMutableArray<NSString *> *sources = [NSMutableArray array];
        NSMutableArray<NSString *> *checked = [NSMutableArray array];
        NSMutableArray<NSString *> *found = [NSMutableArray array];
        NSMutableArray<NSString *> *roots = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSDictionary *> *reports = [NSMutableDictionary dictionary];
        NSFileManager *fm = [NSFileManager defaultManager];

        for (NSString *p in [self exactCandidateMappingPaths]) SCIAddUniquePath(checked, p);
        NSArray<NSString *> *recursiveFound = [self recursiveCandidateMappingPathsWithChecked:checked roots:roots];
        NSMutableArray<NSString *> *toInspect = [NSMutableArray array];
        for (NSString *p in [self exactCandidateMappingPaths]) SCIAddUniquePath(toInspect, p);
        for (NSString *p in recursiveFound) SCIAddUniquePath(toInspect, p);

        for (NSString *path in toInspect) {
            if (!path.length) continue;
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) continue;
            SCIAddUniquePath(found, path);

            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data.length) {
                reports[path] = [self reportForPath:path mapping:@{} named:@{} json:nil error:nil size:size];
                [sources addObject:[NSString stringWithFormat:@"%@ exists-empty", path.lastPathComponent]];
                continue;
            }
            NSError *err = nil;
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
            if (!obj || err) {
                reports[path] = [self reportForPath:path mapping:@{} named:@{} json:nil error:err size:size];
                [sources addObject:[NSString stringWithFormat:@"%@ parse-error", path.lastPathComponent]];
                continue;
            }
            NSMutableDictionary *named = [NSMutableDictionary dictionary];
            NSDictionary *parsed = [self parseMappingObject:obj named:named];
            reports[path] = [self reportForPath:path mapping:parsed ?: @{} named:named ?: @{} json:obj error:nil size:size];
            if (parsed.count || named.count) {
                [allMapping addEntriesFromDictionary:parsed ?: @{}];
                [allNamed addEntriesFromDictionary:named ?: @{}];
                [sources addObject:[NSString stringWithFormat:@"%@ (%lu ids/%lu named)", path.lastPathComponent, (unsigned long)parsed.count, (unsigned long)named.count]];
            } else {
                [sources addObject:[NSString stringWithFormat:@"%@ parsed-empty", path.lastPathComponent]];
            }
        }

        gSCIMCMapping = allMapping ?: @{};
        gSCIMCNamedConfigs = allNamed ?: @{};
        gSCIMCCheckedPaths = [checked copy] ?: @[];
        gSCIMCFoundPaths = [found copy] ?: @[];
        gSCIMCRoots = [roots copy] ?: @[];
        gSCIMCFileReports = [reports copy] ?: @{};
        if (sources.count) {
            gSCIMCMappingSource = [sources componentsJoinedByString:@", "];
            NSLog(@"[RyukGram][MCMapping] loaded %@", gSCIMCMappingSource);
        } else {
            gSCIMCMappingSource = @"none";
            NSLog(@"[RyukGram][MCMapping] no MobileConfig mapping/startup JSON found; checked=%lu roots=%lu", (unsigned long)checked.count, (unsigned long)roots.count);
        }
    });
}

+ (void)reloadMapping {
    dispatch_barrier_sync(SCIMCMappingQueue(), ^{
        gSCIMCMapping = nil;
        gSCIMCNamedConfigs = nil;
        gSCIMCMappingSource = nil;
        gSCIMCCheckedPaths = nil;
        gSCIMCFoundPaths = nil;
        gSCIMCRoots = nil;
        gSCIMCFileReports = nil;
    });
    [self loadMappingIfNeeded];
}

+ (NSString *)mappingSourceDescription {
    [self loadMappingIfNeeded];
    __block NSString *s = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        s = [NSString stringWithFormat:@"%@ · ids=%lu named=%lu · checkedJson=%lu foundCandidates=%lu roots=%lu", gSCIMCMappingSource ?: @"none", (unsigned long)gSCIMCMapping.count, (unsigned long)gSCIMCNamedConfigs.count, (unsigned long)gSCIMCCheckedPaths.count, (unsigned long)gSCIMCFoundPaths.count, (unsigned long)gSCIMCRoots.count];
    });
    return s ?: @"none";
}

+ (NSString *)mappingDebugDescription {
    [self loadMappingIfNeeded];
    __block NSString *message = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"Mapping: %@", [self mappingSourceDescription]]];
        [lines addObject:@"Recursive search roots:"];
        if (gSCIMCRoots.count) {
            for (NSString *p in gSCIMCRoots) [lines addObject:[NSString stringWithFormat:@"  - %@", p]];
        } else {
            [lines addObject:@"  none"];
        }

        [lines addObject:@"Found mapping/mobileconfig JSON candidates:"];
        if (gSCIMCFoundPaths.count) {
            NSUInteger limit = MIN((NSUInteger)40, gSCIMCFoundPaths.count);
            for (NSUInteger i = 0; i < limit; i++) {
                NSString *p = gSCIMCFoundPaths[i];
                NSDictionary *r = gSCIMCFileReports[p] ?: @{};
                NSString *line = [NSString stringWithFormat:@"  + %@ size=%@ kind=%@ ids=%@ named=%@", p, r[@"size"] ?: @0, r[@"jsonKind"] ?: @"?", r[@"ids"] ?: @0, r[@"named"] ?: @0];
                [lines addObject:line];
                NSArray *sample = [r[@"sampleKeys"] isKindOfClass:[NSArray class]] ? r[@"sampleKeys"] : nil;
                if (sample.count) [lines addObject:[NSString stringWithFormat:@"    sample=%@", sample]];
                if (r[@"arrayCount"]) [lines addObject:[NSString stringWithFormat:@"    arrayCount=%@", r[@"arrayCount"]]];
                if (r[@"error"]) [lines addObject:[NSString stringWithFormat:@"    error=%@", r[@"error"]]];
            }
            if (gSCIMCFoundPaths.count > limit) [lines addObject:[NSString stringWithFormat:@"  ... %lu more", (unsigned long)(gSCIMCFoundPaths.count - limit)]];
        } else {
            [lines addObject:@"  none"];
        }

        [lines addObject:@"Checked JSON files / exact candidate paths:"];
        NSUInteger checkedLimit = MIN((NSUInteger)60, gSCIMCCheckedPaths.count);
        for (NSUInteger i = 0; i < checkedLimit; i++) [lines addObject:[NSString stringWithFormat:@"  - %@", gSCIMCCheckedPaths[i]]];
        if (gSCIMCCheckedPaths.count > checkedLimit) [lines addObject:[NSString stringWithFormat:@"  ... %lu more", (unsigned long)(gSCIMCCheckedPaths.count - checkedLimit)]];

        [lines addObject:@"Sample parsed ids:"];
        NSArray<NSString *> *keys = [[gSCIMCMapping allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger sampleCount = MIN((NSUInteger)8, keys.count);
        for (NSUInteger i = 0; i < sampleCount; i++) {
            NSString *key = keys[i];
            NSDictionary *flag = gSCIMCMapping[key];
            NSDictionary *subs = [flag[@"subs"] isKindOfClass:[NSDictionary class]] ? flag[@"subs"] : @{};
            NSArray *subKeys = [[subs allKeys] sortedArrayUsingSelector:@selector(compare:)];
            NSArray *firstSubs = subKeys.count > 5 ? [subKeys subarrayWithRange:NSMakeRange(0, 5)] : subKeys;
            [lines addObject:[NSString stringWithFormat:@"  %@ -> %@ subs=%@", key, flag[@"name"] ?: @"", firstSubs]];
        }
        if (!sampleCount) [lines addObject:@"  none"];

        [lines addObject:@"Sample named startup configs:"];
        NSArray<NSString *> *namedKeys = [[gSCIMCNamedConfigs allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger namedSampleCount = MIN((NSUInteger)12, namedKeys.count);
        for (NSUInteger i = 0; i < namedSampleCount; i++) {
            NSString *key = namedKeys[i];
            NSDictionary *entry = gSCIMCNamedConfigs[key];
            NSString *lid = [entry[@"lid"] isKindOfClass:[NSString class]] ? entry[@"lid"] : @"";
            id value = entry[@"v"];
            [lines addObject:[NSString stringWithFormat:@"  %@ lid=%@ v=%@", key, lid.length ? lid : @"empty", value ?: @"<default>"]];
        }
        if (!namedSampleCount) [lines addObject:@"  none"];
        message = [lines componentsJoinedByString:@"\n"];
    });
    return message ?: @"Mapping: none";
}

+ (NSString *)resolvedNameForSpecifier:(unsigned long long)specifier {
    [self loadMappingIfNeeded];

    uint32_t flagId32 = (uint32_t)(specifier >> 32);
    uint32_t paramId32 = (uint32_t)(specifier & 0xffffffffULL);
    NSString *flagDec = [NSString stringWithFormat:@"%u", flagId32];
    NSString *paramDec = [NSString stringWithFormat:@"%u", paramId32];
    NSString *flagHex = [NSString stringWithFormat:@"0x%08x", flagId32];
    NSString *paramHex = [NSString stringWithFormat:@"0x%08x", paramId32];

    __block NSDictionary *flag = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        flag = gSCIMCMapping[flagDec] ?: gSCIMCMapping[flagHex] ?: gSCIMCMapping[[flagHex uppercaseString]];
    });
    if (![flag isKindOfClass:[NSDictionary class]]) return nil;

    NSString *flagName = [flag[@"name"] isKindOfClass:[NSString class]] ? flag[@"name"] : @"";
    NSDictionary *subs = [flag[@"subs"] isKindOfClass:[NSDictionary class]] ? flag[@"subs"] : @{};
    NSString *paramName = nil;
    id p = subs[paramDec] ?: subs[paramHex] ?: subs[[paramHex uppercaseString]];
    if (p) paramName = [p description];

    if (flagName.length && paramName.length) return [NSString stringWithFormat:@"%@ / %@", flagName, paramName];
    if (flagName.length) return [NSString stringWithFormat:@"%@ / param %@", flagName, paramDec];
    if (paramName.length) return [NSString stringWithFormat:@"flag %@ / %@", flagDec, paramName];
    return nil;
}

@end
