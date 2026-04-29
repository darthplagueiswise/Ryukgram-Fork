#import "SCIPersistedQueryCatalog.h"

extern NSData *SCIEmbeddedMobileConfigSchemaData(void);
extern NSString *SCIEmbeddedMobileConfigSchemaName(void);

@implementation SCIPersistedQueryEntry

- (NSString *)summaryLine {
    return [NSString stringWithFormat:@"%@ · doc=%@ · nameHash=%@ · textHash=%@ · schema=%@ · %@",
            self.operationName ?: @"?",
            self.clientDocID ?: @"",
            self.operationNameHash ?: @"",
            self.operationTextHash ?: @"",
            self.schema ?: @"",
            self.category ?: @"Other"];
}

@end

static NSArray<NSString *> *SCIPQQuickSnapPriorityNames(void) {
    return @[
        @"IGQuickSnapGetQuickSnapsQuery",
        @"IGQuickSnapGetHistoryQuery",
        @"IGQuickSnapGetHistoryPaginatedQuery",
        @"IGQuickSnapGetPromptsQuery",
        @"IGQuickSnapBadgingInfoQuery",
        @"IGQuickSnapUpdateBadgingStateMutation",
        @"IGQuickSnapUpdateSeenStateMutation",
        @"IGQuickSnapSendEmojiReactionMutation",
        @"MSHGetQuickSnapsQuery",
        @"MSHQuickSnapGetHistoryQuery"
    ];
}

static NSArray<NSString *> *SCIPQDogfoodPriorityNames(void) {
    return @[
        @"DogfoodingEligibilityQuery",
        @"ExposeExperimentFromClientQuery",
        @"HasOptedIntoHomecomingFlagOnUserQuery",
        @"IGHomecomingOptInStatusMutation"
    ];
}

static NSString *SCIPQTrim(id obj) {
    if (!obj || obj == (id)kCFNull) return @"";
    NSString *s = [obj isKindOfClass:NSString.class] ? obj : ([obj respondsToSelector:@selector(description)] ? [obj description] : @"");
    return [[s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
}

static BOOL SCIPQContainsAny(NSString *lower, NSArray<NSString *> *tokens) {
    if (!lower.length) return NO;
    for (NSString *token in tokens) {
        if (token.length && [lower containsString:token]) return YES;
    }
    return NO;
}

static NSString *SCIPQCategoryForOperation(NSString *operationName) {
    NSString *l = operationName.lowercaseString ?: @"";

    if (SCIPQContainsAny(l, @[@"quicksnap", @"quick_snap", @"instant"])) return @"Direct / QuickSnap";
    if (SCIPQContainsAny(l, @[@"dogfood", @"exposeexperiment", @"homecoming", @"internal", @"employee"])) return @"Experimentos / Dogfood / Internal";
    if (SCIPQContainsAny(l, @[@"friendmap", @"friendsmap", @"friend_map", @"location", @"livelo", @"map"])) return @"Friend Map / Localização";
    if (SCIPQContainsAny(l, @[@"directnotes", @"note", @"notestray", @"notes"])) return @"Direct / Notes";
    if (SCIPQContainsAny(l, @[@"direct", @"inbox", @"thread", @"message", @"messaging", @"msh"])) return @"Direct / Mensagens";
    if (SCIPQContainsAny(l, @[@"genai", @"ai", @"avatar", @"character", @"imagine", @"llama"])) return @"AI / GenAI / Characters";
    if (SCIPQContainsAny(l, @[@"reel", @"clips", @"audio", @"video", @"music"])) return @"Reels / Clips / Áudio-Vídeo";
    if (SCIPQContainsAny(l, @[@"feed", @"explore", @"search", @"ranking", @"discover", @"recommend"])) return @"Feed / Explore / Discovery";
    if (SCIPQContainsAny(l, @[@"story", @"stories", @"reelstray"])) return @"Stories";
    if (SCIPQContainsAny(l, @[@"profile", @"account", @"identity", @"user", @"following", @"follower"])) return @"Perfil / Conta / Identidade";
    if (SCIPQContainsAny(l, @[@"creator", @"business", @"professional", @"monetization", @"insights"])) return @"Creator / Business / Monetização";
    if (SCIPQContainsAny(l, @[@"payment", @"pay", @"autofill", @"checkout", @"commerce", @"shop", @"order"])) return @"Payments / Commerce / Autofill";
    if (SCIPQContainsAny(l, @[@"threadsbcn", @"barcelona", @"textapp", @"bcn"])) return @"Threads / Barcelona";
    if (SCIPQContainsAny(l, @[@"bloks", @"ui", @"surface", @"launcher", @"navigation", @"tab", @"prism"])) return @"UI / Bloks / Superfícies";
    if (SCIPQContainsAny(l, @[@"privacy", @"safety", @"integrity", @"report", @"block", @"restrict", @"spam"])) return @"Safety / Privacy / Integrity";
    return @"Other";
}

static NSString *SCIPQSurfaceForOperation(NSString *operationName) {
    NSString *category = SCIPQCategoryForOperation(operationName);
    if ([category isEqualToString:@"Direct / QuickSnap"]) return @"QuickSnap / Instants GraphQL surface";
    if ([category isEqualToString:@"Experimentos / Dogfood / Internal"]) return @"Dogfood/Internal GraphQL surface";
    return category;
}

static dispatch_queue_t SCIPQQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("sci.persisted_query_catalog", DISPATCH_QUEUE_CONCURRENT);
    });
    return q;
}

