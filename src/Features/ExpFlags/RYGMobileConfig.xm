#import "RYGMobileConfig.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Security/RYGSecureBlob.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <pthread.h>
#import <execinfo.h>
#import <string>
#import <unordered_map>

// MobileConfig engine: enumerate every param from IG's in-memory table, name them
// from the bundled catalog, read live values, and write overrides through IG's own
// C++ overrides table.

struct RYGSharedPtr { void *ptr; void *ctrl; ~RYGSharedPtr(); };
RYGSharedPtr::~RYGSharedPtr() {}

static __weak id gManager;
static NSMutableDictionary<NSNumber *, id> *gManagersByUnit;      // (pid>>48 & 0xF0) -> manager
static NSMutableDictionary<NSNumber *, NSValue *> *gCallSites;
static NSMutableDictionary<NSNumber *, id> *gOverrideValues;      // pid -> value (all types), the force table
static NSMutableDictionary<NSNumber *, NSNumber *> *gRealPidByOrdIdx;  // (ordinal<<20|idx) -> real pid
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;

static void *rygSym(const char *n) { return dlsym(RTLD_DEFAULT, n); }

static id rygOverrideValue(unsigned long long pid) {
    pthread_mutex_lock(&gLock);
    id v = gOverrideValues ? gOverrideValues[@(pid)] : nil;
    pthread_mutex_unlock(&gLock);
    return v;
}

// The two unit variants (sessionless 0x40, session-based 0x80) of a param share
// ordinal/index/serial and differ only in the unit byte, and reconstruction can't
// tell which one IG actually reads. So key storage by the sessionless form and
// force/write BOTH variants — whichever IG reads is covered.
static unsigned long long rygCanonicalPid(unsigned long long pid) {
    unsigned long long type = (pid >> 48) & 0x0F;
    return (pid & 0x0000FFFFFFFFFFFFULL) | ((0x40ULL | type) << 48);
}
static unsigned long long rygVariantPid(unsigned long long pid, unsigned long long base) {
    unsigned long long type = (pid >> 48) & 0x0F;
    return (pid & 0x0000FFFFFFFFFFFFULL) | ((base | type) << 48);
}
static void rygSetForce(unsigned long long pid, id value) {
    pthread_mutex_lock(&gLock);
    if (!gOverrideValues) gOverrideValues = [NSMutableDictionary new];
    gOverrideValues[@(rygVariantPid(pid, 0x40))] = value;
    gOverrideValues[@(rygVariantPid(pid, 0x80))] = value;
    pthread_mutex_unlock(&gLock);
}
static void rygClearForce(unsigned long long pid) {
    pthread_mutex_lock(&gLock);
    [gOverrideValues removeObjectForKey:@(rygVariantPid(pid, 0x40))];
    [gOverrideValues removeObjectForKey:@(rygVariantPid(pid, 0x80))];
    pthread_mutex_unlock(&gLock);
}

static id rygCoerce(id value, RYGMCType type) {
    if (!value) return nil;
    switch (type) {
        case RYGMCTypeBool:   return [value respondsToSelector:@selector(boolValue)] ? @([value boolValue]) : nil;
        case RYGMCTypeInt:    return [value respondsToSelector:@selector(longLongValue)] ? @([value longLongValue]) : nil;
        case RYGMCTypeDouble: return [value respondsToSelector:@selector(doubleValue)] ? @([value doubleValue]) : nil;
        case RYGMCTypeString: return [value isKindOfClass:[NSString class]] ? value : [value description];
    }
    return nil;
}

static void rygCaptureManager(id mgr, unsigned long long pid) {
    gManager = mgr;
    unsigned long long unit = (pid >> 48) & 0xF0;
    unsigned int ordinal = (pid >> 32) & 0xFFFF;
    unsigned int idx = (pid >> 16) & 0xFFFF;
    pthread_mutex_lock(&gLock);
    if (!gManagersByUnit) gManagersByUnit = [NSMutableDictionary new];
    if (!gRealPidByOrdIdx) gRealPidByOrdIdx = [NSMutableDictionary new];
    gManagersByUnit[@(unit)] = mgr;
    gRealPidByOrdIdx[@(((unsigned long long)ordinal << 20) | idx)] = @(pid);
    pthread_mutex_unlock(&gLock);
}

#pragma mark - live-value + manager-capture hooks

static void rygRecordCaller(unsigned long long pid) {
    void *frames[6];
    int n = backtrace(frames, 6);
    pthread_mutex_lock(&gLock);
    if (!gCallSites) gCallSites = [NSMutableDictionary new];
    NSNumber *k = @(pid);
    if (!gCallSites[k] && n > 3) {
        void *f = frames[3];
        gCallSites[k] = [NSValue valueWithPointer:f];
    }
    pthread_mutex_unlock(&gLock);
}

