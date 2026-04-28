#import "SCIMachODexKitResolver.h"
#import "SCIExpMobileConfigMapping.h"

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>

@implementation SCIMachODexKitResolvedName
@end

typedef struct {
    uintptr_t start;
    uintptr_t end;
} SCIRange;

static NSString *SCIBaseName(const char *path) {
    if (!path) return @"?";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"?";
}

static BOOL SCIStringHasUsefulToken(NSString *s) {
    if (s.length < 3) return NO;
    NSString *l = s.lowercaseString;

    static NSArray<NSString *> *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokens = @[
            @"ig_", @"fb_", @"fbios", @"mobileconfig", @"experiment", @"config",
            @"dogfood", @"dogfooding", @"employee", @"internal", @"test_user",
            @"quick", @"quicksnap", @"quick_snap", @"snap", @"instants",
            @"notes", @"direct", @"friend", @"map", @"prism", @"homecoming",
            @"launcher", @"enabled", @"eligib", @"gate", @"override"
        ];
    });

    for (NSString *t in tokens) {
        if ([l containsString:t]) return YES;
    }
    return NO;
}

static NSInteger SCIStringScore(NSString *s) {
    if (!s.length) return 0;
    NSString *l = s.lowercaseString;
    NSInteger score = 0;

    if ([l containsString:@"ig_"]) score += 60;
    if ([l containsString:@"quick_snap"] || [l containsString:@"quicksnap"]) score += 50;
    if ([l containsString:@"employee"]) score += 50;
    if ([l containsString:@"dogfood"]) score += 45;
    if ([l containsString:@"internal"]) score += 35;
    if ([l containsString:@"experiment"]) score += 30;
    if ([l containsString:@"enabled"]) score += 20;
    if ([l containsString:@"eligib"]) score += 20;
    if ([l containsString:@"notes"]) score += 15;
    if ([l containsString:@"instants"]) score += 15;
    if ([l containsString:@"prism"]) score += 15;
    if ([l containsString:@"homecoming"]) score += 15;
    if ([l containsString:@"launcher"]) score += 10;

    if (s.length > 140) score -= 50;
    if ([l containsString:@"/"]) score -= 20;
    if ([l containsString:@"http"]) score -= 20;

    return score;
}

static BOOL SCILooksLikeMCSpecifier(unsigned long long value) {
    return value != 0 && ((value >> 56) == 0) && ((value >> 48) != 0);
}

static int64_t SCISignExtend(uint64_t value, int bits) {
    uint64_t m = 1ULL << (bits - 1);
    return (int64_t)((value ^ m) - m);
}

static BOOL SCIIsLikelyFunctionPrologue(uint32_t insn) {
    if ((insn & 0xFFC003FF) == 0xA98003FD) return YES;
    if ((insn & 0xFF8003FF) == 0xD10003FF) return YES;
    if (insn == 0xD503237F || insn == 0xD503233F) return YES;
    return NO;
}

static BOOL SCIIsFunctionEnd(uint32_t insn) {
    if (insn == 0xD65F03C0) return YES;
    if ((insn & 0xFFFFFC1F) == 0xD61F0000) return YES;
    return NO;
}

static BOOL SCIAddrInRanges(uintptr_t addr, NSArray<NSValue *> *ranges) {
    for (NSValue *v in ranges) {
        NSRange r = v.rangeValue;
        uintptr_t s = (uintptr_t)r.location;
        uintptr_t e = s + (uintptr_t)r.length;
        if (addr >= s && addr < e) return YES;
    }
    return NO;
}

static void SCIAddRange(NSMutableArray<NSValue *> *ranges, uintptr_t start, uintptr_t end) {
    if (!start || end <= start) return;
    [ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]];
}

static BOOL SCIReadCStringAt(uintptr_t addr, NSArray<NSValue *> *stringRanges, NSString **outString) {
    if (!addr || !SCIAddrInRanges(addr, stringRanges)) return NO;

    const char *p = (const char *)addr;
    NSUInteger len = 0;

    while (len < 220 && SCIAddrInRanges(addr + len, stringRanges)) {
        unsigned char c = (unsigned char)p[len];
        if (c == 0) break;
        if (c < 0x20 || c > 0x7e) return NO;
        len++;
    }

    if (len < 3 || len >= 220) return NO;

    NSString *s = [[NSString alloc] initWithBytes:p length:len encoding:NSASCIIStringEncoding];
    if (!s.length) return NO;

    if (outString) *outString = s;
    return YES;
}

