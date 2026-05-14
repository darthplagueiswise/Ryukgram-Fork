#import "SCIIgMobileDeprecatedConfigCatalog.h"

NSString * const SCIIgMobileDeprecatedConfigCatalogDidUpdateNotification = @"SCIIgMobileDeprecatedConfigCatalogDidUpdateNotification";

static NSString * const kSCIIgMobileDeprecatedCatalogKeys = @"sci.igmobile.deprecated.catalog.keys";
static NSString * const kSCIIgMobileDeprecatedCatalogSource = @"sci.igmobile.deprecated.catalog.source";
static NSString * const kSCIIgMobileDeprecatedCatalogImportedAt = @"sci.igmobile.deprecated.catalog.imported_at";
static NSString * const kSCIIgMobileDeprecatedCatalogCount = @"sci.igmobile.deprecated.catalog.count";

@implementation SCIIgMobileDeprecatedConfigMatch
@end

static NSObject *SCIIgMobileCatalogLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static NSMutableDictionary<NSString *, id> *SCIIgMobileMemoryCache(void) {
    static NSMutableDictionary<NSString *, id> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

static NSString *SCIIgMobileString(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSString *SCIIgMobileLower(NSString *value) {
    return SCIIgMobileString(value).lowercaseString ?: @"";
}

static NSString *SCIIgMobileISODate(NSDate *date) {
    if (![date isKindOfClass:NSDate.class]) return @"";
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    return [fmt stringFromDate:date] ?: @"";
}

static NSArray<NSString *> *SCIIgMobileTokenize(NSString *value) {
    NSString *lower = SCIIgMobileLower(value);
    if (!lower.length) return @[];

    NSMutableString *expanded = [NSMutableString stringWithCapacity:lower.length * 2];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar ch = [lower characterAtIndex:i];
        if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) [expanded appendFormat:@"%C", ch];
        else [expanded appendString:@" "];
    }

    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    for (NSString *part in [expanded componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (part.length < 3) continue;
        [set addObject:part];
    }
    return set.array;
}

static NSArray<NSString *> *SCIIgMobileFeatureTokens(void) {
    return @[
        @"quicksnap", @"instants", @"instant",
        @"story", @"stories", @"tray",
        @"prism", @"notes", @"note", @"directnotes", @"direct",
        @"friendmap", @"friend", @"map", @"location",
        @"icebreaker", @"mutual", @"interest",
        @"employee", @"dogfood", @"internal",
        @"reels", @"feed", @"camera", @"launcher", @"tabbar", @"liquid", @"glass"
    ];
}

static NSDictionary<NSString *, NSArray<NSString *> *> *SCIIgMobileTokenIndexForKeys(NSArray<NSString *> *keys) {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *idx = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSMutableOrderedSet<NSString *> *tokens = [NSMutableOrderedSet orderedSetWithArray:SCIIgMobileTokenize(key)];
        NSString *group = [key componentsSeparatedByString:@"."].firstObject ?: @"";
        for (NSString *t in SCIIgMobileTokenize(group)) [tokens addObject:t];

        for (NSString *t in tokens.array) {
            NSMutableArray *arr = idx[t];
            if (!arr) {
                arr = [NSMutableArray array];
                idx[t] = arr;
            }
            [arr addObject:key];
        }
    }
    return idx;
}

