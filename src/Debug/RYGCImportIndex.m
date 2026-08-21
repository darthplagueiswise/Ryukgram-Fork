#import "RYGCImportIndex.h"
#import "../../modules/fishhook/fishhook.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <os/lock.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

@implementation RYGCImportSymbol
- (NSNumber *)overrideValue { return [RYGCImportIndex scalarOverrideForSymbol:self]; }
@end

static dispatch_queue_t RYGCImportQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ryukgram.c-import-index", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(queue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static NSMutableDictionary<NSString *, NSArray<RYGCImportSymbol *> *> *gRYGCIndexes;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGCOverrides;
static NSMutableDictionary<NSString *, NSValue *> *gRYGCOriginalPointers;
static os_unfair_lock gRYGCPatchLock = OS_UNFAIR_LOCK_INIT;

static NSString *RYGCCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGCFindImage(NSString *path,
                          const struct mach_header **headerOut,
                          intptr_t *slideOut) {
    NSString *wanted = RYGCCanonicalPath(path);
    if (!wanted.length) return NO;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *candidate = RYGCCanonicalPath([NSString stringWithUTF8String:raw]);
        if (![candidate isEqualToString:wanted]) continue;
        if (headerOut) *headerOut = _dyld_get_image_header(index);
        if (slideOut) *slideOut = _dyld_get_image_vmaddr_slide(index);
        return YES;
    }
    return NO;
}

static NSString *RYGCDisplayName(const char *raw) {
    if (!raw || !*raw) return @"";
    const char *display = raw[0] == '_' && raw[1] ? raw + 1 : raw;
    return [NSString stringWithUTF8String:display] ?: @"";
}

static NSString *RYGCPatchKey(NSString *imagePath, NSString *rawName) {
    return [NSString stringWithFormat:@"%@\n%@", RYGCCanonicalPath(imagePath), rawName ?: @""];
}

static uintptr_t RYGCForceZero(void) { return 0; }
static uintptr_t RYGCForceOne(void) { return 1; }

