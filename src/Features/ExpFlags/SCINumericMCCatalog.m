#import "SCINumericMCCatalog.h"
#import "SCIMobileConfigBrokerStore.h"

NSString * const SCINumericMCCatalogDidReloadNotification = @"SCINumericMCCatalogDidReloadNotification";

static NSArray<SCINumericMCEntry *> *gSCINumericMCEntries;
static NSString *gSCINumericMCSource;

static NSString *SCINMCString(id obj) { return [obj isKindOfClass:NSString.class] ? (NSString *)obj : @""; }
static NSArray *SCINMCArray(id obj) { return [obj isKindOfClass:NSArray.class] ? (NSArray *)obj : @[]; }

static unsigned long long SCINMCParseHex(NSString *hex) {
    NSString *s = [[hex ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    unsigned long long value = 0;
    [[NSScanner scannerWithString:s] scanHexLongLong:&value];
    return value;
}

@implementation SCINumericMCEntry

+ (instancetype)entryWithDictionary:(NSDictionary *)dict {
    SCINumericMCEntry *e = [SCINumericMCEntry new];
    e.specifierHex = SCINMCString(dict[@"specifier"]);
    e.specifier = SCINMCParseHex(e.specifierHex);
    e.label = SCINMCString(dict[@"label"]);
    e.featureGroup = SCINMCString(dict[@"feature_group"] ?: dict[@"feature"]);
    e.classification = SCINMCString(dict[@"classification"]);
    id rec = dict[@"recommended_default_force_value"] ?: dict[@"recommended"];
    e.recommendedValue = [rec isKindOfClass:NSNumber.class] ? (NSNumber *)rec : nil;
    e.source = SCINMCString(dict[@"source"]);
    e.confidence = SCINMCString(dict[@"confidence"]);
    e.fileoff = SCINMCString(dict[@"fileoff"]);
    e.vmaddr = SCINMCString(dict[@"vmaddr"]);

    NSMutableArray *ev = [NSMutableArray array];
    for (id item in SCINMCArray(dict[@"evidence"])) {
        NSString *s = [item isKindOfClass:NSString.class] ? item : ([item respondsToSelector:@selector(description)] ? [item description] : @"");
        if (s.length) [ev addObject:s];
    }
    e.evidence = ev;
    return e;
}

- (NSString *)overrideKey {
    return [SCIMobileConfigBrokerStore overrideKeyForBrokerID:@"ig" value:(uint64_t)self.specifier];
}

- (NSString *)displayTitle {
    return self.label.length ? self.label : self.specifierHex;
}

- (NSString *)displaySubtitle {
    NSMutableArray<NSString *> *bits = [NSMutableArray array];
    if (self.specifierHex.length) [bits addObject:self.specifierHex];
    if (self.featureGroup.length) [bits addObject:self.featureGroup];
    if (self.recommendedValue) [bits addObject:self.recommendedValue.boolValue ? @"suggested ON" : @"suggested OFF"];
    if (self.confidence.length) [bits addObject:self.confidence];
    if (self.fileoff.length) [bits addObject:[@"fileoff " stringByAppendingString:self.fileoff]];
    return [bits componentsJoinedByString:@" · "];
}
@end

@implementation SCINumericMCCatalog

+ (NSString *)catalogPath {
    NSArray<NSURL *> *urls = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    NSString *docs = urls.firstObject.path ?: NSTemporaryDirectory();
    return [[docs stringByAppendingPathComponent:@"mobileconfig"] stringByAppendingPathComponent:@"sci_numeric_mc_overrides.json"];
}

+ (NSArray<NSString *> *)candidatePaths {
    NSMutableArray *paths = [NSMutableArray array];
    [paths addObject:[self catalogPath]];

    NSBundle *b = NSBundle.mainBundle;
    NSString *res = [b pathForResource:@"sci_numeric_mc_overrides" ofType:@"json"];
    if (res.length) [paths addObject:res];

    NSString *res2 = [b pathForResource:@"sci_numeric_mc_overrides.menu_candidates" ofType:@"json"];
    if (res2.length) [paths addObject:res2];

    NSString *bundle = [[b bundlePath] stringByAppendingPathComponent:@"sci_numeric_mc_overrides.json"];
    if (bundle.length) [paths addObject:bundle];

    return paths;
}

+ (BOOL)hasInstalledCatalog {
    return [NSFileManager.defaultManager fileExistsAtPath:[self catalogPath]];
}

+ (NSString *)sourceDescription {
    [self allEntries];
    return gSCINumericMCSource ?: @"not loaded";
}

+ (NSArray<SCINumericMCEntry *> *)entriesFromData:(NSData *)data source:(NSString *)source error:(NSError **)error {
    if (!data.length) return @[];
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class]) return @[];

    NSArray *raw = SCINMCArray(root[@"overrides"]);
    NSMutableArray *out = [NSMutableArray array];

    for (id obj in raw) {
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        SCINumericMCEntry *e = [SCINumericMCEntry entryWithDictionary:obj];
        if (e.specifier != 0) [out addObject:e];
    }

    [out sortUsingComparator:^NSComparisonResult(SCINumericMCEntry *a, SCINumericMCEntry *b) {
        NSComparisonResult g = [a.featureGroup localizedCaseInsensitiveCompare:b.featureGroup];
        if (g != NSOrderedSame) return g;
        return [a.displayTitle localizedCaseInsensitiveCompare:b.displayTitle];
    }];

    gSCINumericMCSource = [NSString stringWithFormat:@"%@ · entries=%lu", source ?: @"json", (unsigned long)out.count];
    return out;
}

