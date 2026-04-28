#import "SCIMachODexKitResolver.h"
#import "SCIExpMobileConfigMapping.h"
#import "SCIExpCallsiteResolver.h"   // for SCIExpDescribeCallsite fallback
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>

@implementation SCIMachODexKitResolvedName
@end

// MARK: - Helpers (style compatible with existing RG* functions)

static NSString *SCIBaseName(const char *path) {
    if (!path) return @"?";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"?";
}

static BOOL SCILooksLikeMCSpecifier(unsigned long long value) {
    return value != 0 && ((value >> 56) == 0) && ((value >> 48) != 0);
}

static int64_t SCISignExtend(uint64_t value, int bits) {
    uint64_t m = 1ULL << (bits - 1);
    return (int64_t)((value ^ m) - m);
}

static BOOL SCIAddrInRanges(uintptr_t addr, NSArray<NSValue *> *ranges) {
    for (NSValue *v in ranges) {
        NSRange r = v.rangeValue;
        if (addr >= (uintptr_t)r.location && addr < (uintptr_t)r.location + (uintptr_t)r.length) return YES;
    }
    return NO;
}

static void SCIAddRange(NSMutableArray<NSValue *> *ranges, uintptr_t start, uintptr_t end) {
    if (!start || end <= start) return;
    [ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]];
}

// MARK: - Image Info

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
@implementation SCIMachOImageInfo @end

// MARK: - Resolver

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
    dispatch_once(&once, ^{ r = [SCIMachODexKitResolver new]; });
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
        [self buildIndexIfNeeded];
    }
}

- (NSDictionary<NSNumber *, NSString *> *)allKnownSpecifierNames {
    [self buildIndexIfNeeded];
    @synchronized (self) { return [self.specifierNames copy]; }
}

- (NSArray<NSString *> *)reportLines {
    [self buildIndexIfNeeded];
    @synchronized (self) { return [self.reports copy]; }
}

- (SCIMachODexKitResolvedName *)makeResult:(NSString *)name source:(NSString *)source confidence:(NSString *)confidence specifier:(unsigned long long)specifier {
    SCIMachODexKitResolvedName *r = [SCIMachODexKitResolvedName new];
    r.name = name ?: @"unknown";
    r.source = source ?: @"unknown";
    r.confidence = confidence ?: @"low";
    r.specifier = specifier;
    return r;
}

- (SCIMachODexKitResolvedName *)resolvedNameForSpecifier:(unsigned long long)specifier
                                            functionName:(NSString *)functionName
                                            existingName:(NSString *)existingName
                                           callerAddress:(void *)callerAddress {

    [self buildIndexIfNeeded];

    // 1. Exact mapping from JSON files on disk (highest confidence)
    NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:specifier];
    if (mapped.length) {
        return [self makeResult:mapped source:@"MobileConfigMapping" confidence:@"exact" specifier:specifier];
    }

    // 2. Data symbol correlation (Mach-O)
    NSString *symbolName = nil;
    @synchronized (self) { symbolName = self.specifierNames[@(specifier)]; }
    if (symbolName.length) {
        return [self makeResult:symbolName source:@"Mach-O data symbol" confidence:@"high" specifier:specifier];
    }

    // 3. Existing callsite string xref (good fallback)
    if (callerAddress) {
        NSString *caller = SCIExpDescribeCallsite(callerAddress);
        if (caller.length && ![caller isEqualToString:@"unknown"]) {
            NSString *name = functionName.length
                ? [NSString stringWithFormat:@"%@ · %@ · 0x%016llx", caller, functionName, specifier]
                : [NSString stringWithFormat:@"%@ · 0x%016llx", caller, specifier];
            return [self makeResult:name source:@"callsite-xref" confidence:@"medium" specifier:specifier];
        }
    }

    // 4. Final fallback
    return [self makeResult:[NSString stringWithFormat:@"unknown 0x%016llx", specifier]
                     source:@"raw" confidence:@"low" specifier:specifier];
}

// MARK: - Index Building

- (void)buildIndexIfNeeded {
    @synchronized (self) {
        if (self.didBuild) return;
        self.didBuild = YES;
    }

    [self enumerateImages];
    [self buildSpecifierMapFromDataSymbols];
    [self addHardcodedSafetySpecifiers];

    @synchronized (self) {
        [self.reports addObject:[NSString stringWithFormat:@"[DexKit] images=%lu specifiers=%lu",
                                 (unsigned long)self.images.count,
                                 (unsigned long)self.specifierNames.count]];
    }
}

- (BOOL)shouldIndexImage:(NSString *)name {
    if (!name.length) return NO;
    NSString *l = name.lowercaseString;
    return [l containsString:@"instagram"] || [l containsString:@"fbsharedframework"];
}

- (void)enumerateImages {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *mhRaw = _dyld_get_image_header(i);
        if (!mhRaw || mhRaw->magic != MH_MAGIC_64) continue;

        NSString *name = SCIBaseName(_dyld_get_image_name(i));
        if (![self shouldIndexImage:name]) continue;

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
        uintptr_t linkeditVMAddr = 0, linkeditFileOff = 0;

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

                    if (strcmp(sec[s].segname, "__TEXT") == 0 && strcmp(sec[s].sectname, "__text") == 0) {
                        info.textStart = ss; info.textEnd = se;
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
        info.stringRanges = stringRanges;
        info.dataRanges = dataRanges;

        @synchronized (self) {
            [self.images addObject:info];
            [self.reports addObject:[NSString stringWithFormat:@"[DexKit] image=%@ nsyms=%u data=%lu",
                                     info.name, info.nsyms, (unsigned long)info.dataRanges.count]];
        }
    }
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
            if (!sym.length) continue;

            // Only interesting symbols
            NSString *l = sym.lowercaseString;
            if (![l hasPrefix:@"_ig_"] && ![l hasPrefix:@"_fb_"] &&
                ![l containsString:@"quick_snap"] && ![l containsString:@"employee"] &&
                ![l containsString:@"dogfood"] && ![l containsString:@"internal"]) continue;

            uintptr_t addr = (uintptr_t)(symbols[i].n_value + img.slide);
            if (!SCIAddrInRanges(addr, img.dataRanges)) continue;

            NSString *clean = [sym hasPrefix:@"_"] ? [sym substringFromIndex:1] : sym;

            // Scan up to 96 following uint64_t looking for specifiers
            for (NSUInteger idx = 0; idx < 96; idx++) {
                uintptr_t p = addr + idx * sizeof(unsigned long long);
                if (!SCIAddrInRanges(p, img.dataRanges)) break;

                unsigned long long value = *(const unsigned long long *)p;
                if (!SCILooksLikeMCSpecifier(value)) {
                    if (idx == 0) break;
                    if (idx > 8) break;
                    continue;
                }

                NSString *resolved = (idx == 0) ? clean : [NSString stringWithFormat:@"%@[%lu]", clean, (unsigned long)idx];

                @synchronized (self) {
                    if (!self.specifierNames[@(value)]) {
                        self.specifierNames[@(value)] = resolved;
                        [self.reports addObject:[NSString stringWithFormat:@"[DexKit] symbol %@ 0x%016llx → %@", img.name, value, resolved]];
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
                [self.reports addObject:[NSString stringWithFormat:@"[DexKit] fallback 0x%016llx → %@", key.unsignedLongLongValue, obj]];
            }
        }];
    }
}

@end