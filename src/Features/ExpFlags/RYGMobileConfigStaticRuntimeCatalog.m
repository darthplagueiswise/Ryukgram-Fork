#import "RYGMobileConfigStaticRuntimeCatalog.h"
#import "RYGMobileConfig.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>
#include <stdint.h>
#include <string.h>

static const char *RYGMCStaticSymbolName(const char *raw) {
    return raw && raw[0] == '_' ? raw + 1 : raw;
}

static BOOL RYGMCStaticSymbolMatches(const char *raw, const char *wanted) {
    if (!raw || !wanted) return NO;
    if (strcmp(raw, wanted) == 0) return YES;
    const char *trimmed = RYGMCStaticSymbolName(raw);
    return trimmed && strcmp(trimmed, wanted) == 0;
}

static void *RYGMCStaticFindSymbol(const char *wanted) {
    if (!wanted || !*wanted) return NULL;
    void *exported = dlsym(RTLD_DEFAULT, wanted);
    if (exported) return exported;

    for (uint32_t imageIndex = 0; imageIndex < _dyld_image_count(); imageIndex++) {
        const struct mach_header *generic = _dyld_get_image_header(imageIndex);
        if (!generic || generic->magic != MH_MAGIC_64) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)generic;
        const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
        const uint8_t *end = cursor + header->sizeofcmds;
        const struct symtab_command *symtab = NULL;
        const struct segment_command_64 *linkedit = NULL;
        for (uint32_t i = 0; i < header->ncmds; i++) {
            if (cursor + sizeof(struct load_command) > end) break;
            const struct load_command *command = (const struct load_command *)cursor;
            if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) break;
            if (command->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)cursor;
            else if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
                if (!strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname))) linkedit = segment;
            }
            cursor += command->cmdsize;
        }
        if (!symtab || !linkedit || !symtab->nsyms || symtab->nsyms > 2000000 || !symtab->strsize) continue;

        intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
        uintptr_t base = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
        const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
        const char *strings = (const char *)(base + symtab->stroff);
        for (uint32_t i = 0; i < symtab->nsyms; i++) {
            struct nlist_64 entry = symbols[i];
            if ((entry.n_type & N_STAB) || !entry.n_un.n_strx || entry.n_un.n_strx >= symtab->strsize) continue;
            const char *name = strings + entry.n_un.n_strx;
            size_t remaining = symtab->strsize - entry.n_un.n_strx;
            if (!name || !memchr(name, 0, remaining) || !RYGMCStaticSymbolMatches(name, wanted)) continue;
            uint8_t type = entry.n_type & N_TYPE;
            if (type == N_SECT && entry.n_value) return (void *)((uintptr_t)entry.n_value + (uintptr_t)slide);
            if (type == N_ABS && entry.n_value) return (void *)(uintptr_t)entry.n_value;
        }
    }
    return NULL;
}

static BOOL RYGMCStaticRangeReadable(const void *pointer, size_t length) {
    if (!pointer || !length) return NO;
    uintptr_t start = (uintptr_t)pointer;
    if (start > UINTPTR_MAX - length) return NO;
    uintptr_t finish = start + length;
    Dl_info info = {0};
    if (!dladdr(pointer, &info) || !info.dli_fbase) return NO;
    const struct mach_header *generic = (const struct mach_header *)info.dli_fbase;
    if (generic->magic != MH_MAGIC_64) return NO;
    const struct mach_header_64 *header = (const struct mach_header_64 *)generic;
    const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
    const uint8_t *end = cursor + header->sizeofcmds;
    uint64_t textVM = UINT64_MAX;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > end) return NO;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) return NO;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if (!strncmp(segment->segname, SEG_TEXT, sizeof(segment->segname))) textVM = segment->vmaddr;
        }
        cursor += command->cmdsize;
    }
    if (textVM == UINT64_MAX || (uintptr_t)header < textVM) return NO;
    uintptr_t slide = (uintptr_t)header - (uintptr_t)textVM;
    cursor = (const uint8_t *)header + sizeof(*header);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if ((segment->initprot & VM_PROT_READ) && segment->vmaddr <= UINTPTR_MAX - slide) {
                uintptr_t a = slide + (uintptr_t)segment->vmaddr;
                if ((uintptr_t)segment->vmsize <= UINTPTR_MAX - a) {
                    uintptr_t b = a + (uintptr_t)segment->vmsize;
                    if (start >= a && finish <= b) return YES;
                }
            }
        }
        cursor += command->cmdsize;
    }
    return NO;
}

