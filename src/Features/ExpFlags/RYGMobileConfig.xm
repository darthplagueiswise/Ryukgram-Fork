#import "RYGMobileConfig.h"
#import "../../Utils.h"
#import "../../Localization/RYGLocalization.h"
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

// The browser model is deliberately the UNION of two independent sources:
//  1. Instagram's live MobileConfig parameter metadata, which is authoritative
//     for paramID/type/runtime access; and
//  2. id_name_mapping, which is authoritative for config/parameter names and
//     can contain entries absent from this iOS build's live parameter table.
// A mapping-only row is visible/searchable, but it is never given a guessed
// type or a fabricated paramID and therefore cannot be toggled/applied.

struct RYGSharedPtr { void *ptr; void *ctrl; ~RYGSharedPtr(); };
RYGSharedPtr::~RYGSharedPtr() {}

static __weak id gManager;
static NSMutableDictionary<NSNumber *, id> *gManagersByUnit;
static NSMutableDictionary<NSNumber *, NSValue *> *gCallSites;
static NSMutableDictionary<NSNumber *, id> *gOverrideValues;
static NSMutableDictionary<NSNumber *, NSNumber *> *gRealPidByOrdIdx;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;

static void *rygSym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

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

    for (uint32_t index = 0; index < header->ncmds; index++) {
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
    for (uint32_t index = 0; index < header->ncmds; index++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if ((segment->initprot & VM_PROT_READ) && segment->vmaddr <= UINTPTR_MAX - slide) {
                uintptr_t segmentStart = slide + (uintptr_t)segment->vmaddr;
                if ((uintptr_t)segment->vmsize <= UINTPTR_MAX - segmentStart) {
                    uintptr_t segmentEnd = segmentStart + (uintptr_t)segment->vmsize;
                    if (start >= segmentStart && end <= segmentEnd) return YES;
                }
            }
        }
        cursor += command->cmdsize;
    }
    return NO;
}

static unsigned long long rygCanonicalPid(unsigned long long pid) {
    if (!pid) return 0;
    unsigned long long type = (pid >> 48) & 0x0F;
    return (pid & 0x0000FFFFFFFFFFFFULL) | ((0x40ULL | type) << 48);
}

static unsigned long long rygVariantPid(unsigned long long pid, unsigned long long base) {
    if (!pid) return 0;
    unsigned long long type = (pid >> 48) & 0x0F;
    return (pid & 0x0000FFFFFFFFFFFFULL) | ((base | type) << 48);
}

static id rygOverrideValue(unsigned long long pid) {
    pthread_mutex_lock(&gLock);
    id value = gOverrideValues ? gOverrideValues[@(pid)] : nil;
    pthread_mutex_unlock(&gLock);
    return value;
}

static void rygSetForce(unsigned long long pid, id value) {
    if (!pid || !value) return;
    pthread_mutex_lock(&gLock);
    if (!gOverrideValues) gOverrideValues = [NSMutableDictionary new];
    gOverrideValues[@(rygVariantPid(pid, 0x40))] = value;
    gOverrideValues[@(rygVariantPid(pid, 0x80))] = value;
    pthread_mutex_unlock(&gLock);
}

static void rygClearForce(unsigned long long pid) {
    if (!pid) return;
    pthread_mutex_lock(&gLock);
    [gOverrideValues removeObjectForKey:@(rygVariantPid(pid, 0x40))];
    [gOverrideValues removeObjectForKey:@(rygVariantPid(pid, 0x80))];
    pthread_mutex_unlock(&gLock);
}

static void rygCaptureManager(id manager, unsigned long long pid) {
    if (!manager || !pid) return;
    gManager = manager;
    unsigned long long unit = (pid >> 48) & 0xF0;
    unsigned int ordinal = (unsigned int)((pid >> 32) & 0xFFFF);
    unsigned int index = (unsigned int)((pid >> 16) & 0xFFFF);
    pthread_mutex_lock(&gLock);
    if (!gManagersByUnit) gManagersByUnit = [NSMutableDictionary new];
    if (!gRealPidByOrdIdx) gRealPidByOrdIdx = [NSMutableDictionary new];
    gManagersByUnit[@(unit)] = manager;
    gRealPidByOrdIdx[@(((unsigned long long)ordinal << 20) | index)] = @(pid);
    pthread_mutex_unlock(&gLock);
}

static void rygRecordCaller(unsigned long long pid) {
    if (!pid) return;
    pthread_mutex_lock(&gLock);
    BOOL alreadyRecorded = gCallSites[@(pid)] != nil;
    pthread_mutex_unlock(&gLock);
    if (alreadyRecorded) return;

    void *frames[6] = {0};
    int count = backtrace(frames, 6);
    if (count <= 3) return;
    pthread_mutex_lock(&gLock);
    if (!gCallSites) gCallSites = [NSMutableDictionary new];
    if (!gCallSites[@(pid)]) gCallSites[@(pid)] = [NSValue valueWithPointer:frames[3]];
    pthread_mutex_unlock(&gLock);
}

#pragma mark - Context manager pass-through hooks