static BOOL (*orig_getBool)(id, SEL, unsigned long long);
static BOOL new_getBool(id self, SEL _cmd, unsigned long long pid) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v boolValue];
    return orig_getBool(self, _cmd, pid);
}
static BOOL (*orig_getBoolDef)(id, SEL, unsigned long long, BOOL);
static BOOL new_getBoolDef(id self, SEL _cmd, unsigned long long pid, BOOL def) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v boolValue];
    return orig_getBoolDef(self, _cmd, pid, def);
}
static BOOL (*orig_getBoolOpts)(id, SEL, unsigned long long, id);
static BOOL new_getBoolOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if (v) return [v boolValue];
    return orig_getBoolOpts(self, _cmd, pid, opts);
}
static BOOL (*orig_getBoolOptsDef)(id, SEL, unsigned long long, id, BOOL);
static BOOL new_getBoolOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, BOOL def) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if (v) return [v boolValue];
    return orig_getBoolOptsDef(self, _cmd, pid, opts, def);
}
static long long (*orig_getInt)(id, SEL, unsigned long long);
static long long new_getInt(id self, SEL _cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getInt(self, _cmd, pid);
}
static long long (*orig_getIntDef)(id, SEL, unsigned long long, long long);
static long long new_getIntDef(id self, SEL _cmd, unsigned long long pid, long long def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getIntDef(self, _cmd, pid, def);
}
static long long (*orig_getIntOpts)(id, SEL, unsigned long long, id);
static long long new_getIntOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getIntOpts(self, _cmd, pid, opts);
}
static long long (*orig_getIntOptsDef)(id, SEL, unsigned long long, id, long long);
static long long new_getIntOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, long long def) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getIntOptsDef(self, _cmd, pid, opts, def);
}
static double (*orig_getDouble)(id, SEL, unsigned long long);
static double new_getDouble(id self, SEL _cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDouble(self, _cmd, pid);
}
static double (*orig_getDoubleDef)(id, SEL, unsigned long long, double);
static double new_getDoubleDef(id self, SEL _cmd, unsigned long long pid, double def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDoubleDef(self, _cmd, pid, def);
}
static double (*orig_getDoubleOpts)(id, SEL, unsigned long long, id);
static double new_getDoubleOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDoubleOpts(self, _cmd, pid, opts);
}
static double (*orig_getDoubleOptsDef)(id, SEL, unsigned long long, id, double);
static double new_getDoubleOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, double def) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDoubleOptsDef(self, _cmd, pid, opts, def);
}
static id (*orig_getString)(id, SEL, unsigned long long);
static id new_getString(id self, SEL _cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getString(self, _cmd, pid);
}
static id (*orig_getStringDef)(id, SEL, unsigned long long, id);
static id new_getStringDef(id self, SEL _cmd, unsigned long long pid, id def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getStringDef(self, _cmd, pid, def);
}
static id (*orig_getStringOpts)(id, SEL, unsigned long long, id);
static id new_getStringOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getStringOpts(self, _cmd, pid, opts);
}
static id (*orig_getStringOptsDef)(id, SEL, unsigned long long, id, id);
static id new_getStringOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, id def) {
    rygCaptureManager(self, pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getStringOptsDef(self, _cmd, pid, opts, def);
}

#pragma mark - model

static NSString *rygNormalize(NSString *s);

@interface RYGMCParam ()
@property (nonatomic, copy) NSString *cachedNormalizedName;
@end

@interface RYGMCConfig ()
@property (nonatomic, copy) NSString *cachedNormalizedName;
@property (nonatomic, copy) NSString *cachedDisplayName;
@end

@implementation RYGMCParam
- (NSString *)typeName {
    switch (self.type) {
        case RYGMCTypeBool:   return @"bool";
        case RYGMCTypeInt:    return @"int";
        case RYGMCTypeDouble: return @"double";
        case RYGMCTypeString: return @"string";
    }
    return @"?";
}
- (NSString *)normalizedName {
    if (!_cachedNormalizedName) _cachedNormalizedName = rygNormalize(self.name);
    return _cachedNormalizedName;
}
@end

@implementation RYGMCConfig
- (NSString *)displayName {
    if (!_cachedDisplayName)
        _cachedDisplayName = self.name.length ? self.name : [NSString stringWithFormat:@"config %u", self.number];
    return _cachedDisplayName;
}
- (NSString *)normalizedName {
    if (!_cachedNormalizedName) _cachedNormalizedName = rygNormalize(self.name);
    return _cachedNormalizedName;
}
@end

#pragma mark - engine

@interface RYGMobileConfig ()
- (NSString *)mcDirectory;
- (BOOL)applyOverride:(id)value pid:(unsigned long long)pid type:(RYGMCType)type;
- (void)migrateLegacyStore;
- (void)reloadFromDisk;
- (void)resetAllNotes;
- (void)mergeStoreAtPath:(NSString *)dir;
- (RYGMCParam *)paramForConfigNumber:(unsigned int)number paramIndex:(unsigned int)paramIndex;
@end

@implementation RYGMobileConfig {
    NSArray<RYGMCConfig *> *_configs;
    NSMutableDictionary<NSNumber *, id> *_overrides;
    NSMutableDictionary<NSNumber *, NSString *> *_notes;
    BOOL _ready;
    int (*_typeFromParam)(unsigned long long);
}

+ (instancetype)shared {
    static RYGMobileConfig *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [RYGMobileConfig new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self migrateLegacyStore];
        _overrides = [self loadOverrides];
        _notes = [self loadNotes];
        _typeFromParam = (int (*)(unsigned long long))rygSym("_ZN12mobileconfig17typeFromParameterEy");
        for (NSNumber *k in _overrides) rygSetForce(k.unsignedLongLongValue, _overrides[k]);
    }
    return self;
}

