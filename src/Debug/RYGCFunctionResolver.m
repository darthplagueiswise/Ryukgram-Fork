#import "RYGCFunctionResolver.h"
#import "../../modules/fishhook/fishhook.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <os/lock.h>
#include <stdint.h>
#include <string.h>

static NSString *const RYGCFunctionErrorDomain = @"com.ryukgram.runtime.cfunctions";
static os_unfair_lock gRYGCBindingLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, id> *gRYGCBindings;
static NSMutableDictionary<NSString *, NSArray<RYGCFunctionRow *> *> *gRYGCFunctionCache;

static NSString *RYGCCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGCImageInfo(NSString *path, const struct mach_header_64 **headerOut, intptr_t *slideOut) {
    NSString *wanted = RYGCCanonicalPath(path);
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *loaded = RYGCCanonicalPath([NSString stringWithUTF8String:raw]);
        if (![loaded isEqualToString:wanted]) continue;
        const struct mach_header *header = _dyld_get_image_header(index);
        if (!header || header->magic != MH_MAGIC_64) return NO;
        if (headerOut) *headerOut = (const struct mach_header_64 *)header;
        if (slideOut) *slideOut = _dyld_get_image_vmaddr_slide(index);
        return YES;
    }
    return NO;
}

static NSString *RYGCUUIDForHeader(const struct mach_header_64 *header) {
    if (!header || !header->ncmds || header->sizeofcmds > 64 * 1024 * 1024) return nil;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (cursor + sizeof(struct load_command) > end) return nil;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) return nil;
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uuid = (const struct uuid_command *)cursor;
            const unsigned char *u = uuid->uuid;
            return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                    u[0],u[1],u[2],u[3],u[4],u[5],u[6],u[7],u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15]];
        }
        cursor += command->cmdsize;
    }
    return nil;
}

static BOOL RYGCIsBL(uint32_t instruction, uint64_t pc, uint64_t target) {
    if ((instruction & 0xFC000000u) != 0x94000000u) return NO;
    int64_t immediate = (int64_t)(instruction & 0x03FFFFFFu);
    if (immediate & 0x02000000LL) immediate |= ~0x03FFFFFFLL;
    uint64_t destination = (uint64_t)((int64_t)pc + (immediate << 2));
    return destination == target;
}

static BOOL RYGCIsW0CBZ(uint32_t instruction) {
    // CBZ/CBNZ W0/X0. sf is intentionally ignored; both consume x0/w0 as a
    // zero/non-zero predicate and are safe evidence for a 0/1 replacement.
    return (instruction & 0x1Fu) == 0 && (instruction & 0x7E000000u) == 0x34000000u;
}

static BOOL RYGCIsW0TBZ(uint32_t instruction) {
    // TBZ/TBNZ W0/X0, any tested bit. This is still predicate consumption, but
    // only bit 0 is accepted below because Force On returns exactly 1.
    if ((instruction & 0x1Fu) != 0 || (instruction & 0x7E000000u) != 0x36000000u) return NO;
    unsigned bit = ((instruction >> 19) & 0x1Fu) | ((instruction >> 26) & 0x20u);
    return bit == 0;
}

static BOOL RYGCIsCMPW0Immediate(uint32_t instruction) {
    // CMP W0/X0, #imm is SUBS WZR/XZR, W0/X0, #imm. Only compare-to-zero is
    // accepted; a following conditional branch then proves boolean use.
    if ((instruction & 0x7F0003FFu) != 0x7100001Fu) return NO;
    unsigned immediate = (instruction >> 10) & 0xFFFu;
    unsigned shift = (instruction >> 22) & 1u;
    return immediate == 0 && shift == 0;
}

static BOOL RYGCIsConditionalBranch(uint32_t instruction) {
    return (instruction & 0xFF000010u) == 0x54000000u;
}

