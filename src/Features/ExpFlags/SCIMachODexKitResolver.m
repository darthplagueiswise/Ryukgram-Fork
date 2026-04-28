#import "SCIMachODexKitResolver.h"
#import "SCIExpMobileConfigMapping.h"

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>

#ifndef LC_DYLD_INFO_ONLY
#define LC_DYLD_INFO_ONLY 0x80000022
#endif

#ifndef LC_DYLD_EXPORTS_TRIE
#define LC_DYLD_EXPORTS_TRIE 0x80000033
#endif

#ifndef EXPORT_SYMBOL_FLAGS_REEXPORT
#define EXPORT_SYMBOL_FLAGS_REEXPORT 0x08
#endif

#ifndef EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER
#define EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER 0x10
#endif

@implementation SCIMachODexKitResolvedName
@end

typedef struct {
    const uint8_t *start;
    const uint8_t *end;
    const uint8_t *cursor;
} SCIByteCursor;

static NSString *SCIBaseName(const char *path) {
    if (!path) return @"?";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"?";
}

static NSString *SCICleanSymbolName(NSString *name) {
    if (!name.length) return @"?";
    if ([name hasPrefix:@"_"]) return [name substringFromIndex:1];
    return name;
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
            @"launcher", @"enabled", @"eligib", @"gate", @"override",
            @"creator", @"creation", @"instamadillo", @"liquid", @"liquidglass",
            @"liquid_glass", @"igds", @"teen", @"avocado", @"camera"
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

    if ([l hasPrefix:@"ig_"] || [l containsString:@"ig_ios_"]) score += 80;
    if ([l containsString:@"quick_snap"] || [l containsString:@"quicksnap"]) score += 60;
    if ([l containsString:@"employee"]) score += 60;
    if ([l containsString:@"dogfood"]) score += 55;
    if ([l containsString:@"internal"]) score += 45;
    if ([l containsString:@"mobileconfig"]) score += 40;
    if ([l containsString:@"experiment"]) score += 35;
    if ([l containsString:@"prism"]) score += 35;
    if ([l containsString:@"liquidglass"] || [l containsString:@"liquid_glass"]) score += 35;
    if ([l containsString:@"instamadillo"]) score += 35;
    if ([l containsString:@"creator"] || [l containsString:@"creation"]) score += 30;
    if ([l containsString:@"notes"]) score += 30;
    if ([l containsString:@"friend_map"] || [l containsString:@"friendmap"]) score += 30;
    if ([l containsString:@"instants"]) score += 25;
    if ([l containsString:@"homecoming"]) score += 25;
    if ([l containsString:@"enabled"]) score += 20;
    if ([l containsString:@"eligib"]) score += 20;
    if ([l containsString:@"launcher"]) score += 10;

    if (s.length > 160) score -= 60;
    if ([l containsString:@"/"]) score -= 20;
    if ([l containsString:@"http"]) score -= 20;
    if ([l containsString:@"com.apple"]) score -= 30;
    if ([l containsString:@"uikit"]) score -= 20;

    return score;
}

static BOOL SCILooksLikeMCSpecifier(unsigned long long value) {
    if (value == 0) return NO;

    unsigned int b0 = (unsigned int)((value >> 56) & 0xff);
    unsigned int b1 = (unsigned int)((value >> 48) & 0xff);

    BOOL prefixLooksValid = (b0 == 0x00 || b0 == 0x20);
    BOOL familyLooksValid = (b1 >= 0x81 && b1 <= 0x84);

    return prefixLooksValid && familyLooksValid;
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

    while (len < 240 && SCIAddrInRanges(addr + len, stringRanges)) {
        unsigned char c = (unsigned char)p[len];
        if (c == 0) break;
        if (c < 0x20 || c > 0x7e) return NO;
        len++;
    }

    if (len < 3 || len >= 240) return NO;

    NSString *s = [[NSString alloc] initWithBytes:p length:len encoding:NSASCIIStringEncoding];
    if (!s.length) return NO;

    if (outString) *outString = s;
    return YES;
}

