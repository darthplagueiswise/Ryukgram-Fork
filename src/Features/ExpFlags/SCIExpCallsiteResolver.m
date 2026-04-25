#import "SCIExpCallsiteResolver.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>

static NSString *RGImageBasename(const char *path) {
    if (!path) return @"?";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"?";
}

static BOOL RGIsPrintableCString(const char *p, uintptr_t lo, uintptr_t hi, NSUInteger *outLen) {
    if (!p) return NO;
    uintptr_t a = (uintptr_t)p;
    if (a < lo || a >= hi) return NO;
    NSUInteger n = 0;
    while (a + n < hi && n < 160) {
        unsigned char c = (unsigned char)p[n];
        if (c == 0) break;
        if (c < 0x20 || c > 0x7e) return NO;
        n++;
    }
    if (n < 6 || n >= 160) return NO;
    if (outLen) *outLen = n;
    return YES;
}

static int64_t RGSignExtend(uint64_t value, int bits) {
    uint64_t m = 1ULL << (bits - 1);
    return (int64_t)((value ^ m) - m);
}

static BOOL RGIsLikelyFunctionPrologue(uint32_t insn) {
    // Common arm64 prologues:
    // stp x29, x30, [sp, #-imm]!
    // sub sp, sp, #imm
    // pacibsp / paciasp followed by frame setup may also appear, so this is approximate.
    if ((insn & 0xFFC003FF) == 0xA98003FD) return YES;
    if ((insn & 0xFFC003FF) == 0xA9A003FD) return YES;
    if ((insn & 0xFF8003FF) == 0xD10003FF) return YES;
    if (insn == 0xD503237F || insn == 0xD503233F) return YES; // pacibsp/paciasp
    return NO;
}

static BOOL RGIsReturnOrBranchEnd(uint32_t insn) {
    if (insn == 0xD65F03C0) return YES; // ret
    if ((insn & 0xFFFFFC1F) == 0xD61F0000) return YES; // br/blr reg, boundary-ish
    return NO;
}

static BOOL RGFindImageAndText(void *addr,
                               const struct mach_header_64 **outHeader,
                               intptr_t *outSlide,
                               NSString **outImageName,
                               uintptr_t *outTextStart,
                               uintptr_t *outTextEnd,
                               uintptr_t *outConstStart,
                               uintptr_t *outConstEnd) {
    uintptr_t target = (uintptr_t)addr;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (!mh || mh->magic != MH_MAGIC_64) continue;
        const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const uint8_t *cmdPtr = (const uint8_t *)(h + 1);
        uintptr_t textStart = 0, textEnd = 0, constStart = 0, constEnd = 0;
        uintptr_t imageMin = UINTPTR_MAX, imageMax = 0;

        for (uint32_t c = 0; c < h->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                uintptr_t segStart = (uintptr_t)(seg->vmaddr + slide);
                uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;
                if (segStart < imageMin) imageMin = segStart;
                if (segEnd > imageMax) imageMax = segEnd;

                const struct section_64 *sec = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    uintptr_t ss = (uintptr_t)(sec[s].addr + slide);
                    uintptr_t se = ss + (uintptr_t)sec[s].size;
                    if (strcmp(sec[s].segname, "__TEXT") == 0 && strcmp(sec[s].sectname, "__text") == 0) {
                        textStart = ss;
                        textEnd = se;
                    }
                    if ((strcmp(sec[s].segname, "__TEXT") == 0 || strcmp(sec[s].segname, "__DATA_CONST") == 0 || strcmp(sec[s].segname, "__DATA") == 0) &&
                        (strcmp(sec[s].sectname, "__cstring") == 0 || strcmp(sec[s].sectname, "__const") == 0 || strcmp(sec[s].sectname, "__objc_methname") == 0 || strcmp(sec[s].sectname, "__objc_classname") == 0)) {
                        if (!constStart || ss < constStart) constStart = ss;
                        if (se > constEnd) constEnd = se;
                    }
                }
            }
            cmdPtr += lc->cmdsize;
        }

        if (target >= imageMin && target < imageMax) {
            if (outHeader) *outHeader = h;
            if (outSlide) *outSlide = slide;
            if (outImageName) *outImageName = RGImageBasename(_dyld_get_image_name(i));
            if (outTextStart) *outTextStart = textStart;
            if (outTextEnd) *outTextEnd = textEnd;
            if (outConstStart) *outConstStart = constStart ? constStart : imageMin;
            if (outConstEnd) *outConstEnd = constEnd ? constEnd : imageMax;
            return YES;
        }
    }
    return NO;
}