@interface SCIMachOImageInfo : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) const struct mach_header_64 *header;
@property (nonatomic, assign) intptr_t slide;
@property (nonatomic, assign) uintptr_t base;
@property (nonatomic, assign) uintptr_t minAddress;
@property (nonatomic, assign) uintptr_t maxAddress;
@property (nonatomic, assign) uintptr_t textStart;
@property (nonatomic, assign) uintptr_t textEnd;
@property (nonatomic, assign) uintptr_t linkeditBase;
@property (nonatomic, assign) uintptr_t symoff;
@property (nonatomic, assign) uintptr_t stroff;
@property (nonatomic, assign) uint32_t nsyms;
@property (nonatomic, strong) NSArray<NSValue *> *stringRanges;
@property (nonatomic, strong) NSArray<NSValue *> *dataRanges;

@end

@implementation SCIMachOImageInfo
@end

@interface SCIMachODexKitResolver ()

@property (nonatomic, strong) NSMutableArray<SCIMachOImageInfo *> *images;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *specifierNames;
@property (nonatomic, strong) NSMutableArray<NSString *> *reports;
@property (nonatomic, assign) BOOL didBuild;

@end

@implementation SCIMachODexKitResolver

+ (instancetype)sharedResolver {
    static SCIMachODexKitResolver *r;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        r = [SCIMachODexKitResolver new];
    });
    return r;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _images = [NSMutableArray array];
        _specifierNames = [NSMutableDictionary dictionary];
        _reports = [NSMutableArray array];
    }
    return self;
}

- (void)rebuildIndex {
    @synchronized (self) {
        self.didBuild = NO;
        [self.images removeAllObjects];
        [self.specifierNames removeAllObjects];
        [self.reports removeAllObjects];
    }
    [self buildIndexIfNeeded];
}

- (NSDictionary<NSNumber *, NSString *> *)allKnownSpecifierNames {
    [self buildIndexIfNeeded];
    @synchronized (self) {
        return [self.specifierNames copy];
    }
}

- (NSArray<NSString *> *)reportLines {
    [self buildIndexIfNeeded];
    @synchronized (self) {
        return [self.reports copy];
    }
}

- (SCIMachODexKitResolvedName *)makeResult:(NSString *)name
                                    source:(NSString *)source
                                confidence:(NSString *)confidence
                                 specifier:(unsigned long long)specifier {
    SCIMachODexKitResolvedName *r = [SCIMachODexKitResolvedName new];
    r.name = name ?: @"unknown";
    r.source = source ?: @"unknown";
    r.confidence = confidence ?: @"unknown";
    r.specifier = specifier;
    return r;
}

- (SCIMachODexKitResolvedName *)resolvedNameForSpecifier:(unsigned long long)specifier
                                            functionName:(NSString *)functionName
                                            existingName:(NSString *)existingName
                                           callerAddress:(void *)callerAddress {
    [self buildIndexIfNeeded];

    if (existingName.length &&
        ![existingName isEqualToString:@"unknown"] &&
        ![existingName hasPrefix:@"callsite "] &&
        ![existingName hasPrefix:@"spec_0x"]) {
        return [self makeResult:existingName
                          source:@"hook-provided"
                      confidence:@"exact"
                       specifier:specifier];
    }

    NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:specifier];
    if (mapped.length) {
        return [self makeResult:mapped
                          source:@"SCIExpMobileConfigMapping"
                      confidence:@"exact-map"
                       specifier:specifier];
    }

    NSString *symbolName = nil;
    @synchronized (self) {
        symbolName = self.specifierNames[@(specifier)];
    }

    if (symbolName.length) {
        return [self makeResult:symbolName
                          source:@"Mach-O data symbol"
                      confidence:@"exact-data-symbol"
                       specifier:specifier];
    }

    NSArray<NSString *> *near = [self usefulStringsNearCaller:callerAddress functionStart:NULL functionEnd:NULL image:NULL];
    NSString *best = [self bestStringFromStrings:near];

    NSString *caller = [self callerDescription:callerAddress];
    if (best.length) {
        NSString *name = nil;
        if (caller.length) {
            name = [NSString stringWithFormat:@"%@ · %@ · 0x%016llx", best, functionName ?: @"Gate", specifier];
        } else {
            name = [NSString stringWithFormat:@"%@ · 0x%016llx", best, specifier];
        }

        return [self makeResult:name
                          source:caller.length ? caller : @"callsite-string-xref"
                      confidence:@"callsite-string-xref"
                       specifier:specifier];
    }

    if (caller.length) {
        return [self makeResult:[@"callsite " stringByAppendingString:caller]
                          source:@"caller"
                      confidence:@"callsite-only"
                       specifier:specifier];
    }

    return [self makeResult:[NSString stringWithFormat:@"unknown 0x%016llx", specifier]
                      source:@"raw"
                  confidence:@"raw"
                   specifier:specifier];
}