static uint64_t SCIReadULEB128(SCIByteCursor *cursor, BOOL *ok) {
    uint64_t result = 0;
    int bit = 0;

    if (ok) *ok = NO;
    if (!cursor) return 0;

    while (cursor->cursor < cursor->end) {
        uint8_t byte = *cursor->cursor++;
        result |= ((uint64_t)(byte & 0x7f) << bit);

        if ((byte & 0x80) == 0) {
            if (ok) *ok = YES;
            return result;
        }

        bit += 7;
        if (bit > 63) return 0;
    }

    return 0;
}

static const uint8_t *SCISkipCString(const uint8_t *p, const uint8_t *end) {
    while (p < end && *p != 0) p++;
    if (p < end) p++;
    return p;
}

static void *SCIDlsymFlexible(NSString *symbolName) {
    if (!symbolName.length) return NULL;

    NSString *clean = SCICleanSymbolName(symbolName);

    void *ptr = dlsym(RTLD_DEFAULT, clean.UTF8String);
    if (ptr) return ptr;

    NSString *underscored = [@"_" stringByAppendingString:clean];
    ptr = dlsym(RTLD_DEFAULT, underscored.UTF8String);
    if (ptr) return ptr;

    if ([symbolName hasPrefix:@"_"]) {
        ptr = dlsym(RTLD_DEFAULT, [symbolName substringFromIndex:1].UTF8String);
        if (ptr) return ptr;
    }

    return NULL;
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
@property (nonatomic, assign) uintptr_t exportTrieStart;
@property (nonatomic, assign) uintptr_t exportTrieSize;
@property (nonatomic, strong) NSArray<NSValue *> *stringRanges;
@property (nonatomic, strong) NSArray<NSValue *> *dataRanges;
@property (nonatomic, strong) NSArray<NSValue *> *allRanges;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *candidateSymbols;

@end

@implementation SCIMachOImageInfo
@end

@interface SCIMachODexKitResolver ()

@property (nonatomic, strong) NSMutableArray<SCIMachOImageInfo *> *images;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *specifierNames;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *specifierSources;
@property (nonatomic, strong) NSMutableArray<NSString *> *reports;
@property (nonatomic, assign) BOOL didBuild;

@end

@implementation SCIMachODexKitResolver

+ (instancetype)sharedResolver {
    static SCIMachODexKitResolver *resolver;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        resolver = [SCIMachODexKitResolver new];
    });
    return resolver;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _images = [NSMutableArray array];
        _specifierNames = [NSMutableDictionary dictionary];
        _specifierSources = [NSMutableDictionary dictionary];
        _reports = [NSMutableArray array];
    }
    return self;
}