- (BOOL)ready { return _ready; }

#pragma mark names catalog

- (NSDictionary *)loadNameCatalog {
    NSData *data = [RYGSecureBlob decryptBundleResource:@"ryg_mc_names" ofType:@"bin"];
    if (!data.length) return @{};
    const uint8_t *b = (const uint8_t *)data.bytes;
    size_t len = data.length, off = 0;
    #define RD(T) ({ if (off + sizeof(T) > len) return cat; T _v; memcpy(&_v, b + off, sizeof(T)); off += sizeof(T); _v; })
    NSMutableDictionary *cat = [NSMutableDictionary dictionary];
    uint32_t nconfigs = RD(uint32_t);
    for (uint32_t i = 0; i < nconfigs; i++) {
        uint32_t cn = RD(uint32_t);
        uint16_t nl = RD(uint16_t);
        if (off + nl > len) break;
        NSString *cname = [[NSString alloc] initWithBytes:b + off length:nl encoding:NSUTF8StringEncoding];
        off += nl;
        uint16_t pc = RD(uint16_t);
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        for (uint16_t j = 0; j < pc; j++) {
            uint16_t idx = RD(uint16_t);
            uint16_t pl = RD(uint16_t);
            if (off + pl > len) break;
            NSString *pn = [[NSString alloc] initWithBytes:b + off length:pl encoding:NSUTF8StringEncoding];
            off += pl;
            if (pn) params[@(idx)] = pn;
        }
        if (cname) cat[@(cn)] = @{@"name": cname, @"params": [params mutableCopy]};
    }
    #undef RD
    [self mergeDiskNamesInto:cat];
    return cat;
}

// Overlay any names IG has on disk (id_name_mapping.json, or id_to_names in the
// sync-response dumps) onto the bundled catalog. Both use the colon form
// "<configNum>:<configName>:<idx>:<param>:…".
- (NSString *)mcDirectory {
    id mgr = gManager;
    if (!mgr || ![mgr respondsToSelector:@selector(getOverridesTablePath)]) return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(mgr, @selector(getOverridesTablePath));
    NSString *base = [v isKindOfClass:[NSURL class]] ? [(NSURL *)v path] : [v description];
    if ([base hasPrefix:@"file://"]) base = [[NSURL URLWithString:base] path];
    return base.length ? [base stringByDeletingLastPathComponent] : nil;
}

- (void)mergeDiskNamesInto:(NSMutableDictionary *)cat {
    NSString *mcdir = [self mcDirectory];
    if (!mcdir) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *sub in @[@"", @"sessionless.data"]) {
        NSString *d = sub.length ? [mcdir stringByAppendingPathComponent:sub] : mcdir;
        for (NSString *f in [fm contentsOfDirectoryAtPath:d error:nil]) {
            if ([f isEqualToString:@"id_name_mapping.json"] || [f hasPrefix:@"mc_sync_response_dump"])
                [files addObject:[d stringByAppendingPathComponent:f]];
        }
    }
    for (NSString *path in files) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data.length) continue;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *entries = nil;
        if ([json isKindOfClass:[NSArray class]]) entries = json;                 // id_name_mapping.json
        else if ([json isKindOfClass:[NSDictionary class]]) {
            id itn = json[@"id_to_names"];                                        // sync dump
            if ([itn isKindOfClass:[NSArray class]]) entries = itn;
            else if ([itn isKindOfClass:[NSString class]] && [(NSString *)itn length]) entries = @[itn];
        }
        for (id e in entries) {
            if (![e isKindOfClass:[NSString class]]) continue;
            NSArray *parts = [e componentsSeparatedByString:@":"];
            if (parts.count < 2) continue;
            unsigned int cn = (unsigned int)strtoul([parts[0] UTF8String], NULL, 10);
            if (!cn) continue;
            NSMutableDictionary *params = cat[@(cn)][@"params"] ? [cat[@(cn)][@"params"] mutableCopy] : [NSMutableDictionary dictionary];
            for (NSUInteger i = 2; i + 1 < parts.count; i += 2)
                params[@((unsigned int)strtoul([parts[i] UTF8String], NULL, 10))] = parts[i + 1];
            cat[@(cn)] = @{@"name": parts[1], @"params": params};
        }
    }
}

#pragma mark enumeration

- (const char *)paramsArrayStride:(size_t *)stride count:(size_t *)count {
    void *listSym = rygSym("_ZN12mobileconfig23kMobileConfigParamsListE");
    void *sizeSym = rygSym("_ZN12mobileconfig23kMobileConfigParamsSizeE");
    if (!listSym) return NULL;
    void **pp = (void **)listSym;
    const char *arr = NULL;
    for (int i = 0; i < 4 && !arr; i++)
        if (pp[i] > (void *)0x100000000ULL && pp[i] < (void *)0x800000000000ULL) arr = (const char *)pp[i];
    if (!arr) return NULL;
    void *first = *(void **)arr;
    size_t st = 0;
    for (size_t s = 16; s <= 128 && !st; s += 8)
        if (*(void **)(arr + s) == first && *(void **)(arr + s + 8) == first) st = s;
    if (stride) *stride = st;
    if (count) *count = sizeSym ? ((unsigned int *)sizeSym)[1] : 0;
    return arr;
}

