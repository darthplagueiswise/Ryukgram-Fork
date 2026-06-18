// SCIRuntimeXrefScanner.m
#import "SCIRuntimeXrefScanner.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/getsect.h>
#import <dlfcn.h>
#import <os/log.h>
#import <stdint.h>
#import <string.h>

#define XLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] Xref " fmt, ##__VA_ARGS__)

@implementation SCIXrefHit
@end

#pragma mark - ARM64 decoders (unit-validated)

// ADRP xRd, #page  → page-aligned PC + (signed imm21 << 12)
static inline int sci_decode_adrp(uint32_t instr, uint64_t pc, int *rd, uint64_t *page) {
    if ((instr & 0x9F000000u) != 0x90000000u) return 0;
    *rd = (int)(instr & 0x1F);
    uint32_t immlo = (instr >> 29) & 0x3;
    uint32_t immhi = (instr >> 5) & 0x7FFFF;
    int64_t imm = (int64_t)((immhi << 2) | immlo);
    if (imm & (1LL << 20)) imm -= (1LL << 21);   // sign-extend 21 bits
    *page = (pc & ~0xFFFULL) + (uint64_t)(imm << 12);
    return 1;
}

// ADD (immediate), 64-bit
static inline int sci_decode_add_imm(uint32_t instr, int *rd, int *rn, uint64_t *imm) {
    if ((instr & 0xFF800000u) != 0x91000000u) return 0;
    *rd = (int)(instr & 0x1F);
    *rn = (int)((instr >> 5) & 0x1F);
    uint64_t imm12 = (instr >> 10) & 0xFFF;
    if ((instr >> 22) & 1) imm12 <<= 12;
    *imm = imm12;
    return 1;
}

// BL #imm  → PC + (signed imm26 << 2)
static inline int sci_decode_bl(uint32_t instr, uint64_t pc, uint64_t *target) {
    if ((instr & 0xFC000000u) != 0x94000000u) return 0;
    int64_t imm26 = instr & 0x3FFFFFF;
    if (imm26 & (1LL << 25)) imm26 -= (1LL << 26);
    *target = pc + (uint64_t)(imm26 << 2);
    return 1;
}

#pragma mark - Image / section resolution

// Resolve the __text bounds (runtime addresses) and short name for the image
// that owns `probeAddress`, or — if imageSubstring is set — the first image
// whose path contains that substring.
//
// Runtime address is computed explicitly as section->addr + slide (robust;
// avoids the getsectiondata slide ambiguity).
static BOOL sci_text_bounds_for(uintptr_t probeAddress, NSString *imageSubstring,
                                const uint32_t **outCode, uint64_t *outBase,
                                size_t *outCount, NSString **outName) {
    // When locating by address, first resolve which image base owns it.
    const void *wantedBase = NULL;
    if (!imageSubstring.length) {
        Dl_info info; memset(&info, 0, sizeof(info));
        if (dladdr((const void *)probeAddress, &info) == 0 || !info.dli_fbase) return NO;
        wantedBase = info.dli_fbase;
    }
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *path = _dyld_get_image_name(i);
        const struct mach_header *raw = _dyld_get_image_header(i);
        if (!path || !raw || raw->magic != MH_MAGIC_64) continue;
        if (imageSubstring.length) {
            if (strstr(path, imageSubstring.UTF8String) == NULL) continue;
        } else if ((const void *)raw != wantedBase) {
            continue; // not the image that owns probeAddress
        }
        const struct mach_header_64 *mh = (const struct mach_header_64 *)raw;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct section_64 *sect = getsectbynamefromheader_64(mh, "__TEXT", "__text");
        if (!sect || sect->size < 8) continue;
        uint64_t textStart = (uint64_t)sect->addr + (uint64_t)slide;
        *outCode = (const uint32_t *)(uintptr_t)textStart;
        *outBase = textStart;
        *outCount = (size_t)(sect->size / 4);
        const char *slash = strrchr(path, '/');
        *outName = [NSString stringWithUTF8String:slash ? slash + 1 : path];
        return YES;
    }
    return NO;
}

#pragma mark - Scan core