static BOOL RYGCCallConsumesPredicate(const uint32_t *instructions, size_t instructionCount, size_t callIndex) {
    if (!instructions || callIndex + 1 >= instructionCount) return NO;
    for (size_t offset = 1; offset <= 3 && callIndex + offset < instructionCount; offset++) {
        uint32_t instruction = instructions[callIndex + offset];
        if (instruction == 0xD503201Fu) continue; // NOP
        if (RYGCIsW0CBZ(instruction) || RYGCIsW0TBZ(instruction)) return YES;
        if (RYGCIsCMPW0Immediate(instruction)) {
            for (size_t branchOffset = offset + 1; branchOffset <= offset + 2 && callIndex + branchOffset < instructionCount; branchOffset++) {
                uint32_t branch = instructions[callIndex + branchOffset];
                if (branch == 0xD503201Fu) continue;
                return RYGCIsConditionalBranch(branch);
            }
        }
        return NO;
    }
    return NO;
}

typedef struct {
    NSUInteger directCalls;
    NSUInteger predicateCalls;
} RYGCCallEvidence;

static RYGCCallEvidence RYGCEvidenceForStub(const struct mach_header_64 *header, intptr_t slide, uint64_t stubAddress) {
    RYGCCallEvidence evidence = {0, 0};
    if (!header || !stubAddress) return evidence;
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            const struct section_64 *section = (const struct section_64 *)(segment + 1);
            for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++) {
                uint32_t attributes = section[sectionIndex].flags;
                BOOL executable = (attributes & (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS)) != 0;
                if (!executable || !section[sectionIndex].size || section[sectionIndex].size > 1024ULL * 1024ULL * 1024ULL) continue;
                const uint32_t *instructions = (const uint32_t *)((uintptr_t)slide + (uintptr_t)section[sectionIndex].addr);
                size_t count = (size_t)(section[sectionIndex].size / sizeof(uint32_t));
                uint64_t base = (uint64_t)((intptr_t)slide + (intptr_t)section[sectionIndex].addr);
                for (size_t i = 0; i < count; i++) {
                    uint64_t pc = base + i * 4ULL;
                    if (!RYGCIsBL(instructions[i], pc, stubAddress)) continue;
                    evidence.directCalls++;
                    if (RYGCCallConsumesPredicate(instructions, count, i)) evidence.predicateCalls++;
                }
            }
        }
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) break;
        cursor += command->cmdsize;
    }
    return evidence;
}

@interface RYGCFunctionBinding : NSObject
@property (nonatomic, copy) NSString *identity;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *fishhookName;
@property (nonatomic, assign) void *original;
@property (nonatomic, strong) NSNumber *forcedValue;
@end
@implementation RYGCFunctionBinding @end

@implementation RYGCFunctionRow
- (NSString *)identity {
    return [NSString stringWithFormat:@"C|%@|%@|predicate-v1", self.imageUUID ?: @"", self.symbolName ?: @""];
}
- (NSNumber *)overrideValue { return [RYGCFunctionResolver overrideForFunction:self]; }
@end

static uintptr_t RYGCForceFalse(void) { return 0; }
static uintptr_t RYGCForceTrue(void) { return 1; }

static RYGCFunctionBinding *RYGCBindingForIdentity(NSString *identity) {
    if (!identity.length) return nil;
    os_unfair_lock_lock(&gRYGCBindingLock);
    RYGCFunctionBinding *binding = gRYGCBindings[identity];
    os_unfair_lock_unlock(&gRYGCBindingLock);
    return binding;
}

static BOOL RYGCRebind(NSString *imagePath, NSString *fishhookName, void *replacement, void **replaced) {
    const struct mach_header_64 *header = NULL;
    intptr_t slide = 0;
    if (!RYGCImageInfo(imagePath, &header, &slide) || !header || !fishhookName.length || !replacement) return NO;
    struct rebinding rebinding = {.name = fishhookName.UTF8String, .replacement = replacement, .replaced = replaced};
    return rebind_symbols_image((void *)header, slide, &rebinding, 1) == 0;
}

@implementation RYGCFunctionResolver