static uintptr_t RYGMCStaticCanonicalPointer(const void *pointer) {
    return ((uintptr_t)pointer) & 0x0000FFFFFFFFFFFFULL;
}

typedef int (*RYGMCStaticTypeFn)(unsigned long long);

static unsigned long long RYGMCStaticValidPID(RYGMCStaticTypeFn typeFn,
                                               unsigned int ordinal,
                                               unsigned int paramIndex,
                                               unsigned int serial,
                                               RYGMCType type) {
    if (!typeFn || !RYGMCTypeIsRuntimeValue(type)) return 0;
    for (unsigned long long base = 0x40; base <= 0x80; base += 0x40) {
        unsigned long long pid = ((base | type) << 48) |
                                 ((unsigned long long)ordinal << 32) |
                                 ((unsigned long long)paramIndex << 16) |
                                 serial;
        if (typeFn(pid) == (int)type) return pid;
    }
    return 0;
}

static size_t RYGMCStaticParamCount(void) {
    void *symbol = RYGMCStaticFindSymbol("_ZN12mobileconfig23kMobileConfigParamsSizeE");
    if (!RYGMCStaticRangeReadable(symbol, 4 * sizeof(uint32_t))) return 0;
    uint32_t raw[4] = {0};
    memcpy(raw, symbol, sizeof(raw));
    for (NSUInteger i = 0; i < 4; i++) if (raw[i] && raw[i] <= 200000)
        for (NSUInteger j = i + 1; j < 4; j++) if (raw[j] == raw[i]) return raw[i];
    for (NSUInteger i = 0; i < 4; i++) if (raw[i] && raw[i] <= 200000) return raw[i];
    return 0;
}

static BOOL RYGMCStaticDescriptorValid(const char *row,
                                        size_t stride,
                                        RYGMCStaticTypeFn typeFn,
                                        BOOL validatePID) {
    if (!row || stride < 40 || !RYGMCStaticRangeReadable(row, stride)) return NO;
    unsigned int paramIndex = 0, ordinalMix = 0, typeSerial = 0;
    memcpy(&paramIndex, row + 16, 4);
    memcpy(&ordinalMix, row + 20, 4);
    memcpy(&typeSerial, row + 24, 4);
    RYGMCType type = (RYGMCType)(typeSerial >> 16);
    if (!RYGMCTypeIsRuntimeValue(type)) return NO;
    if (!validatePID) return YES;
    return RYGMCStaticValidPID(typeFn, ordinalMix & 0xFFFF, paramIndex, typeSerial & 0xFFFF, type) != 0;
}

static const char *RYGMCStaticParamsTable(RYGMCStaticTypeFn typeFn, size_t *strideOut, size_t *countOut) {
    void *listSymbol = RYGMCStaticFindSymbol("_ZN12mobileconfig23kMobileConfigParamsListE");
    size_t rowCount = RYGMCStaticParamCount();
    if (!rowCount || !RYGMCStaticRangeReadable(listSymbol, 8 * sizeof(void *))) return NULL;
    void *slots[8] = {0};
    memcpy(slots, listSymbol, sizeof(slots));
    const size_t samples[] = {0, 1, 2, 7, 31, 127};
    const char *bestTable = NULL;
    size_t bestStride = 0;
    NSUInteger bestScore = 0;
    for (NSUInteger slot = 0; slot < 8; slot++) {
        uintptr_t canonical = RYGMCStaticCanonicalPointer(slots[slot]);
        const char *table = canonical ? (const char *)canonical : NULL;
        if (!RYGMCStaticRangeReadable(table, 256)) continue;
        for (size_t stride = 32; stride <= 128; stride += 8) {
            if (stride > SIZE_MAX / rowCount || !RYGMCStaticRangeReadable(table, stride * rowCount)) continue;
            NSUInteger score = 0, attempted = 0;
            for (NSUInteger s = 0; s < sizeof(samples)/sizeof(samples[0]); s++) {
                if (samples[s] >= rowCount) continue;
                attempted++;
                if (RYGMCStaticDescriptorValid(table + samples[s] * stride, stride, typeFn, YES)) score++;
            }
            if (attempted && score > bestScore) { bestScore = score; bestStride = stride; bestTable = table; }
        }
    }
    if (!bestTable || bestScore < 3) return NULL;
    if (strideOut) *strideOut = bestStride;
    if (countOut) *countOut = rowCount;
    return bestTable;
}