- (unsigned long long)validParamIDForOrdinal:(unsigned int)ordinal
                                        index:(unsigned int)paramIndex
                                       serial:(unsigned int)serial
                                         type:(RYGMCType)type {
    for (unsigned long long base = 0x40; base <= 0x80; base += 0x40) {
        unsigned long long unit = base | type;
        unsigned long long pid = (unit << 48) | ((unsigned long long)ordinal << 32) |
                                 ((unsigned long long)paramIndex << 16) | serial;
        if (_typeFromParam && _typeFromParam(pid) == (int)type) return pid;
    }
    return 0;
}

- (void)prepare {
    if (_ready) return;
    NSDictionary *catalog = [self loadNameCatalog];

    size_t stride = 0, count = 0;
    const char *arr = [self paramsArrayStride:&stride count:&count];
    NSMutableDictionary<NSNumber *, NSMutableArray<RYGMCParam *> *> *byConfig = [NSMutableDictionary dictionary];

    if (arr && stride && count && _typeFromParam) {
        for (size_t i = 0; i < count; i++) {
            const char *row = arr + i * stride;
            unsigned int ordMix    = *(const unsigned int *)(row + 20);
            unsigned int typeSerial = *(const unsigned int *)(row + 24);
            unsigned int cfg        = *(const unsigned int *)(row + stride - 4);
            unsigned int ordinal    = ordMix & 0xFFFF;
            unsigned int paramIndex = *(const unsigned int *)(row + 16);
            unsigned int serial     = typeSerial & 0xFFFF;
            RYGMCType type          = (RYGMCType)(typeSerial >> 16);
            if (type < RYGMCTypeBool || type > RYGMCTypeString) continue;

            unsigned long long pid = [self validParamIDForOrdinal:ordinal index:paramIndex serial:serial type:type];
            if (!pid) continue;

            RYGMCParam *p = [RYGMCParam new];
            p.paramID = pid;
            p.ordinal = ordinal;
            p.configNumber = cfg;
            p.paramIndex = paramIndex;
            p.type = type;
            NSDictionary *cinfo = catalog[@(cfg)];
            p.name = cinfo[@"params"][@(paramIndex)];

            NSMutableArray *list = byConfig[@(cfg)];
            if (!list) { list = [NSMutableArray array]; byConfig[@(cfg)] = list; }
            [list addObject:p];
        }
    }

    NSMutableArray<RYGMCConfig *> *configs = [NSMutableArray array];
    for (NSNumber *cn in byConfig) {
        RYGMCConfig *c = [RYGMCConfig new];
        c.number = cn.unsignedIntValue;
        c.name = catalog[cn][@"name"];
        c.params = [byConfig[cn] sortedArrayUsingComparator:^NSComparisonResult(RYGMCParam *a, RYGMCParam *b) {
            return a.paramIndex < b.paramIndex ? NSOrderedAscending : NSOrderedDescending;
        }];
        [configs addObject:c];
    }
    [configs sortUsingComparator:^NSComparisonResult(RYGMCConfig *a, RYGMCConfig *b) {
        BOOL an = a.name.length > 0, bn = b.name.length > 0;
        if (an != bn) return an ? NSOrderedAscending : NSOrderedDescending;
        if (an) return [a.name caseInsensitiveCompare:b.name];
        return a.number < b.number ? NSOrderedAscending : NSOrderedDescending;
    }];

    _configs = configs;
    _namedConfigCount = catalog.count;
    _ready = YES;
}

- (NSArray<RYGMCConfig *> *)allConfigs { [self prepare]; return _configs ?: @[]; }

// Lowercase + strip non-alphanumerics so "core creation" matches "core_creation".
static NSString *rygNormalize(NSString *s) {
    if (!s.length) return @"";
    NSString *lower = s.lowercaseString;
    NSUInteger n = lower.length;
    unichar stackBuf[128];
    unichar *src = n <= 128 ? stackBuf : (unichar *)malloc(n * sizeof(unichar));
    [lower getCharacters:src range:NSMakeRange(0, n)];
    NSUInteger k = 0;
    for (NSUInteger i = 0; i < n; i++) {
        unichar ch = src[i];
        if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) src[k++] = ch;
    }
    NSString *out = [NSString stringWithCharacters:src length:k];
    if (src != stackBuf) free(src);
    return out;
}