static BOOL gSCIPQLoaded = NO;
static BOOL gSCIPQLoading = NO;
static NSArray<SCIPersistedQueryEntry *> *gSCIPQEntries = nil;
static NSDictionary<NSString *, SCIPersistedQueryEntry *> *gSCIPQByOperation = nil;
static NSDictionary<NSString *, SCIPersistedQueryEntry *> *gSCIPQByDocID = nil;
static NSDictionary<NSString *, NSArray<SCIPersistedQueryEntry *> *> *gSCIPQByCategory = nil;
static NSString *gSCIPQSource = nil;
static NSString *gSCIPQError = nil;

@implementation SCIPersistedQueryCatalog

+ (instancetype)sharedCatalog {
    static SCIPersistedQueryCatalog *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = [SCIPersistedQueryCatalog new]; });
    return catalog;
}

+ (void)prewarmInBackground {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [[SCIPersistedQueryCatalog sharedCatalog] allEntries];
        });
    });
}

- (BOOL)isLoaded {
    __block BOOL loaded = NO;
    dispatch_sync(SCIPQQueue(), ^{ loaded = gSCIPQLoaded; });
    return loaded;
}

- (void)reload {
    dispatch_barrier_sync(SCIPQQueue(), ^{
        gSCIPQLoaded = NO;
        gSCIPQLoading = NO;
        gSCIPQEntries = nil;
        gSCIPQByOperation = nil;
        gSCIPQByDocID = nil;
        gSCIPQByCategory = nil;
        gSCIPQSource = nil;
        gSCIPQError = nil;
    });
    [self loadIfNeededSynchronously:YES];
}

- (NSArray<NSString *> *)candidateJSONPaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSBundle *main = NSBundle.mainBundle;

    NSString *resource = [main pathForResource:@"igios-instagram-schema_client-persist" ofType:@"json"];
    if (resource.length) [paths addObject:resource];

    NSString *bundleResource = [[main bundlePath] stringByAppendingPathComponent:@"igios-instagram-schema_client-persist.json"];
    if (bundleResource.length) [paths addObject:bundleResource];

    NSString *frameworksPath = main.privateFrameworksPath;
    if (frameworksPath.length) {
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"FBSharedFramework.framework/igios-instagram-schema_client-persist.json"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"FBSharedFramework.framework/igios-facebook-schema_client-persist.json"]];
        [paths addObject:[frameworksPath stringByAppendingPathComponent:@"FBSharedModules.framework/igios-instagram-schema_client-persist.json"]];
    }

    return paths;
}

- (NSData *)schemaDataWithSource:(NSString **)sourceOut {
    NSData *embedded = SCIEmbeddedMobileConfigSchemaData();
    NSString *embeddedName = SCIEmbeddedMobileConfigSchemaName();
    if (embedded.length) {
        if (sourceOut) *sourceOut = [NSString stringWithFormat:@"embedded:%@", embeddedName ?: @"igios-instagram-schema_client-persist.json"];
        return embedded;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in [self candidateJSONPaths]) {
        if (![fm fileExistsAtPath:path]) continue;
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (data.length) {
            if (sourceOut) *sourceOut = [@"file:" stringByAppendingString:path];
            return data;
        }
    }

    if (sourceOut) *sourceOut = @"missing embedded/resource/app-framework JSON";
    return nil;
}

- (SCIPersistedQueryEntry *)entryFromKey:(NSString *)key value:(id)value {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *d = (NSDictionary *)value;

    NSString *opName = SCIPQTrim(d[@"operation_name"]);
    if (!opName.length) opName = SCIPQTrim(key);
    if (!opName.length) return nil;

    SCIPersistedQueryEntry *e = [SCIPersistedQueryEntry new];
    e.operationName = opName;
    e.operationNameHash = SCIPQTrim(d[@"operation_name_hash"]);
    e.operationTextHash = SCIPQTrim(d[@"operation_text_hash"]);
    e.clientDocID = SCIPQTrim(d[@"client_doc_id"]);
    e.schema = SCIPQTrim(d[@"schema"]);
    e.rawKey = SCIPQTrim(key);
    e.category = SCIPQCategoryForOperation(opName);
    e.surface = SCIPQSurfaceForOperation(opName);
    return e;
}