- (void)rebuildIndex {
    @synchronized (self) {
        self.didBuild = NO;
        [self.images removeAllObjects];
        [self.specifierNames removeAllObjects];
        [self.specifierSources removeAllObjects];
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
    SCIMachODexKitResolvedName *result = [SCIMachODexKitResolvedName new];
    result.name = name ?: @"unknown";
    result.source = source ?: @"unknown";
    result.confidence = confidence ?: @"low";
    result.specifier = specifier;
    return result;
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
    NSString *symbolSource = nil;

    @synchronized (self) {
        symbolName = self.specifierNames[@(specifier)];
        symbolSource = self.specifierSources[@(specifier)];
    }

    if (symbolName.length) {
        return [self makeResult:symbolName
                          source:symbolSource ?: @"dynamic Mach-O symbol"
                      confidence:@"high"
                       specifier:specifier];
    }

    NSArray<NSString *> *near = [self usefulStringsNearCaller:callerAddress
                                                functionStart:NULL
                                                  functionEnd:NULL
                                                        image:NULL];
    NSString *best = [self bestStringFromStrings:near];
    NSString *caller = [self callerDescription:callerAddress];

    if (best.length) {
        NSString *name = functionName.length
            ? [NSString stringWithFormat:@"%@ · %@ · 0x%016llx", best, functionName, specifier]
            : [NSString stringWithFormat:@"%@ · 0x%016llx", best, specifier];

        return [self makeResult:name
                          source:caller.length ? caller : @"callsite string xref"
                      confidence:@"medium"
                       specifier:specifier];
    }

    if (caller.length) {
        return [self makeResult:[@"callsite " stringByAppendingString:caller]
                          source:@"caller"
                      confidence:@"low-medium"
                       specifier:specifier];
    }

    return [self makeResult:[NSString stringWithFormat:@"unknown 0x%016llx", specifier]
                      source:@"raw"
                  confidence:@"low"
                   specifier:specifier];
}

#pragma mark - Build

- (void)buildIndexIfNeeded {
    @synchronized (self) {
        if (self.didBuild) return;
        self.didBuild = YES;
    }

    [self enumerateImages];
    [self discoverCandidateSymbolsFromSymtabs];
    [self discoverCandidateSymbolsFromExportTries];
    [self buildSpecifierMapFromDiscoveredSymbols];
    [self addHardcodedSafetySpecifiers];

    @synchronized (self) {
        [self.reports addObject:[NSString stringWithFormat:@"[MachoDex] images=%lu knownSpecifiers=%lu",
                                 (unsigned long)self.images.count,
                                 (unsigned long)self.specifierNames.count]];
    }
}

- (BOOL)shouldIndexImageName:(NSString *)name {
    if (!name.length) return NO;
    NSString *lower = name.lowercaseString;

    if ([lower containsString:@"instagram"]) return YES;
    if ([lower containsString:@"fbsharedframework"]) return YES;
    if ([lower containsString:@"fbsharedmodules"]) return YES;
    if ([lower containsString:@"sharedmodules"]) return YES;

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
        info.candidateSymbols = [NSMutableDictionary dictionary];

        NSMutableArray<NSValue *> *stringRanges = [NSMutableArray array];
        NSMutableArray<NSValue *> *dataRanges = [NSMutableArray array];
        NSMutableArray<NSValue *> *allRanges = [NSMutableArray array];

        uintptr_t linkeditVMAddr = 0;
        uintptr_t linkeditFileOff = 0;

        const uint8_t *cmdPtr = (const uint8_t *)(mh + 1);

        for (uint32_t c = 0; c < mh->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;

            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                uintptr_t segStart = (uintptr_t)(seg->vmaddr + slide);
                uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;

                if (segStart < info.minAddress) info.minAddress = segStart;
                if (segEnd > info.maxAddress) info.maxAddress = segEnd;

                SCIAddRange(allRanges, segStart, segEnd);

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
                        strcmp(sec[s].sectname, "__objc_classname") == 0 ||
                        strcmp(sec[s].sectname, "__swift5_typeref") == 0 ||
                        strcmp(sec[s].sectname, "__swift5_reflstr") == 0) {
                        SCIAddRange(stringRanges, ss, se);
                    }

                    if (strcmp(sec[s].sectname, "__const") == 0 ||
                        strcmp(sec[s].sectname, "__data") == 0 ||
                        strcmp(sec[s].sectname, "__objc_const") == 0 ||
                        strcmp(sec[s].sectname, "__objc_data") == 0 ||
                        strcmp(sec[s].sectname, "__cfstring") == 0) {
                        SCIAddRange(dataRanges, ss, se);
                    }
                }
            } else if (lc->cmd == LC_SYMTAB) {
                const struct symtab_command *st = (const struct symtab_command *)lc;
                info.symoff = st->symoff;
                info.stroff = st->stroff;
                info.nsyms = st->nsyms;
            } else if (lc->cmd == LC_DYLD_INFO_ONLY) {
                const struct dyld_info_command *dyldInfo = (const struct dyld_info_command *)lc;
                if (dyldInfo->export_off && dyldInfo->export_size) {
                    info.exportTrieStart = dyldInfo->export_off;
                    info.exportTrieSize = dyldInfo->export_size;
                }
            } else if (lc->cmd == LC_DYLD_EXPORTS_TRIE) {
                const struct linkedit_data_command *exports = (const struct linkedit_data_command *)lc;
                if (exports->dataoff && exports->datasize) {
                    info.exportTrieStart = exports->dataoff;
                    info.exportTrieSize = exports->datasize;
                }
            }

            cmdPtr += lc->cmdsize;
        }

        if (linkeditVMAddr && linkeditFileOff) {
            info.linkeditBase = (uintptr_t)(slide + linkeditVMAddr - linkeditFileOff);
        }

        info.stringRanges = [stringRanges copy];
        info.dataRanges = [dataRanges copy];
        info.allRanges = [allRanges copy];

        @synchronized (self) {
            [self.images addObject:info];
            [self.reports addObject:[NSString stringWithFormat:@"[MachoDex] image=%@ nsyms=%u exportSize=0x%lx strings=%lu data=%lu",
                                     info.name,
                                     info.nsyms,
                                     (unsigned long)info.exportTrieSize,
                                     (unsigned long)info.stringRanges.count,
                                     (unsigned long)info.dataRanges.count]];
        }
    }
}

