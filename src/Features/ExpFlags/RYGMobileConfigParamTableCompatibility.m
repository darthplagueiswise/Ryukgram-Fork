#import "RYGMobileConfig.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#include <stdint.h>
#include <string.h>

static BOOL RYGMCReadableRange(const void *pointer, size_t length) {
    if (!pointer || !length) return NO;
    mach_vm_address_t wanted = (mach_vm_address_t)(uintptr_t)pointer;
    if (wanted > UINT64_MAX - length) return NO;

    mach_vm_address_t region = wanted;
    mach_vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info = {0};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t kr = mach_vm_region(mach_task_self(), &region, &regionSize,
                                      VM_REGION_BASIC_INFO_64,
                                      (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    if (kr != KERN_SUCCESS || !(info.protection & VM_PROT_READ)) return NO;
    if (wanted < region || wanted - region > regionSize) return NO;
    return length <= regionSize - (wanted - region);
}

static uintptr_t RYGMCComparablePointer(const void *pointer) {
    // Current Instagram app addresses are below the 48-bit userspace boundary.
    // Comparing only the canonical address lets two dyld/PAC encodings of the
    // same target compare equal without ever dereferencing a stripped pointer.
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
        const char *table = (const char *)candidates[candidateIndex];
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