- (void)loadIfNeededSynchronously:(BOOL)synchronous {
    __block BOOL shouldStart = NO;
    dispatch_barrier_sync(SCIPQQueue(), ^{
        if (!gSCIPQLoaded && !gSCIPQLoading) {
            gSCIPQLoading = YES;
            shouldStart = YES;
        }
    });

    if (!shouldStart) {
        if (!synchronous) return;
        while (![self isLoaded]) {
            [NSThread sleepForTimeInterval:0.01];
        }
        return;
    }

    void (^work)(void) = ^{
        NSString *source = nil;
        NSData *data = [self schemaDataWithSource:&source];
        NSError *error = nil;
        id obj = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;

        NSMutableArray<SCIPersistedQueryEntry *> *entries = [NSMutableArray array];
        NSMutableDictionary<NSString *, SCIPersistedQueryEntry *> *byOperation = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, SCIPersistedQueryEntry *> *byDocID = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSMutableArray<SCIPersistedQueryEntry *> *> *byCategory = [NSMutableDictionary dictionary];

        if ([obj isKindOfClass:NSDictionary.class]) {
            NSDictionary *root = (NSDictionary *)obj;
            for (NSString *key in root) {
                SCIPersistedQueryEntry *entry = [self entryFromKey:key value:root[key]];
                if (!entry) continue;
                [entries addObject:entry];
                byOperation[entry.operationName] = entry;
                if (entry.clientDocID.length) byDocID[entry.clientDocID] = entry;
                NSMutableArray *bucket = byCategory[entry.category] ?: [NSMutableArray array];
                [bucket addObject:entry];
                byCategory[entry.category] = bucket;
            }
        }

        [entries sortUsingComparator:^NSComparisonResult(SCIPersistedQueryEntry *a, SCIPersistedQueryEntry *b) {
            NSComparisonResult c = [a.category caseInsensitiveCompare:b.category];
            if (c != NSOrderedSame) return c;
            return [a.operationName caseInsensitiveCompare:b.operationName];
        }];

        NSMutableDictionary *frozenByCategory = [NSMutableDictionary dictionary];
        for (NSString *category in byCategory) {
            NSArray *sorted = [byCategory[category] sortedArrayUsingComparator:^NSComparisonResult(SCIPersistedQueryEntry *a, SCIPersistedQueryEntry *b) {
                return [a.operationName caseInsensitiveCompare:b.operationName];
            }];
            frozenByCategory[category] = sorted;
        }

        NSString *loadError = nil;
        if (!data.length) loadError = @"Persisted query JSON not found. Embed resources/igios-instagram-schema_client-persist.json or keep it inside FBSharedFramework.framework.";
        else if (error) loadError = error.localizedDescription ?: @"JSON parse error";
        else if (![obj isKindOfClass:NSDictionary.class]) loadError = @"Persisted query JSON root is not a dictionary.";

        dispatch_barrier_sync(SCIPQQueue(), ^{
            gSCIPQEntries = [entries copy] ?: @[];
            gSCIPQByOperation = [byOperation copy] ?: @{};
            gSCIPQByDocID = [byDocID copy] ?: @{};
            gSCIPQByCategory = [frozenByCategory copy] ?: @{};
            gSCIPQSource = source ?: @"unknown";
            gSCIPQError = loadError;
            gSCIPQLoaded = YES;
            gSCIPQLoading = NO;
        });

        NSLog(@"[RyukGram][PersistedQueries] loaded=%lu source=%@ error=%@",
              (unsigned long)entries.count,
              source ?: @"unknown",
              loadError ?: @"none");
    };

    if (synchronous) work();
    else dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), work);
}

- (NSArray<SCIPersistedQueryEntry *> *)allEntries {
    [self loadIfNeededSynchronously:YES];
    __block NSArray *entries = nil;
    dispatch_sync(SCIPQQueue(), ^{ entries = gSCIPQEntries ?: @[]; });
    return entries;
}

- (NSString *)sourceDescription {
    [self loadIfNeededSynchronously:YES];
    __block NSString *desc = nil;
    dispatch_sync(SCIPQQueue(), ^{
        desc = [NSString stringWithFormat:@"%@ · entries=%lu%@%@",
                gSCIPQSource ?: @"unknown",
                (unsigned long)(gSCIPQEntries.count),
                gSCIPQError.length ? @" · error=" : @"",
                gSCIPQError ?: @""];
    });
    return desc ?: @"unknown";
}