#pragma mark - Dynamic symbol discovery

- (BOOL)symbolNameLooksRelevant:(NSString *)name {
    if (!name.length) return NO;

    NSString *clean = SCICleanSymbolName(name);
    NSString *lower = clean.lowercaseString;

    if ([lower hasPrefix:@"ig_"]) return YES;
    if ([lower hasPrefix:@"fb_"]) return YES;
    if ([lower hasPrefix:@"igds_"]) return YES;

    NSArray<NSString *> *tokens = @[
        @"quick_snap", @"quicksnap", @"instants", @"notes", @"friend_map", @"friendmap",
        @"dogfood", @"employee", @"internal", @"mobileconfig", @"experiment", @"easygating",
        @"homecoming", @"prism", @"liquid", @"liquidglass", @"liquid_glass",
        @"creator", @"creation", @"instamadillo", @"teen", @"avocado"
    ];

    for (NSString *token in tokens) {
        if ([lower containsString:token]) return YES;
    }

    return NO;
}

- (void)addCandidateSymbol:(NSString *)symbolName address:(uintptr_t)address image:(SCIMachOImageInfo *)image source:(NSString *)source {
    if (!symbolName.length || !address || !image) return;
    if (![self symbolNameLooksRelevant:symbolName]) return;

    NSString *clean = SCICleanSymbolName(symbolName);
    image.candidateSymbols[clean] = @(address);

    @synchronized (self) {
        [self.reports addObject:[NSString stringWithFormat:@"[MachoDex] candidate %@ %@ addr=0x%lx source=%@",
                                 image.name ?: @"?",
                                 clean,
                                 (unsigned long)address,
                                 source ?: @"unknown"]];
    }
}

- (void)discoverCandidateSymbolsFromSymtabs {
    for (SCIMachOImageInfo *img in self.images) {
        if (!img.linkeditBase || !img.symoff || !img.stroff || !img.nsyms) continue;

        const struct nlist_64 *symbols = (const struct nlist_64 *)(img.linkeditBase + img.symoff);
        const char *strtab = (const char *)(img.linkeditBase + img.stroff);

        for (uint32_t i = 0; i < img.nsyms; i++) {
            uint8_t type = symbols[i].n_type;
            if (type & N_STAB) continue;

            uint8_t ntype = (type & N_TYPE);
            if (ntype != N_SECT && ntype != N_ABS) continue;

            uint32_t strx = symbols[i].n_un.n_strx;
            if (!strx) continue;

            const char *raw = strtab + strx;
            if (!raw || !raw[0]) continue;

            NSString *name = [NSString stringWithUTF8String:raw];
            if (!name.length || ![self symbolNameLooksRelevant:name]) continue;

            uintptr_t address = (uintptr_t)(symbols[i].n_value + img.slide);
            if (!address) continue;
            if (!SCIAddrInRanges(address, img.allRanges)) continue;

            [self addCandidateSymbol:name address:address image:img source:@"LC_SYMTAB"];
        }
    }
}

