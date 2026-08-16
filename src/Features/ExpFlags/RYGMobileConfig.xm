#import "RYGMobileConfig.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"
#import "../../Networking/RYGInstagramAPI.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>
#import <pthread.h>
#import <execinfo.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#include <stdint.h>
#include <string.h>
#import <string>

// MobileConfig engine: enumerate every param from IG's live in-memory table,
// discover names only from Instagram's current on-device mappings, read live
// values, and write overrides through IG's own C++ overrides table. No bundled
// or preloaded parameter-name table is used.

struct RYGSharedPtr { void *ptr; void *ctrl; ~RYGSharedPtr(); };
RYGSharedPtr::~RYGSharedPtr() {}

static __weak id gManager;
static NSMutableDictionary<NSNumber *, id> *gManagersByUnit;      // (pid>>48 & 0xF0) -> manager
static NSMutableDictionary<NSNumber *, NSValue *> *gCallSites;
static NSMutableDictionary<NSNumber *, id> *gOverrideValues;      // pid -> value (all types), the force table
static NSMutableDictionary<NSNumber *, NSNumber *> *gRealPidByOrdIdx;  // (ordinal<<20|idx) -> real pid
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;

static void *rygSym(const char *n) { return dlsym(RTLD_DEFAULT, n); }

// dlsym gives us addresses in loaded Instagram images. Before dereferencing a
// private data symbol, prove that the complete byte range belongs to a readable
// mapped Mach-O segment. A missing or changed layout therefore produces an
// empty live scan instead of an invalid-memory crash.
static BOOL rygImageRangeIsReadable(const void *pointer, size_t length) {
    if (!pointer || !length) return NO;
    uintptr_t start = (uintptr_t)pointer;
    if (start > UINTPTR_MAX - length) return NO;
    uintptr_t end = start + length;

    Dl_info info = {0};
    if (!dladdr(pointer, &info) || !info.dli_fbase) return NO;
    const struct mach_header *raw = (const struct mach_header *)info.dli_fbase;
    if (raw->magic != MH_MAGIC_64) return NO;
    const struct mach_header_64 *header = (const struct mach_header_64 *)raw;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *commandsEnd = cursor + header->sizeofcmds;
    uint64_t textVMAddr = UINT64_MAX;

    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cursor > commandsEnd || (size_t)(commandsEnd - cursor) < sizeof(struct load_command)) return NO;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(commandsEnd - cursor)) return NO;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (segment->cmdsize < sizeof(*segment)) return NO;
            if (strncmp(segment->segname, SEG_TEXT, sizeof(segment->segname)) == 0) textVMAddr = segment->vmaddr;
        }
        cursor += command->cmdsize;
    }
    if (textVMAddr == UINT64_MAX || (uintptr_t)header < textVMAddr) return NO;
    uintptr_t slide = (uintptr_t)header - (uintptr_t)textVMAddr;

    cursor = (const uint8_t *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if ((segment->initprot & VM_PROT_READ) && segment->vmsize <= UINTPTR_MAX - slide
                && segment->vmaddr <= UINTPTR_MAX - slide) {
                uintptr_t segmentStart = slide + (uintptr_t)segment->vmaddr;
                if (segmentStart <= UINTPTR_MAX - (uintptr_t)segment->vmsize) {
                    uintptr_t segmentEnd = segmentStart + (uintptr_t)segment->vmsize;
                    if (start >= segmentStart && end <= segmentEnd) return YES;
                }
            }
        }
        cursor += command->cmdsize;
    }
    return NO;
}

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
    pthread_mutex_lock(&gLock);
    BOOL alreadyRecorded = gCallSites[@(pid)] != nil;
    pthread_mutex_unlock(&gLock);
    if (alreadyRecorded) return;

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
    return orig_getBool ? orig_getBool(self, _cmd, pid) : NO;
}
static BOOL (*orig_getBoolDef)(id, SEL, unsigned long long, BOOL);
static BOOL new_getBoolDef(id self, SEL _cmd, unsigned long long pid, BOOL def) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v boolValue];
    return orig_getBoolDef ? orig_getBoolDef(self, _cmd, pid, def) : def;
}
static BOOL (*orig_getBoolOpts)(id, SEL, unsigned long long, id);
static BOOL new_getBoolOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v boolValue];
    return orig_getBoolOpts ? orig_getBoolOpts(self, _cmd, pid, opts) : NO;
}
static BOOL (*orig_getBoolOptsDef)(id, SEL, unsigned long long, id, BOOL);
static BOOL new_getBoolOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, BOOL def) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v boolValue];
    return orig_getBoolOptsDef ? orig_getBoolOptsDef(self, _cmd, pid, opts, def) : def;
}
static long long (*orig_getInt)(id, SEL, unsigned long long);
static long long new_getInt(id self, SEL _cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getInt ? orig_getInt(self, _cmd, pid) : 0;
}
static long long (*orig_getIntDef)(id, SEL, unsigned long long, long long);
static long long new_getIntDef(id self, SEL _cmd, unsigned long long pid, long long def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getIntDef ? orig_getIntDef(self, _cmd, pid, def) : def;
}
static long long (*orig_getIntOpts)(id, SEL, unsigned long long, id);
static long long new_getIntOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getIntOpts ? orig_getIntOpts(self, _cmd, pid, opts) : 0;
}
static long long (*orig_getIntOptsDef)(id, SEL, unsigned long long, id, long long);
static long long new_getIntOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, long long def) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v longLongValue];
    return orig_getIntOptsDef ? orig_getIntOptsDef(self, _cmd, pid, opts, def) : def;
}
static double (*orig_getDouble)(id, SEL, unsigned long long);
static double new_getDouble(id self, SEL _cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDouble ? orig_getDouble(self, _cmd, pid) : 0.0;
}
static double (*orig_getDoubleDef)(id, SEL, unsigned long long, double);
static double new_getDoubleDef(id self, SEL _cmd, unsigned long long pid, double def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDoubleDef ? orig_getDoubleDef(self, _cmd, pid, def) : def;
}
static double (*orig_getDoubleOpts)(id, SEL, unsigned long long, id);
static double new_getDoubleOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDoubleOpts ? orig_getDoubleOpts(self, _cmd, pid, opts) : 0.0;
}
static double (*orig_getDoubleOptsDef)(id, SEL, unsigned long long, id, double);
static double new_getDoubleOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, double def) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if (v) return [v doubleValue];
    return orig_getDoubleOptsDef ? orig_getDoubleOptsDef(self, _cmd, pid, opts, def) : def;
}
static id (*orig_getString)(id, SEL, unsigned long long);
static id new_getString(id self, SEL _cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getString ? orig_getString(self, _cmd, pid) : nil;
}
static id (*orig_getStringDef)(id, SEL, unsigned long long, id);
static id new_getStringDef(id self, SEL _cmd, unsigned long long pid, id def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getStringDef ? orig_getStringDef(self, _cmd, pid, def) : def;
}
static id (*orig_getStringOpts)(id, SEL, unsigned long long, id);
static id new_getStringOpts(id self, SEL _cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getStringOpts ? orig_getStringOpts(self, _cmd, pid, opts) : nil;
}
static id (*orig_getStringOptsDef)(id, SEL, unsigned long long, id, id);
static id new_getStringOptsDef(id self, SEL _cmd, unsigned long long pid, id opts, id def) {
    rygCaptureManager(self, pid);
    rygRecordCaller(pid);
    id v = rygOverrideValue(pid);
    if ([v isKindOfClass:[NSString class]]) return v;
    return orig_getStringOptsDef ? orig_getStringOptsDef(self, _cmd, pid, opts, def) : def;
}