- (NSArray<RYGMCConfig *> *)configsMatching:(NSString *)query onlyOverridden:(BOOL)onlyOverridden {
    [self prepare];
    NSString *nq = rygNormalize(query);
    NSString *digits = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    unsigned long long qnum = digits.length ? strtoull(digits.UTF8String, NULL, 10) : 0;
    NSMutableArray *out = [NSMutableArray array];
    for (RYGMCConfig *c in _configs) {
        if (onlyOverridden) {
            BOOL any = NO;
            for (RYGMCParam *p in c.params) if ([self overrideStateFor:p] == RYGMCOverrideSet) { any = YES; break; }
            if (!any) continue;
        }
        if (nq.length) {
            BOOL hit = [c.normalizedName containsString:nq] ||
                       (qnum && c.number == qnum);
            if (!hit) for (RYGMCParam *p in c.params)
                if ([p.normalizedName containsString:nq]) { hit = YES; break; }
            if (!hit) continue;
        }
        [out addObject:c];
    }
    return out;
}

// Param names in a config matching the query (symbol-insensitive), for a result hint.
- (NSArray<NSString *> *)paramNamesMatching:(NSString *)query inConfig:(RYGMCConfig *)c {
    NSString *nq = rygNormalize(query);
    if (!nq.length) return @[];
    NSMutableArray *hits = [NSMutableArray array];
    for (RYGMCParam *p in c.params)
        if (p.name.length && [p.normalizedName containsString:nq]) [hits addObject:p.name];
    return hits;
}

- (NSArray<RYGMCParam *> *)paramsMatching:(NSString *)query inConfig:(RYGMCConfig *)c {
    NSString *nq = rygNormalize(query);
    if (!nq.length) return c.params ?: @[];
    NSString *digits = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    unsigned long long qnum = digits.length ? strtoull(digits.UTF8String, NULL, 10) : 0;
    NSMutableArray *out = [NSMutableArray array];
    for (RYGMCParam *p in c.params) {
        if (p.normalizedName.length && [p.normalizedName containsString:nq]) { [out addObject:p]; continue; }
        if (qnum && p.paramIndex == qnum) { [out addObject:p]; continue; }
        NSString *note = [self noteFor:p];
        if (note.length && [rygNormalize(note) containsString:nq]) [out addObject:p];
    }
    return out;
}

#pragma mark pid + manager routing

// Prefer a param ID the app has actually read for this ordinal+index — it carries
// the true unit byte. Fall back to the reconstructed ID.
- (unsigned long long)bestParamIDFor:(RYGMCParam *)p {
    pthread_mutex_lock(&gLock);
    NSNumber *real = gRealPidByOrdIdx[@(((unsigned long long)p.ordinal << 20) | p.paramIndex)];
    pthread_mutex_unlock(&gLock);
    return real ? real.unsignedLongLongValue : p.paramID;
}

- (id)managerForPid:(unsigned long long)pid {
    unsigned long long unit = (pid >> 48) & 0xF0;
    pthread_mutex_lock(&gLock);
    id mgr = gManagersByUnit[@(unit)];
    pthread_mutex_unlock(&gLock);
    return mgr ?: gManager;
}

#pragma mark live values