static BOOL (*orig_getBool)(id, SEL, unsigned long long);
static BOOL new_getBool(id self, SEL cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced boolValue] : (orig_getBool ? orig_getBool(self, cmd, pid) : NO);
}
static BOOL (*orig_getBoolDef)(id, SEL, unsigned long long, BOOL);
static BOOL new_getBoolDef(id self, SEL cmd, unsigned long long pid, BOOL def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced boolValue] : (orig_getBoolDef ? orig_getBoolDef(self, cmd, pid, def) : def);
}
static BOOL (*orig_getBoolOpts)(id, SEL, unsigned long long, id);
static BOOL new_getBoolOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced boolValue] : (orig_getBoolOpts ? orig_getBoolOpts(self, cmd, pid, opts) : NO);
}
static BOOL (*orig_getBoolOptsDef)(id, SEL, unsigned long long, id, BOOL);
static BOOL new_getBoolOptsDef(id self, SEL cmd, unsigned long long pid, id opts, BOOL def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced boolValue] : (orig_getBoolOptsDef ? orig_getBoolOptsDef(self, cmd, pid, opts, def) : def);
}

static long long (*orig_getInt)(id, SEL, unsigned long long);
static long long new_getInt(id self, SEL cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced longLongValue] : (orig_getInt ? orig_getInt(self, cmd, pid) : 0);
}
static long long (*orig_getIntDef)(id, SEL, unsigned long long, long long);
static long long new_getIntDef(id self, SEL cmd, unsigned long long pid, long long def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced longLongValue] : (orig_getIntDef ? orig_getIntDef(self, cmd, pid, def) : def);
}
static long long (*orig_getIntOpts)(id, SEL, unsigned long long, id);
static long long new_getIntOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced longLongValue] : (orig_getIntOpts ? orig_getIntOpts(self, cmd, pid, opts) : 0);
}
static long long (*orig_getIntOptsDef)(id, SEL, unsigned long long, id, long long);
static long long new_getIntOptsDef(id self, SEL cmd, unsigned long long pid, id opts, long long def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced longLongValue] : (orig_getIntOptsDef ? orig_getIntOptsDef(self, cmd, pid, opts, def) : def);
}

static double (*orig_getDouble)(id, SEL, unsigned long long);
static double new_getDouble(id self, SEL cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced doubleValue] : (orig_getDouble ? orig_getDouble(self, cmd, pid) : 0.0);
}
static double (*orig_getDoubleDef)(id, SEL, unsigned long long, double);
static double new_getDoubleDef(id self, SEL cmd, unsigned long long pid, double def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced doubleValue] : (orig_getDoubleDef ? orig_getDoubleDef(self, cmd, pid, def) : def);
}
static double (*orig_getDoubleOpts)(id, SEL, unsigned long long, id);
static double new_getDoubleOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced doubleValue] : (orig_getDoubleOpts ? orig_getDoubleOpts(self, cmd, pid, opts) : 0.0);
}
static double (*orig_getDoubleOptsDef)(id, SEL, unsigned long long, id, double);
static double new_getDoubleOptsDef(id self, SEL cmd, unsigned long long pid, id opts, double def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return forced ? [forced doubleValue] : (orig_getDoubleOptsDef ? orig_getDoubleOptsDef(self, cmd, pid, opts, def) : def);
}

static id (*orig_getString)(id, SEL, unsigned long long);
static id new_getString(id self, SEL cmd, unsigned long long pid) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return [forced isKindOfClass:NSString.class] ? forced : (orig_getString ? orig_getString(self, cmd, pid) : nil);
}
static id (*orig_getStringDef)(id, SEL, unsigned long long, id);
static id new_getStringDef(id self, SEL cmd, unsigned long long pid, id def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return [forced isKindOfClass:NSString.class] ? forced : (orig_getStringDef ? orig_getStringDef(self, cmd, pid, def) : def);
}
static id (*orig_getStringOpts)(id, SEL, unsigned long long, id);
static id new_getStringOpts(id self, SEL cmd, unsigned long long pid, id opts) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return [forced isKindOfClass:NSString.class] ? forced : (orig_getStringOpts ? orig_getStringOpts(self, cmd, pid, opts) : nil);
}
static id (*orig_getStringOptsDef)(id, SEL, unsigned long long, id, id);
static id new_getStringOptsDef(id self, SEL cmd, unsigned long long pid, id opts, id def) {
    rygCaptureManager(self, pid); rygRecordCaller(pid);
    id forced = rygOverrideValue(pid);
    return [forced isKindOfClass:NSString.class] ? forced : (orig_getStringOptsDef ? orig_getStringOptsDef(self, cmd, pid, opts, def) : def);
}

#pragma mark - Models

@implementation RYGMCParam
- (NSString *)typeName {
    if (!self.runtimeBacked) return @"mapping";
    switch (self.type) {
        case RYGMCTypeBool: return @"bool";
        case RYGMCTypeInt: return @"int";
        case RYGMCTypeString: return @"string";
        case RYGMCTypeDouble: return @"double";
        case RYGMCTypeUnknown: break;
    }
    return @"unknown";
}
@end

