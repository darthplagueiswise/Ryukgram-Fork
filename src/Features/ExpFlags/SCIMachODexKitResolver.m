#import "SCIMachODexKitResolver.h"

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>

@implementation SCIMachODexKitResolvedName
@end

@interface SCIMachOScanImage : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) const struct mach_header_64 *header;
@property (nonatomic, assign) intptr_t slide;
@property (nonatomic, strong) NSArray<NSValue *> *stringRanges;
@property (nonatomic, strong) NSArray<NSValue *> *dataRanges;
@property (nonatomic, strong) NSArray<NSValue *> *allRanges;
@end
@implementation SCIMachOScanImage
@end

@interface SCIMachODexKitResolver ()
@property (nonatomic, assign) BOOL didBuild;
@property (nonatomic, strong) NSMutableArray<SCIMachOScanImage *> *images;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *specifierNames;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *specifierSources;
@property (nonatomic, strong) NSMutableArray<NSString *> *reports;
@end

static NSString *SCIBaseName(const char *path) {
    if (!path) return @"?";
    const char *slash = strrchr(path, '/');
    return [NSString stringWithUTF8String:(slash ? slash + 1 : path)] ?: @"?";
}

static void SCIAddRange(NSMutableArray<NSValue *> *ranges, uintptr_t start, uintptr_t end) {
    if (!start || end <= start) return;
    [ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]];
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

static BOOL SCILooksLikeMCSpecifier(uint64_t value) {
    if (!value) return NO;
    uint8_t tag = (uint8_t)((value >> 56) & 0xff);
    uint8_t famHi = (uint8_t)((value >> 48) & 0xff);
    BOOL tagOK = (tag == 0x00 || tag == 0x20 || tag == 0x21 || tag == 0x24);
    BOOL familyOK = (famHi == 0x41 || (famHi >= 0x81 && famHi <= 0x84));
    return tagOK && familyOK;
}

static uint64_t SCINormalizedSpecifier(uint64_t value) {
    uint8_t tag = (uint8_t)((value >> 56) & 0xff);
    if (tag == 0x20 || tag == 0x21 || tag == 0x24) return value & 0x00ffffffffffffffULL;
    return value;
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

static BOOL SCIStringLooksLikeNameCandidate(NSString *s) {
    if (!s.length || s.length > 220) return NO;
    NSString *l = s.lowercaseString;
    if ([l hasPrefix:@"http"] || [l containsString:@"://"]) return NO;
    if ([l hasPrefix:@"__"] || [l hasPrefix:@"_$s"]) return NO;
    if ([l containsString:@"%@"] || [l containsString:@"%s"] || [l containsString:@"%d"]) return NO;

    NSArray<NSString *> *tokens = @[
        @"ig_", @"fb_", @"mobileconfig", @"experiment", @"config", @"dogfood",
        @"dogfooding", @"employee", @"internal", @"test_user", @"quick", @"quicksnap",
        @"quick_snap", @"instants", @"notes", @"direct", @"friend_map", @"friendmap",
        @"prism", @"homecoming", @"launcher", @"enabled", @"eligib", @"gate",
        @"creator", @"creation", @"instamadillo", @"liquid", @"liquidglass", @"liquid_glass",
        @"igds", @"teen", @"avocado", @"camera", @"reels", @"feed", @"stories"
    ];
    for (NSString *t in tokens) if ([l containsString:t]) return YES;
    if ([s containsString:@"_"] && ![s containsString:@" "] && ![s containsString:@"."] && s.length >= 6) return YES;
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
    if ([l containsString:@"/"]) score -= 15;
    if (s.length > 160) score -= 50;
    return score;
}

static BOOL SCIReadPossibleStringFromPointer(uintptr_t ptr, SCIMachOScanImage *img, NSString **outString) {
    NSString *direct = nil;
    if (SCIReadCStringAt(ptr, img.stringRanges, &direct) && SCIStringLooksLikeNameCandidate(direct)) {
        if (outString) *outString = direct;
        return YES;
    }
    if (SCIAddrInRanges(ptr, img.dataRanges) && SCIAddrInRanges(ptr + 0x18, img.dataRanges)) {
        uintptr_t cstr = 0;
        memcpy(&cstr, (const void *)(ptr + 0x10), sizeof(cstr));
        NSString *boxed = nil;
        if (SCIReadCStringAt(cstr, img.stringRanges, &boxed) && SCIStringLooksLikeNameCandidate(boxed)) {
            if (outString) *outString = boxed;
            return YES;
        }
    }
    return NO;
}

@implementation SCIMachODexKitResolver

+ (instancetype)sharedResolver {
    static SCIMachODexKitResolver *resolver;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ resolver = [SCIMachODexKitResolver new]; });
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
    @synchronized (self) { return [self.specifierNames copy]; }
}