#pragma mark - model

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
@end

@implementation RYGMCConfig
- (NSString *)displayName {
    return self.name.length ? self.name : [NSString stringWithFormat:@"config %u", self.number];
}
@end

#pragma mark - engine

@interface RYGMobileConfig ()
- (NSString *)mcDirectory;
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
    NSMutableDictionary *cat = [NSMutableDictionary dictionary];
    [self mergeDiskNamesInto:cat];
    return cat.copy;
}

// Read names IG has on disk (id_name_mapping.json, or id_to_names in the
// sync-response dumps) at scan time. Both use the colon form
// "<configNum>:<configName>:<idx>:<param>:…".
- (NSString *)mcDirectory {
    id mgr = gManager;
    SEL selector = @selector(getOverridesTablePath);
    Method method = mgr ? class_getInstanceMethod(object_getClass(mgr), selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@') return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(mgr, selector);
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
    if (!rygImageRangeIsReadable(listSym, sizeof(void *) * 8)
        || !rygImageRangeIsReadable(sizeSym, sizeof(uint32_t) * 4)) return NULL;

    void **pp = (void **)listSym;
    const char *arr = NULL;
    size_t st = 0;
    for (int candidate = 0; candidate < 8 && !arr; candidate++) {
        const char *possible = (const char *)pp[candidate];
        if (!rygImageRangeIsReadable(possible, 256)) continue;
        void *first = NULL;
        memcpy(&first, possible, sizeof(first));
        if (!first) continue;
        // The fields consumed below end at byte 28; reject any apparent stride
        // too short to contain one complete row.
        for (size_t s = 32; s <= 128 && !st; s += 8) {
            void *rowFirst = NULL, *rowSecond = NULL;
            memcpy(&rowFirst, possible + s, sizeof(rowFirst));
            memcpy(&rowSecond, possible + s + sizeof(void *), sizeof(rowSecond));
            if (rowFirst == first && rowSecond == first) st = s;
        }
        if (st) arr = possible;
    }
    if (!arr || !st) return NULL;

    uint32_t rawSizes[4] = {0};
    memcpy(rawSizes, sizeSym, sizeof(rawSizes));
    size_t n = 0;
    // Current MobileConfig exports the count twice. Prefer that repeated value;
    // accept one bounded value for compatible layouts that export it once.
    for (size_t i = 0; i < 4 && !n; i++) {
        if (!rawSizes[i] || rawSizes[i] > 200000) continue;
        for (size_t j = i + 1; j < 4; j++) {
            if (rawSizes[j] == rawSizes[i]) { n = rawSizes[i]; break; }
        }
    }
    if (!n) {
        for (size_t i = 0; i < 4; i++) {
            if (rawSizes[i] && rawSizes[i] <= 200000) { n = rawSizes[i]; break; }
        }
    }
    if (!n || st > SIZE_MAX / n || !rygImageRangeIsReadable(arr, st * n)) return NULL;
    if (stride) *stride = st;
    if (count) *count = n;
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
    // The MobileConfig framework can be loaded after RyukGram's constructor.
    // Resolve its exported validator at the moment of each live scan.
    _typeFromParam = (int (*)(unsigned long long))rygSym("_ZN12mobileconfig17typeFromParameterEy");
    NSDictionary *catalog = [self loadNameCatalog];

    size_t stride = 0, count = 0;
    const char *arr = [self paramsArrayStride:&stride count:&count];
    NSMutableDictionary<NSNumber *, NSMutableArray<RYGMCParam *> *> *byConfig = [NSMutableDictionary dictionary];

    if (arr && stride && count && _typeFromParam) {
        for (size_t i = 0; i < count; i++) {
            const char *row = arr + i * stride;
            unsigned int ordMix = 0, typeSerial = 0, cfg = 0, paramIndex = 0;
            memcpy(&ordMix, row + 20, sizeof(ordMix));
            memcpy(&typeSerial, row + 24, sizeof(typeSerial));
            memcpy(&cfg, row + stride - 4, sizeof(cfg));
            memcpy(&paramIndex, row + 16, sizeof(paramIndex));
            unsigned int ordinal    = ordMix & 0xFFFF;
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

- (void)reloadFromRuntime {
    _ready = NO;
    _configs = nil;
    _namedConfigCount = 0;
    [self prepare];
}

- (NSArray<RYGMCConfig *> *)allConfigs { [self prepare]; return _configs ?: @[]; }

// Lowercase and strip every non-alphanumeric so "core creation" matches
// "core_creation", "multi-select" matches "multiSelect", etc.
static NSString *rygNormalize(NSString *s) {
    if (!s.length) return @"";
    NSMutableString *o = [NSMutableString stringWithCapacity:s.length];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar ch = [s.lowercaseString characterAtIndex:i];
        if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) [o appendFormat:@"%C", ch];
    }
    return o;
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
            BOOL hit = [rygNormalize(c.name) containsString:nq] ||
                       (qnum && c.number == qnum);
            if (!hit) for (RYGMCParam *p in c.params)
                if ([rygNormalize(p.name) containsString:nq]) { hit = YES; break; }
            if (!hit) continue;
        }
        [out addObject:c];
    }
    return out;
}