@implementation RYGMCConfig
- (NSString *)displayName {
    return self.name.length ? self.name : [NSString stringWithFormat:@"Config %u", self.number];
}
- (BOOL)hasRuntimeBacking {
    for (RYGMCParam *param in self.params) if (param.runtimeBacked) return YES;
    return NO;
}
@end

#pragma mark - Engine

@interface RYGMobileConfig ()
- (NSString *)mcDirectory;
- (NSDictionary *)loadNameCatalog;
- (NSMutableDictionary *)loadOverrides;
- (NSMutableDictionary *)loadNotes;
- (void)saveOverrides;
- (void)saveNotes;
@end

@implementation RYGMobileConfig {
    NSArray<RYGMCConfig *> *_configs;
    NSMutableDictionary<NSNumber *, id> *_overrides;
    NSMutableDictionary<NSNumber *, NSString *> *_notes;
    BOOL _ready;
    NSUInteger _namedConfigCount;
    int (*_typeFromParam)(unsigned long long);
}

+ (instancetype)shared {
    static RYGMobileConfig *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [RYGMobileConfig new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _overrides = [self loadOverrides];
    _notes = [self loadNotes];
    _typeFromParam = (int (*)(unsigned long long))rygSym("_ZN12mobileconfig17typeFromParameterEy");
    for (NSNumber *key in _overrides) rygSetForce(key.unsignedLongLongValue, _overrides[key]);
    return self;
}

- (BOOL)ready { return _ready; }
- (NSUInteger)namedConfigCount { return _namedConfigCount; }

#pragma mark Name catalog fallback

- (NSDictionary *)loadNameCatalog {
    NSMutableDictionary *catalog = [NSMutableDictionary dictionary];
    [self mergeDiskNamesInto:catalog];
    return catalog.copy;
}

- (NSString *)mcDirectory {
    id manager = gManager;
    SEL selector = @selector(getOverridesTablePath);
    Method method = manager ? class_getInstanceMethod([manager class], selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    if (returnType[0] != '@') return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(manager, selector);
    NSString *base = [value isKindOfClass:NSURL.class] ? [(NSURL *)value path] : [value description];
    if ([base hasPrefix:@"file://"]) base = [[NSURL URLWithString:base] path];
    return base.length ? base.stringByDeletingLastPathComponent : nil;
}

- (void)mergeDiskNamesInto:(NSMutableDictionary *)catalog {
    NSString *directory = [self mcDirectory];
    if (!directory.length) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *subdirectory in @[@"", @"sessionless.data"]) {
        NSString *candidate = subdirectory.length ? [directory stringByAppendingPathComponent:subdirectory] : directory;
        for (NSString *name in [fm contentsOfDirectoryAtPath:candidate error:nil]) {
            if ([name isEqualToString:@"id_name_mapping.json"] || [name hasPrefix:@"mc_sync_response_dump"]) {
                [files addObject:[candidate stringByAppendingPathComponent:name]];
            }
        }
    }

    for (NSString *path in files) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data.length) continue;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *entries = nil;
        if ([json isKindOfClass:NSArray.class]) entries = json;
        else if ([json isKindOfClass:NSDictionary.class]) {
            id names = json[@"id_to_names"];
            if ([names isKindOfClass:NSArray.class]) entries = names;
            else if ([names isKindOfClass:NSString.class] && [names length]) entries = @[names];
        }
        for (id rawEntry in entries) {
            if (![rawEntry isKindOfClass:NSString.class]) continue;
            NSArray<NSString *> *parts = [(NSString *)rawEntry componentsSeparatedByString:@":"];
            if (parts.count < 2) continue;
            unsigned long long rawConfig = strtoull(parts[0].UTF8String, NULL, 10);
            if (!rawConfig || rawConfig > UINT32_MAX) continue;
            NSNumber *configKey = @((unsigned int)rawConfig);
            NSDictionary *old = [catalog[configKey] isKindOfClass:NSDictionary.class] ? catalog[configKey] : nil;
            NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:
                [old[@"params"] isKindOfClass:NSDictionary.class] ? old[@"params"] : @{}];
            for (NSUInteger index = 2; index + 1 < parts.count; index += 2) {
                unsigned long long rawParam = strtoull(parts[index].UTF8String, NULL, 10);
                if (rawParam > UINT32_MAX) continue;
                if (parts[index + 1].length) params[@((unsigned int)rawParam)] = parts[index + 1];
            }
            NSString *configName = parts[1].length ? parts[1] : old[@"name"];
            catalog[configKey] = @{@"name": configName ?: @"", @"params": params.copy};
        }
    }
}

#pragma mark Runtime metadata enumeration