- (void)discoverCandidateSymbolsFromExportTries {
    for (SCIMachOImageInfo *img in self.images) {
        if (!img.linkeditBase || !img.exportTrieStart || !img.exportTrieSize) continue;

        const uint8_t *start = (const uint8_t *)(img.linkeditBase + img.exportTrieStart);
        const uint8_t *end = start + img.exportTrieSize;

        [self walkExportTrieNode:start
                             end:end
                            node:start
                          prefix:@""
                           image:img
                           depth:0];
    }
}

- (void)walkExportTrieNode:(const uint8_t *)start
                       end:(const uint8_t *)end
                      node:(const uint8_t *)node
                    prefix:(NSString *)prefix
                     image:(SCIMachOImageInfo *)image
                     depth:(NSUInteger)depth {
    if (!start || !end || !node || node < start || node >= end || depth > 64) return;

    SCIByteCursor cursor = { start, end, node };
    BOOL ok = NO;
    uint64_t terminalSize = SCIReadULEB128(&cursor, &ok);
    if (!ok) return;

    const uint8_t *childrenCursor = cursor.cursor + terminalSize;
    if (childrenCursor > end) return;

    if (terminalSize > 0) {
        SCIByteCursor terminal = { start, childrenCursor, cursor.cursor };

        BOOL flagsOK = NO;
        uint64_t flags = SCIReadULEB128(&terminal, &flagsOK);
        if (flagsOK) {
            BOOL isReexport = (flags & EXPORT_SYMBOL_FLAGS_REEXPORT) != 0;
            BOOL isStubAndResolver = (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER) != 0;

            if (!isReexport && !isStubAndResolver) {
                BOOL addrOK = NO;
                uint64_t encodedAddress = SCIReadULEB128(&terminal, &addrOK);
                if (addrOK) {
                    uintptr_t candidates[2] = {
                        (uintptr_t)(encodedAddress + image.slide),
                        (uintptr_t)(image.base + encodedAddress)
                    };

                    for (NSUInteger i = 0; i < 2; i++) {
                        uintptr_t address = candidates[i];
                        if (SCIAddrInRanges(address, image.allRanges)) {
                            [self addCandidateSymbol:prefix
                                             address:address
                                               image:image
                                              source:@"EXPORT_TRIE"];
                            break;
                        }
                    }
                }
            }
        }
    }

    const uint8_t *p = childrenCursor;
    if (p >= end) return;

    uint8_t childCount = *p++;

    for (uint8_t i = 0; i < childCount; i++) {
        if (p >= end) return;

        const char *suffix = (const char *)p;
        const uint8_t *afterString = SCISkipCString(p, end);
        if (afterString > end) return;

        NSString *suffixString = [NSString stringWithUTF8String:suffix] ?: @"";
        p = afterString;

        SCIByteCursor childCursor = { start, end, p };
        BOOL childOK = NO;
        uint64_t childOffset = SCIReadULEB128(&childCursor, &childOK);
        if (!childOK) return;

        p = childCursor.cursor;

        if (childOffset >= (uint64_t)(end - start)) continue;

        NSString *childPrefix = [prefix stringByAppendingString:suffixString];
        const uint8_t *childNode = start + childOffset;

        [self walkExportTrieNode:start
                             end:end
                            node:childNode
                          prefix:childPrefix
                           image:image
                           depth:depth + 1];
    }
}

#pragma mark - Specifier map

- (BOOL)addressIsReadableData:(uintptr_t)address {
    for (SCIMachOImageInfo *img in self.images) {
        if (SCIAddrInRanges(address, img.dataRanges)) return YES;
    }
    return NO;
}