#pragma mark - Index

- (void)buildIndexIfNeeded {
    @synchronized (self) {
        if (self.didBuild) return;
        self.didBuild = YES;
    }

    [self enumerateImages];
    [self buildSpecifierMapFromDataSymbols];
    [self addHardcodedSafetySpecifiers];

    @synchronized (self) {
        [self.reports addObject:[NSString stringWithFormat:@"[MachODexKit] images=%lu specifierNames=%lu",
                                 (unsigned long)self.images.count,
                                 (unsigned long)self.specifierNames.count]];
    }
}

- (BOOL)shouldIndexImageName:(NSString *)name {
    if (!name.length) return NO;
    NSString *l = name.lowercaseString;

    if ([l containsString:@"instagram"]) return YES;
    if ([l containsString:@"fbsharedframework"]) return YES;
    if ([l containsString:@"fbsharedmodules"]) return YES;
    if ([l containsString:@"sharedmodules"]) return YES;

    return NO;
}

- (void)enumerateImages {
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mhRaw = _dyld_get_image_header(i);
        if (!mhRaw || mhRaw->magic != MH_MAGIC_64) continue;

        NSString *name = SCIBaseName(_dyld_get_image_name(i));
        if (![self shouldIndexImageName:name]) continue;

        const struct mach_header_64 *mh = (const struct mach_header_64 *)mhRaw;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);

        SCIMachOImageInfo *info = [SCIMachOImageInfo new];
        info.name = name;
        info.header = mh;
        info.slide = slide;
        info.base = (uintptr_t)mh;
        info.minAddress = UINTPTR_MAX;
        info.maxAddress = 0;

        NSMutableArray<NSValue *> *stringRanges = [NSMutableArray array];
        NSMutableArray<NSValue *> *dataRanges = [NSMutableArray array];

        const uint8_t *cmdPtr = (const uint8_t *)(mh + 1);

        uintptr_t linkeditVMAddr = 0;
        uintptr_t linkeditFileOff = 0;

        for (uint32_t c = 0; c < mh->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;

            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;

                uintptr_t segStart = (uintptr_t)(seg->vmaddr + slide);
                uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;

                if (segStart < info.minAddress) info.minAddress = segStart;
                if (segEnd > info.maxAddress) info.maxAddress = segEnd;

                if (strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkeditVMAddr = (uintptr_t)seg->vmaddr;
                    linkeditFileOff = (uintptr_t)seg->fileoff;
                }

                const struct section_64 *sec = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    uintptr_t ss = (uintptr_t)(sec[s].addr + slide);
                    uintptr_t se = ss + (uintptr_t)sec[s].size;

                    if (strcmp(sec[s].segname, "__TEXT") == 0 &&
                        strcmp(sec[s].sectname, "__text") == 0) {
                        info.textStart = ss;
                        info.textEnd = se;
                    }

                    if (strcmp(sec[s].sectname, "__cstring") == 0 ||
                        strcmp(sec[s].sectname, "__objc_methname") == 0 ||
                        strcmp(sec[s].sectname, "__objc_classname") == 0) {
                        SCIAddRange(stringRanges, ss, se);
                    }

                    if (strcmp(sec[s].sectname, "__const") == 0 ||
                        strcmp(sec[s].sectname, "__data") == 0 ||
                        strcmp(sec[s].sectname, "__objc_const") == 0 ||
                        strcmp(sec[s].sectname, "__objc_data") == 0) {
                        SCIAddRange(dataRanges, ss, se);
                    }
                }
            } else if (lc->cmd == LC_SYMTAB) {
                const struct symtab_command *st = (const struct symtab_command *)lc;
                info.symoff = st->symoff;
                info.stroff = st->stroff;
                info.nsyms = st->nsyms;
            }

            cmdPtr += lc->cmdsize;
        }

        if (linkeditVMAddr && linkeditFileOff) {
            info.linkeditBase = (uintptr_t)(slide + linkeditVMAddr - linkeditFileOff);
        }

        info.stringRanges = [stringRanges copy];
        info.dataRanges = [dataRanges copy];

        @synchronized (self) {
            [self.images addObject:info];
            [self.reports addObject:[NSString stringWithFormat:@"[MachODexKit] image=%@ text=0x%lx-0x%lx strings=%lu data=%lu nsyms=%u",
                                     info.name,
                                     (unsigned long)info.textStart,
                                     (unsigned long)info.textEnd,
                                     (unsigned long)info.stringRanges.count,
                                     (unsigned long)info.dataRanges.count,
                                     info.nsyms]];
        }
    }
}