- (id)liveValueFor:(RYGMCParam *)p {
    unsigned long long pid = [self bestParamIDFor:p];
    id mgr = [self managerForPid:pid];
    if (!mgr) return nil;
    switch (p.type) {
        case RYGMCTypeBool:
            return @(((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getBool:), pid));
        case RYGMCTypeInt:
            return @(((long long (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getInt64:), pid));
        case RYGMCTypeDouble:
            return @(((double (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getDouble:), pid));
        case RYGMCTypeString:
            return ((id (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getString:), pid);
    }
    return nil;
}

#pragma mark overrides

- (void *)overridesTableForPid:(unsigned long long)pid {
    id mgr = [self managerForPid:pid];
    Ivar iv = mgr ? class_getInstanceVariable(NSClassFromString(@"IGMobileConfigContextManager"), "_configManager") : NULL;
    if (!iv) return NULL;
    void *cpp = ((void **)((char *)(__bridge void *)mgr + ivar_getOffset(iv)))[0];
    void *fn = rygSym("_ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb");
    if (!cpp || !fn) return NULL;
    typedef RYGSharedPtr (*Fn)(void *, bool);
    RYGSharedPtr sp = ((Fn)fn)(cpp, true);
    return sp.ptr;
}

- (RYGMCOverrideState)overrideStateFor:(RYGMCParam *)p {
    return _overrides[@(rygCanonicalPid(p.paramID))] ? RYGMCOverrideSet : RYGMCOverrideNone;
}
- (id)overrideValueFor:(RYGMCParam *)p { return _overrides[@(rygCanonicalPid(p.paramID))]; }

// Write one override into IG's C++ overrides table. flag=false = don't require a
// restart; we want it live.
- (BOOL)writeNativeForPid:(unsigned long long)pid value:(id)value type:(RYGMCType)type {
    void *table = [self overridesTableForPid:pid];
    if (!table) return NO;
    switch (type) {
        case RYGMCTypeBool: {
            void *fn = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb");
            if (!fn) return NO;
            ((void (*)(void *, unsigned long long, bool, bool))fn)(table, pid, [value boolValue], false);
            break;
        }
        case RYGMCTypeInt: {
            void *fn = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyxb");
            if (!fn) return NO;
            ((void (*)(void *, unsigned long long, long long, bool))fn)(table, pid, [value longLongValue], false);
            break;
        }
        case RYGMCTypeDouble: {
            void *fn = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEydb");
            if (!fn) return NO;
            ((void (*)(void *, unsigned long long, double, bool))fn)(table, pid, [value doubleValue], false);
            break;
        }
        case RYGMCTypeString: {
            void *fn = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyRKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEEb");
            if (!fn) return NO;
            std::string s([value description].UTF8String ?: "");
            ((void (*)(void *, unsigned long long, const std::string &, bool))fn)(table, pid, s, false);
            break;
        }
    }
    return YES;
}

// Write the override into IG's C++ table for whichever unit owns this config.
- (void)writeNativeBothUnitsForPid:(unsigned long long)pid value:(id)value type:(RYGMCType)type {
    [self writeNativeForPid:rygVariantPid(pid, 0x40) value:value type:type];
    [self writeNativeForPid:rygVariantPid(pid, 0x80) value:value type:type];
}

- (void)removeNativeBothUnitsForPid:(unsigned long long)pid {
    void *fn = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb");
    if (!fn) return;
    for (unsigned long long base = 0x40; base <= 0x80; base += 0x40) {
        unsigned long long v = rygVariantPid(pid, base);
        void *table = [self overridesTableForPid:v];
        if (table) ((void (*)(void *, unsigned long long, bool))fn)(table, v, false);
    }
}

- (void)reapplyOverridesToNativeTable {
    for (NSNumber *k in [_overrides copy]) {
        unsigned long long pid = k.unsignedLongLongValue;
        int t = (int)((pid >> 48) & 0x0F);
        if (t < RYGMCTypeBool || t > RYGMCTypeString) continue;
        [self writeNativeBothUnitsForPid:pid value:_overrides[k] type:(RYGMCType)t];
    }
}

- (BOOL)applyOverride:(id)value pid:(unsigned long long)pid type:(RYGMCType)type {
    unsigned long long canon = rygCanonicalPid(pid);
    [self writeNativeBothUnitsForPid:canon value:value type:type];
    rygSetForce(canon, value);
    _overrides[@(canon)] = value;
    [self saveOverrides];
    return YES;
}

- (BOOL)setOverride:(id)value for:(RYGMCParam *)p {
    return [self applyOverride:value pid:p.paramID type:p.type];
}

- (void)clearOverrideFor:(RYGMCParam *)p {
    unsigned long long canon = rygCanonicalPid(p.paramID);
    [self removeNativeBothUnitsForPid:canon];
    rygClearForce(canon);
    [_overrides removeObjectForKey:@(canon)];
    [self saveOverrides];
}

- (void)resetOverridesForConfig:(RYGMCConfig *)c {
    for (RYGMCParam *p in c.params)
        if ([self overrideStateFor:p] == RYGMCOverrideSet) [self clearOverrideFor:p];
}

- (NSUInteger)overrideCount { return _overrides.count; }

- (void)resetAllOverrides {
    for (NSNumber *k in _overrides.allKeys) {
        [self removeNativeBothUnitsForPid:k.unsignedLongLongValue];
        rygClearForce(k.unsignedLongLongValue);
    }
    [_overrides removeAllObjects];
    [self saveOverrides];
}

#pragma mark call site

- (NSString *)callSiteFor:(RYGMCParam *)p {
    pthread_mutex_lock(&gLock);
    NSValue *v = gCallSites[@(p.paramID)];
    pthread_mutex_unlock(&gLock);
    if (!v) return nil;
    void *addr = v.pointerValue;
    Dl_info info = {0};
    if (dladdr(addr, &info) && info.dli_sname) {
        const char *nm = info.dli_sname;
        return [NSString stringWithFormat:@"%s", nm];
    }
    return nil;
}

#pragma mark notes

- (NSString *)noteFor:(RYGMCParam *)p { return _notes[@(p.paramID)]; }
- (void)setNote:(NSString *)note for:(RYGMCParam *)p {
    if (note.length) _notes[@(p.paramID)] = note;
    else [_notes removeObjectForKey:@(p.paramID)];
    [self saveNotes];
}

#pragma mark persistence

+ (NSString *)storageDirectory {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"RyukGram/MobileConfig"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

// Launch guard is device state, so it lives outside the backed-up store.
- (NSString *)storePathFor:(NSString *)name {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"RyukGram"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

- (NSString *)mcStorePathFor:(NSString *)name {
    return [[RYGMobileConfig storageDirectory] stringByAppendingPathComponent:name];
}

- (void)migrateLegacyStore {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *map = @{ @"mc_overrides.plist": @"overrides.plist", @"mc_notes.plist": @"notes.plist" };
    for (NSString *old in map) {
        NSString *src = [self storePathFor:old];
        NSString *dst = [self mcStorePathFor:map[old]];
        if ([fm fileExistsAtPath:src] && ![fm fileExistsAtPath:dst]) [fm moveItemAtPath:src toPath:dst error:nil];
    }
}

- (NSMutableDictionary *)loadOverrides {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self mcStorePathFor:@"overrides.plist"]];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    // Canonicalize on load so pre-fix entries (stored under either unit) collapse to one stable key.
    for (NSString *k in d) out[@(rygCanonicalPid(strtoull(k.UTF8String, NULL, 10)))] = d[k];
    return out;
}
- (void)saveOverrides {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSNumber *k in _overrides) d[k.stringValue] = _overrides[k];
    [d writeToFile:[self mcStorePathFor:@"overrides.plist"] atomically:YES];
}

- (NSMutableDictionary *)loadNotes {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self mcStorePathFor:@"notes.plist"]];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in d) out[@(strtoull(k.UTF8String, NULL, 10))] = d[k];
    return out;
}
- (void)saveNotes {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSNumber *k in _notes) d[k.stringValue] = _notes[k];
    [d writeToFile:[self mcStorePathFor:@"notes.plist"] atomically:YES];
}