- (const char *)paramsArrayStride:(size_t *)stride count:(size_t *)count {
    void *listSymbol = rygSym("_ZN12mobileconfig23kMobileConfigParamsListE");
    void *sizeSymbol = rygSym("_ZN12mobileconfig23kMobileConfigParamsSizeE");
    if (!rygImageRangeIsReadable(listSymbol, sizeof(void *) * 8) ||
        !rygImageRangeIsReadable(sizeSymbol, sizeof(uint32_t) * 4)) return NULL;

    void **candidates = (void **)listSymbol;
    const char *array = NULL;
    size_t foundStride = 0;
    for (int candidateIndex = 0; candidateIndex < 8 && !array; candidateIndex++) {
        const char *possible = (const char *)candidates[candidateIndex];
        if (!rygImageRangeIsReadable(possible, 256)) continue;
        void *first = NULL;
        memcpy(&first, possible, sizeof(first));
        if (!first) continue;
        for (size_t candidateStride = 32; candidateStride <= 128; candidateStride += 8) {
            void *rowFirst = NULL, *rowSecond = NULL;
            memcpy(&rowFirst, possible + candidateStride, sizeof(rowFirst));
            memcpy(&rowSecond, possible + candidateStride + sizeof(void *), sizeof(rowSecond));
            if (rowFirst == first && rowSecond == first) {
                foundStride = candidateStride;
                array = possible;
                break;
            }
        }
    }
    if (!array || !foundStride) return NULL;

    uint32_t sizes[4] = {0};
    memcpy(sizes, sizeSymbol, sizeof(sizes));
    size_t foundCount = 0;
    for (size_t left = 0; left < 4 && !foundCount; left++) {
        if (!sizes[left] || sizes[left] > 200000) continue;
        for (size_t right = left + 1; right < 4; right++) {
            if (sizes[right] == sizes[left]) { foundCount = sizes[left]; break; }
        }
    }
    if (!foundCount) {
        for (size_t index = 0; index < 4; index++) {
            if (sizes[index] && sizes[index] <= 200000) { foundCount = sizes[index]; break; }
        }
    }
    if (!foundCount || foundStride > SIZE_MAX / foundCount ||
        !rygImageRangeIsReadable(array, foundStride * foundCount)) return NULL;
    if (stride) *stride = foundStride;
    if (count) *count = foundCount;
    return array;
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
    _typeFromParam = (int (*)(unsigned long long))rygSym("_ZN12mobileconfig17typeFromParameterEy");
    NSDictionary<NSNumber *, NSDictionary *> *catalog = [self loadNameCatalog] ?: @{};

    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, RYGMCParam *> *> *paramsByConfig = [NSMutableDictionary dictionary];

    size_t stride = 0, count = 0;
    const char *array = [self paramsArrayStride:&stride count:&count];
    if (array && stride && count && _typeFromParam) {
        for (size_t rowIndex = 0; rowIndex < count; rowIndex++) {
            const char *row = array + rowIndex * stride;
            unsigned int ordinalMix = 0, typeSerial = 0, configNumber = 0, paramIndex = 0;
            memcpy(&paramIndex, row + 16, sizeof(paramIndex));
            memcpy(&ordinalMix, row + 20, sizeof(ordinalMix));
            memcpy(&typeSerial, row + 24, sizeof(typeSerial));
            memcpy(&configNumber, row + stride - 4, sizeof(configNumber));
            unsigned int ordinal = ordinalMix & 0xFFFF;
            unsigned int serial = typeSerial & 0xFFFF;
            RYGMCType type = (RYGMCType)(typeSerial >> 16);
            if (!RYGMCTypeIsRuntimeValue(type)) continue;
            unsigned long long pid = [self validParamIDForOrdinal:ordinal index:paramIndex serial:serial type:type];
            if (!pid) continue;

            RYGMCParam *param = [RYGMCParam new];
            param.paramID = pid;
            param.ordinal = ordinal;
            param.configNumber = configNumber;
            param.paramIndex = paramIndex;
            param.type = type;
            param.runtimeBacked = YES;
            NSDictionary *configInfo = catalog[@(configNumber)];
            NSDictionary *mappedParams = [configInfo[@"params"] isKindOfClass:NSDictionary.class] ? configInfo[@"params"] : nil;
            param.name = mappedParams[@(paramIndex)];

            NSNumber *configKey = @(configNumber);
            NSMutableDictionary *bucket = paramsByConfig[configKey];
            if (!bucket) { bucket = [NSMutableDictionary dictionary]; paramsByConfig[configKey] = bucket; }
            bucket[@(paramIndex)] = param;
        }
    }

    [catalog enumerateKeysAndObjectsUsingBlock:^(NSNumber *configKey, NSDictionary *info, BOOL *stop) {
        NSMutableDictionary<NSNumber *, RYGMCParam *> *bucket = paramsByConfig[configKey];
        if (!bucket) { bucket = [NSMutableDictionary dictionary]; paramsByConfig[configKey] = bucket; }
        NSDictionary<NSNumber *, NSString *> *mappedParams = [info[@"params"] isKindOfClass:NSDictionary.class] ? info[@"params"] : @{};
        [mappedParams enumerateKeysAndObjectsUsingBlock:^(NSNumber *paramKey, NSString *name, BOOL *innerStop) {
            RYGMCParam *existing = bucket[paramKey];
            if (existing) {
                if (name.length) existing.name = name;
                return;
            }
            RYGMCParam *param = [RYGMCParam new];
            param.paramID = 0;
            param.ordinal = 0;
            param.configNumber = configKey.unsignedIntValue;
            param.paramIndex = paramKey.unsignedIntValue;
            param.type = RYGMCTypeUnknown;
            param.runtimeBacked = NO;
            param.name = name;
            bucket[paramKey] = param;
        }];
    }];

    NSMutableArray<RYGMCConfig *> *configs = [NSMutableArray arrayWithCapacity:paramsByConfig.count];
    [paramsByConfig enumerateKeysAndObjectsUsingBlock:^(NSNumber *configKey, NSMutableDictionary<NSNumber *, RYGMCParam *> *bucket, BOOL *stop) {
        RYGMCConfig *config = [RYGMCConfig new];
        config.number = configKey.unsignedIntValue;
        NSDictionary *info = catalog[configKey];
        config.name = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : nil;
        config.params = [bucket.allValues sortedArrayUsingComparator:^NSComparisonResult(RYGMCParam *left, RYGMCParam *right) {
            if (left.paramIndex == right.paramIndex) return NSOrderedSame;
            return left.paramIndex < right.paramIndex ? NSOrderedAscending : NSOrderedDescending;
        }];
        [configs addObject:config];
    }];

    [configs sortUsingComparator:^NSComparisonResult(RYGMCConfig *left, RYGMCConfig *right) {
        BOOL leftNamed = left.name.length > 0, rightNamed = right.name.length > 0;
        if (leftNamed != rightNamed) return leftNamed ? NSOrderedAscending : NSOrderedDescending;
        if (leftNamed) {
            NSComparisonResult nameResult = [left.name localizedCaseInsensitiveCompare:right.name];
            if (nameResult != NSOrderedSame) return nameResult;
        }
        if (left.number == right.number) return NSOrderedSame;
        return left.number < right.number ? NSOrderedAscending : NSOrderedDescending;
    }];

    _configs = configs.copy;
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

static NSString *rygNormalize(NSString *string) {
    if (!string.length) return @"";
    NSMutableString *result = [NSMutableString stringWithCapacity:string.length];
    NSString *lowercase = string.lowercaseString;
    for (NSUInteger index = 0; index < lowercase.length; index++) {
        unichar character = [lowercase characterAtIndex:index];
        if ((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9')) [result appendFormat:@"%C", character];
    }
    return result;
}

- (NSArray<RYGMCConfig *> *)configsMatching:(NSString *)query onlyOverridden:(BOOL)onlyOverridden {
    [self prepare];
    NSString *normalized = rygNormalize(query);
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    unsigned long long numeric = trimmed.length ? strtoull(trimmed.UTF8String, NULL, 10) : 0;
    NSMutableArray *matches = [NSMutableArray array];
    for (RYGMCConfig *config in _configs) {
        if (onlyOverridden) {
            BOOL hasOverride = NO;
            for (RYGMCParam *param in config.params) {
                if ([self overrideStateFor:param] == RYGMCOverrideSet) { hasOverride = YES; break; }
            }
            if (!hasOverride) continue;
        }
        if (normalized.length) {
            BOOL hit = [rygNormalize(config.name) containsString:normalized] || (numeric && config.number == numeric);
            if (!hit) {
                for (RYGMCParam *param in config.params) {
                    if ([rygNormalize(param.name) containsString:normalized] ||
                        (numeric && param.paramIndex == numeric) ||
                        (param.paramID && numeric == param.paramID)) { hit = YES; break; }
                }
            }
            if (!hit) continue;
        }
        [matches addObject:config];
    }
    return matches.copy;
}

- (NSArray<NSString *> *)paramsMatching:(NSString *)query inConfig:(RYGMCConfig *)config {
    NSString *normalized = rygNormalize(query);
    if (!normalized.length) return @[];
    NSMutableArray *matches = [NSMutableArray array];
    for (RYGMCParam *param in config.params) {
        if (param.name.length && [rygNormalize(param.name) containsString:normalized]) [matches addObject:param.name];
    }
    return matches.copy;
}

#pragma mark PID + manager routing

- (unsigned long long)bestParamIDFor:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID) return 0;
    pthread_mutex_lock(&gLock);
    NSNumber *real = gRealPidByOrdIdx[@(((unsigned long long)param.ordinal << 20) | param.paramIndex)];
    pthread_mutex_unlock(&gLock);
    return real ? real.unsignedLongLongValue : param.paramID;
}

- (id)managerForPid:(unsigned long long)pid {
    if (!pid) return nil;
    unsigned long long unit = (pid >> 48) & 0xF0;
    pthread_mutex_lock(&gLock);
    id manager = gManagersByUnit[@(unit)];
    pthread_mutex_unlock(&gLock);
    return manager ?: gManager;
}

#pragma mark Live values

- (id)liveValueFor:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID || param.type == RYGMCTypeUnknown) return nil;
    unsigned long long pid = [self bestParamIDFor:param];
    id manager = [self managerForPid:pid];
    if (!manager) return nil;
    switch (param.type) {
        case RYGMCTypeBool:
            if ([manager respondsToSelector:@selector(getBool:)]) return @(((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(manager, @selector(getBool:), pid));
            break;
        case RYGMCTypeInt:
            if ([manager respondsToSelector:@selector(getInt64:)]) return @(((long long (*)(id, SEL, unsigned long long))objc_msgSend)(manager, @selector(getInt64:), pid));
            break;
        case RYGMCTypeString:
            if ([manager respondsToSelector:@selector(getString:)]) {
                id value = ((id (*)(id, SEL, unsigned long long))objc_msgSend)(manager, @selector(getString:), pid);
                return [value isKindOfClass:NSString.class] ? value : nil;
            }
            break;
        case RYGMCTypeDouble:
            if ([manager respondsToSelector:@selector(getDouble:)]) return @(((double (*)(id, SEL, unsigned long long))objc_msgSend)(manager, @selector(getDouble:), pid));
            break;
        case RYGMCTypeUnknown: break;
    }
    return nil;
}

#pragma mark Native overrides

- (void *)overridesTableForPid:(unsigned long long)pid {
    if (!pid) return NULL;
    id manager = [self managerForPid:pid];
    if (!manager) return NULL;

    Ivar ivar = class_getInstanceVariable([manager class], "_configManager");
    if (!ivar) return NULL;
    void *cppManager = NULL;
    memcpy(&cppManager, (char *)(__bridge void *)manager + ivar_getOffset(ivar), sizeof(cppManager));
    void *function = rygSym("_ZN12mobileconfig21FBMobileConfigManager25getOrCreateOverridesTableEb");
    if (!cppManager || !function || !rygImageRangeIsReadable(function, 4)) return NULL;
    typedef RYGSharedPtr (*Fn)(void *, bool);
    RYGSharedPtr table = ((Fn)function)(cppManager, true);
    return table.ptr;
}

- (RYGMCOverrideState)overrideStateFor:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID) return RYGMCOverrideNone;
    return _overrides[@(rygCanonicalPid(param.paramID))] ? RYGMCOverrideSet : RYGMCOverrideNone;
}