static NSArray<SCIXrefHit *> *sci_scan(const uint32_t *code, uint64_t base, size_t count,
                                       uint64_t target, uint64_t budget, int maxHits,
                                       NSString *image, BOOL *outHitBudget) {
    NSMutableArray<SCIXrefHit *> *hits = [NSMutableArray array];
    if (!code || count < 2) { if (outHitBudget) *outHitBudget = NO; return hits; }
    uint64_t scanned = 0;
    BOOL budgetExhausted = NO;
    for (size_t i = 0; i + 1 < count; i++) {
        if (++scanned > budget) { budgetExhausted = YES; break; }
        int rd; uint64_t page;
        if (!sci_decode_adrp(code[i], base + i * 4, &rd, &page)) continue;
        int ard, arn; uint64_t aimm;
        if (!sci_decode_add_imm(code[i + 1], &ard, &arn, &aimm)) continue;
        if (arn != rd) continue;
        if (page + aimm != target) continue;

        // Found a load of `target`. Look forward (bounded) for the bl reader call.
        uint64_t loadPC = base + i * 4;
        for (size_t j = i + 2; j < count && j < i + 18; j++) {
            uint64_t blPC = base + j * 4, blTarget;
            if (!sci_decode_bl(code[j], blPC, &blTarget)) continue;
            SCIXrefHit *h = [SCIXrefHit new];
            h.loadPC = (uintptr_t)loadPC;
            h.callPC = (uintptr_t)blPC;
            h.calleeAddress = (uintptr_t)blTarget;
            h.image = image;
            Dl_info ci; memset(&ci, 0, sizeof(ci));
            if (dladdr((const void *)(uintptr_t)blTarget, &ci) && ci.dli_sname) {
                const char *s = ci.dli_sname;
                h.calleeSymbol = [NSString stringWithUTF8String:(s[0] == '_') ? s + 1 : s];
            }
            Dl_info kr; memset(&kr, 0, sizeof(kr));
            if (dladdr((const void *)(uintptr_t)loadPC, &kr) && kr.dli_sname) {
                const char *s = kr.dli_sname;
                h.callerSymbol = [NSString stringWithUTF8String:(s[0] == '_') ? s + 1 : s];
            }
            [hits addObject:h];
            break; // one consumer per load site is enough
        }
        if (maxHits > 0 && (int)hits.count >= maxHits) break;
    }
    if (outHitBudget) *outHitBudget = budgetExhausted;
    return hits;
}

@implementation SCIRuntimeXrefScanner

+ (uint64_t)defaultBudget { return 6000000ULL; } // ~6M instructions: fast, bounded

+ (NSString *)describeAddress:(uintptr_t)address {
    if (!address) return @"(null)";
    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr((const void *)address, &info) == 0) return [NSString stringWithFormat:@"0x%lx", (unsigned long)address];
    const char *path = info.dli_fname ?: "";
    const char *slash = strrchr(path, '/');
    NSString *img = [NSString stringWithUTF8String:slash ? slash + 1 : path];
    if (info.dli_sname) {
        const char *s = info.dli_sname;
        NSString *sym = [NSString stringWithUTF8String:(s[0] == '_') ? s + 1 : s];
        uintptr_t off = address - (uintptr_t)info.dli_saddr;
        return off ? [NSString stringWithFormat:@"%@`%@+0x%lx", img, sym, (unsigned long)off]
                   : [NSString stringWithFormat:@"%@`%@", img, sym];
    }
    uintptr_t off = address - (uintptr_t)info.dli_fbase;
    return [NSString stringWithFormat:@"%@+0x%lx", img, (unsigned long)off];
}

+ (NSArray<SCIXrefHit *> *)consumersOfAddress:(uintptr_t)targetAddress
                                imageSubstring:(NSString *)imageSubstring
                                        budget:(uint64_t)budget
                                       maxHits:(int)maxHits
                                     hitBudget:(BOOL *)outHitBudget {
    if (!targetAddress) { if (outHitBudget) *outHitBudget = NO; return @[]; }
    const uint32_t *code = NULL; uint64_t base = 0; size_t count = 0; NSString *name = nil;
    if (!sci_text_bounds_for(targetAddress, imageSubstring, &code, &base, &count, &name)) {
        if (outHitBudget) *outHitBudget = NO;
        return @[];
    }
    XLOG("scan target=0x%lx image=%{public}s count=%zu budget=%llu",
         (unsigned long)targetAddress, name.UTF8String ?: "?", count, budget);
    return sci_scan(code, base, count, (uint64_t)targetAddress,
                    budget ?: [self defaultBudget], maxHits, name, outHitBudget);
}

+ (void)findConsumersOfAddress:(uintptr_t)targetAddress
                 imageSubstring:(NSString *)imageSubstring
                         budget:(uint64_t)budget
                        maxHits:(int)maxHits
                     completion:(void (^)(NSArray<SCIXrefHit *> *, BOOL))completion {
    if (!completion) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL hitBudget = NO;
        NSArray<SCIXrefHit *> *hits = [self consumersOfAddress:targetAddress
                                                imageSubstring:imageSubstring
                                                        budget:budget
                                                       maxHits:maxHits
                                                     hitBudget:&hitBudget];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(hits, hitBudget); });
    });
}

@end