- (BOOL)symbolNameLooksRelevant:(NSString *)name {
    if (!name.length) return NO;

    NSString *n = name;
    if ([n hasPrefix:@"_"]) n = [n substringFromIndex:1];

    NSString *l = n.lowercaseString;

    if ([l hasPrefix:@"ig_"]) return YES;
    if ([l hasPrefix:@"fb_"]) return YES;
    if ([l containsString:@"quick_snap"]) return YES;
    if ([l containsString:@"quicksnap"]) return YES;
    if ([l containsString:@"instants"]) return YES;
    if ([l containsString:@"dogfood"]) return YES;
    if ([l containsString:@"employee"]) return YES;
    if ([l containsString:@"internal"]) return YES;
    if ([l containsString:@"mobileconfig"]) return YES;
    if ([l containsString:@"experiment"]) return YES;
    if ([l containsString:@"easygating"]) return YES;

    return NO;
}

- (NSString *)cleanSymbolName:(NSString *)name {
    if (!name.length) return @"?";
    if ([name hasPrefix:@"_"]) return [name substringFromIndex:1];
    return name;
}

- (void)buildSpecifierMapFromDataSymbols {
    for (SCIMachOImageInfo *img in self.images) {
        if (!img.linkeditBase || !img.symoff || !img.stroff || !img.nsyms) continue;

        const struct nlist_64 *symbols = (const struct nlist_64 *)(img.linkeditBase + img.symoff);
        const char *strtab = (const char *)(img.linkeditBase + img.stroff);

        for (uint32_t i = 0; i < img.nsyms; i++) {
            uint32_t strx = symbols[i].n_un.n_strx;
            if (!strx) continue;

            const char *raw = strtab + strx;
            if (!raw || !raw[0]) continue;

            NSString *sym = [NSString stringWithUTF8String:raw];
            if (![self symbolNameLooksRelevant:sym]) continue;

            uintptr_t addr = (uintptr_t)(symbols[i].n_value + img.slide);
            if (!addr) continue;

            BOOL isInData = SCIAddrInRanges(addr, img.dataRanges);
            if (!isInData) continue;

            NSString *clean = [self cleanSymbolName:sym];

            NSUInteger maxItems = 96;
            for (NSUInteger idx = 0; idx < maxItems; idx++) {
                uintptr_t p = addr + idx * sizeof(unsigned long long);
                if (!SCIAddrInRanges(p, img.dataRanges)) break;

                unsigned long long value = *(const unsigned long long *)p;
                if (!SCILooksLikeMCSpecifier(value)) {
                    if (idx == 0) break;
                    if (idx > 8) break;
                    continue;
                }

                NSString *resolved = idx == 0
                    ? clean
                    : [NSString stringWithFormat:@"%@[%lu]", clean, (unsigned long)idx];

                @synchronized (self) {
                    if (!self.specifierNames[@(value)]) {
                        self.specifierNames[@(value)] = resolved;
                        [self.reports addObject:[NSString stringWithFormat:@"[MachODexKit] data-symbol %@ 0x%016llx %@", img.name, value, resolved]];
                    }
                }
            }
        }
    }
}

- (void)addHardcodedSafetySpecifiers {
    NSDictionary<NSNumber *, NSString *> *fallback = @{
        @(0x0081030f00000a95ULL): @"ig_is_employee[0]",
        @(0x0081030f00010a96ULL): @"ig_is_employee[1]",
        @(0x008100b200000161ULL): @"ig_is_employee_or_test_user"
    };

    @synchronized (self) {
        [fallback enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSString *obj, BOOL *stop) {
            if (!self.specifierNames[key]) {
                self.specifierNames[key] = obj;
                [self.reports addObject:[NSString stringWithFormat:@"[MachODexKit] fallback-symbol 0x%016llx %@", key.unsignedLongLongValue, obj]];
            }
        }];
    }
}

#pragma mark - Callsite analysis