static NSArray<RYGCImportSymbol *> *RYGCBuildIndex(NSString *imagePath) {
    const struct mach_header *generic = NULL;
    intptr_t slide = 0;
    NSString *canonical = RYGCCanonicalPath(imagePath);
    if (!RYGCFindImage(canonical, &generic, &slide) || !generic || generic->magic != MH_MAGIC_64) return @[];

    const struct mach_header_64 *header = (const struct mach_header_64 *)generic;
    if (!header->sizeofcmds || header->sizeofcmds > 64 * 1024 * 1024 || header->ncmds > 65535) return @[];

    const struct symtab_command *symtabCommand = NULL;
    const struct dysymtab_command *dysymtabCommand = NULL;
    const struct segment_command_64 *linkedit = NULL;
    NSMutableArray<NSValue *> *pointerSections = [NSMutableArray array];

    const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
    const uint8_t *commandsEnd = cursor + header->sizeofcmds;
    for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
        if (cursor + sizeof(struct load_command) > commandsEnd) return @[];
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > commandsEnd) return @[];

        if (command->cmd == LC_SYMTAB) symtabCommand = (const struct symtab_command *)cursor;
        else if (command->cmd == LC_DYSYMTAB) dysymtabCommand = (const struct dysymtab_command *)cursor;
        else if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if (!strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname))) linkedit = segment;
            if (segment->nsects <= 4096 && command->cmdsize >= sizeof(*segment) + segment->nsects * sizeof(struct section_64)) {
                const struct section_64 *sections = (const struct section_64 *)(segment + 1);
                for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++) {
                    uint32_t sectionType = sections[sectionIndex].flags & SECTION_TYPE;
                    if (sectionType == S_LAZY_SYMBOL_POINTERS || sectionType == S_NON_LAZY_SYMBOL_POINTERS) {
                        [pointerSections addObject:[NSValue valueWithPointer:&sections[sectionIndex]]];
                    }
                }
            }
        }
        cursor += command->cmdsize;
    }

    if (!symtabCommand || !dysymtabCommand || !linkedit || !pointerSections.count) return @[];
    if (symtabCommand->nsyms > 2000000 || symtabCommand->strsize > 512 * 1024 * 1024 || dysymtabCommand->nindirectsyms > 4000000) return @[];

    uintptr_t linkeditBase = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(linkeditBase + symtabCommand->symoff);
    const char *strings = (const char *)(linkeditBase + symtabCommand->stroff);
    const uint32_t *indirectSymbols = (const uint32_t *)(linkeditBase + dysymtabCommand->indirectsymoff);

    NSMutableDictionary<NSString *, RYGCImportSymbol *> *byRawName = [NSMutableDictionary dictionary];
    for (NSValue *sectionValue in pointerSections) {
        const struct section_64 *section = (const struct section_64 *)sectionValue.pointerValue;
        if (!section || section->size % sizeof(void *) != 0) continue;
        uint64_t slotCount = section->size / sizeof(void *);
        if (slotCount > 2000000 || section->reserved1 >= dysymtabCommand->nindirectsyms) continue;
        uint32_t sectionType = section->flags & SECTION_TYPE;
        NSString *kind = sectionType == S_LAZY_SYMBOL_POINTERS ? @"lazy import" : @"non-lazy import";

        for (uint64_t slotIndex = 0; slotIndex < slotCount; slotIndex++) {
            uint64_t indirectIndexOffset = (uint64_t)section->reserved1 + slotIndex;
            if (indirectIndexOffset >= dysymtabCommand->nindirectsyms) break;
            uint32_t symbolIndex = indirectSymbols[indirectIndexOffset];
            if (symbolIndex == INDIRECT_SYMBOL_ABS || symbolIndex == INDIRECT_SYMBOL_LOCAL ||
                symbolIndex == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS) || symbolIndex >= symtabCommand->nsyms) continue;

            struct nlist_64 symbolEntry = symbols[symbolIndex];
            uint32_t stringOffset = symbolEntry.n_un.n_strx;
            if (!stringOffset || stringOffset >= symtabCommand->strsize) continue;
            const char *rawName = strings + stringOffset;
            size_t remaining = symtabCommand->strsize - stringOffset;
            if (!rawName || !*rawName || !memchr(rawName, 0, remaining)) continue;
            NSString *raw = [NSString stringWithUTF8String:rawName] ?: @"";
            if (!raw.length) continue;

            uintptr_t slotAddress = (uintptr_t)slide + (uintptr_t)section->addr + slotIndex * sizeof(void *);
            RYGCImportSymbol *row = byRawName[raw];
            if (!row) {
                row = [RYGCImportSymbol new];
                row.imagePath = canonical;
                row.rawName = raw;
                row.name = RYGCDisplayName(rawName);
                row.bindingKind = kind;
                row.firstSlotAddress = slotAddress;
                row.currentTarget = slotAddress ? *(const uintptr_t *)slotAddress : 0;
                row.slotCount = 1;
                byRawName[raw] = row;
            } else {
                row.slotCount += 1;
                if (![row.bindingKind containsString:kind]) row.bindingKind = @"lazy + non-lazy import";
            }
        }
    }

    NSArray<RYGCImportSymbol *> *rows = byRawName.allValues;
    return [rows sortedArrayUsingComparator:^NSComparisonResult(RYGCImportSymbol *left, RYGCImportSymbol *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
}

@implementation RYGCImportIndex

+ (void)requestIndexForImagePath:(NSString *)imagePath completion:(RYGCImportIndexCompletion)completion {
    NSString *requested = [imagePath copy] ?: @"";
    dispatch_async(RYGCImportQueue(), ^{
        if (!gRYGCIndexes) gRYGCIndexes = [NSMutableDictionary dictionary];
        NSString *key = RYGCCanonicalPath(requested);
        NSArray<RYGCImportSymbol *> *rows = gRYGCIndexes[key];
        NSTimeInterval duration = 0;
        if (!rows) {
            NSDate *started = NSDate.date;
            rows = RYGCBuildIndex(requested) ?: @[];
            duration = -started.timeIntervalSinceNow;
            if (key.length) gRYGCIndexes[key] = rows;
        }
        NSArray *snapshot = rows ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(snapshot, duration); });
    });
}

