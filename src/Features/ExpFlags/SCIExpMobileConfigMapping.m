#import "SCIExpMobileConfigMapping.h"

static NSDictionary<NSString *, NSDictionary *> *gSCIMCMapping = nil;
static NSDictionary<NSString *, NSDictionary *> *gSCIMCNamedConfigs = nil;
static NSString *gSCIMCMappingSource = nil;
static NSArray<NSString *> *gSCIMCCheckedPaths = nil;
static NSArray<NSString *> *gSCIMCFoundPaths = nil;

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

@implementation SCIExpMobileConfigMapping

+ (NSArray<NSString *> *)candidateMappingPaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];

    NSString *home = NSHomeDirectory();
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *appSupport = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tmp = NSTemporaryDirectory();
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    NSString *fbFramework = [bundle stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework"];

    NSArray<NSString *> *baseDirs = @[
        home ?: @"",
        docs ?: @"",
        lib ?: @"",
        appSupport ?: @"",
        caches ?: @"",
        tmp ?: @"",
        bundle ?: @"",
        fbFramework ?: @"",
    ];

    NSArray<NSString *> *relative = @[
        @"id_name_mapping.json",
        @"example_mapping.json",
        @"mc_startup_configs.json",
        @"startup_configs.json",
        @"mobileconfig/id_name_mapping.json",
        @"mobileconfig/example_mapping.json",
        @"mobileconfig/mc_startup_configs.json",
        @"mobileconfig/startup_configs.json",
        @"Library/mobileconfig/id_name_mapping.json",
        @"Library/mobileconfig/example_mapping.json",
        @"Library/Application Support/mobileconfig/id_name_mapping.json",
        @"Library/Application Support/mobileconfig/example_mapping.json",
        @"Documents/mobileconfig/id_name_mapping.json",
        @"Documents/mobileconfig/example_mapping.json",
        @"RyukGram.bundle/id_name_mapping.json",
        @"RyukGram.bundle/example_mapping.json",
        @"RyukGram.bundle/mc_startup_configs.json",
        @"RyukGram.bundle/startup_configs.json",
        @"Library/Application Support/RyukGram.bundle/id_name_mapping.json",
        @"Library/Application Support/RyukGram.bundle/example_mapping.json",
        @"Library/Application Support/RyukGram.bundle/mc_startup_configs.json",
        @"Library/Application Support/RyukGram.bundle/startup_configs.json",
    ];

    for (NSString *base in baseDirs) {
        if (!base.length) continue;
        for (NSString *rel in relative) {
            SCIAddUniquePath(paths, [base stringByAppendingPathComponent:rel]);
        }
    }

    for (NSBundle *b in [NSBundle allBundles]) {
        NSString *bundlePath = b.bundlePath;
        if (bundlePath.length) {
            for (NSString *rel in relative) {
                SCIAddUniquePath(paths, [bundlePath stringByAppendingPathComponent:rel]);
            }
        }
        for (NSString *name in @[@"id_name_mapping", @"example_mapping", @"mc_startup_configs", @"startup_configs"]) {
            NSString *p = [b pathForResource:name ofType:@"json"];
            if (p.length) SCIAddUniquePath(paths, p);
        }
    }

    return paths;
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

    NSString *lid = [d[@"lid"] isKindOfClass:[NSString class]] ? d[@"lid"] : [[d[@"lid"] description] isKindOfClass:[NSString class]] ? [d[@"lid"] description] : @"";
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
                NSString *flagId = [d[@"flagId"] description] ?: [d[@"id"] description] ?: [d[@"key"] description];
                NSString *name = [d[@"name"] description] ?: [d[@"flagName"] description] ?: @"";
                NSDictionary *subs = [d[@"subs"] isKindOfClass:[NSDictionary class]] ? d[@"subs"] : @{};
                if (flagId.length) out[flagId] = @{@"name": name ?: @"", @"subs": subs ?: @{}};
            }
        }
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        for (NSString *flagId in dict.allKeys) {
            id value = dict[flagId];
            if ([value isKindOfClass:[NSString class]]) {
                NSDictionary *parsed = [self parseMappingRawString:value];
                NSString *realId = parsed[@"flagId"] ?: flagId;
                if (realId.length) out[realId] = @{@"name": parsed[@"name"] ?: @"", @"subs": parsed[@"subs"] ?: @{}};
            } else if ([value isKindOfClass:[NSDictionary class]]) {
                NSDictionary *d = value;
                NSString *name = [d[@"name"] description] ?: [d[@"flagName"] description] ?: @"";
                NSDictionary *subs = [d[@"subs"] isKindOfClass:[NSDictionary class]] ? d[@"subs"] : nil;
                if (subs || name.length) {
                    out[[flagId description]] = @{@"name": name ?: @"", @"subs": subs ?: @{}};
                } else {
                    [self addNamedConfigKey:[flagId description] value:value toMap:out named:namedOut];
                }
            }
        }
    }

    return out;
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
        NSFileManager *fm = [NSFileManager defaultManager];

        for (NSString *path in [self candidateMappingPaths]) {
            if (!path.length) continue;
            [checked addObject:path];
            if (![fm fileExistsAtPath:path]) continue;
            [found addObject:path];
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (!data.length) {
                [sources addObject:[NSString stringWithFormat:@"%@ exists-empty", path.lastPathComponent]];
                continue;
            }
            NSError *err = nil;
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
            if (!obj || err) {
                [sources addObject:[NSString stringWithFormat:@"%@ parse-error=%@", path.lastPathComponent, err.localizedDescription ?: @"unknown"]];
                continue;
            }
            NSMutableDictionary *named = [NSMutableDictionary dictionary];
            NSDictionary *parsed = [self parseMappingObject:obj named:named];
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
        if (sources.count) {
            gSCIMCMappingSource = [sources componentsJoinedByString:@", "];
            NSLog(@"[RyukGram][MCMapping] loaded %@", gSCIMCMappingSource);
        } else {
            gSCIMCMappingSource = @"none";
            NSLog(@"[RyukGram][MCMapping] no MobileConfig mapping/startup JSON found; checked=%lu", (unsigned long)checked.count);
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
    });
    [self loadMappingIfNeeded];
}