#pragma mark store-level backup hooks

+ (void)reloadStoreFromDisk { [[self shared] reloadFromDisk]; }

+ (void)resetStore {
    RYGMobileConfig *e = [self shared];
    [e resetAllOverrides];
    [e resetAllNotes];
}

+ (void)mergeImportedStoreAtPath:(NSString *)importedDir {
    if (!importedDir.length) return;
    [[self shared] mergeStoreAtPath:importedDir];
}

- (void)detachAllOverrides {
    for (NSNumber *k in _overrides) {
        [self removeNativeBothUnitsForPid:k.unsignedLongLongValue];
        rygClearForce(k.unsignedLongLongValue);
    }
}

- (void)reloadFromDisk {
    [self detachAllOverrides];
    _overrides = [self loadOverrides];
    _notes = [self loadNotes];
    for (NSNumber *k in _overrides) rygSetForce(k.unsignedLongLongValue, _overrides[k]);
    [self reapplyOverridesToNativeTable];
}

- (void)resetAllNotes {
    [_notes removeAllObjects];
    [self saveNotes];
}

// Local values win on a clash, matching every other store's merge.
- (void)mergeStoreAtPath:(NSString *)dir {
    NSDictionary *(^read)(NSString *, NSString *) = ^NSDictionary *(NSString *name, NSString *legacy) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:name]];
        return d ?: [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:legacy]];
    };
    NSDictionary *ov = read(@"overrides.plist", @"mc_overrides.plist");
    NSDictionary *nt = read(@"notes.plist", @"mc_notes.plist");

    for (NSString *k in ov) {
        NSNumber *key = @(rygCanonicalPid(strtoull(k.UTF8String, NULL, 10)));
        if (!_overrides[key]) _overrides[key] = ov[k];
    }
    for (NSString *k in nt) {
        NSNumber *key = @(strtoull(k.UTF8String, NULL, 10));
        if (!_notes[key]) _notes[key] = nt[k];
    }
    [self saveOverrides];
    [self saveNotes];
    [self reloadFromDisk];
}

#pragma mark portable export / import

- (RYGMCParam *)paramForConfigNumber:(unsigned int)number paramIndex:(unsigned int)paramIndex {
    [self prepare];
    for (RYGMCConfig *c in _configs) {
        if (c.number != number) continue;
        for (RYGMCParam *p in c.params) if (p.paramIndex == paramIndex) return p;
    }
    return nil;
}

- (NSArray<NSDictionary *> *)exportEntries {
    [self prepare];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet<NSNumber *> *covered = [NSMutableSet set];

    for (RYGMCConfig *c in _configs) {
        for (RYGMCParam *p in c.params) {
            id value = [self overrideValueFor:p];
            NSString *note = [self noteFor:p];
            if (!value && !note.length) continue;
            unsigned long long canon = rygCanonicalPid(p.paramID);
            [covered addObject:@(canon)];

            NSMutableDictionary *e = [NSMutableDictionary dictionary];
            e[@"config"] = @(c.number);
            e[@"index"] = @(p.paramIndex);
            e[@"type"] = @(p.type);
            e[@"pid"] = [@(canon) stringValue];
            if (value) e[@"value"] = value;
            if (note.length) e[@"note"] = note;
            if (c.name.length) e[@"config_name"] = c.name;
            if (p.name.length) e[@"name"] = p.name;
            [out addObject:e];
        }
    }

    // Overrides whose param vanished from this build still travel, keyed by id alone.
    for (NSNumber *k in _overrides) {
        if ([covered containsObject:k]) continue;
        unsigned long long pid = k.unsignedLongLongValue;
        [out addObject:@{ @"pid": k.stringValue, @"type": @((pid >> 48) & 0x0F), @"value": _overrides[k] }];
    }
    return out;
}