static NSArray<NSString *> *SCIIgMobileStoredKeys(void) {
    @synchronized (SCIIgMobileCatalogLock()) {
        NSArray *mem = SCIIgMobileMemoryCache()[@"keys"];
        if ([mem isKindOfClass:NSArray.class]) return mem;
    }

    NSArray *keys = [NSUserDefaults.standardUserDefaults arrayForKey:kSCIIgMobileDeprecatedCatalogKeys];
    if (![keys isKindOfClass:NSArray.class]) keys = @[];

    @synchronized (SCIIgMobileCatalogLock()) {
        SCIIgMobileMemoryCache()[@"keys"] = keys;
    }
    return keys;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *SCIIgMobileStoredTokenIndex(void) {
    @synchronized (SCIIgMobileCatalogLock()) {
        NSDictionary *mem = SCIIgMobileMemoryCache()[@"tokenIndex"];
        if ([mem isKindOfClass:NSDictionary.class]) return mem;
    }

    NSDictionary *idx = SCIIgMobileTokenIndexForKeys(SCIIgMobileStoredKeys());
    @synchronized (SCIIgMobileCatalogLock()) {
        SCIIgMobileMemoryCache()[@"tokenIndex"] = idx;
    }
    return idx;
}

@implementation SCIIgMobileDeprecatedConfigCatalog

+ (NSDictionary *)importDeprecatedConfigValuesObject:(id)object source:(NSString *)source {
    NSDictionary *root = [object isKindOfClass:NSDictionary.class] ? (NSDictionary *)object : nil;
    NSDictionary *values = nil;

    if ([root[@"configValues"] isKindOfClass:NSDictionary.class]) values = root[@"configValues"];
    else if ([root[@"values"] isKindOfClass:NSDictionary.class]) values = root[@"values"];
    else values = root;

    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (id key in values.allKeys) {
        if ([key isKindOfClass:NSString.class] && [(NSString *)key length]) [keys addObject:(NSString *)key];
    }
    [keys sortUsingSelector:@selector(caseInsensitiveCompare:)];

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:keys forKey:kSCIIgMobileDeprecatedCatalogKeys];
    [d setObject:source ?: @"" forKey:kSCIIgMobileDeprecatedCatalogSource];
    [d setObject:SCIIgMobileISODate([NSDate date]) forKey:kSCIIgMobileDeprecatedCatalogImportedAt];
    [d setObject:@(keys.count) forKey:kSCIIgMobileDeprecatedCatalogCount];
    [d synchronize];

    @synchronized (SCIIgMobileCatalogLock()) {
        [SCIIgMobileMemoryCache() removeAllObjects];
        SCIIgMobileMemoryCache()[@"keys"] = [keys copy];
        SCIIgMobileMemoryCache()[@"tokenIndex"] = SCIIgMobileTokenIndexForKeys(keys);
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SCIIgMobileDeprecatedConfigCatalogDidUpdateNotification object:nil];

    return @{
        @"ok": @(keys.count > 0),
        @"count": @(keys.count),
        @"source": source ?: @"",
        @"status": [NSString stringWithFormat:@"igmobile deprecated catalog imported · keys=%lu", (unsigned long)keys.count]
    };
}

+ (NSDictionary *)importDeprecatedConfigValuesFileAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path ?: @"" options:0 error:nil];
    if (!data.length) return @{@"ok": @NO, @"count": @0, @"source": path ?: @"", @"status": @"igmobile deprecated catalog import failed: file not readable"};

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!json) return @{@"ok": @NO, @"count": @0, @"source": path ?: @"", @"status": @"igmobile deprecated catalog import failed: invalid json"};

    return [self importDeprecatedConfigValuesObject:json source:path ?: @""];
}

+ (NSUInteger)configCount {
    NSNumber *stored = [NSUserDefaults.standardUserDefaults objectForKey:kSCIIgMobileDeprecatedCatalogCount];
    if ([stored respondsToSelector:@selector(unsignedIntegerValue)]) return stored.unsignedIntegerValue;
    return SCIIgMobileStoredKeys().count;
}

+ (NSArray<NSString *> *)allKeys {
    return SCIIgMobileStoredKeys();
}

+ (NSString *)summaryLine {
    NSUInteger count = [self configCount];
    if (!count) return nil;
    NSString *source = [NSUserDefaults.standardUserDefaults stringForKey:kSCIIgMobileDeprecatedCatalogSource] ?: @"";
    NSString *date = [NSUserDefaults.standardUserDefaults stringForKey:kSCIIgMobileDeprecatedCatalogImportedAt] ?: @"";
    return [NSString stringWithFormat:@"igmobile deprecated catalog · keys=%lu%@%@",
            (unsigned long)count,
            source.length ? [NSString stringWithFormat:@" · source=%@", source.lastPathComponent] : @"",
            date.length ? [NSString stringWithFormat:@" · imported=%@", date] : @""];
}

