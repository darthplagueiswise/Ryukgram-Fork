#import "SCINumericMCCatalog.h"

NSString * const SCINumericMCCatalogDidReloadNotification = @"SCINumericMCCatalogDidReloadNotification";

static NSArray<SCINumericMCEntry *> *gEntries;
static NSString *gSource;

static NSString *S(id obj) { return [obj isKindOfClass:NSString.class] ? (NSString *)obj : @""; }
static NSArray *A(id obj) { return [obj isKindOfClass:NSArray.class] ? (NSArray *)obj : @[]; }
static unsigned long long H(NSString *hex) {
    NSString *s = [[hex ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    unsigned long long v = 0;
    [[NSScanner scannerWithString:s] scanHexLongLong:&v];
    return v;
}
static NSString *HX(unsigned long long v) { return [NSString stringWithFormat:@"%016llx", v]; }

@implementation SCINumericMCEntry
+ (instancetype)entryWithDictionary:(NSDictionary *)dict {
    SCINumericMCEntry *e = [SCINumericMCEntry new];
    e.specifierHex = S(dict[@"specifier"]);
    e.specifier = H(e.specifierHex);
    e.label = S(dict[@"label"]);
    e.featureGroup = S(dict[@"feature_group"] ?: dict[@"feature"]);
    e.classification = S(dict[@"classification"]);
    id rec = dict[@"recommended_default_force_value"] ?: dict[@"recommended"];
    e.recommendedValue = [rec isKindOfClass:NSNumber.class] ? (NSNumber *)rec : nil;
    e.source = S(dict[@"source"]);
    e.confidence = S(dict[@"confidence"]);
    e.fileoff = S(dict[@"fileoff"]);
    e.vmaddr = S(dict[@"vmaddr"]);
    NSMutableArray *ev = [NSMutableArray array];
    for (id item in A(dict[@"evidence"])) {
        NSString *line = [item isKindOfClass:NSString.class] ? item : ([item respondsToSelector:@selector(description)] ? [item description] : @"");
        if (line.length) [ev addObject:line];
    }
    e.evidence = ev;
    return e;
}
- (NSString *)overrideKey { return [NSString stringWithFormat:@"mcbr:ig:%@", HX(self.specifier)]; }
- (NSString *)displayTitle { return self.label.length ? self.label : self.specifierHex; }
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
+ (BOOL)hasInstalledCatalog { return [NSFileManager.defaultManager fileExistsAtPath:[self catalogPath]]; }
+ (NSString *)sourceDescription { [self allEntries]; return gSource ?: @"not loaded"; }
+ (NSArray<NSString *> *)candidatePaths {
    NSMutableArray *paths = [NSMutableArray arrayWithObject:[self catalogPath]];
    NSBundle *b = NSBundle.mainBundle;
    NSString *p = [b pathForResource:@"sci_numeric_mc_overrides" ofType:@"json"];
    if (p.length) [paths addObject:p];
    p = [[b bundlePath] stringByAppendingPathComponent:@"sci_numeric_mc_overrides.json"];
    if (p.length) [paths addObject:p];
    return paths;
}
+ (NSArray<SCINumericMCEntry *> *)parseData:(NSData *)data source:(NSString *)source error:(NSError **)error {
    id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
    if (![root isKindOfClass:NSDictionary.class]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id obj in A(root[@"overrides"])) {
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        SCINumericMCEntry *e = [SCINumericMCEntry entryWithDictionary:obj];
        if (e.specifier) [out addObject:e];
    }
    [out sortUsingComparator:^NSComparisonResult(SCINumericMCEntry *x, SCINumericMCEntry *y) {
        NSComparisonResult r = [x.featureGroup localizedCaseInsensitiveCompare:y.featureGroup];
        return r == NSOrderedSame ? [x.displayTitle localizedCaseInsensitiveCompare:y.displayTitle] : r;
    }];
    gSource = [NSString stringWithFormat:@"%@ · entries=%lu", source ?: @"json", (unsigned long)out.count];
    return out;
}
+ (BOOL)installCatalogJSONData:(NSData *)data error:(NSError **)error {
    NSArray *parsed = [self parseData:data source:@"import" error:error];
    if (!parsed.count) return NO;
    NSString *path = [self catalogPath];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:error];
    if (ok) {
        gEntries = parsed;
        [[NSNotificationCenter defaultCenter] postNotificationName:SCINumericMCCatalogDidReloadNotification object:nil];
    }
    return ok;
}
+ (void)reload { gEntries = nil; gSource = nil; [self allEntries]; }
+ (NSArray<SCINumericMCEntry *> *)allEntries {
    if (gEntries) return gEntries;
    for (NSString *path in [self candidatePaths]) {
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (!data.length) continue;
        NSError *err = nil;
        NSArray *entries = [self parseData:data source:path.lastPathComponent error:&err];
        if (entries.count) { gEntries = entries; return entries; }
    }
    gSource = @"missing mobileconfig/sci_numeric_mc_overrides.json";
    gEntries = @[];
    return gEntries;
}
+ (NSUInteger)entryCount { return [self allEntries].count; }
+ (NSArray<NSString *> *)allFeatureGroups {
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
    for (SCINumericMCEntry *e in [self allEntries]) if (e.featureGroup.length) [set addObject:e.featureGroup];
    return set.array;
}
+ (NSArray<SCINumericMCEntry *> *)entriesForFeatureGroup:(NSString *)group {
    if (!group.length) return [self allEntries];
    NSMutableArray *out = [NSMutableArray array];
    for (SCINumericMCEntry *e in [self allEntries]) if ([e.featureGroup isEqualToString:group]) [out addObject:e];
    return out;
}
+ (NSArray<SCINumericMCEntry *> *)entriesMatchingQuery:(NSString *)query group:(NSString *)group {
    NSString *q = query.lowercaseString ?: @"";
    NSMutableArray *out = [NSMutableArray array];
    for (SCINumericMCEntry *e in [self entriesForFeatureGroup:group]) {
        if (q.length) {
            NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@", e.label ?: @"", e.specifierHex ?: @"", e.featureGroup ?: @"", e.classification ?: @"", e.confidence ?: @""] lowercaseString];
            if ([hay rangeOfString:q].location == NSNotFound) continue;
        }
        [out addObject:e];
    }
    return out;
}
@end