- (SCIMachOImageInfo *)imageForAddress:(void *)addr {
    uintptr_t a = (uintptr_t)addr;

    for (SCIMachOImageInfo *img in self.images) {
        if (a >= img.minAddress && a < img.maxAddress) return img;
    }

    return nil;
}

- (NSString *)callerDescription:(void *)callerAddress {
    if (!callerAddress) return @"";

#if __has_builtin(__builtin_extract_return_addr)
    callerAddress = __builtin_extract_return_addr(callerAddress);
#endif

    SCIMachOImageInfo *img = [self imageForAddress:callerAddress];
    if (!img) return [NSString stringWithFormat:@"caller=%p", callerAddress];

    Dl_info di;
    memset(&di, 0, sizeof(di));

    if (dladdr(callerAddress, &di) && di.dli_sname && di.dli_saddr) {
        NSString *sym = [NSString stringWithUTF8String:di.dli_sname] ?: @"?";
        uintptr_t off = (uintptr_t)callerAddress - (uintptr_t)di.dli_saddr;
        uintptr_t imgOff = (uintptr_t)callerAddress - img.base;
        return [NSString stringWithFormat:@"%@:%@+0x%lx image+0x%lx",
                img.name,
                sym,
                (unsigned long)off,
                (unsigned long)imgOff];
    }

    uintptr_t fs = 0;
    uintptr_t fe = 0;
    [self functionBoundsForCaller:callerAddress image:img start:&fs end:&fe];

    uintptr_t sub = fs > img.base ? fs - img.base : fs;
    uintptr_t off = fs ? ((uintptr_t)callerAddress - fs) : 0;

    return [NSString stringWithFormat:@"%@:sub_%lx+0x%lx",
            img.name,
            (unsigned long)sub,
            (unsigned long)off];
}

- (void)functionBoundsForCaller:(void *)callerAddress
                          image:(SCIMachOImageInfo *)img
                          start:(uintptr_t *)outStart
                            end:(uintptr_t *)outEnd {
    if (outStart) *outStart = 0;
    if (outEnd) *outEnd = 0;

    if (!callerAddress || !img || !img.textStart || !img.textEnd) return;

#if __has_builtin(__builtin_extract_return_addr)
    callerAddress = __builtin_extract_return_addr(callerAddress);
#endif

    uintptr_t pc = (uintptr_t)callerAddress;
    uintptr_t scanPC = pc >= 4 ? pc - 4 : pc;

    if (scanPC < img.textStart) scanPC = img.textStart;
    if (scanPC >= img.textEnd) scanPC = img.textEnd - 4;

    uintptr_t backLimit = scanPC > 0x3000 ? scanPC - 0x3000 : img.textStart;
    if (backLimit < img.textStart) backLimit = img.textStart;

    uintptr_t functionStart = img.textStart;

    for (uintptr_t p = scanPC & ~3ULL; p >= backLimit && p + 4 <= img.textEnd; p -= 4) {
        uint32_t insn = *(const uint32_t *)p;
        if (SCIIsLikelyFunctionPrologue(insn)) {
            functionStart = p;
            break;
        }
        if (p == backLimit || p < 4) break;
    }

    uintptr_t functionEnd = img.textEnd;
    uintptr_t forwardLimit = functionStart + 0x7000;
    if (forwardLimit > img.textEnd) forwardLimit = img.textEnd;

    for (uintptr_t p = scanPC & ~3ULL; p + 4 <= forwardLimit; p += 4) {
        uint32_t insn = *(const uint32_t *)p;
        if (p > scanPC + 4 && SCIIsLikelyFunctionPrologue(insn)) {
            functionEnd = p;
            break;
        }
        if (SCIIsFunctionEnd(insn)) {
            functionEnd = p + 4;
            break;
        }
    }

    if (outStart) *outStart = functionStart;
    if (outEnd) *outEnd = functionEnd;
}

- (uintptr_t)resolveADRPPageAtPC:(uintptr_t)pc instruction:(uint32_t)insn {
    uint64_t immlo = (insn >> 29) & 0x3;
    uint64_t immhi = (insn >> 5) & 0x7FFFF;
    int64_t imm = SCISignExtend((immhi << 2) | immlo, 21) << 12;
    return (pc & ~0xFFFULL) + imm;
}

- (void)addStringAtAddress:(uintptr_t)addr
                     image:(SCIMachOImageInfo *)img
                    output:(NSMutableOrderedSet<NSString *> *)out {
    NSString *s = nil;
    if (SCIReadCStringAt(addr, img.stringRanges, &s) && SCIStringHasUsefulToken(s)) {
        [out addObject:s];
    }
}