+ (NSArray<SCIIgMobileDeprecatedConfigMatch *> *)matchesForClassName:(NSString *)className
                                                        selectorName:(NSString *)selectorName
                                                          ownerGroup:(NSString *)ownerGroup
                                                           familyKey:(NSString *)familyKey
                                                    semanticCategory:(NSString *)semanticCategory
                                                               limit:(NSUInteger)limit {
    if (![self configCount]) return @[];

    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%lu", className ?: @"", selectorName ?: @"", ownerGroup ?: @"", familyKey ?: @"", semanticCategory ?: @"", (unsigned long)limit];
    @synchronized (SCIIgMobileCatalogLock()) {
        NSDictionary *mc = SCIIgMobileMemoryCache()[@"matchCache"];
        NSArray *cached = [mc isKindOfClass:NSDictionary.class] ? mc[cacheKey] : nil;
        if (cached) return cached;
    }

    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@", className ?: @"", selectorName ?: @"", ownerGroup ?: @"", familyKey ?: @"", semanticCategory ?: @""];
    NSString *lowerHay = hay.lowercaseString ?: @"";
    NSMutableOrderedSet<NSString *> *queryTokens = [NSMutableOrderedSet orderedSet];

    for (NSString *t in SCIIgMobileTokenize(hay)) [queryTokens addObject:t];
    for (NSString *t in SCIIgMobileFeatureTokens()) if ([lowerHay containsString:t]) [queryTokens addObject:t];
    if (!queryTokens.count) return @[];

    NSDictionary<NSString *, NSArray<NSString *> *> *idx = SCIIgMobileStoredTokenIndex();
    NSMutableDictionary<NSString *, NSNumber *> *scores = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *matched = [NSMutableDictionary dictionary];

    for (NSString *token in queryTokens.array) {
        NSArray<NSString *> *candidateKeys = idx[token] ?: @[];
        for (NSString *key in candidateKeys) {
            NSInteger add = [SCIIgMobileFeatureTokens() containsObject:token] ? 35 : 10;
            if (selectorName.length && [key.lowercaseString containsString:selectorName.lowercaseString]) add += 30;
            scores[key] = @(scores[key].integerValue + add);
            NSMutableArray *arr = matched[key];
            if (!arr) {
                arr = [NSMutableArray array];
                matched[key] = arr;
            }
            if (![arr containsObject:token]) [arr addObject:token];
        }
    }

    NSMutableArray<SCIIgMobileDeprecatedConfigMatch *> *matches = [NSMutableArray array];
    for (NSString *key in scores) {
        NSInteger score = scores[key].integerValue;
        if (score <= 0) continue;
        NSArray<NSString *> *parts = [key componentsSeparatedByString:@"."];
        SCIIgMobileDeprecatedConfigMatch *m = [SCIIgMobileDeprecatedConfigMatch new];
        m.name = key;
        m.group = parts.count ? parts.firstObject : @"";
        m.param = parts.count > 1 ? [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"."] : @"";
        m.score = score;
        m.evidence = [NSString stringWithFormat:@"igmobile-deprecated catalog · group=%@ · tokens=%@ · score=%ld", m.group ?: @"", [matched[key] componentsJoinedByString:@","], (long)score];
        [matches addObject:m];
    }

    [matches sortUsingComparator:^NSComparisonResult(SCIIgMobileDeprecatedConfigMatch *a, SCIIgMobileDeprecatedConfigMatch *b) {
        if (a.score != b.score) return a.score > b.score ? NSOrderedAscending : NSOrderedDescending;
        return [a.name caseInsensitiveCompare:b.name];
    }];

    if (limit && matches.count > limit) matches = [[matches subarrayWithRange:NSMakeRange(0, limit)] mutableCopy];
    NSArray *result = matches ?: @[];
    @synchronized (SCIIgMobileCatalogLock()) {
        NSMutableDictionary *mc = SCIIgMobileMemoryCache()[@"matchCache"];
        if (![mc isKindOfClass:NSMutableDictionary.class]) {
            mc = [NSMutableDictionary dictionary];
            SCIIgMobileMemoryCache()[@"matchCache"] = mc;
        }
        mc[cacheKey] = result;
    }
    return result;
}

+ (SCIIgMobileDeprecatedConfigMatch *)bestMatchForClassName:(NSString *)className
                                                selectorName:(NSString *)selectorName
                                                  ownerGroup:(NSString *)ownerGroup
                                                   familyKey:(NSString *)familyKey
                                            semanticCategory:(NSString *)semanticCategory {
    return [self matchesForClassName:className selectorName:selectorName ownerGroup:ownerGroup familyKey:familyKey semanticCategory:semanticCategory limit:1].firstObject;
}

@end