- (NSArray<NSString *> *)reportLines {
    [self buildIndexIfNeeded];
    @synchronized (self) { return [self.reports copy]; }
}

- (SCIMachODexKitResolvedName *)resolvedNameForSpecifier:(unsigned long long)specifier
                                            functionName:(NSString *)functionName
                                            existingName:(NSString *)existingName
                                           callerAddress:(void *)callerAddress {
    [self buildIndexIfNeeded];

    SCIMachODexKitResolvedName *result = [SCIMachODexKitResolvedName new];
    result.specifier = specifier;
    result.confidence = @"low";
    result.source = @"raw";

    if (existingName.length &&
        ![existingName isEqualToString:@"unknown"] &&
        ![existingName hasPrefix:@"unknown 0x"] &&
        ![existingName hasPrefix:@"callsite "] &&
        ![existingName hasPrefix:@"spec_0x"]) {
        result.name = existingName;
        result.source = @"hook-provided";
        result.confidence = @"exact";
        return result;
    }

    uint64_t normalized = SCINormalizedSpecifier(specifier);
    @synchronized (self) {
        NSString *mapped = self.specifierNames[@(normalized)] ?: self.specifierNames[@(specifier)];
        NSString *source = self.specifierSources[@(normalized)] ?: self.specifierSources[@(specifier)];
        if (mapped.length) {
            result.name = mapped;
            result.source = source ?: @"Mach-O table";
            result.confidence = @"high";
            return result;
        }
    }

    result.name = [NSString stringWithFormat:@"unknown 0x%016llx", specifier];
    (void)functionName;
    (void)callerAddress;
    return result;
}

- (BOOL)shouldIndexImageName:(NSString *)name {
    NSString *l = name.lowercaseString ?: @"";
    return [l containsString:@"instagram"] ||
           [l containsString:@"fbsharedframework"] ||
           [l containsString:@"fbsharedmodules"] ||
           [l containsString:@"sharedmodules"];
}

- (void)buildIndexIfNeeded {
    @synchronized (self) {
        if (self.didBuild) return;
        self.didBuild = YES;
    }
    [self enumerateImages];
    [self buildSpecifierMapFromNearbyDataTables];
    [self addHardcodedSafetySpecifiers];
    @synchronized (self) {
        [self.reports addObject:[NSString stringWithFormat:@"[MachoDex2] images=%lu knownSpecifiers=%lu", (unsigned long)self.images.count, (unsigned long)self.specifierNames.count]];
    }
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

        NSMutableArray<NSValue *> *strings = [NSMutableArray array];
        NSMutableArray<NSValue *> *data = [NSMutableArray array];
        NSMutableArray<NSValue *> *all = [NSMutableArray array];

        const uint8_t *cmdPtr = (const uint8_t *)(mh + 1);
        for (uint32_t c = 0; c < mh->ncmds; c++) {
            const struct load_command *lc = (const struct load_command *)cmdPtr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
                uintptr_t segStart = (uintptr_t)(seg->vmaddr + slide);
                uintptr_t segEnd = segStart + (uintptr_t)seg->vmsize;
                SCIAddRange(all, segStart, segEnd);
                const struct section_64 *sec = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    uintptr_t ss = (uintptr_t)(sec[s].addr + slide);
                    uintptr_t se = ss + (uintptr_t)sec[s].size;
                    if (strcmp(sec[s].sectname, "__cstring") == 0 ||
                        strcmp(sec[s].sectname, "__objc_methname") == 0 ||
                        strcmp(sec[s].sectname, "__objc_classname") == 0 ||
                        strcmp(sec[s].sectname, "__swift5_typeref") == 0 ||
                        strcmp(sec[s].sectname, "__swift5_reflstr") == 0) {
                        SCIAddRange(strings, ss, se);
                    }
                    if (strcmp(sec[s].sectname, "__const") == 0 ||
                        strcmp(sec[s].sectname, "__data") == 0 ||
                        strcmp(sec[s].sectname, "__objc_const") == 0 ||
                        strcmp(sec[s].sectname, "__objc_data") == 0 ||
                        strcmp(sec[s].sectname, "__cfstring") == 0) {
                        SCIAddRange(data, ss, se);
                    }
                }
            }
            cmdPtr += lc->cmdsize;
        }

        SCIMachOScanImage *img = [SCIMachOScanImage new];
        img.name = name;
        img.header = mh;
        img.slide = slide;
        img.stringRanges = strings.copy;
        img.dataRanges = data.copy;
        img.allRanges = all.copy;
        @synchronized (self) {
            [self.images addObject:img];
            [self.reports addObject:[NSString stringWithFormat:@"[MachoDex2] image=%@ strings=%lu data=%lu", name, (unsigned long)strings.count, (unsigned long)data.count]];
        }
    }
}