- (void)addPointerToStringAtAddress:(uintptr_t)addr
                              image:(SCIMachOImageInfo *)img
                             output:(NSMutableOrderedSet<NSString *> *)out {
    if (!SCIAddrInRanges(addr, img.dataRanges) && !SCIAddrInRanges(addr, img.stringRanges)) return;

    uintptr_t ptr = *(const uintptr_t *)addr;
    [self addStringAtAddress:ptr image:img output:out];
}

- (NSArray<NSString *> *)usefulStringsNearCaller:(void *)callerAddress
                                   functionStart:(uintptr_t *)outStart
                                     functionEnd:(uintptr_t *)outEnd
                                           image:(SCIMachOImageInfo **)outImage {
    if (!callerAddress) return @[];

#if __has_builtin(__builtin_extract_return_addr)
    callerAddress = __builtin_extract_return_addr(callerAddress);
#endif

    SCIMachOImageInfo *img = [self imageForAddress:callerAddress];
    if (!img) return @[];

    uintptr_t fs = 0;
    uintptr_t fe = 0;
    [self functionBoundsForCaller:callerAddress image:img start:&fs end:&fe];

    if (outStart) *outStart = fs;
    if (outEnd) *outEnd = fe;
    if (outImage) *outImage = img;

    if (!fs || !fe || fe <= fs) return @[];

    NSMutableOrderedSet<NSString *> *strings = [NSMutableOrderedSet orderedSet];

    uintptr_t maxEnd = fe;
    if (maxEnd - fs > 0x7000) maxEnd = fs + 0x7000;

    for (uintptr_t pc = fs; pc + 4 <= maxEnd; pc += 4) {
        uint32_t insn = *(const uint32_t *)pc;

        // LDR literal: sometimes points to literal pointer/string.
        if ((insn & 0x3B000000) == 0x18000000) {
            int64_t imm19 = SCISignExtend((insn >> 5) & 0x7FFFF, 19) << 2;
            uintptr_t lit = pc + imm19;

            [self addStringAtAddress:lit image:img output:strings];
            [self addPointerToStringAtAddress:lit image:img output:strings];
        }

        // ADRP
        if ((insn & 0x9F000000) == 0x90000000) {
            uint32_t rd = insn & 0x1F;
            uintptr_t page = [self resolveADRPPageAtPC:pc instruction:insn];

            for (uintptr_t pc2 = pc + 4; pc2 <= pc + 64 && pc2 + 4 <= maxEnd; pc2 += 4) {
                uint32_t next = *(const uint32_t *)pc2;
                uint32_t rn = (next >> 5) & 0x1F;
                uint32_t rd2 = next & 0x1F;

                if (rn != rd || rd2 != rd) continue;

                // ADD immediate.
                if ((next & 0x7F000000) == 0x11000000) {
                    uint64_t imm12 = (next >> 10) & 0xFFF;
                    if ((next >> 22) & 1) imm12 <<= 12;

                    uintptr_t ptr = page + imm12;
                    [self addStringAtAddress:ptr image:img output:strings];
                    [self addPointerToStringAtAddress:ptr image:img output:strings];
                }

                // LDR unsigned immediate, 64-bit or 32-bit.
                if ((next & 0xFFC00000) == 0xF9400000 || (next & 0xFFC00000) == 0xB9400000) {
                    uint64_t scale = ((next & 0xFFC00000) == 0xF9400000) ? 8 : 4;
                    uint64_t imm12 = ((next >> 10) & 0xFFF) * scale;

                    uintptr_t ptrAddr = page + imm12;
                    [self addStringAtAddress:ptrAddr image:img output:strings];
                    [self addPointerToStringAtAddress:ptrAddr image:img output:strings];
                }
            }
        }
    }

    NSArray<NSString *> *all = strings.array;
    if (all.count > 20) {
        return [all subarrayWithRange:NSMakeRange(0, 20)];
    }

    return all;
}

- (NSString *)bestStringFromStrings:(NSArray<NSString *> *)strings {
    NSString *best = nil;
    NSInteger bestScore = NSIntegerMin;

    for (NSString *s in strings) {
        NSInteger score = SCIStringScore(s);
        if (score > bestScore) {
            bestScore = score;
            best = s;
        }
    }

    if (bestScore <= 0) return nil;
    return best;
}

@end