+ (NSString *)mappingSourceDescription {
    [self loadMappingIfNeeded];
    __block NSString *s = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        s = [NSString stringWithFormat:@"%@ · ids=%lu named=%lu · checked=%lu found=%lu", gSCIMCMappingSource ?: @"none", (unsigned long)gSCIMCMapping.count, (unsigned long)gSCIMCNamedConfigs.count, (unsigned long)gSCIMCCheckedPaths.count, (unsigned long)gSCIMCFoundPaths.count];
    });
    return s ?: @"none";
}

+ (NSString *)mappingDebugDescription {
    [self loadMappingIfNeeded];
    __block NSString *message = nil;
    dispatch_sync(SCIMCMappingQueue(), ^{
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"Mapping: %@", [self mappingSourceDescription]]];
        [lines addObject:@"Found mapping paths:"];
        if (gSCIMCFoundPaths.count) {
            for (NSString *p in gSCIMCFoundPaths) [lines addObject:[NSString stringWithFormat:@"  + %@", p]];
        } else {
            [lines addObject:@"  none"];
        }
        [lines addObject:@"Checked mapping paths:"];
        NSUInteger limit = MIN((NSUInteger)40, gSCIMCCheckedPaths.count);
        for (NSUInteger i = 0; i < limit; i++) [lines addObject:[NSString stringWithFormat:@"  - %@", gSCIMCCheckedPaths[i]]];
        if (gSCIMCCheckedPaths.count > limit) [lines addObject:[NSString stringWithFormat:@"  … %lu more", (unsigned long)(gSCIMCCheckedPaths.count - limit)]];

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