static NSString *RGKnownSymbolForAddress(void *addr, uintptr_t functionStart, uintptr_t imageBase, NSString *imageName) {
    Dl_info info;
    memset(&info, 0, sizeof(info));
    if (dladdr(addr, &info) && info.dli_sname && info.dli_saddr) {
        NSString *sym = [NSString stringWithUTF8String:info.dli_sname] ?: @"?";
        uintptr_t off = (uintptr_t)addr - (uintptr_t)info.dli_saddr;
        return [NSString stringWithFormat:@"%@:%@+0x%lx", imageName ?: @"?", sym, (unsigned long)off];
    }
    uintptr_t sub = imageBase ? functionStart - imageBase : functionStart;
    uintptr_t off = (uintptr_t)addr - functionStart;
    return [NSString stringWithFormat:@"%@:sub_%lx+0x%lx", imageName ?: @"?", (unsigned long)sub, (unsigned long)off];
}

static NSArray<NSString *> *RGStringsNearFunction(uintptr_t functionStart,
                                                  uintptr_t functionEnd,
                                                  uintptr_t constStart,
                                                  uintptr_t constEnd) {
    NSMutableOrderedSet<NSString *> *strings = [NSMutableOrderedSet orderedSet];
    if (!functionStart || !functionEnd || functionEnd <= functionStart) return @[];

    uintptr_t maxEnd = functionEnd;
    if (maxEnd - functionStart > 0x3000) maxEnd = functionStart + 0x3000;

    for (uintptr_t pc = functionStart; pc + 4 <= maxEnd; pc += 4) {
        uint32_t insn = *(const uint32_t *)pc;

        // LDR literal, 64-bit or 32-bit: load direct pointer/string-ish value nearby.
        if ((insn & 0x3B000000) == 0x18000000) {
            int rt = insn & 0x1F;
            (void)rt;
            int64_t imm19 = RGSignExtend((insn >> 5) & 0x7FFFF, 19) << 2;
            uintptr_t literalAddr = pc + imm19;
            if (literalAddr >= constStart && literalAddr + sizeof(uintptr_t) <= constEnd) {
                uintptr_t maybePtr = *(const uintptr_t *)literalAddr;
                NSUInteger len = 0;
                if (RGIsPrintableCString((const char *)maybePtr, constStart, constEnd, &len)) {
                    NSString *s = [[NSString alloc] initWithBytes:(const void *)maybePtr length:len encoding:NSASCIIStringEncoding];
                    if (s.length) [strings addObject:s];
                }
            }
        }

        // ADRP + ADD immediate resolves many C string references.
        if ((insn & 0x9F000000) == 0x90000000) {
            uint32_t rd = insn & 0x1F;
            uint64_t immlo = (insn >> 29) & 0x3;
            uint64_t immhi = (insn >> 5) & 0x7FFFF;
            int64_t imm = RGSignExtend((immhi << 2) | immlo, 21) << 12;
            uintptr_t page = (pc & ~0xFFFULL) + imm;

            for (uintptr_t pc2 = pc + 4; pc2 <= pc + 28 && pc2 + 4 <= maxEnd; pc2 += 4) {
                uint32_t next = *(const uint32_t *)pc2;
                uint32_t rn = (next >> 5) & 0x1F;
                uint32_t rd2 = next & 0x1F;
                if (rn != rd || rd2 != rd) continue;

                // ADD Xd, Xn, #imm12{, LSL #12}
                if ((next & 0x7F000000) == 0x11000000) {
                    uint64_t imm12 = (next >> 10) & 0xFFF;
                    if ((next >> 22) & 1) imm12 <<= 12;
                    uintptr_t ptr = page + imm12;
                    NSUInteger len = 0;
                    if (RGIsPrintableCString((const char *)ptr, constStart, constEnd, &len)) {
                        NSString *s = [[NSString alloc] initWithBytes:(const void *)ptr length:len encoding:NSASCIIStringEncoding];
                        if (s.length) [strings addObject:s];
                    }
                }

                // LDR Xt/Wt, [Xn, #imm]
                if ((next & 0xFFC00000) == 0xF9400000 || (next & 0xFFC00000) == 0xB9400000) {
                    uint64_t scale = ((next & 0xFFC00000) == 0xF9400000) ? 8 : 4;
                    uint64_t imm12 = ((next >> 10) & 0xFFF) * scale;
                    uintptr_t literalAddr = page + imm12;
                    if (literalAddr >= constStart && literalAddr + sizeof(uintptr_t) <= constEnd) {
                        uintptr_t maybePtr = *(const uintptr_t *)literalAddr;
                        NSUInteger len = 0;
                        if (RGIsPrintableCString((const char *)maybePtr, constStart, constEnd, &len)) {
                            NSString *s = [[NSString alloc] initWithBytes:(const void *)maybePtr length:len encoding:NSASCIIStringEncoding];
                            if (s.length) [strings addObject:s];
                        }
                    }
                }
            }
        }
    }

    NSArray *all = strings.array;
    if (all.count > 8) return [all subarrayWithRange:NSMakeRange(0, 8)];
    return all;
}