- (BOOL)addSpecifier:(unsigned long long)specifier
                name:(NSString *)name
              source:(NSString *)source
         replaceWeak:(BOOL)replaceWeak {
    if (!SCILooksLikeMCSpecifier(specifier) || !name.length) return NO;

    NSNumber *key = @(specifier);

    @synchronized (self) {
        NSString *existing = self.specifierNames[key];
        BOOL weak = !existing.length ||
                    [existing hasPrefix:@"unknown"] ||
                    [existing hasPrefix:@"callsite"] ||
                    [existing hasPrefix:@"spec_0x"];

        if (!existing.length || (replaceWeak && weak)) {
            self.specifierNames[key] = name;
            self.specifierSources[key] = source ?: @"dynamic";
            [self.reports addObject:[NSString stringWithFormat:@"[MachoDex] specifier 0x%016llx → %@ source=%@",
                                     specifier,
                                     name,
                                     source ?: @"dynamic"]];
            return YES;
        }
    }

    return NO;
}

- (NSUInteger)readSpecifierArrayAtAddress:(uintptr_t)address
                               symbolName:(NSString *)symbolName
                                   source:(NSString *)source {
    if (!address || !symbolName.length) return 0;
    if (![self addressIsReadableData:address]) return 0;

    NSUInteger added = 0;
    NSUInteger consecutiveMisses = 0;
    NSUInteger maxItems = 512;

    for (NSUInteger idx = 0; idx < maxItems; idx++) {
        uintptr_t slot = address + idx * sizeof(unsigned long long);
        if (![self addressIsReadableData:slot]) break;

        unsigned long long value = *(const unsigned long long *)slot;

        if (!SCILooksLikeMCSpecifier(value)) {
            consecutiveMisses++;
            if (idx == 0 || consecutiveMisses > 2) break;
            continue;
        }

        consecutiveMisses = 0;

        NSString *clean = SCICleanSymbolName(symbolName);
        NSString *resolved = idx == 0
            ? clean
            : [NSString stringWithFormat:@"%@[%lu]", clean, (unsigned long)idx];

        if ([self addSpecifier:value name:resolved source:source replaceWeak:YES]) {
            added++;
        }
    }

    return added;
}

- (void)buildSpecifierMapFromDiscoveredSymbols {
    NSUInteger candidateCount = 0;
    NSUInteger dlsymResolved = 0;
    NSUInteger addressResolved = 0;
    NSUInteger specifiersAdded = 0;

    for (SCIMachOImageInfo *img in self.images) {
        NSDictionary<NSString *, NSNumber *> *candidates = [img.candidateSymbols copy];

        for (NSString *symbol in candidates) {
            candidateCount++;

            void *dlsymPtr = SCIDlsymFlexible(symbol);
            if (dlsymPtr) {
                NSUInteger added = [self readSpecifierArrayAtAddress:(uintptr_t)dlsymPtr
                                                           symbolName:symbol
                                                               source:[NSString stringWithFormat:@"dlsym:%@", symbol]];
                if (added > 0) {
                    dlsymResolved++;
                    specifiersAdded += added;
                    continue;
                }
            }

            uintptr_t address = candidates[symbol].unsignedLongLongValue;
            NSUInteger added = [self readSpecifierArrayAtAddress:address
                                                      symbolName:symbol
                                                          source:[NSString stringWithFormat:@"symbol:%@:%@", img.name ?: @"image", symbol]];
            if (added > 0) {
                addressResolved++;
                specifiersAdded += added;
            }
        }
    }

    @synchronized (self) {
        [self.reports addObject:[NSString stringWithFormat:@"[MachoDex] dynamic candidates=%lu dlsymResolved=%lu addressResolved=%lu specifiersAdded=%lu",
                                 (unsigned long)candidateCount,
                                 (unsigned long)dlsymResolved,
                                 (unsigned long)addressResolved,
                                 (unsigned long)specifiersAdded]];
    }
}

