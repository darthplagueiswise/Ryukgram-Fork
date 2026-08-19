#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

static NSString *const kRYGRuntimeOverridesKey = @"ryg_runtime_bool_overrides";
static NSDictionary<NSString *, NSNumber *> *gRYGOverrideCache;
static NSMutableSet<NSString *> *gRYGInstalledKeys;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGObservedValues;
static BOOL gRYGReinstallScheduled;

static NSString *RYGMethodKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@",
            classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
}

static NSString *RYGCanonicalImagePath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static NSDictionary<NSString *, NSNumber *> *RYGPersistedOverrides(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kRYGRuntimeOverridesKey];
    if (![value isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        (void)stop;
        if ([key isKindOfClass:NSString.class] && [object isKindOfClass:NSNumber.class]) clean[key] = object;
    }];
    return clean.copy;
}

static void RYGRefreshOverrideCache(void) {
    @synchronized(RYGRuntimeBrowserEngine.class) {
        gRYGOverrideCache = RYGPersistedOverrides();
    }
}

static NSNumber *RYGCachedOverride(NSString *key) {
    if (!key.length) return nil;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        id value = gRYGOverrideCache[key];
        return [value isKindOfClass:NSNumber.class] ? value : nil;
    }
}

static NSNumber *RYGObservedValue(NSString *key) {
    if (!key.length) return nil;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        id value = gRYGObservedValues[key];
        return [value isKindOfClass:NSNumber.class] ? value : nil;
    }
}

static void RYGRememberObservedValue(NSString *key, BOOL value) {
    if (!key.length) return;
    BOOL changed = NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGObservedValues) gRYGObservedValues = [NSMutableDictionary dictionary];
        NSNumber *previous = gRYGObservedValues[key];
        if (!previous || previous.boolValue != value) {
            gRYGObservedValues[key] = @(value);
            changed = YES;
        }
    }
    if (!changed) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification
                                                          object:nil
                                                        userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
    });
}

static const char *RYGSkipTypeQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGArgumentKindForMethod(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;

    char encoded[64] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGSkipTypeQualifiers(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    // Only true integer/scalar register arguments use this adapter. A pointer
    // or C string is not an integer ABI just because arm64 passes it in a GPR.
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGMethodHasSupportedBoolSignature(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *type = RYGSkipTypeQualifiers(encoded);
    RYGRuntimeArgumentKind argument = RYGArgumentKindForMethod(method);
    return type && *type == 'B'
        && argument >= RYGRuntimeArgumentNone
        && argument <= RYGRuntimeArgumentInteger;
}

// Declared-method lookup avoids triggering custom Objective-C resolution just
// because the developer browser is inspecting a target.
static Method RYGDeclaredMethodInHierarchy(Class owner, SEL selector) {
    for (Class cursor = owner; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int index = 0; index < count; index++) {
            if (method_getName(methods[index]) == selector) {
                found = methods[index];
                break;
            }
        }
        if (methods) free(methods);
        if (found) return found;
    }
    return NULL;
}

static BOOL RYGParseMethodKey(NSString *key,
                              NSString **className,
                              NSString **selectorName,
                              BOOL *classMethod) {
    if (key.length < 4) return NO;
    unichar prefix = [key characterAtIndex:0];
    if (prefix != '+' && prefix != '-') return NO;
    NSString *body = [key substringFromIndex:1];
    NSRange separator = [body rangeOfString:@"#"];
    if (separator.location == NSNotFound || separator.location == 0 || NSMaxRange(separator) >= body.length) return NO;
    if (className) *className = [body substringToIndex:separator.location];
    if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(separator)];
    if (classMethod) *classMethod = prefix == '+';
    return YES;
}