+ (NSArray<RYGCImportSymbol *> *)cachedIndexForImagePath:(NSString *)imagePath {
    __block NSArray *rows = nil;
    NSString *key = RYGCCanonicalPath(imagePath);
    dispatch_sync(RYGCImportQueue(), ^{ rows = gRYGCIndexes[key]; });
    return rows;
}

+ (void)invalidate {
    dispatch_async(RYGCImportQueue(), ^{ [gRYGCIndexes removeAllObjects]; });
}

+ (NSNumber *)scalarOverrideForSymbol:(RYGCImportSymbol *)symbol {
    if (![symbol isKindOfClass:RYGCImportSymbol.class] || !symbol.rawName.length) return nil;
    NSString *key = RYGCPatchKey(symbol.imagePath, symbol.rawName);
    os_unfair_lock_lock(&gRYGCPatchLock);
    NSNumber *value = gRYGCOverrides[key];
    os_unfair_lock_unlock(&gRYGCPatchLock);
    return value;
}

+ (BOOL)setScalarOverride:(NSNumber *)value forSymbol:(RYGCImportSymbol *)symbol error:(NSError **)error {
    if (![symbol isKindOfClass:RYGCImportSymbol.class] || !symbol.rawName.length || !symbol.imagePath.length) {
        if (error) *error = [NSError errorWithDomain:@"com.ryukgram.cimport" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Invalid C import row."}];
        return NO;
    }

    const struct mach_header *header = NULL;
    intptr_t slide = 0;
    if (!RYGCFindImage(symbol.imagePath, &header, &slide) || !header) {
        if (error) *error = [NSError errorWithDomain:@"com.ryukgram.cimport" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Selected Mach-O image is not loaded."}];
        return NO;
    }

    NSString *key = RYGCPatchKey(symbol.imagePath, symbol.rawName);
    NSString *fishhookName = [symbol.rawName hasPrefix:@"_"] ? [symbol.rawName substringFromIndex:1] : symbol.rawName;
    if (!fishhookName.length) return NO;

    os_unfair_lock_lock(&gRYGCPatchLock);
    NSValue *storedOriginal = gRYGCOriginalPointers[key];
    os_unfair_lock_unlock(&gRYGCPatchLock);

    void *capturedOriginal = NULL;
    void *replacement = NULL;
    void **capture = NULL;
    if (value) {
        replacement = value.boolValue ? (void *)&RYGCForceOne : (void *)&RYGCForceZero;
        capture = storedOriginal ? NULL : &capturedOriginal;
    } else {
        replacement = storedOriginal.pointerValue;
        if (!replacement) {
            if (error) *error = [NSError errorWithDomain:@"com.ryukgram.cimport" code:3 userInfo:@{NSLocalizedDescriptionKey:@"No native import pointer was captured for this symbol."}];
            return NO;
        }
    }

    struct rebinding binding = {
        .name = fishhookName.UTF8String,
        .replacement = replacement,
        .replaced = capture,
    };
    int result = rebind_symbols_image((void *)header, slide, &binding, 1);
    if (result != 0) {
        if (error) *error = [NSError errorWithDomain:@"com.ryukgram.cimport" code:4 userInfo:@{NSLocalizedDescriptionKey:@"fishhook could not rebind this import slot."}];
        return NO;
    }

    os_unfair_lock_lock(&gRYGCPatchLock);
    if (!gRYGCOverrides) gRYGCOverrides = [NSMutableDictionary dictionary];
    if (!gRYGCOriginalPointers) gRYGCOriginalPointers = [NSMutableDictionary dictionary];
    if (value) {
        if (!storedOriginal && capturedOriginal) gRYGCOriginalPointers[key] = [NSValue valueWithPointer:capturedOriginal];
        gRYGCOverrides[key] = @(value.boolValue);
    } else {
        [gRYGCOverrides removeObjectForKey:key];
        [gRYGCOriginalPointers removeObjectForKey:key];
    }
    os_unfair_lock_unlock(&gRYGCPatchLock);
    return YES;
}

@end