- (void)buildSpecifierMapFromNearbyDataTables {
    for (SCIMachOScanImage *img in self.images) {
        for (NSValue *rangeValue in img.dataRanges) {
            NSRange r = rangeValue.rangeValue;
            uintptr_t start = (uintptr_t)r.location;
            uintptr_t end = start + (uintptr_t)r.length;
            if (end <= start || r.length < 16) continue;

            for (uintptr_t p = start; p + sizeof(uint64_t) <= end; p += 8) {
                uint64_t raw = 0;
                memcpy(&raw, (const void *)p, sizeof(raw));
                if (!SCILooksLikeMCSpecifier(raw)) continue;
                [self tryResolveSpecifier:raw atAddress:p image:img dataStart:start dataEnd:end];
            }
        }
    }
}

- (void)tryResolveSpecifier:(uint64_t)raw atAddress:(uintptr_t)address image:(SCIMachOScanImage *)img dataStart:(uintptr_t)dataStart dataEnd:(uintptr_t)dataEnd {
    uint64_t normalized = SCINormalizedSpecifier(raw);
    if (!normalized) return;

    NSNumber *key = @(normalized);
    @synchronized (self) {
        if (self.specifierNames[key].length) return;
    }

    uintptr_t scanStart = address > 0x180 ? address - 0x180 : dataStart;
    if (scanStart < dataStart) scanStart = dataStart;
    uintptr_t scanEnd = address + 0x180;
    if (scanEnd > dataEnd) scanEnd = dataEnd;

    NSString *best = nil;
    NSInteger bestScore = NSIntegerMin;
    for (uintptr_t p = scanStart; p + sizeof(uintptr_t) <= scanEnd; p += sizeof(uintptr_t)) {
        uintptr_t ptr = 0;
        memcpy(&ptr, (const void *)p, sizeof(ptr));
        NSString *candidate = nil;
        if (!SCIReadPossibleStringFromPointer(ptr, img, &candidate)) continue;
        NSInteger score = SCIStringScore(candidate);
        if (labs((long)(p - address)) < 0x40) score += 20;
        if (score > bestScore) {
            bestScore = score;
            best = candidate;
        }
    }

    if (best.length && bestScore > 0) {
        @synchronized (self) {
            self.specifierNames[@(normalized)] = best;
            self.specifierSources[@(normalized)] = [NSString stringWithFormat:@"%@ data-near-specifier", img.name ?: @"Mach-O"];
            if (raw != normalized) {
                self.specifierNames[@(raw)] = best;
                self.specifierSources[@(raw)] = [NSString stringWithFormat:@"%@ data-near-specifier/raw", img.name ?: @"Mach-O"];
            }
        }
    }
}

- (void)addHardcodedSafetySpecifiers {
    NSDictionary<NSNumber *, NSString *> *anchors = @{
        @(0x0081030f00000a95ULL): @"ig_is_employee",
        @(0x0081030f00010a96ULL): @"ig_is_employee",
        @(0x008100b200000161ULL): @"ig_is_employee_or_test_user"
    };
    @synchronized (self) {
        [anchors enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSString *obj, BOOL *stop) {
            if (!self.specifierNames[key].length) {
                self.specifierNames[key] = obj;
                self.specifierSources[key] = @"hardcoded-anchor";
            }
        }];
    }
}

@end