NSArray<RYGMCConfig *> *RYGMCStaticRuntimeConfigs(NSDictionary<NSNumber *, NSDictionary *> *nameCatalog) {
    RYGMCStaticTypeFn typeFn = (RYGMCStaticTypeFn)RYGMCStaticFindSymbol("_ZN12mobileconfig17typeFromParameterEy");
    if (!typeFn) return @[];
    size_t stride = 0, count = 0;
    const char *table = RYGMCStaticParamsTable(typeFn, &stride, &count);
    if (!table || !stride || !count) return @[];

    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, RYGMCParam *> *> *buckets = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < count; i++) {
        const char *row = table + i * stride;
        if (!RYGMCStaticDescriptorValid(row, stride, typeFn, NO)) continue;
        unsigned int paramIndex = 0, ordinalMix = 0, typeSerial = 0, configNumber = 0;
        memcpy(&paramIndex, row + 16, 4);
        memcpy(&ordinalMix, row + 20, 4);
        memcpy(&typeSerial, row + 24, 4);
        memcpy(&configNumber, row + stride - 4, 4);
        RYGMCType type = (RYGMCType)(typeSerial >> 16);
        unsigned int ordinal = ordinalMix & 0xFFFF;
        unsigned int serial = typeSerial & 0xFFFF;
        unsigned long long pid = RYGMCStaticValidPID(typeFn, ordinal, paramIndex, serial, type);
        if (!pid) continue;

        RYGMCParam *param = [RYGMCParam new];
        param.paramID = pid;
        param.ordinal = ordinal;
        param.configNumber = configNumber;
        param.paramIndex = paramIndex;
        param.type = type;
        param.runtimeBacked = YES;
        NSDictionary *info = nameCatalog[@(configNumber)];
        NSDictionary *mapped = [info[@"params"] isKindOfClass:NSDictionary.class] ? info[@"params"] : nil;
        param.name = mapped[@(paramIndex)];
        NSMutableDictionary *bucket = buckets[@(configNumber)];
        if (!bucket) { bucket = [NSMutableDictionary dictionary]; buckets[@(configNumber)] = bucket; }
        bucket[@(paramIndex)] = param;
    }

    NSMutableArray<RYGMCConfig *> *configs = [NSMutableArray arrayWithCapacity:buckets.count];
    [buckets enumerateKeysAndObjectsUsingBlock:^(NSNumber *configKey, NSMutableDictionary<NSNumber *, RYGMCParam *> *bucket, BOOL *stop) {
        (void)stop;
        RYGMCConfig *config = [RYGMCConfig new];
        config.number = configKey.unsignedIntValue;
        NSDictionary *info = nameCatalog[configKey];
        config.name = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : nil;
        config.params = [bucket.allValues sortedArrayUsingComparator:^NSComparisonResult(RYGMCParam *left, RYGMCParam *right) {
            if (left.paramIndex < right.paramIndex) return NSOrderedAscending;
            if (left.paramIndex > right.paramIndex) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        [configs addObject:config];
    }];
    [configs sortUsingComparator:^NSComparisonResult(RYGMCConfig *left, RYGMCConfig *right) {
        if (left.number < right.number) return NSOrderedAscending;
        if (left.number > right.number) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return configs.copy;
}
