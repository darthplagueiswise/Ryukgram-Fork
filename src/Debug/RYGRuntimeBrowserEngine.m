#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

static NSMutableDictionary<NSString *, NSNumber *> *gRYGOverrides;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGObservedValues;
static NSMutableSet<NSString *> *gRYGInstalledKeys;
static NSMutableDictionary<NSString *, NSArray<RYGMachOSymbol *> *> *gRYGSymbolIndexes;

static NSString *RYGCanonicalImagePath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static const struct mach_header *RYGDyldHeaderForImagePath(NSString *path) {
    if (!path.length) return NULL;
    NSString *wanted = RYGCanonicalImagePath(path);
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *loaded = RYGCanonicalImagePath([NSString stringWithUTF8String:raw]);
        if ([loaded isEqualToString:wanted]) return _dyld_get_image_header(index);
    }
    return NULL;
}

static NSString *RYGDyldRuntimeNameForImagePath(NSString *path) {
    if (!path.length) return nil;
    NSString *wanted = RYGCanonicalImagePath(path);
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *loaded = [NSString stringWithUTF8String:raw];
        if ([RYGCanonicalImagePath(loaded) isEqualToString:wanted]) return loaded;
    }
    return nil;
}

static BOOL RYGImagePathMatches(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    const struct mach_header *lh = RYGDyldHeaderForImagePath(left);
    const struct mach_header *rh = RYGDyldHeaderForImagePath(right);
    if (lh && rh) return lh == rh;
    return [RYGCanonicalImagePath(left) isEqualToString:RYGCanonicalImagePath(right)];
}

static NSString *RYGMethodKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
}

static const char *RYGSkipTypeQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGIsBoolType(const char *type) {
    type = RYGSkipTypeQualifiers(type);
    return type && (*type == 'B' || *type == 'c' || *type == 'C');
}

static BOOL RYGIsObjectRegisterType(const char *type) {
    type = RYGSkipTypeQualifiers(type);
    return type && *type == '@';
}

static BOOL RYGIsInt64RegisterType(const char *type) {
    type = RYGSkipTypeQualifiers(type);
    return type && (*type == 'q' || *type == 'Q');
}

static RYGRuntimeArgumentKind RYGArgumentKindForMethod(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[128] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    if (RYGIsObjectRegisterType(encoded)) return RYGRuntimeArgumentObject;
    if (RYGIsInt64RegisterType(encoded)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGMethodHasSupportedBoolABI(Method method) {
    if (!method) return NO;
    char encoded[64] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    if (!RYGIsBoolType(encoded)) return NO;
    RYGRuntimeArgumentKind kind = RYGArgumentKindForMethod(method);
    return kind >= RYGRuntimeArgumentNone && kind <= RYGRuntimeArgumentInteger;
}

static BOOL RYGMethodIMPBelongsToImage(Method method, NSString *imagePath) {
    IMP imp = method ? method_getImplementation(method) : NULL;
    if (!imp || !imagePath.length) return NO;
    Dl_info info = {0};
    if (!dladdr((const void *)imp, &info)) return NO;
    const struct mach_header *target = RYGDyldHeaderForImagePath(imagePath);
    if (target && info.dli_fbase) return info.dli_fbase == (const void *)target;
    if (!info.dli_fname) return NO;
    return RYGImagePathMatches([NSString stringWithUTF8String:info.dli_fname], imagePath);
}

static BOOL RYGClassDefinedInImage(Class cls, NSString *imagePath) {
    if (!cls || !imagePath.length) return NO;
    const char *raw = class_getImageName(cls);
    if (!raw) return NO;
    return RYGImagePathMatches([NSString stringWithUTF8String:raw], imagePath);
}

static NSNumber *RYGOverrideForKey(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { return gRYGOverrides[key]; }
}

static NSNumber *RYGObservedForKey(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { return gRYGObservedValues[key]; }
}

static void RYGRememberObserved(NSString *key, BOOL value) {
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
    if (changed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification
                                                               object:nil
                                                             userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
        });
    }
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

static void RYGForgetInstalledKey(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGInstalledKeys removeObject:key]; }
}