- (NSArray<NSString *> *)allCategories {
    [self loadIfNeededSynchronously:YES];
    __block NSArray *cats = nil;
    dispatch_sync(SCIPQQueue(), ^{ cats = [[gSCIPQByCategory allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]; });
    return cats ?: @[];
}

- (NSArray<SCIPersistedQueryEntry *> *)entriesForCategory:(NSString *)category {
    [self loadIfNeededSynchronously:YES];
    if (!category.length) return [self allEntries];
    __block NSArray *entries = nil;
    dispatch_sync(SCIPQQueue(), ^{ entries = gSCIPQByCategory[category] ?: @[]; });
    return entries ?: @[];
}

- (NSArray<SCIPersistedQueryEntry *> *)entriesMatchingQuery:(NSString *)query category:(NSString *)category limit:(NSUInteger)limit {
    NSArray<SCIPersistedQueryEntry *> *source = category.length ? [self entriesForCategory:category] : [self allEntries];
    NSString *q = query.lowercaseString ?: @"";
    NSMutableArray *out = [NSMutableArray array];
    for (SCIPersistedQueryEntry *e in source) {
        if (q.length) {
            NSString *joined = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@",
                                 e.operationName ?: @"",
                                 e.clientDocID ?: @"",
                                 e.operationNameHash ?: @"",
                                 e.operationTextHash ?: @"",
                                 e.schema ?: @"",
                                 e.category ?: @""] lowercaseString];
            if (![joined containsString:q]) continue;
        }
        [out addObject:e];
        if (limit && out.count >= limit) break;
    }
    return out;
}

- (SCIPersistedQueryEntry *)entryForOperationName:(NSString *)operationName {
    if (!operationName.length) return nil;
    if (![self isLoaded]) {
        [SCIPersistedQueryCatalog prewarmInBackground];
        return nil;
    }
    __block SCIPersistedQueryEntry *entry = nil;
    dispatch_sync(SCIPQQueue(), ^{ entry = gSCIPQByOperation[operationName]; });
    return entry;
}

- (SCIPersistedQueryEntry *)entryForClientDocID:(NSString *)clientDocID {
    if (!clientDocID.length) return nil;
    if (![self isLoaded]) {
        [SCIPersistedQueryCatalog prewarmInBackground];
        return nil;
    }
    __block SCIPersistedQueryEntry *entry = nil;
    dispatch_sync(SCIPQQueue(), ^{ entry = gSCIPQByDocID[clientDocID]; });
    return entry;
}

- (NSArray<SCIPersistedQueryEntry *> *)entriesForPriorityNames:(NSArray<NSString *> *)names {
    [self loadIfNeededSynchronously:YES];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in names) {
        __block SCIPersistedQueryEntry *entry = nil;
        dispatch_sync(SCIPQQueue(), ^{ entry = gSCIPQByOperation[name]; });
        if (entry) [out addObject:entry];
    }
    return out;
}

- (NSArray<SCIPersistedQueryEntry *> *)priorityQuickSnapEntries {
    return [self entriesForPriorityNames:SCIPQQuickSnapPriorityNames()];
}

- (NSArray<SCIPersistedQueryEntry *> *)priorityDogfoodEntries {
    return [self entriesForPriorityNames:SCIPQDogfoodPriorityNames()];
}

- (NSString *)diagnosticReport {
    [self loadIfNeededSynchronously:YES];
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Persisted GraphQL Query Catalog\n%@\n\n", [self sourceDescription]];

    [out appendString:@"Categories\n"];
    for (NSString *category in [self allCategories]) {
        [out appendFormat:@"  %@: %lu\n", category, (unsigned long)[self entriesForCategory:category].count];
    }

    [out appendString:@"\nQuickSnap priority operations\n"];
    for (NSString *name in SCIPQQuickSnapPriorityNames()) {
        SCIPersistedQueryEntry *e = [self entryForOperationName:name];
        [out appendFormat:@"  %@ %@\n", e ? @"FOUND" : @"missing", e ? [e summaryLine] : name];
    }

    [out appendString:@"\nDogfood/Internal priority operations\n"];
    for (NSString *name in SCIPQDogfoodPriorityNames()) {
        SCIPersistedQueryEntry *e = [self entryForOperationName:name];
        [out appendFormat:@"  %@ %@\n", e ? @"FOUND" : @"missing", e ? [e summaryLine] : name];
    }

    return out;
}

@end