+ (BOOL)installCatalogJSONData:(NSData *)data error:(NSError **)error {
    if (!data.length) return NO;

    NSArray *parsed = [self entriesFromData:data source:@"pasteboard/import" error:error];
    if (!parsed.count) return NO;

    NSString *path = [self catalogPath];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:error];
    if (ok) {
        gSCINumericMCEntries = parsed;
        [[NSNotificationCenter defaultCenter] postNotificationName:SCINumericMCCatalogDidReloadNotification object:nil];
    }
    return ok;
}

+ (void)reload {
    gSCINumericMCEntries = nil;
    gSCINumericMCSource = nil;
    [self allEntries];
}

+ (NSArray<SCINumericMCEntry *> *)allEntries {
    if (gSCINumericMCEntries) return gSCINumericMCEntries;

    for (NSString *path in [self candidatePaths]) {
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (!data.length) continue;

        NSError *err = nil;
        NSArray *entries = [self entriesFromData:data source:path.lastPathComponent error:&err];
        if (entries.count) {
            gSCINumericMCEntries = entries;
            return entries;
        }
    }

    gSCINumericMCSource = @"missing mobileconfig/sci_numeric_mc_overrides.json";
    gSCINumericMCEntries = @[];
    return gSCINumericMCEntries;
}

+ (NSUInteger)entryCount { return [self allEntries].count; }

+ (NSArray<NSString *> *)allFeatureGroups {
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    for (SCINumericMCEntry *e in [self allEntries]) {
        if (e.featureGroup.length) [set addObject:e.featureGroup];
    }
    return set.array;
}

+ (NSArray<SCINumericMCEntry *> *)entriesForFeatureGroup:(NSString *)group {
    if (!group.length) return [self allEntries];

    NSMutableArray *out = [NSMutableArray array];
    for (SCINumericMCEntry *e in [self allEntries]) {
        if ([e.featureGroup isEqualToString:group]) [out addObject:e];
    }
    return out;
}

+ (NSArray<SCINumericMCEntry *> *)entriesMatchingQuery:(NSString *)query group:(NSString *)group {
    NSString *q = query.lowercaseString ?: @"";
    NSMutableArray *out = [NSMutableArray array];

    for (SCINumericMCEntry *e in [self entriesForFeatureGroup:group]) {
        if (q.length) {
            NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@",
                              e.label ?: @"",
                              e.specifierHex ?: @"",
                              e.featureGroup ?: @"",
                              e.classification ?: @"",
                              e.confidence ?: @"",
                              e.fileoff ?: @""] lowercaseString];
            if ([hay rangeOfString:q].location == NSNotFound) continue;
        }
        [out addObject:e];
    }
    return out;
}
@end