static BOOL RYGInstallUnifiedBoolHook(NSString *key) {
    if (!key.length) return NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGInstalledKeys) gRYGInstalledKeys = [NSMutableSet set];
        if ([gRYGInstalledKeys containsObject:key]) return YES;
        [gRYGInstalledKeys addObject:key];
    }

    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGParseMethodKey(key, &className, &selectorName, &classMethod)) {
        RYGForgetInstalledKey(key);
        return NO;
    }

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGMethodHasSupportedBoolABI(method)) {
        RYGForgetInstalledKey(key);
        return NO;
    }

    RYGRuntimeArgumentKind kind = RYGArgumentKindForMethod(method);
    NSString *capturedKey = key.copy;
    SEL capturedSelector = selector;
    __block IMP original = NULL;
    IMP replacement = NULL;

    if (kind == RYGRuntimeArgumentNone) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL native = original ? ((BOOL (*)(id, SEL))original)(receiver, capturedSelector) : NO;
            RYGRememberObserved(capturedKey, native);
            NSNumber *forced = RYGOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = original ? ((BOOL (*)(id, SEL, id))original)(receiver, capturedSelector, argument) : NO;
            RYGRememberObserved(capturedKey, native);
            NSNumber *forced = RYGOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = original ? ((BOOL (*)(id, SEL, uint64_t))original)(receiver, capturedSelector, argument) : NO;
            RYGRememberObserved(capturedKey, native);
            NSNumber *forced = RYGOverrideForKey(capturedKey);
            return forced ? forced.boolValue : native;
        });
    }

    if (!replacement) {
        RYGForgetInstalledKey(key);
        return NO;
    }

    Method current = class_getInstanceMethod(owner, selector);
    if (!current || !RYGMethodHasSupportedBoolABI(current)) {
        imp_removeBlock(replacement);
        RYGForgetInstalledKey(key);
        return NO;
    }
    original = method_setImplementation(current, replacement);
    if (!original) {
        imp_removeBlock(replacement);
        RYGForgetInstalledKey(key);
        return NO;
    }
    return YES;
}

static RYGRuntimeBoolMethod *RYGBoolRow(Class cls, Method method, BOOL classMethod, NSString *imagePath) {
    if (!cls || !method || !RYGMethodHasSupportedBoolABI(method)) return nil;
    SEL selector = method_getName(method);
    if (!selector) return nil;
    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.imagePath = imagePath ?: @"";
    row.className = NSStringFromClass(cls) ?: @"";
    row.selectorName = NSStringFromSelector(selector) ?: @"";
    row.classMethod = classMethod;
    row.argumentKind = RYGArgumentKindForMethod(method);
    const char *types = method_getTypeEncoding(method);
    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    return row;
}

static void RYGCountHookableMembersForClass(Class cls,
                                             NSString *imagePath,
                                             NSUInteger *instanceCount,
                                             NSUInteger *classCount) {
    NSUInteger counts[2] = {0, 0};
    for (NSUInteger pass = 0; pass < 2; pass++) {
        Class owner = pass ? object_getClass(cls) : cls;
        unsigned int count = 0;
        Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
        for (unsigned int index = 0; methods && index < count; index++) {
            Method method = methods[index];
            if (!RYGMethodHasSupportedBoolABI(method)) continue;
            if (!RYGMethodIMPBelongsToImage(method, imagePath)) continue;
            SEL selector = method_getName(method);
            NSString *name = selector ? NSStringFromSelector(selector) : @"";
            if ([RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:name]) continue;
            counts[pass]++;
        }
        if (methods) free(methods);
    }
    if (instanceCount) *instanceCount = counts[0];
    if (classCount) *classCount = counts[1];
}

@implementation RYGRuntimeClassRow @end