+ (NSArray<RYGCFunctionRow *> *)functionsForImagePath:(NSString *)imagePath {
    NSString *canonical = RYGCCanonicalPath(imagePath);
    @synchronized(self) {
        NSArray *cached = gRYGCFunctionCache[canonical];
        if (cached) return cached;
    }

    const struct mach_header_64 *header = NULL;
    intptr_t slide = 0;
    if (!RYGCImageInfo(canonical, &header, &slide) || !header || !header->ncmds || header->sizeofcmds > 64 * 1024 * 1024) return @[];
    NSString *uuid = RYGCUUIDForHeader(header);
    if (!uuid.length) return @[];

    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (cursor + sizeof(struct load_command) > end) return @[];
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) return @[];
        if (command->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)cursor;
        else if (command->cmd == LC_DYSYMTAB) dysymtab = (const struct dysymtab_command *)cursor;
        else if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if (!strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname))) linkedit = segment;
        }
        cursor += command->cmdsize;
    }
    if (!symtab || !dysymtab || !linkedit || !dysymtab->nindirectsyms || symtab->nsyms > 2000000 || symtab->strsize > 512 * 1024 * 1024) return @[];

    uintptr_t linkeditBase = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(linkeditBase + symtab->symoff);
    const char *strings = (const char *)(linkeditBase + symtab->stroff);
    const uint32_t *indirect = (const uint32_t *)(linkeditBase + dysymtab->indirectsymoff);

    NSMutableDictionary<NSString *, RYGCFunctionRow *> *rows = [NSMutableDictionary dictionary];
    cursor = (const uint8_t *)(header + 1);
    for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            const struct section_64 *section = (const struct section_64 *)(segment + 1);
            for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++) {
                uint32_t type = section[sectionIndex].flags & SECTION_TYPE;
                if (type != S_SYMBOL_STUBS || !section[sectionIndex].reserved2) continue;
                uint64_t stubCount = section[sectionIndex].size / section[sectionIndex].reserved2;
                uint64_t first = section[sectionIndex].reserved1;
                if (first + stubCount > dysymtab->nindirectsyms) continue;
                for (uint64_t stubIndex = 0; stubIndex < stubCount; stubIndex++) {
                    uint32_t symbolIndex = indirect[first + stubIndex];
                    if (symbolIndex & (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS) || symbolIndex >= symtab->nsyms) continue;
                    struct nlist_64 entry = symbols[symbolIndex];
                    if ((entry.n_type & N_TYPE) != N_UNDF || !(entry.n_type & N_EXT) || !entry.n_un.n_strx || entry.n_un.n_strx >= symtab->strsize) continue;
                    const char *rawName = strings + entry.n_un.n_strx;
                    size_t remaining = symtab->strsize - entry.n_un.n_strx;
                    if (!rawName || !*rawName || !memchr(rawName, 0, remaining)) continue;
                    NSString *symbolName = [NSString stringWithUTF8String:rawName];
                    if (!symbolName.length) continue;
                    NSString *fishhookName = [symbolName hasPrefix:@"_"] ? [symbolName substringFromIndex:1] : symbolName;
                    if (!fishhookName.length) continue;

                    uint64_t stubAddress = (uint64_t)((intptr_t)slide + (intptr_t)section[sectionIndex].addr + (intptr_t)(stubIndex * section[sectionIndex].reserved2));
                    RYGCCallEvidence evidence = RYGCEvidenceForStub(header, slide, stubAddress);
                    RYGCFunctionRow *row = rows[symbolName];
                    if (!row) {
                        row = [RYGCFunctionRow new];
                        row.imagePath = canonical;
                        row.imageUUID = uuid;
                        row.symbolName = symbolName;
                        row.fishhookName = fishhookName;
                        row.stubAddress = stubAddress;
                        rows[symbolName] = row;
                    }
                    row.directCallSiteCount += evidence.directCalls;
                    NSUInteger previousPredicates = 0;
                    if (row.evidence.length) {
                        NSArray *parts = [row.evidence componentsSeparatedByString:@"/"];
                        if (parts.count) previousPredicates = (NSUInteger)[parts.firstObject integerValue];
                    }
                    NSUInteger predicates = previousPredicates + evidence.predicateCalls;
                    row.evidence = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)predicates, (unsigned long)row.directCallSiteCount];
                }
            }
        }
        cursor += command->cmdsize;
    }

    NSMutableArray<RYGCFunctionRow *> *result = [NSMutableArray array];
    for (RYGCFunctionRow *row in rows.allValues) {
        NSArray *parts = [row.evidence componentsSeparatedByString:@"/"];
        NSUInteger predicates = parts.count ? (NSUInteger)[parts.firstObject integerValue] : 0;
        row.predicateHookable = row.directCallSiteCount > 0 && predicates == row.directCallSiteCount;
        row.evidence = row.predicateHookable
            ? [NSString stringWithFormat:@"ABI verified: %lu/%lu direct BL call sites consume w0 as predicate", (unsigned long)predicates, (unsigned long)row.directCallSiteCount]
            : (row.directCallSiteCount
                ? [NSString stringWithFormat:@"Inspect only: %lu/%lu direct BL call sites consume w0 as predicate", (unsigned long)predicates, (unsigned long)row.directCallSiteCount]
                : @"Inspect only: no direct BL call sites were resolved for this import stub");
        [result addObject:row];
    }
    [result sortUsingComparator:^NSComparisonResult(RYGCFunctionRow *left, RYGCFunctionRow *right) {
        if (left.predicateHookable != right.predicateHookable) return left.predicateHookable ? NSOrderedAscending : NSOrderedDescending;
        return [left.symbolName localizedCaseInsensitiveCompare:right.symbolName];
    }];

    NSArray *snapshot = result.copy;
    @synchronized(self) {
        if (!gRYGCFunctionCache) gRYGCFunctionCache = [NSMutableDictionary dictionary];
        gRYGCFunctionCache[canonical] = snapshot;
    }
    return snapshot;
}