- (id)overrideValueFor:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID) return nil;
    return _overrides[@(rygCanonicalPid(param.paramID))];
}

- (BOOL)writeNativeForPid:(unsigned long long)pid value:(id)value type:(RYGMCType)type {
    if (!pid || !RYGMCTypeIsRuntimeValue(type)) return NO;
    void *table = [self overridesTableForPid:pid];
    if (!table) return NO;
    switch (type) {
        case RYGMCTypeBool: {
            void *function = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEybb");
            if (!function) return NO;
            ((void (*)(void *, unsigned long long, bool, bool))function)(table, pid, [value boolValue], false);
            return YES;
        }
        case RYGMCTypeInt: {
            void *function = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyxb");
            if (!function) return NO;
            ((void (*)(void *, unsigned long long, long long, bool))function)(table, pid, [value longLongValue], false);
            return YES;
        }
        case RYGMCTypeString: {
            void *function = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEyRKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEEb");
            if (!function) return NO;
            std::string stringValue([value description].UTF8String ?: "");
            ((void (*)(void *, unsigned long long, const std::string &, bool))function)(table, pid, stringValue, false);
            return YES;
        }
        case RYGMCTypeDouble: {
            void *function = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22updateOverrideForParamEydb");
            if (!function) return NO;
            ((void (*)(void *, unsigned long long, double, bool))function)(table, pid, [value doubleValue], false);
            return YES;
        }
        case RYGMCTypeUnknown: return NO;
    }
    return NO;
}