@implementation RYGRuntimeMemberRow
- (BOOL)method { return self.kind == RYGRuntimeMemberInstanceMethod || self.kind == RYGRuntimeMemberClassMethod; }
- (BOOL)classMember { return self.kind == RYGRuntimeMemberClassMethod || self.kind == RYGRuntimeMemberClassProperty; }
@end

@implementation RYGRuntimeBoolMethod
- (NSString *)overrideKey { return RYGMethodKey(self.className, self.selectorName, self.classMethod); }
- (NSNumber *)overrideValue { return [RYGRuntimeBrowserEngine overrideForKey:self.overrideKey]; }
- (NSNumber *)liveValue { return [RYGRuntimeBrowserEngine observedNativeValueForKey:self.overrideKey]; }
@end

@implementation RYGMachOSymbol @end

@implementation RYGRuntimeBrowserEngine

+ (NSArray<NSString *> *)runtimeImagePaths {
    NSString *bundle = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *executable = NSBundle.mainBundle.executablePath.stringByStandardizingPath;
    NSString *frameworks = [[bundle stringByAppendingPathComponent:@"Frameworks"] stringByStandardizingPath];
    NSMutableOrderedSet<NSString *> *images = [NSMutableOrderedSet orderedSet];
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
        BOOL main = RYGImagePathMatches(path, executable);
        BOOL framework = [path hasPrefix:[frameworks stringByAppendingString:@"/"]];
        BOOL bundledDylib = [path hasPrefix:[bundle stringByAppendingString:@"/"]] && [path.pathExtension.lowercaseString isEqualToString:@"dylib"];
        if (main || framework || bundledDylib) [images addObject:path];
    }
    return [images.array sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        BOOL leftMain = RYGImagePathMatches(left, executable);
        BOOL rightMain = RYGImagePathMatches(right, executable);
        if (leftMain != rightMain) return leftMain ? NSOrderedAscending : NSOrderedDescending;
        return [[self shortNameForImagePath:left] localizedCaseInsensitiveCompare:[self shortNameForImagePath:right]];
    }];
}

+ (NSString *)shortNameForImagePath:(NSString *)imagePath {
    return imagePath.lastPathComponent.length ? imagePath.lastPathComponent : @"Image";
}

+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName {
    if (!selectorName.length) return YES;
    static NSSet<NSString *> *noise;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        noise = [NSSet setWithArray:@[
            @"isEqual:", @"hash", @"class", @"self", @"superclass",
            @"respondsToSelector:", @"isKindOfClass:", @"isMemberOfClass:",
            @"conformsToProtocol:", @"methodForSelector:", @"description",
            @"debugDescription", @"retainCount", @"zone"
        ]];
    });
    return [noise containsObject:selectorName];
}

+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath {
    if (!imagePath.length || !RYGDyldHeaderForImagePath(imagePath)) return @[];
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    NSString *runtimeName = RYGDyldRuntimeNameForImagePath(imagePath) ?: imagePath;
    unsigned int directCount = 0;
    const char **directNames = objc_copyClassNamesForImage(runtimeName.fileSystemRepresentation, &directCount);
    for (unsigned int index = 0; directNames && index < directCount; index++) {
        if (!directNames[index] || !*directNames[index]) continue;
        NSString *name = [NSString stringWithUTF8String:directNames[index]];
        if (name.length) [names addObject:name];
    }
    if (directNames) free(directNames);

    if (!names.count) {
        int total = objc_getClassList(NULL, 0);
        if (total <= 0 || total > 500000) return @[];
        Class __unsafe_unretained *classes = (Class __unsafe_unretained *)calloc((size_t)total, sizeof(Class));
        if (!classes) return @[];
        int filled = objc_getClassList(classes, total);
        for (int index = 0; index < filled; index++) {
            Class cls = classes[index];
            if (!RYGClassDefinedInImage(cls, imagePath)) continue;
            NSString *name = NSStringFromClass(cls);
            if (name.length) [names addObject:name];
        }
        free(classes);
    }

    NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray array];
    for (NSString *name in names) {
        Class cls = objc_lookUpClass(name.UTF8String);
        if (!cls) continue;
        NSUInteger instanceCount = 0, classCount = 0;
        RYGCountHookableMembersForClass(cls, imagePath, &instanceCount, &classCount);
        if (instanceCount + classCount == 0) continue;
        RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
        row.imagePath = imagePath;
        row.className = name;
        row.instanceMethodCount = instanceCount;
        row.classMethodCount = classCount;
        row.propertyCount = 0;
        [rows addObject:row];
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *left, RYGRuntimeClassRow *right) {
        return [left.className localizedCaseInsensitiveCompare:right.className];
    }];
    return rows.copy;
}