- (void)addHardcodedSafetySpecifiers {
    NSDictionary<NSNumber *, NSString *> *fallback = @{
        @(0x0081030f00000a95ULL): @"ig_is_employee[0]",
        @(0x0081030f00010a96ULL): @"ig_is_employee[1]",
        @(0x008100b200000161ULL): @"ig_is_employee_or_test_user"
    };

    [fallback enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSString *obj, BOOL *stop) {
        [self addSpecifier:key.unsignedLongLongValue
                      name:obj
                    source:@"hardcoded safety fallback"
               replaceWeak:NO];
    }];
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

    Dl_info info;
    memset(&info, 0, sizeof(info));

    if (dladdr(callerAddress, &info) && info.dli_fname) {
        NSString *imageName = SCIBaseName(info.dli_fname);
        uintptr_t imageBase = (uintptr_t)info.dli_fbase;
        uintptr_t imageOffset = imageBase ? ((uintptr_t)callerAddress - imageBase) : 0;

        if (info.dli_sname && info.dli_saddr) {
            NSString *sym = [NSString stringWithUTF8String:info.dli_sname] ?: @"?";
            uintptr_t off = (uintptr_t)callerAddress - (uintptr_t)info.dli_saddr;
            return [NSString stringWithFormat:@"%@:%@+0x%lx image+0x%lx",
                    imageName,
                    sym,
                    (unsigned long)off,
                    (unsigned long)imageOffset];
        }

        return [NSString stringWithFormat:@"%@+0x%lx", imageName, (unsigned long)imageOffset];
    }

    if (!img) {
        return [NSString stringWithFormat:@"caller=%p", callerAddress];
    }

    uintptr_t fs = 0;
    uintptr_t fe = 0;
    [self functionBoundsForCaller:callerAddress image:img start:&fs end:&fe];

    uintptr_t sub = fs > img.base ? fs - img.base : fs;
    uintptr_t off = fs ? ((uintptr_t)callerAddress - fs) : 0;

    return [NSString stringWithFormat:@"%@:sub_%lx+0x%lx",
            img.name ?: @"image",
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

    uintptr_t backLimit = scanPC > 0x4000 ? scanPC - 0x4000 : img.textStart;
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
    uintptr_t forwardLimit = functionStart + 0x8000;
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
    if (maxEnd - fs > 0x8000) maxEnd = fs + 0x8000;

    for (uintptr_t pc = fs; pc + 4 <= maxEnd; pc += 4) {
        uint32_t insn = *(const uint32_t *)pc;

        if ((insn & 0x3B000000) == 0x18000000) {
            int64_t imm19 = SCISignExtend((insn >> 5) & 0x7FFFF, 19) << 2;
            uintptr_t lit = pc + imm19;

            [self addStringAtAddress:lit image:img output:strings];
            [self addPointerToStringAtAddress:lit image:img output:strings];
        }

        if ((insn & 0x9F000000) == 0x90000000) {
            uint32_t rd = insn & 0x1F;
            uintptr_t page = [self resolveADRPPageAtPC:pc instruction:insn];

            for (uintptr_t pc2 = pc + 4; pc2 <= pc + 80 && pc2 + 4 <= maxEnd; pc2 += 4) {
                uint32_t next = *(const uint32_t *)pc2;
                uint32_t rn = (next >> 5) & 0x1F;
                uint32_t rd2 = next & 0x1F;

                if (rn != rd || rd2 != rd) continue;

                if ((next & 0x7F000000) == 0x11000000) {
                    uint64_t imm12 = (next >> 10) & 0xFFF;
                    if ((next >> 22) & 1) imm12 <<= 12;

                    uintptr_t ptr = page + imm12;
                    [self addStringAtAddress:ptr image:img output:strings];
                    [self addPointerToStringAtAddress:ptr image:img output:strings];
                }

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
    if (all.count > 24) return [all subarrayWithRange:NSMakeRange(0, 24)];
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