- (void)writeNativeBothUnitsForPid:(unsigned long long)pid value:(id)value type:(RYGMCType)type {
    [self writeNativeForPid:rygVariantPid(pid, 0x40) value:value type:type];
    [self writeNativeForPid:rygVariantPid(pid, 0x80) value:value type:type];
}

- (void)removeNativeBothUnitsForPid:(unsigned long long)pid {
    if (!pid) return;
    void *function = rygSym("_ZN12mobileconfig28FBMobileConfigOverridesTable22removeOverrideForParamEyb");
    if (!function) return;
    for (unsigned long long base = 0x40; base <= 0x80; base += 0x40) {
        unsigned long long variant = rygVariantPid(pid, base);
        void *table = [self overridesTableForPid:variant];
        if (table) ((void (*)(void *, unsigned long long, bool))function)(table, variant, false);
    }
}

- (void)reapplyOverridesToNativeTable {
    for (NSNumber *key in _overrides.copy) {
        unsigned long long pid = key.unsignedLongLongValue;
        RYGMCType type = (RYGMCType)((pid >> 48) & 0x0F);
        if (!RYGMCTypeIsRuntimeValue(type)) continue;
        [self writeNativeBothUnitsForPid:pid value:_overrides[key] type:type];
    }
}

- (BOOL)setOverride:(id)value for:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID || !RYGMCTypeIsRuntimeValue(param.type)) return NO;
    BOOL validValue = param.type == RYGMCTypeString ? [value isKindOfClass:NSString.class] : [value isKindOfClass:NSNumber.class];
    if (!validValue) return NO;
    unsigned long long canonical = rygCanonicalPid(param.paramID);
    [self writeNativeBothUnitsForPid:canonical value:value type:param.type];
    rygSetForce(canonical, value);
    _overrides[@(canonical)] = value;
    [self saveOverrides];
    return YES;
}

