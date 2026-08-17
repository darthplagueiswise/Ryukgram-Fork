#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#include <stdint.h>
#include <string.h>

static BOOL RYGMCReadableRange(const void *pointer, size_t length) {
    if (!pointer || !length) return NO;
    uintptr_t start = (uintptr_t)pointer;
    if (start > UINTPTR_MAX - length) return NO;
    uintptr_t end = start + length;

    Dl_info info = {0};
    if (!dladdr(pointer, &info) || !info.dli_fbase) return NO;
    const struct mach_header *raw = (const struct mach_header *)info.dli_fbase;
    if (raw->magic != MH_MAGIC_64) return NO;
    const struct mach_header_64 *header = (const struct mach_header_64 *)raw;
    if (!header->sizeofcmds || header->sizeofcmds > 16 * 1024 * 1024 || header->ncmds > 65535) return NO;

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
    if (textVMAddr == UINT64_MAX || (uintptr_t)header < (uintptr_t)textVMAddr) return NO;
    uintptr_t slide = (uintptr_t)header - (uintptr_t)textVMAddr;

    cursor = (const uint8_t *)(header + 1);
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (cursor > commandsEnd || (size_t)(commandsEnd - cursor) < sizeof(struct load_command)) return NO;
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(commandsEnd - cursor)) return NO;
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

static uintptr_t RYGMCComparablePointer(const void *pointer) {
    // Current Instagram app addresses are below the 48-bit userspace boundary.
    // Comparing only the canonical address lets two dyld/PAC encodings of the
    // same target compare equal without ever dereferencing a signed pointer.
    return ((uintptr_t)pointer) & 0x0000FFFFFFFFFFFFULL;
}

static BOOL RYGMCReadPointerPair(const char *row, uintptr_t *first, uintptr_t *second) {
    if (!RYGMCReadableRange(row, 2 * sizeof(void *))) return NO;
    void *a = NULL, *b = NULL;
    memcpy(&a, row, sizeof(a));
    memcpy(&b, row + sizeof(void *), sizeof(b));
    uintptr_t ca = RYGMCComparablePointer(a), cb = RYGMCComparablePointer(b);
    if (!ca || !cb) return NO;
    if (first) *first = ca;
    if (second) *second = cb;
    return YES;
}

static size_t RYGMCExportedCount(void *sizeSymbol) {
    if (!RYGMCReadableRange(sizeSymbol, 4 * sizeof(uint32_t))) return 0;
    uint32_t raw[4] = {0};
    memcpy(raw, sizeSymbol, sizeof(raw));
    for (NSUInteger i = 0; i < 4; i++) {
        if (!raw[i] || raw[i] > 200000) continue;
        for (NSUInteger j = i + 1; j < 4; j++) if (raw[j] == raw[i]) return raw[i];
    }
    for (NSUInteger i = 0; i < 4; i++) if (raw[i] && raw[i] <= 200000) return raw[i];
    return 0;
}

@implementation RYGMobileConfig (RYGParamTableCompatibility)

- (const char *)ryg_complete_paramsArrayStride:(size_t *)stride count:(size_t *)count {
    void *listSymbol = dlsym(RTLD_DEFAULT, "_ZN12mobileconfig23kMobileConfigParamsListE");
    void *sizeSymbol = dlsym(RTLD_DEFAULT, "_ZN12mobileconfig23kMobileConfigParamsSizeE");
    size_t rowCount = RYGMCExportedCount(sizeSymbol);
    if (!rowCount || !RYGMCReadableRange(listSymbol, 8 * sizeof(void *))) {
        return [self ryg_complete_paramsArrayStride:stride count:count];
    }

    void *candidates[8] = {0};
    memcpy(candidates, listSymbol, sizeof(candidates));
    for (NSUInteger candidateIndex = 0; candidateIndex < 8; candidateIndex++) {
        uintptr_t tableAddress = RYGMCComparablePointer(candidates[candidateIndex]);
        const char *table = tableAddress ? (const char *)tableAddress : NULL;
        if (!RYGMCReadableRange(table, 160)) continue;

        uintptr_t firstA = 0, firstB = 0;
        if (!RYGMCReadPointerPair(table, &firstA, &firstB)) continue;

        // The 2026-08-17 FBSharedFramework supplied for this branch exposes
        // 34,990 descriptors with a 40-byte row. Keep this generic by scanning
        // plausible aligned strides and validating the complete first pointer
        // pair rather than relying on one hard-coded stride.
        for (size_t candidateStride = 32; candidateStride <= 128; candidateStride += 8) {
            uintptr_t nextA = 0, nextB = 0;
            if (!RYGMCReadPointerPair(table + candidateStride, &nextA, &nextB)) continue;
            if (nextA != firstA || nextB != firstB) continue;
            if (candidateStride > SIZE_MAX / rowCount ||
                !RYGMCReadableRange(table, candidateStride * rowCount)) continue;
            if (stride) *stride = candidateStride;
            if (count) *count = rowCount;
            return table;
        }
    }

    // Compatible fallback for a future layout that fails the stricter pair
    // validation. The previous scanner remains available but no longer wins for
    // the current 40-byte table.
    return [self ryg_complete_paramsArrayStride:stride count:count];
}

@end

__attribute__((constructor(65480))) static void RYGInstallMobileConfigParamTableCompatibility(void) {
    Class cls = RYGMobileConfig.class;
    SEL originalSelector = NSSelectorFromString(@"paramsArrayStride:count:");
    SEL replacementSelector = @selector(ryg_complete_paramsArrayStride:count:);
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