+ (NSArray<RYGRuntimeMemberRow *> *)membersForClassName:(NSString *)className imagePath:(NSString *)imagePath {
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    if (!cls || !RYGClassDefinedInImage(cls, imagePath)) return @[];
    NSMutableArray<RYGRuntimeMemberRow *> *rows = [NSMutableArray array];
    for (NSUInteger pass = 0; pass < 2; pass++) {
        BOOL classMethod = pass == 1;
        Class owner = classMethod ? object_getClass(cls) : cls;
        unsigned int count = 0;
        Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
        for (unsigned int index = 0; methods && index < count; index++) {
            Method method = methods[index];
            if (!RYGMethodHasSupportedBoolABI(method) || !RYGMethodIMPBelongsToImage(method, imagePath)) continue;
            NSString *name = NSStringFromSelector(method_getName(method));
            if ([self isStructuralNoiseSelectorName:name]) continue;
            RYGRuntimeMemberRow *row = [RYGRuntimeMemberRow new];
            row.imagePath = imagePath;
            row.className = className;
            row.name = name ?: @"";
            const char *types = method_getTypeEncoding(method);
            row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
            row.kind = classMethod ? RYGRuntimeMemberClassMethod : RYGRuntimeMemberInstanceMethod;
            row.hookableBool = YES;
            row.argumentKind = RYGArgumentKindForMethod(method);
            [rows addObject:row];
        }
        if (methods) free(methods);
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMemberRow *left, RYGRuntimeMemberRow *right) {
        if (left.kind != right.kind) return left.kind < right.kind ? NSOrderedAscending : NSOrderedDescending;
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return rows.copy;
}

+ (RYGRuntimeBoolMethod *)boolMethodForMember:(RYGRuntimeMemberRow *)member {
    if (![member isKindOfClass:RYGRuntimeMemberRow.class] || !member.method || !member.hookableBool) return nil;
    Class cls = objc_lookUpClass(member.className.UTF8String);
    BOOL classMethod = member.kind == RYGRuntimeMemberClassMethod;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    SEL selector = member.name.length ? NSSelectorFromString(member.name) : NULL;
    Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
    if (!method || !RYGMethodHasSupportedBoolABI(method) || !RYGMethodIMPBelongsToImage(method, member.imagePath)) return nil;
    return RYGBoolRow(cls, method, classMethod, member.imagePath);
}

+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath scope:(RYGRuntimeBrowserScope)scope {
    (void)scope;
    NSMutableArray<RYGRuntimeBoolMethod *> *rows = [NSMutableArray array];
    for (RYGRuntimeClassRow *classRow in [self classesForImagePath:imagePath]) {
        for (RYGRuntimeMemberRow *member in [self membersForClassName:classRow.className imagePath:imagePath]) {
            RYGRuntimeBoolMethod *method = [self boolMethodForMember:member];
            if (method) [rows addObject:method];
        }
    }
    return rows.copy;
}

+ (NSInteger)dyldIndexForImagePath:(NSString *)imagePath {
    const struct mach_header *target = RYGDyldHeaderForImagePath(imagePath);
    if (!target) return NSNotFound;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) if (_dyld_get_image_header(index) == target) return (NSInteger)index;
    return NSNotFound;
}

