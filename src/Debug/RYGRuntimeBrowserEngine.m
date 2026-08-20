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

static NSMutableDictionary<NSString *, NSNumber *> *gRYGOverrides;
static NSMutableSet<NSString *> *gRYGInstalledKeys;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGObservedValues;

static NSString *RYGMethodKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
}

static NSString *RYGCanonicalImagePath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGImagePathMatches(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    NSString *a = RYGCanonicalImagePath(left), *b = RYGCanonicalImagePath(right);
    if ([a isEqualToString:b]) return YES;
    return [a.lastPathComponent isEqualToString:b.lastPathComponent];
}

static const char *RYGSkipTypeQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGIsObjCBoolType(const char *type) {
    type = RYGSkipTypeQualifiers(type);
    return type && strchr("BcC", *type) != NULL;
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
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGMethodHasSupportedBoolSignature(Method method) {
    if (!method) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    RYGRuntimeArgumentKind argument = RYGArgumentKindForMethod(method);
    return RYGIsObjCBoolType(encoded) && argument >= RYGRuntimeArgumentNone && argument <= RYGRuntimeArgumentInteger;
}

static Method RYGDeclaredMethodInHierarchy(Class owner, SEL selector) {
    for (Class cursor = owner; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int index = 0; index < count; index++) {
            if (method_getName(methods[index]) == selector) { found = methods[index]; break; }
        }
        if (methods) free(methods);
        if (found) return found;
    }
    return NULL;
}

static NSNumber *RYGOverrideForKey(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { return gRYGOverrides[key]; }
}

static NSNumber *RYGObservedValue(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { return gRYGObservedValues[key]; }
}

static void RYGRememberObservedValue(NSString *key, BOOL value) {
    if (!key.length) return;
    BOOL changed = NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGObservedValues) gRYGObservedValues = [NSMutableDictionary dictionary];
        NSNumber *previous = gRYGObservedValues[key];
        if (!previous || previous.boolValue != value) { gRYGObservedValues[key] = @(value); changed = YES; }
    }
    if (changed) dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification object:nil userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
    });
}