- (void)clearOverrideFor:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID) return;
    unsigned long long canonical = rygCanonicalPid(param.paramID);
    [self removeNativeBothUnitsForPid:canonical];
    rygClearForce(canonical);
    [_overrides removeObjectForKey:@(canonical)];
    [self saveOverrides];
}

- (void)resetOverridesForConfig:(RYGMCConfig *)config {
    for (RYGMCParam *param in config.params) if ([self overrideStateFor:param] == RYGMCOverrideSet) [self clearOverrideFor:param];
}

- (NSUInteger)overrideCount { return _overrides.count; }

- (void)resetAllOverrides {
    for (NSNumber *key in _overrides.allKeys.copy) {
        [self removeNativeBothUnitsForPid:key.unsignedLongLongValue];
        rygClearForce(key.unsignedLongLongValue);
    }
    [_overrides removeAllObjects];
    [self saveOverrides];
}

#pragma mark Runtime observation

- (NSString *)callSiteFor:(RYGMCParam *)param {
    if (!param.runtimeBacked || !param.paramID) return nil;
    unsigned long long best = [self bestParamIDFor:param];
    pthread_mutex_lock(&gLock);
    NSValue *value = gCallSites[@(best)] ?: gCallSites[@(rygVariantPid(param.paramID, 0x40))] ?: gCallSites[@(rygVariantPid(param.paramID, 0x80))];
    pthread_mutex_unlock(&gLock);
    if (!value) return nil;
    Dl_info info = {0};
    if (dladdr(value.pointerValue, &info) && info.dli_sname) return [NSString stringWithUTF8String:info.dli_sname];
    return nil;
}

- (NSNumber *)noteKeyForParam:(RYGMCParam *)param {
    if (param.runtimeBacked && param.paramID) return @(param.paramID);
    return @(((unsigned long long)param.configNumber << 32) | param.paramIndex);
}

- (NSString *)noteFor:(RYGMCParam *)param { return _notes[[self noteKeyForParam:param]]; }
- (void)setNote:(NSString *)note for:(RYGMCParam *)param {
    NSNumber *key = [self noteKeyForParam:param];
    if (note.length) _notes[key] = note; else [_notes removeObjectForKey:key];
    [self saveNotes];
}

#pragma mark Persistence

- (NSString *)storePathFor:(NSString *)name {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"RyukGram"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:name];
}

- (NSMutableDictionary *)loadOverrides {
    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:[self storePathFor:@"mc_overrides.plist"]];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id rawKey in disk) {
        if (![rawKey isKindOfClass:NSString.class]) continue;
        unsigned long long pid = strtoull([(NSString *)rawKey UTF8String], NULL, 10);
        RYGMCType type = (RYGMCType)((pid >> 48) & 0x0F);
        id value = disk[rawKey];
        BOOL valid = type == RYGMCTypeString ? [value isKindOfClass:NSString.class] : [value isKindOfClass:NSNumber.class];
        if (pid && RYGMCTypeIsRuntimeValue(type) && valid) result[@(rygCanonicalPid(pid))] = value;
    }
    return result;
}

- (void)saveOverrides {
    NSMutableDictionary *disk = [NSMutableDictionary dictionary];
    for (NSNumber *key in _overrides) disk[key.stringValue] = _overrides[key];
    [disk writeToFile:[self storePathFor:@"mc_overrides.plist"] atomically:YES];
}

- (NSMutableDictionary *)loadNotes {
    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:[self storePathFor:@"mc_notes.plist"]];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id rawKey in disk) {
        id value = disk[rawKey];
        if (![rawKey isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]) continue;
        unsigned long long key = strtoull([(NSString *)rawKey UTF8String], NULL, 10);
        if (key) result[@(key)] = value;
    }
    return result;
}

- (void)saveNotes {
    NSMutableDictionary *disk = [NSMutableDictionary dictionary];
    for (NSNumber *key in _notes) disk[key.stringValue] = _notes[key];
    [disk writeToFile:[self storePathFor:@"mc_notes.plist"] atomically:YES];
}

- (BOOL)consumeCrashLoopFlag {
    NSString *path = [self storePathFor:@"mc_launch.plist"];
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    NSInteger pending = [state[@"pending"] integerValue] + 1;
    BOOL loop = pending >= 3;
    if (loop) {
        if (_overrides.count) [self resetAllOverrides];
        pending = 0;
    }
    state[@"pending"] = @(pending);
    [state writeToFile:path atomically:YES];
    return loop;
}

- (void)markLaunchStable {
    NSString *path = [self storePathFor:@"mc_launch.plist"];
    NSMutableDictionary *state = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    state[@"pending"] = @0;
    [state writeToFile:path atomically:YES];
}