// Param names in a config matching the query (symbol-insensitive), for a result hint.
- (NSArray<NSString *> *)paramsMatching:(NSString *)query inConfig:(RYGMCConfig *)c {
    NSString *nq = rygNormalize(query);
    if (!nq.length) return @[];
    NSMutableArray *hits = [NSMutableArray array];
    for (RYGMCParam *p in c.params)
        if (p.name.length && [rygNormalize(p.name) containsString:nq]) [hits addObject:p.name];
    return hits;
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
        case RYGMCTypeBool: {
            if (![mgr respondsToSelector:@selector(getBool:)]) return nil;
            return @(((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getBool:), pid));
        }
        case RYGMCTypeInt: {
            if (![mgr respondsToSelector:@selector(getInt64:)]) return nil;
            return @(((long long (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getInt64:), pid));
        }
        case RYGMCTypeDouble: {
            if (![mgr respondsToSelector:@selector(getDouble:)]) return nil;
            return @(((double (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getDouble:), pid));
        }
        case RYGMCTypeString: {
            if (![mgr respondsToSelector:@selector(getString:)]) return nil;
            id value = ((id (*)(id, SEL, unsigned long long))objc_msgSend)(mgr, @selector(getString:), pid);
            return [value isKindOfClass:NSString.class] ? value : nil;
        }
    }
    return nil;
}

#pragma mark overrides

- (void *)overridesTableForPid:(unsigned long long)pid {
    id mgr = [self managerForPid:pid];
    Ivar iv = mgr ? class_getInstanceVariable(object_getClass(mgr), "_configManager") : NULL;
    if (!iv) return NULL;
    void *cpp = NULL;
    memcpy(&cpp, (char *)(__bridge void *)mgr + ivar_getOffset(iv), sizeof(cpp));
    void *fn = rygSym("_ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb");
    if (!cpp || !fn || !rygImageRangeIsReadable(fn, 4)) return NULL;
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

- (BOOL)setOverride:(id)value for:(RYGMCParam *)p {
    if (!p) return NO;
    BOOL validValue = p.type == RYGMCTypeString ? [value isKindOfClass:NSString.class]
        : [value isKindOfClass:NSNumber.class];
    if (!validValue) return NO;
    unsigned long long canon = rygCanonicalPid(p.paramID);
    [self writeNativeBothUnitsForPid:canon value:value type:p.type];
    rygSetForce(canon, value);
    _overrides[@(canon)] = value;
    [self saveOverrides];
    return YES;
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
    unsigned long long best = [self bestParamIDFor:p];
    pthread_mutex_lock(&gLock);
    NSValue *v = gCallSites[@(best)] ?: gCallSites[@(rygVariantPid(p.paramID, 0x40))]
        ?: gCallSites[@(rygVariantPid(p.paramID, 0x80))];
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

- (NSString *)storePathFor:(NSString *)name {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"RyukGram"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

- (NSMutableDictionary *)loadOverrides {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self storePathFor:@"mc_overrides.plist"]];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    // Canonicalize on load so pre-fix entries (stored under either unit) collapse to one stable key.
    for (id rawKey in d) {
        if (![rawKey isKindOfClass:NSString.class]) continue;
        unsigned long long pid = strtoull([(NSString *)rawKey UTF8String], NULL, 10);
        unsigned int type = (unsigned int)((pid >> 48) & 0x0F);
        id value = d[rawKey];
        BOOL validValue = type == RYGMCTypeString ? [value isKindOfClass:NSString.class]
            : [value isKindOfClass:NSNumber.class];
        if (pid && type >= RYGMCTypeBool && type <= RYGMCTypeString && validValue) {
            out[@(rygCanonicalPid(pid))] = value;
        }
    }
    return out;
}
- (void)saveOverrides {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSNumber *k in _overrides) d[k.stringValue] = _overrides[k];
    [d writeToFile:[self storePathFor:@"mc_overrides.plist"] atomically:YES];
}

- (NSMutableDictionary *)loadNotes {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self storePathFor:@"mc_notes.plist"]];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id rawKey in d) {
        id value = d[rawKey];
        if (![rawKey isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]) continue;
        unsigned long long pid = strtoull([(NSString *)rawKey UTF8String], NULL, 10);
        if (pid) out[@(pid)] = value;
    }
    return out;
}
- (void)saveNotes {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSNumber *k in _notes) d[k.stringValue] = _notes[k];
    [d writeToFile:[self storePathFor:@"mc_notes.plist"] atomically:YES];
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