static BOOL RYGInstallUnifiedHookForKey(NSString *key) {
    if (!key.length) return NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGInstalledKeys) gRYGInstalledKeys = [NSMutableSet set];
        if ([gRYGInstalledKeys containsObject:key]) return YES;
        // Reserve before constructing/installing so two UI actions cannot stack
        // two hooks for the same method concurrently.
        [gRYGInstalledKeys addObject:key];
    }

    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGParseMethodKey(key, &className, &selectorName, &classMethod)) {
        @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGInstalledKeys removeObject:key]; }
        return NO;
    }

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = classMethod ? object_getClass(cls) : cls;
    Method method = owner && selector ? RYGDeclaredMethodInHierarchy(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGMethodHasSupportedBoolSignature(method)) {
        @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGInstalledKeys removeObject:key]; }
        return NO;
    }

    RYGRuntimeArgumentKind argumentKind = RYGArgumentKindForMethod(method);
    NSString *capturedKey = key.copy;
    SEL capturedSelector = selector;
    IMP *original = calloc(1, sizeof(IMP));
    if (!original) {
        @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGInstalledKeys removeObject:key]; }
        return NO;
    }

    IMP replacement = NULL;
    if (argumentKind == RYGRuntimeArgumentNone) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
            RYGRememberObservedValue(capturedKey, native);
            NSNumber *forced = RYGCachedOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (argumentKind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
            RYGRememberObservedValue(capturedKey, native);
            NSNumber *forced = RYGCachedOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (argumentKind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
            RYGRememberObservedValue(capturedKey, native);
            NSNumber *forced = RYGCachedOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    }

    if (!replacement) {
        free(original);
        @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGInstalledKeys removeObject:key]; }
        return NO;
    }

    MSHookMessageEx(owner, selector, replacement, original);
    if (!*original) {
        imp_removeBlock(replacement);
        free(original);
        @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGInstalledKeys removeObject:key]; }
        return NO;
    }
    return YES;
}

@implementation RYGRuntimeBoolMethod
- (NSString *)overrideKey { return RYGMethodKey(self.className, self.selectorName, self.classMethod); }
- (NSNumber *)overrideValue { return [RYGRuntimeBrowserEngine overrideForKey:self.overrideKey]; }
- (NSNumber *)liveValue { return [RYGRuntimeBrowserEngine observedNativeValueForKey:self.overrideKey]; }
@end

@implementation RYGMachOSymbol
@end

@implementation RYGRuntimeBrowserEngine

+ (NSArray<NSString *> *)runtimeImagePaths {
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSString *bundleRoot = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *frameworkRoot = [[bundleRoot stringByAppendingPathComponent:@"Frameworks"] stringByStandardizingPath];
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];

    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
        BOOL main = executable.length && [RYGCanonicalImagePath(path) isEqualToString:RYGCanonicalImagePath(executable)];
        BOOL framework = [path hasPrefix:[frameworkRoot stringByAppendingString:@"/"]];
        BOOL bundledDylib = [path hasPrefix:[bundleRoot stringByAppendingString:@"/"]]
            && [path.pathExtension.lowercaseString isEqualToString:@"dylib"];
        if (main || framework || bundledDylib) [paths addObject:path];
    }

    return [paths.array sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        BOOL leftMain = [RYGCanonicalImagePath(left) isEqualToString:RYGCanonicalImagePath(executable)];
        BOOL rightMain = [RYGCanonicalImagePath(right) isEqualToString:RYGCanonicalImagePath(executable)];
        if (leftMain != rightMain) return leftMain ? NSOrderedAscending : NSOrderedDescending;
        return [[self shortNameForImagePath:left] localizedCaseInsensitiveCompare:[self shortNameForImagePath:right]];
    }];
}

+ (NSString *)shortNameForImagePath:(NSString *)imagePath {
    NSString *name = imagePath.lastPathComponent;
    return name.length ? name : @"Image";
}