@end

#pragma mark - Hook installation

static const char *rygMCUnqualifiedType(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL rygMCTypeMatches(const char *raw, char expected) {
    const char *type = rygMCUnqualifiedType(raw);
    if (!type || !*type) return NO;
    switch (expected) {
        case 'P': return *type == 'Q' || *type == 'q' || (*type == '{' && (strstr(type, "=Q}") || strstr(type, "=q}")));
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

static BOOL rygHookMobileConfigMethod(Class cls, NSString *name, IMP replacement, IMP *original, char returnType, const char *arguments) {
    if (!cls || !replacement || !original || *original) return original && *original != NULL;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(cls, selector);
    if (!rygMCMethodMatches(method, returnType, arguments)) return NO;
    MSHookMessageEx(cls, selector, replacement, original);
    return *original != NULL;
}

static NSUInteger rygMobileConfigMethodScore(Class cls) {
    if (!cls) return 0;
    NSUInteger score = 0;
    for (NSString *name in @[@"getBool:", @"getInt64:", @"getDouble:", @"getString:"]) {
        if (class_getInstanceMethod(cls, NSSelectorFromString(name))) score++;
    }
    return score;
}

static void rygInstallMobileConfigHooks(void) {
    Class fb = NSClassFromString(@"FBMobileConfigContextManager");
    Class ig = NSClassFromString(@"IGMobileConfigContextManager");
    Class cls = rygMobileConfigMethodScore(fb) >= rygMobileConfigMethodScore(ig) ? fb : ig;
    if (!cls) return;

    rygHookMobileConfigMethod(cls, @"getBool:", (IMP)new_getBool, (IMP *)&orig_getBool, 'B', "P");
    rygHookMobileConfigMethod(cls, @"getBool:withDefault:", (IMP)new_getBoolDef, (IMP *)&orig_getBoolDef, 'B', "PB");
    rygHookMobileConfigMethod(cls, @"getBool:withOptions:", (IMP)new_getBoolOpts, (IMP *)&orig_getBoolOpts, 'B', "P@");
    rygHookMobileConfigMethod(cls, @"getBool:withOptions:withDefault:", (IMP)new_getBoolOptsDef, (IMP *)&orig_getBoolOptsDef, 'B', "P@B");
    rygHookMobileConfigMethod(cls, @"getInt64:", (IMP)new_getInt, (IMP *)&orig_getInt, 'Q', "P");
    rygHookMobileConfigMethod(cls, @"getInt64:withDefault:", (IMP)new_getIntDef, (IMP *)&orig_getIntDef, 'Q', "PQ");
    rygHookMobileConfigMethod(cls, @"getInt64:withOptions:", (IMP)new_getIntOpts, (IMP *)&orig_getIntOpts, 'Q', "P@");
    rygHookMobileConfigMethod(cls, @"getInt64:withOptions:withDefault:", (IMP)new_getIntOptsDef, (IMP *)&orig_getIntOptsDef, 'Q', "P@Q");
    rygHookMobileConfigMethod(cls, @"getDouble:", (IMP)new_getDouble, (IMP *)&orig_getDouble, 'D', "P");
    rygHookMobileConfigMethod(cls, @"getDouble:withDefault:", (IMP)new_getDoubleDef, (IMP *)&orig_getDoubleDef, 'D', "PD");
    rygHookMobileConfigMethod(cls, @"getDouble:withOptions:", (IMP)new_getDoubleOpts, (IMP *)&orig_getDoubleOpts, 'D', "P@");
    rygHookMobileConfigMethod(cls, @"getDouble:withOptions:withDefault:", (IMP)new_getDoubleOptsDef, (IMP *)&orig_getDoubleOptsDef, 'D', "P@D");
    rygHookMobileConfigMethod(cls, @"getString:", (IMP)new_getString, (IMP *)&orig_getString, '@', "P");
    rygHookMobileConfigMethod(cls, @"getString:withDefault:", (IMP)new_getStringDef, (IMP *)&orig_getStringDef, '@', "P@");
    rygHookMobileConfigMethod(cls, @"getString:withOptions:", (IMP)new_getStringOpts, (IMP *)&orig_getStringOpts, '@', "P@");
    rygHookMobileConfigMethod(cls, @"getString:withOptions:withDefault:", (IMP)new_getStringOptsDef, (IMP *)&orig_getStringOptsDef, '@', "P@@");
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
    (void)header; (void)slide;
    rygScheduleMobileConfigHookInstall();
}

%ctor {
    if (![RYGUtils getBoolPref:@"ryg_metaconfig_enabled"]) return;
    RYGMobileConfig *engine = [RYGMobileConfig shared];
    rygInstallMobileConfigHooks();
    _dyld_register_func_for_add_image(rygMobileConfigImageDidLoad);

    if ([engine consumeCrashLoopFlag]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [RYGUtils showToastForDuration:4.0 title:RYGLocalized(@"MobileConfig overrides were reset after repeated crashes on launch")];
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [engine reapplyOverridesToNativeTable]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [engine markLaunchStable]; });
}