+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath {
    NSString *symbolCacheKey = RYGCanonicalImagePath(imagePath);
    @synchronized(self) { NSArray<RYGMachOSymbol *> *cached = gRYGSymbolIndexes[symbolCacheKey]; if (cached) return cached; }
    NSInteger imageIndex = [self dyldIndexForImagePath:imagePath];
    if (imageIndex == NSNotFound) return @[];
    const struct mach_header *generic = _dyld_get_image_header((uint32_t)imageIndex);
    if (!generic || generic->magic != MH_MAGIC_64) return @[];
    const struct mach_header_64 *header = (const struct mach_header_64 *)generic;
    if (!header->sizeofcmds || header->sizeofcmds > 64 * 1024 * 1024 || header->ncmds > 65535) return @[];

    const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
    const uint8_t *commandsEnd = cursor + header->sizeofcmds;
    const struct symtab_command *symtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (cursor + sizeof(struct load_command) > commandsEnd) return @[];
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > commandsEnd) return @[];
        if (command->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)cursor;
        else if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if (!strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname))) linkedit = segment;
        }
        cursor += command->cmdsize;
    }
    if (!symtab || !linkedit || symtab->nsyms > 2000000 || symtab->strsize > 512 * 1024 * 1024) return @[];
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t linkeditBase = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(linkeditBase + symtab->symoff);
    const char *strings = (const char *)(linkeditBase + symtab->stroff);

    NSMutableArray<RYGMachOSymbol *> *rows = [NSMutableArray array];
    for (uint32_t index = 0; index < symtab->nsyms; index++) {
        struct nlist_64 entry = symbols[index];
        if ((entry.n_type & N_STAB) || !entry.n_un.n_strx || entry.n_un.n_strx >= symtab->strsize) continue;
        const char *name = strings + entry.n_un.n_strx;
        size_t remaining = symtab->strsize - entry.n_un.n_strx;
        if (!name || !*name || !memchr(name, 0, remaining)) continue;
        RYGMachOSymbol *row = [RYGMachOSymbol new];
        row.name = [NSString stringWithUTF8String:name] ?: @"";
        row.external = (entry.n_type & N_EXT) != 0;
        uint8_t type = entry.n_type & N_TYPE;
        if (type == N_UNDF) row.kind = @"undefined";
        else if (type == N_ABS) row.kind = @"absolute";
        else if (type == N_SECT) row.kind = @"section";
        else if (type == N_INDR) row.kind = @"indirect";
        else row.kind = @"symbol";
        if (entry.n_value) row.address = type == N_ABS ? entry.n_value : (uint64_t)((intptr_t)entry.n_value + slide);
        [rows addObject:row];
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGMachOSymbol *left, RYGMachOSymbol *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    NSArray<RYGMachOSymbol *> *snapshot = rows.copy;
    @synchronized(self) { if (!gRYGSymbolIndexes) gRYGSymbolIndexes = [NSMutableDictionary dictionary]; if (symbolCacheKey.length) gRYGSymbolIndexes[symbolCacheKey] = snapshot; }
    return snapshot;
}

+ (void)invalidateMachOSymbolCache { @synchronized(self) { [gRYGSymbolIndexes removeAllObjects]; } }

+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method {
    return [method isKindOfClass:RYGRuntimeBoolMethod.class] && RYGInstallUnifiedBoolHook(method.overrideKey);
}

+ (NSNumber *)observedNativeValueForKey:(NSString *)overrideKey { return RYGObservedForKey(overrideKey); }
+ (NSNumber *)overrideForKey:(NSString *)overrideKey { return RYGOverrideForKey(overrideKey); }

+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return;
    if (value && !RYGInstallUnifiedBoolHook(method.overrideKey)) return;
    @synchronized(self) {
        if (!gRYGOverrides) gRYGOverrides = [NSMutableDictionary dictionary];
        if (value) gRYGOverrides[method.overrideKey] = @(value.boolValue);
        else [gRYGOverrides removeObjectForKey:method.overrideKey];
    }
}

+ (void)reinstallPersistedOverrides { }

@end