+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName {
    // Runtime browsing/hooking is ABI-driven. This compatibility method no
    // longer removes methods based on names such as "isEnabled"/"isEqual".
    return !selectorName.length;
}

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath
                                                      scope:(RYGRuntimeBrowserScope)scope {
    (void)scope;
    if (!imagePath.length) return @[];

    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &classCount);
    if (!classNames) {
        NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
        if (![resolved isEqualToString:imagePath])
            classNames = objc_copyClassNamesForImage(resolved.fileSystemRepresentation, &classCount);
    }
    if (!classNames) return @[];

    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
        const char *rawClass = classNames[classIndex];
        if (!rawClass || !*rawClass) continue;
        Class cls = objc_lookUpClass(rawClass);
        if (!cls) continue;
        NSString *className = [NSString stringWithUTF8String:rawClass];

        for (NSUInteger pass = 0; pass < 2; pass++) {
            BOOL classMethod = pass == 1;
            Class owner = classMethod ? object_getClass(cls) : cls;
            unsigned int methodCount = 0;
            Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                Method method = methods[methodIndex];
                if (!RYGMethodHasSupportedBoolSignature(method)) continue;
                SEL selector = method_getName(method);
                if (!selector) continue;

                RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                row.imagePath = imagePath;
                row.className = className ?: @"";
                row.selectorName = NSStringFromSelector(selector) ?: @"";
                row.classMethod = classMethod;
                row.argumentKind = RYGArgumentKindForMethod(method);
                const char *types = method_getTypeEncoding(method);
                row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
                [rows addObject:row];
            }
            if (methods) free(methods);
        }
    }
    free(classNames);

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult classResult = [left.className localizedCaseInsensitiveCompare:right.className];
        if (classResult != NSOrderedSame) return classResult;
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return rows.copy;
}

+ (NSInteger)dyldIndexForImagePath:(NSString *)imagePath {
    NSString *wanted = RYGCanonicalImagePath(imagePath);
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *candidate = [NSString stringWithUTF8String:raw];
        if ([RYGCanonicalImagePath(candidate) isEqualToString:wanted]) return (NSInteger)index;
    }
    return NSNotFound;
}

+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath {
    NSInteger imageIndex = [self dyldIndexForImagePath:imagePath];
    if (imageIndex == NSNotFound) return @[];

    const struct mach_header *rawHeader = _dyld_get_image_header((uint32_t)imageIndex);
    if (!rawHeader || rawHeader->magic != MH_MAGIC_64) return @[];
    const struct mach_header_64 *header = (const struct mach_header_64 *)rawHeader;
    if (!header->sizeofcmds || header->sizeofcmds > 16 * 1024 * 1024 || header->ncmds > 65535) return @[];

    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *commandsEnd = cursor + header->sizeofcmds;
    const struct symtab_command *symtabCommand = NULL;
    const struct segment_command_64 *linkedit = NULL;
    NSMutableDictionary<NSNumber *, NSString *> *sectionKinds = [NSMutableDictionary dictionary];
    uint16_t sectionOrdinal = 1;

    for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
        if (cursor > commandsEnd || (size_t)(commandsEnd - cursor) < sizeof(struct load_command)) return @[];
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(struct load_command) || command->cmdsize > (size_t)(commandsEnd - cursor)) return @[];

        if (command->cmd == LC_SYMTAB) symtabCommand = (const struct symtab_command *)command;
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (segment->cmdsize < sizeof(*segment) ||
                segment->nsects > (segment->cmdsize - sizeof(*segment)) / sizeof(struct section_64)) return @[];
            if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) linkedit = segment;
            const struct section_64 *sections = (const struct section_64 *)(segment + 1);
            for (uint32_t sectionIndex = 0; sectionIndex < segment->nsects; sectionIndex++, sectionOrdinal++) {
                uint32_t flags = sections[sectionIndex].flags;
                BOOL instructions = (flags & S_ATTR_PURE_INSTRUCTIONS) || (flags & S_ATTR_SOME_INSTRUCTIONS);
                if (sectionOrdinal <= UINT8_MAX) sectionKinds[@(sectionOrdinal)] = instructions ? @"Function" : @"Data";
            }
        }
        cursor += command->cmdsize;
    }

    if (!symtabCommand || !linkedit || !symtabCommand->nsyms || !symtabCommand->strsize) return @[];
    uint64_t linkeditStart = linkedit->fileoff;
    uint64_t linkeditEnd = linkeditStart + linkedit->filesize;
    uint64_t symbolsEnd = (uint64_t)symtabCommand->symoff +
        (uint64_t)symtabCommand->nsyms * sizeof(struct nlist_64);
    uint64_t stringsEnd = (uint64_t)symtabCommand->stroff + symtabCommand->strsize;
    if (linkeditEnd < linkeditStart ||
        symtabCommand->symoff < linkeditStart || symbolsEnd > linkeditEnd ||
        symtabCommand->stroff < linkeditStart || stringsEnd > linkeditEnd) return @[];

    if (slide < 0 || (uintptr_t)slide > UINTPTR_MAX - (uintptr_t)linkedit->vmaddr) return @[];
    uintptr_t slidLinkedit = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr;
    if (slidLinkedit < (uintptr_t)linkedit->fileoff) return @[];
    uintptr_t linkeditBase = slidLinkedit - (uintptr_t)linkedit->fileoff;
    if (linkeditBase > UINTPTR_MAX - symtabCommand->symoff ||
        linkeditBase > UINTPTR_MAX - symtabCommand->stroff) return @[];

    const struct nlist_64 *symbols = (const struct nlist_64 *)(linkeditBase + symtabCommand->symoff);
    const char *strings = (const char *)(linkeditBase + symtabCommand->stroff);
    NSMutableArray<RYGMachOSymbol *> *rows = [NSMutableArray array];
    NSUInteger limit = MIN((NSUInteger)symtabCommand->nsyms, (NSUInteger)50000);

    for (NSUInteger index = 0; index < limit; index++) {
        const struct nlist_64 entry = symbols[index];
        if ((entry.n_type & N_STAB) || entry.n_un.n_strx == 0 || entry.n_un.n_strx >= symtabCommand->strsize) continue;
        size_t remaining = symtabCommand->strsize - entry.n_un.n_strx;
        const char *rawName = strings + entry.n_un.n_strx;
        size_t length = strnlen(rawName, MIN(remaining, (size_t)4096));
        if (!length || length >= remaining) continue;
        NSString *name = [[NSString alloc] initWithBytes:rawName length:length encoding:NSUTF8StringEncoding];
        if (!name.length) continue;

        RYGMachOSymbol *row = [RYGMachOSymbol new];
        row.name = name;
        row.external = (entry.n_type & N_EXT) != 0;
        uint8_t type = entry.n_type & N_TYPE;
        if (type == N_UNDF) row.kind = @"Undefined";
        else if (type == N_ABS) row.kind = @"Absolute";
        else if (type == N_SECT) row.kind = sectionKinds[@(entry.n_sect)] ?: @"Section";
        else row.kind = @"Symbol";
        row.address = entry.n_value ? (type == N_SECT ? entry.n_value + slide : entry.n_value) : 0;
        [rows addObject:row];
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGMachOSymbol *left, RYGMachOSymbol *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return rows.copy;
}