static const char *rygMCUnqualifiedType(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL rygMCTypeMatches(const char *raw, char expected) {
    const char *type = rygMCUnqualifiedType(raw);
    if (!type || !*type) return NO;
    switch (expected) {
        case 'P':
            return *type == 'Q' || *type == 'q'
                || (*type == '{' && (strstr(type, "=Q}") || strstr(type, "=q}")));
        case 'B': return *type == 'B' || *type == 'c' || *type == 'C';
        case 'Q': return *type == 'q' || *type == 'Q';
        case 'D': return *type == 'd';
        case '@': return *type == '@';
        default: return NO;
    }
}

static BOOL rygMCMethodMatches(Method method, char returnType, const char *arguments) {
    if (!method || !arguments || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char encoded[128] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    if (!rygMCTypeMatches(encoded, returnType)) return NO;
    for (unsigned int index = 0; arguments[index]; index++) {
        memset(encoded, 0, sizeof(encoded));
        method_getArgumentType(method, index + 2, encoded, sizeof(encoded));
        if (!rygMCTypeMatches(encoded, arguments[index])) return NO;
    }
    return YES;
}

static BOOL rygHookMobileConfigMethod(Class c, NSString *name, IMP replacement,
                                      IMP *original, char returnType, const char *arguments) {
    if (!c || !replacement || !original || *original) return original && *original != NULL;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(c, selector);
    if (!rygMCMethodMatches(method, returnType, arguments)) return NO;
    MSHookMessageEx(c, selector, replacement, original);
    return *original != NULL;
}

static NSUInteger rygMobileConfigMethodScore(Class c) {
    if (!c) return 0;
    NSUInteger score = 0;
    for (NSString *name in @[@"getBool:", @"getInt64:", @"getDouble:", @"getString:"]) {
        score += class_getInstanceMethod(c, NSSelectorFromString(name)) != NULL;
    }
    return score;
}

static void rygInstallMobileConfigHooks(void) {
    Class fb = NSClassFromString(@"FBMobileConfigContextManager");
    Class ig = NSClassFromString(@"IGMobileConfigContextManager");
    Class mc = rygMobileConfigMethodScore(fb) >= rygMobileConfigMethodScore(ig) ? fb : ig;
    if (!mc) return;

    rygHookMobileConfigMethod(mc, @"getBool:",                          (IMP)new_getBool,          (IMP *)&orig_getBool,          'B', "P");
    rygHookMobileConfigMethod(mc, @"getBool:withDefault:",              (IMP)new_getBoolDef,       (IMP *)&orig_getBoolDef,       'B', "PB");
    rygHookMobileConfigMethod(mc, @"getBool:withOptions:",              (IMP)new_getBoolOpts,      (IMP *)&orig_getBoolOpts,      'B', "P@");
    rygHookMobileConfigMethod(mc, @"getBool:withOptions:withDefault:",  (IMP)new_getBoolOptsDef,   (IMP *)&orig_getBoolOptsDef,   'B', "P@B");
    rygHookMobileConfigMethod(mc, @"getInt64:",                         (IMP)new_getInt,           (IMP *)&orig_getInt,           'Q', "P");
    rygHookMobileConfigMethod(mc, @"getInt64:withDefault:",             (IMP)new_getIntDef,        (IMP *)&orig_getIntDef,        'Q', "PQ");
    rygHookMobileConfigMethod(mc, @"getInt64:withOptions:",             (IMP)new_getIntOpts,       (IMP *)&orig_getIntOpts,       'Q', "P@");
    rygHookMobileConfigMethod(mc, @"getInt64:withOptions:withDefault:", (IMP)new_getIntOptsDef,    (IMP *)&orig_getIntOptsDef,    'Q', "P@Q");
    rygHookMobileConfigMethod(mc, @"getDouble:",                        (IMP)new_getDouble,        (IMP *)&orig_getDouble,        'D', "P");
    rygHookMobileConfigMethod(mc, @"getDouble:withDefault:",            (IMP)new_getDoubleDef,     (IMP *)&orig_getDoubleDef,     'D', "PD");
    rygHookMobileConfigMethod(mc, @"getDouble:withOptions:",            (IMP)new_getDoubleOpts,    (IMP *)&orig_getDoubleOpts,    'D', "P@");
    rygHookMobileConfigMethod(mc, @"getDouble:withOptions:withDefault:",(IMP)new_getDoubleOptsDef, (IMP *)&orig_getDoubleOptsDef, 'D', "P@D");
    rygHookMobileConfigMethod(mc, @"getString:",                        (IMP)new_getString,        (IMP *)&orig_getString,        '@', "P");
    rygHookMobileConfigMethod(mc, @"getString:withDefault:",            (IMP)new_getStringDef,     (IMP *)&orig_getStringDef,     '@', "P@");
    rygHookMobileConfigMethod(mc, @"getString:withOptions:",            (IMP)new_getStringOpts,    (IMP *)&orig_getStringOpts,    '@', "P@");
    rygHookMobileConfigMethod(mc, @"getString:withOptions:withDefault:",(IMP)new_getStringOptsDef, (IMP *)&orig_getStringOptsDef, '@', "P@@");
}

static BOOL gRYGMCHookInstallScheduled;

static void rygScheduleMobileConfigHookInstall(void) {
    @synchronized(RYGMobileConfig.class) {
        if (gRYGMCHookInstallScheduled) return;
        gRYGMCHookInstallScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized(RYGMobileConfig.class) { gRYGMCHookInstallScheduled = NO; }
        rygInstallMobileConfigHooks();
    });
}

static void rygMobileConfigImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    rygScheduleMobileConfigHookInstall();
}

%ctor {
    if (![RYGUtils getBoolPref:@"ryg_metaconfig_enabled"]) return;

    // Load the force table BEFORE hooks so the very first reads at launch already
    // see the overrides (IG caches some config values once on boot).
    RYGMobileConfig *e = [RYGMobileConfig shared];

    // Hook only methods whose runtime ABI matches the wrapper exactly. Retry as
    // app frameworks load; an early nil class must not disable this launch.
    rygInstallMobileConfigHooks();
    _dyld_register_func_for_add_image(rygMobileConfigImageDidLoad);

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