+ (NSNumber *)overrideForFunction:(RYGCFunctionRow *)function {
    RYGCFunctionBinding *binding = RYGCBindingForIdentity(function.identity);
    return binding.forcedValue;
}

+ (BOOL)setOverride:(NSNumber *)value forFunction:(RYGCFunctionRow *)function error:(NSError **)error {
    if (![function isKindOfClass:RYGCFunctionRow.class] || !function.imagePath.length || !function.imageUUID.length || !function.symbolName.length) return NO;
    const struct mach_header_64 *header = NULL;
    if (!RYGCImageInfo(function.imagePath, &header, NULL) || ![RYGCUUIDForHeader(header) isEqualToString:function.imageUUID]) {
        if (error) *error = [NSError errorWithDomain:RYGCFunctionErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"The owning image changed or is no longer loaded."}];
        return NO;
    }
    if (value && !function.predicateHookable) {
        if (error) *error = [NSError errorWithDomain:RYGCFunctionErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"No safe BOOL-return ABI was proven from all direct call sites; this symbol is inspect-only."}];
        return NO;
    }

    NSString *identity = function.identity;
    RYGCFunctionBinding *existing = RYGCBindingForIdentity(identity);
    if (!value) {
        if (!existing) return YES;
        if (!RYGCRebind(existing.imagePath, existing.fishhookName, existing.original, NULL)) {
            if (error) *error = [NSError errorWithDomain:RYGCFunctionErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey:@"Could not restore the original import slot."}];
            return NO;
        }
        os_unfair_lock_lock(&gRYGCBindingLock);
        [gRYGCBindings removeObjectForKey:identity];
        os_unfair_lock_unlock(&gRYGCBindingLock);
        return YES;
    }

    void *replacement = value.boolValue ? (void *)&RYGCForceTrue : (void *)&RYGCForceFalse;
    if (existing) {
        if (!RYGCRebind(existing.imagePath, existing.fishhookName, replacement, NULL)) return NO;
        existing.forcedValue = @(value.boolValue);
        return YES;
    }

    void *original = NULL;
    if (!RYGCRebind(function.imagePath, function.fishhookName, replacement, &original) || !original) {
        if (error) *error = [NSError errorWithDomain:RYGCFunctionErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey:@"fishhook could not rebind this import slot in the selected image."}];
        return NO;
    }
    RYGCFunctionBinding *binding = [RYGCFunctionBinding new];
    binding.identity = identity;
    binding.imagePath = function.imagePath;
    binding.fishhookName = function.fishhookName;
    binding.original = original;
    binding.forcedValue = @(value.boolValue);
    os_unfair_lock_lock(&gRYGCBindingLock);
    if (!gRYGCBindings) gRYGCBindings = [NSMutableDictionary dictionary];
    gRYGCBindings[identity] = binding;
    os_unfair_lock_unlock(&gRYGCBindingLock);
    return YES;
}

+ (void)invalidateImagePath:(NSString *)imagePath {
    NSString *canonical = RYGCCanonicalPath(imagePath);
    @synchronized(self) { [gRYGCFunctionCache removeObjectForKey:canonical]; }
}

@end