+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method {
    if (!method.overrideKey.length) return NO;
    return RYGInstallUnifiedHookForKey(method.overrideKey);
}

+ (NSNumber *)observedNativeValueForKey:(NSString *)overrideKey {
    return RYGObservedValue(overrideKey);
}

+ (NSNumber *)overrideForKey:(NSString *)overrideKey {
    return RYGCachedOverride(overrideKey);
}

+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (!method.overrideKey.length) return;
    NSMutableDictionary *overrides = [RYGPersistedOverrides() mutableCopy];
    if (value) overrides[method.overrideKey] = @([value boolValue]);
    else [overrides removeObjectForKey:method.overrideKey];
    [NSUserDefaults.standardUserDefaults setObject:overrides.copy forKey:kRYGRuntimeOverridesKey];
    RYGRefreshOverrideCache();

    // Force and Observe use the same trampoline. Clearing an override leaves the
    // already-installed hook in pass-through observation mode; no second hook is
    // ever stacked and the original IMP remains the true native source.
    if (value) RYGInstallUnifiedHookForKey(method.overrideKey);
}

+ (void)reinstallPersistedOverrides {
    RYGRefreshOverrideCache();
    for (NSString *key in gRYGOverrideCache) RYGInstallUnifiedHookForKey(key);
}

@end

static void RYGSchedulePersistedOverrideReinstall(void) {
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (gRYGReinstallScheduled) return;
        gRYGReinstallScheduled = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @synchronized(RYGRuntimeBrowserEngine.class) { gRYGReinstallScheduled = NO; }
        [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
    });
}

static void RYGRuntimeImageDidLoad(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    RYGSchedulePersistedOverrideReinstall();
}

__attribute__((constructor)) static void RYGRuntimeOverrideBootstrap(void) {
    @autoreleasepool {
        RYGRefreshOverrideCache();
        _dyld_register_func_for_add_image(RYGRuntimeImageDidLoad);
        RYGSchedulePersistedOverrideReinstall();
    }
}