- (void)importEntries:(NSArray<NSDictionary *> *)entries
              replace:(BOOL)replace
              applied:(NSUInteger *)applied
              skipped:(NSUInteger *)skipped {
    if (replace) {
        [self resetAllOverrides];
        [self resetAllNotes];
    }
    NSUInteger ok = 0, bad = 0;
    for (NSDictionary *e in entries) {
        if (![e isKindOfClass:[NSDictionary class]]) { bad++; continue; }

        RYGMCParam *p = e[@"config"] && e[@"index"]
            ? [self paramForConfigNumber:[e[@"config"] unsignedIntValue] paramIndex:[e[@"index"] unsignedIntValue]]
            : nil;
        NSString *rawPid = [e[@"pid"] respondsToSelector:@selector(stringValue)] ? [e[@"pid"] stringValue] : e[@"pid"];
        unsigned long long raw = [rawPid isKindOfClass:[NSString class]] ? strtoull(rawPid.UTF8String, NULL, 10) : 0;
        unsigned long long pid = p ? rygCanonicalPid(p.paramID) : (raw ? rygCanonicalPid(raw) : 0);
        RYGMCType type = p ? p.type : (RYGMCType)[e[@"type"] intValue];
        if (!pid || type < RYGMCTypeBool || type > RYGMCTypeString) { bad++; continue; }
        // A param that changed type between IG versions would corrupt the read.
        if (p && e[@"type"] && (RYGMCType)[e[@"type"] intValue] != p.type) { bad++; continue; }

        id value = rygCoerce(e[@"value"], type);
        NSString *note = [e[@"note"] isKindOfClass:[NSString class]] ? e[@"note"] : nil;
        BOOL touched = NO;

        if (value && (replace || !_overrides[@(pid)])) {
            [self applyOverride:value pid:pid type:type];
            touched = YES;
        }
        if (note.length && p && (replace || ![self noteFor:p].length)) {
            [self setNote:note for:p];
            touched = YES;
        }
        if (touched) ok++; else bad++;
    }
    if (applied) *applied = ok;
    if (skipped) *skipped = bad;
}

#pragma mark crash guard

- (BOOL)consumeCrashLoopFlag {
    NSString *path = [self storePathFor:@"mc_launch.plist"];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    NSInteger n = [d[@"pending"] integerValue] + 1;
    BOOL loop = NO;
    if (n >= 3) {
        if (_overrides.count) [self resetAllOverrides];
        loop = YES;
        n = 0;
    }
    d[@"pending"] = @(n);
    [d writeToFile:path atomically:YES];
    return loop;
}

- (void)markLaunchStable {
    NSString *path = [self storePathFor:@"mc_launch.plist"];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    d[@"pending"] = @(0);
    [d writeToFile:path atomically:YES];
}

@end

#pragma mark - install

static void hook(Class c, NSString *sel, IMP imp, IMP *orig) {
    if (!c) return;
    SEL s = NSSelectorFromString(sel);
    if (class_getInstanceMethod(c, s)) MSHookMessageEx(c, s, imp, orig);
}

%ctor {
    if (![RYGUtils getBoolPref:@"ryg_metaconfig_enabled"]) return;

    // Load the force table BEFORE hooks so the very first reads at launch already
    // see the overrides (IG caches some config values once on boot).
    RYGMobileConfig *e = [RYGMobileConfig shared];

    Class mc = NSClassFromString(@"IGMobileConfigContextManager");
    hook(mc, @"getBool:",                          (IMP)new_getBool,          (IMP *)&orig_getBool);
    hook(mc, @"getBool:withDefault:",              (IMP)new_getBoolDef,       (IMP *)&orig_getBoolDef);
    hook(mc, @"getBool:withOptions:",              (IMP)new_getBoolOpts,      (IMP *)&orig_getBoolOpts);
    hook(mc, @"getBool:withOptions:withDefault:",  (IMP)new_getBoolOptsDef,   (IMP *)&orig_getBoolOptsDef);
    hook(mc, @"getInt64:",                         (IMP)new_getInt,           (IMP *)&orig_getInt);
    hook(mc, @"getInt64:withDefault:",             (IMP)new_getIntDef,        (IMP *)&orig_getIntDef);
    hook(mc, @"getInt64:withOptions:",             (IMP)new_getIntOpts,       (IMP *)&orig_getIntOpts);
    hook(mc, @"getInt64:withOptions:withDefault:", (IMP)new_getIntOptsDef,    (IMP *)&orig_getIntOptsDef);
    hook(mc, @"getDouble:",                        (IMP)new_getDouble,        (IMP *)&orig_getDouble);
    hook(mc, @"getDouble:withDefault:",            (IMP)new_getDoubleDef,     (IMP *)&orig_getDoubleDef);
    hook(mc, @"getDouble:withOptions:",            (IMP)new_getDoubleOpts,    (IMP *)&orig_getDoubleOpts);
    hook(mc, @"getDouble:withOptions:withDefault:",(IMP)new_getDoubleOptsDef, (IMP *)&orig_getDoubleOptsDef);
    hook(mc, @"getString:",                        (IMP)new_getString,        (IMP *)&orig_getString);
    hook(mc, @"getString:withDefault:",            (IMP)new_getStringDef,     (IMP *)&orig_getStringDef);
    hook(mc, @"getString:withOptions:",            (IMP)new_getStringOpts,    (IMP *)&orig_getStringOpts);
    hook(mc, @"getString:withOptions:withDefault:",(IMP)new_getStringOptsDef, (IMP *)&orig_getStringOptsDef);

    if ([e consumeCrashLoopFlag]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [RYGUtils showToastForDuration:4.0 title:RYGLocalized(@"MobileConfig overrides were reset after repeated crashes on launch")];
        });
    }
    // Re-apply overrides into IG's C++ table once managers are live, for any config
    // read straight from C++ instead of the ObjC getters.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [e reapplyOverridesToNativeTable];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [e markLaunchStable];
    });
}