NSString *SCIExpDescribeCallsite(void *rawCallerAddress) {
    if (!rawCallerAddress) return @"unknown";
#if __has_builtin(__builtin_extract_return_addr)
    void *callerAddress = __builtin_extract_return_addr(rawCallerAddress);
#else
    void *callerAddress = rawCallerAddress;
#endif

    const struct mach_header_64 *header = NULL;
    intptr_t slide = 0;
    NSString *image = nil;
    uintptr_t textStart = 0, textEnd = 0, constStart = 0, constEnd = 0;
    if (!RGFindImageAndText(callerAddress, &header, &slide, &image, &textStart, &textEnd, &constStart, &constEnd)) {
        return [NSString stringWithFormat:@"caller=%p", callerAddress];
    }

    uintptr_t imageBase = (uintptr_t)header;
    uintptr_t pc = (uintptr_t)callerAddress;
    uintptr_t scanPC = pc;
    if (scanPC >= 4) scanPC -= 4;
    if (scanPC < textStart) scanPC = textStart;

    uintptr_t backLimit = scanPC > 0x1400 ? scanPC - 0x1400 : textStart;
    if (backLimit < textStart) backLimit = textStart;
    uintptr_t functionStart = textStart;
    for (uintptr_t p = scanPC & ~3ULL; p >= backLimit && p + 4 <= textEnd; p -= 4) {
        uint32_t insn = *(const uint32_t *)p;
        if (RGIsLikelyFunctionPrologue(insn)) { functionStart = p; break; }
        if (p == backLimit || p < 4) break;
    }

    uintptr_t functionEnd = textEnd;
    uintptr_t forwardLimit = functionStart + 0x3000;
    if (forwardLimit > textEnd) forwardLimit = textEnd;
    for (uintptr_t p = scanPC & ~3ULL; p + 4 <= forwardLimit; p += 4) {
        uint32_t insn = *(const uint32_t *)p;
        if (p > scanPC + 4 && RGIsLikelyFunctionPrologue(insn)) { functionEnd = p; break; }
        if (RGIsReturnOrBranchEnd(insn)) { functionEnd = p + 4; break; }
    }

    NSString *symbol = RGKnownSymbolForAddress(callerAddress, functionStart, imageBase, image);
    uintptr_t imageOffset = pc - imageBase;
    uintptr_t functionOffset = pc - functionStart;
    NSArray<NSString *> *strings = RGStringsNearFunction(functionStart, functionEnd, constStart, constEnd);

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:symbol ?: @"unknown"];
    [parts addObject:[NSString stringWithFormat:@"img+0x%lx", (unsigned long)imageOffset]];
    [parts addObject:[NSString stringWithFormat:@"fn+0x%lx", (unsigned long)functionOffset]];
    if (strings.count) [parts addObject:[NSString stringWithFormat:@"near=%@", [strings componentsJoinedByString:@","]]];
    return [parts componentsJoinedByString:@" · "];
}