static BOOL RYGParseMethodKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
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
        [gRYGInstalledKeys addObject:key];
    }

    NSString *className = nil, *selectorName = nil;
    BOOL classMethod = NO;
    BOOL parsed = RYGParseMethodKey(key, &className, &selectorName, &classMethod);
    Class cls = parsed ? objc_lookUpClass(className.UTF8String) : Nil;
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner && selector ? RYGDeclaredMethodInHierarchy(owner, selector) : NULL;
    if (!parsed || !cls || !owner || !selector || !RYGMethodHasSupportedBoolSignature(method)) {
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
            NSNumber *forced = RYGOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (argumentKind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
            RYGRememberObservedValue(capturedKey, native);
            NSNumber *forced = RYGOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (argumentKind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
            RYGRememberObservedValue(capturedKey, native);
            NSNumber *forced = RYGOverrideForKey(capturedKey);
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

static void RYGAppendMethodsForClass(NSMutableArray<RYGRuntimeBoolMethod *> *rows, Class cls, NSString *imagePath) {
    if (!cls) return;
    const char *rawName = class_getName(cls);
    NSString *className = rawName ? [NSString stringWithUTF8String:rawName] : @"";
    for (NSUInteger pass = 0; pass < 2; pass++) {
        BOOL classMethod = pass == 1;
        Class owner = classMethod ? object_getClass(cls) : cls;
        unsigned int methodCount = 0;
        Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
        for (unsigned int index = 0; index < methodCount; index++) {
            Method method = methods[index];
            if (!RYGMethodHasSupportedBoolSignature(method)) continue;
            SEL selector = method_getName(method);
            if (!selector) continue;
            RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
            row.imagePath = imagePath ?: @"";
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

@implementation RYGRuntimeBoolMethod
- (NSString *)overrideKey { return RYGMethodKey(self.className, self.selectorName, self.classMethod); }
- (NSNumber *)overrideValue { return [RYGRuntimeBrowserEngine overrideForKey:self.overrideKey]; }
- (NSNumber *)liveValue { return [RYGRuntimeBrowserEngine observedNativeValueForKey:self.overrideKey]; }
@end

@implementation RYGMachOSymbol @end

@implementation RYGRuntimeBrowserEngine

+ (NSArray<NSString *> *)runtimeImagePaths {
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSString *bundleRoot = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *frameworkRoot = [[bundleRoot stringByAppendingPathComponent:@"Frameworks"] stringByStandardizingPath];
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
        BOOL main = executable.length && RYGImagePathMatches(path, executable);
        BOOL framework = [path hasPrefix:[frameworkRoot stringByAppendingString:@"/"]];
        BOOL bundledDylib = [path hasPrefix:[bundleRoot stringByAppendingString:@"/"]] && [path.pathExtension.lowercaseString isEqualToString:@"dylib"];
        if (main || framework || bundledDylib) [paths addObject:path];
    }
    return [paths.array sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        BOOL leftMain = RYGImagePathMatches(left, executable), rightMain = RYGImagePathMatches(right, executable);
        if (leftMain != rightMain) return leftMain ? NSOrderedAscending : NSOrderedDescending;
        return [[self shortNameForImagePath:left] localizedCaseInsensitiveCompare:[self shortNameForImagePath:right]];
    }];
}

+ (NSString *)shortNameForImagePath:(NSString *)imagePath { return imagePath.lastPathComponent.length ? imagePath.lastPathComponent : @"Image"; }
+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName { return !selectorName.length; }

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath scope:(RYGRuntimeBrowserScope)scope {
    (void)scope;
    if (!imagePath.length) return @[];
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *seenClasses = [NSMutableSet set];

    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &classCount);
    if ((!classNames || classCount == 0) && imagePath.stringByResolvingSymlinksInPath.length) {
        if (classNames) free(classNames);
        NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
        classNames = objc_copyClassNamesForImage(resolved.fileSystemRepresentation, &classCount);
    }
    if (classNames && classCount) {
        for (unsigned int i = 0; i < classCount; i++) {
            if (!classNames[i] || !*classNames[i]) continue;
            Class cls = objc_lookUpClass(classNames[i]);
            if (!cls) continue;
            NSString *name = [NSString stringWithUTF8String:classNames[i]];
            if (name.length) [seenClasses addObject:name];
            RYGAppendMethodsForClass(rows, cls, imagePath);
        }
        free(classNames);
    }

    if (rows.count == 0) {
        int total = objc_getClassList(NULL, 0);
        if (total > 0 && total < 500000) {
            Class *classes = calloc((size_t)total, sizeof(Class));
            int filled = classes ? objc_getClassList(classes, total) : 0;
            for (int i = 0; i < filled; i++) {
                Class cls = classes[i];
                const char *rawImage = cls ? class_getImageName(cls) : NULL;
                if (!rawImage) continue;
                NSString *actual = [NSString stringWithUTF8String:rawImage];
                if (!RYGImagePathMatches(actual, imagePath)) continue;
                NSString *name = NSStringFromClass(cls);
                if (name.length && [seenClasses containsObject:name]) continue;
                if (name.length) [seenClasses addObject:name];
                RYGAppendMethodsForClass(rows, cls, imagePath);
            }
            free(classes);
        }
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *left, RYGRuntimeBoolMethod *right) {
        NSComparisonResult c = [left.className localizedCaseInsensitiveCompare:right.className];
        if (c != NSOrderedSame) return c;
        if (left.classMethod != right.classMethod) return left.classMethod ? NSOrderedAscending : NSOrderedDescending;
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return rows.copy;
}

+ (NSInteger)dyldIndexForImagePath:(NSString *)imagePath {
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        if (RYGImagePathMatches([NSString stringWithUTF8String:raw], imagePath)) return (NSInteger)index;
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
    const uint8_t *cursor = (const uint8_t *)(header + 1), *commandsEnd = cursor + header->sizeofcmds;
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
            if (segment->cmdsize < sizeof(*segment) || segment->nsects > (segment->cmdsize - sizeof(*segment)) / sizeof(struct section_64)) return @[];
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
    uint64_t linkeditStart = linkedit->fileoff, linkeditEnd = linkeditStart + linkedit->filesize;
    uint64_t symbolsEnd = (uint64_t)symtabCommand->symoff + (uint64_t)symtabCommand->nsyms * sizeof(struct nlist_64);
    uint64_t stringsEnd = (uint64_t)symtabCommand->stroff + symtabCommand->strsize;
    if (linkeditEnd < linkeditStart || symtabCommand->symoff < linkeditStart || symbolsEnd > linkeditEnd || symtabCommand->stroff < linkeditStart || stringsEnd > linkeditEnd) return @[];
    if (slide < 0 || (uintptr_t)slide > UINTPTR_MAX - (uintptr_t)linkedit->vmaddr) return @[];
    uintptr_t slidLinkedit = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr;
    if (slidLinkedit < (uintptr_t)linkedit->fileoff) return @[];
    uintptr_t linkeditBase = slidLinkedit - (uintptr_t)linkedit->fileoff;
    if (linkeditBase > UINTPTR_MAX - symtabCommand->symoff || linkeditBase > UINTPTR_MAX - symtabCommand->stroff) return @[];
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
        RYGMachOSymbol *row = [RYGMachOSymbol new]; row.name = name; row.external = (entry.n_type & N_EXT) != 0;
        uint8_t type = entry.n_type & N_TYPE;
        if (type == N_UNDF) row.kind = @"Undefined"; else if (type == N_ABS) row.kind = @"Absolute"; else if (type == N_SECT) row.kind = sectionKinds[@(entry.n_sect)] ?: @"Section"; else row.kind = @"Symbol";
        row.address = entry.n_value ? (type == N_SECT ? entry.n_value + slide : entry.n_value) : 0;
        [rows addObject:row];
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGMachOSymbol *left, RYGMachOSymbol *right) { return [left.name localizedCaseInsensitiveCompare:right.name]; }];
    return rows.copy;
}

+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method { return method.overrideKey.length ? RYGInstallUnifiedHookForKey(method.overrideKey) : NO; }
+ (NSNumber *)observedNativeValueForKey:(NSString *)overrideKey { return RYGObservedValue(overrideKey); }
+ (NSNumber *)overrideForKey:(NSString *)overrideKey { return RYGOverrideForKey(overrideKey); }
+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (!method.overrideKey.length) return;
    @synchronized(self) {
        if (!gRYGOverrides) gRYGOverrides = [NSMutableDictionary dictionary];
        if (value) gRYGOverrides[method.overrideKey] = @([value boolValue]); else [gRYGOverrides removeObjectForKey:method.overrideKey];
    }
    if (value) RYGInstallUnifiedHookForKey(method.overrideKey);
}

+ (void)reinstallPersistedOverrides { }

@end
