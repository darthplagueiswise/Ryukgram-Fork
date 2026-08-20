#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeLiveObserver.h"
#import <objc/runtime.h>
#import <substrate.h>
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
    return a.lastPathComponent.length && [a.lastPathComponent isEqualToString:b.lastPathComponent];
}

static NSString *RYGMethodKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
}

static const char *RYGSkipTypeQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL RYGIsBoolType(const char *type) { type = RYGSkipTypeQualifiers(type); return type && strchr("BcC", *type); }
static BOOL RYGIsObjectType(const char *type) { type = RYGSkipTypeQualifiers(type); return type && (*type == '@' || *type == '#' || *type == ':'); }
static BOOL RYGIsIntegerRegisterType(const char *type) { type = RYGSkipTypeQualifiers(type); return type && strchr("BcCsSiIlLqQ", *type); }

static RYGRuntimeArgumentKind RYGArgumentKindForMethod(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char encoded[128] = {0}; method_getArgumentType(method, 2, encoded, sizeof(encoded));
    if (RYGIsObjectType(encoded)) return RYGRuntimeArgumentObject;
    if (RYGIsIntegerRegisterType(encoded)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}
static BOOL RYGMethodHasSupportedBoolABI(Method method) {
    if (!method) return NO;
    char encoded[64] = {0}; method_getReturnType(method, encoded, sizeof(encoded));
    RYGRuntimeArgumentKind kind = RYGArgumentKindForMethod(method);
    return RYGIsBoolType(encoded) && kind >= RYGRuntimeArgumentNone && kind <= RYGRuntimeArgumentInteger;
}

static BOOL RYGMethodIMPBelongsToImage(Method method, NSString *imagePath) {
    IMP imp = method ? method_getImplementation(method) : NULL;
    Dl_info info = {0};
    if (!imp || !dladdr((const void *)imp, &info) || !info.dli_fname) return NO;
    return RYGImagePathMatches([NSString stringWithUTF8String:info.dli_fname], imagePath);
}
static BOOL RYGClassDefinesOrContributesToImage(Class cls, NSString *imagePath) {
    if (!cls || !imagePath.length) return NO;
    const char *rawImage = class_getImageName(cls);
    if (rawImage && RYGImagePathMatches([NSString stringWithUTF8String:rawImage], imagePath)) return YES;
    for (NSUInteger pass = 0; pass < 2; pass++) {
        Class owner = pass ? object_getClass(cls) : cls;
        unsigned int count = 0; Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
        BOOL hit = NO;
        for (unsigned int i = 0; methods && i < count; i++) if (RYGMethodIMPBelongsToImage(methods[i], imagePath)) { hit = YES; break; }
        if (methods) free(methods);
        if (hit) return YES;
    }
    return NO;
}

static NSNumber *RYGOverrideForKey(NSString *key) { @synchronized(RYGRuntimeBrowserEngine.class) { return gRYGOverrides[key]; } }
static NSNumber *RYGObservedForKey(NSString *key) { @synchronized(RYGRuntimeBrowserEngine.class) { return gRYGObservedValues[key]; } }
static void RYGRememberObserved(NSString *key, BOOL value) {
    if (!key.length) return;
    __block BOOL changed = NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGObservedValues) gRYGObservedValues = [NSMutableDictionary dictionary];
        NSNumber *old = gRYGObservedValues[key];
        if (!old || old.boolValue != value) { gRYGObservedValues[key] = @(value); changed = YES; }
    }
    if (changed) dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification object:nil userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
    });
}

static BOOL RYGParseMethodKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
    if (key.length < 4) return NO;
    unichar prefix = [key characterAtIndex:0]; if (prefix != '+' && prefix != '-') return NO;
    NSString *body = [key substringFromIndex:1]; NSRange r = [body rangeOfString:@"#"];
    if (r.location == NSNotFound || r.location == 0 || NSMaxRange(r) >= body.length) return NO;
    if (className) *className = [body substringToIndex:r.location];
    if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(r)];
    if (classMethod) *classMethod = prefix == '+';
    return YES;
}

static BOOL RYGInstallUnifiedBoolHook(NSString *key) {
    if (!key.length) return NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGInstalledKeys) gRYGInstalledKeys = [NSMutableSet set];
        if ([gRYGInstalledKeys containsObject:key]) return YES;
        [gRYGInstalledKeys addObject:key];
    }
    NSString *className = nil, *selectorName = nil; BOOL classMethod = NO;
    if (!RYGParseMethodKey(key, &className, &selectorName, &classMethod)) goto fail;
    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGMethodHasSupportedBoolABI(method)) goto fail;

    RYGRuntimeArgumentKind kind = RYGArgumentKindForMethod(method);
    NSString *capturedKey = key.copy; SEL capturedSelector = selector;
    IMP *original = calloc(1, sizeof(IMP)); if (!original) goto fail;
    IMP replacement = NULL;
    if (kind == RYGRuntimeArgumentNone) replacement = imp_implementationWithBlock(^BOOL(id receiver) {
        BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
        RYGRememberObserved(capturedKey, native); NSNumber *forced = RYGOverrideForKey(capturedKey); return forced ? forced.boolValue : native;
    });
    else if (kind == RYGRuntimeArgumentObject) replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
        BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
        RYGRememberObserved(capturedKey, native); NSNumber *forced = RYGOverrideForKey(capturedKey); return forced ? forced.boolValue : native;
    });
    else if (kind == RYGRuntimeArgumentInteger) replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
        BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
        RYGRememberObserved(capturedKey, native); NSNumber *forced = RYGOverrideForKey(capturedKey); return forced ? forced.boolValue : native;
    });
    if (!replacement) { free(original); goto fail; }
    MSHookMessageEx(owner, selector, replacement, original);
    if (!*original) { imp_removeBlock(replacement); free(original); goto fail; }
    return YES;
fail:
    @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGInstalledKeys removeObject:key]; }
    return NO;
}

static RYGRuntimeBoolMethod *RYGBoolRow(Class cls, Method method, BOOL classMethod, NSString *imagePath) {
    if (!cls || !method || !RYGMethodHasSupportedBoolABI(method)) return nil;
    SEL selector = method_getName(method); if (!selector) return nil;
    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.imagePath = imagePath ?: @""; row.className = NSStringFromClass(cls) ?: @"";
    row.selectorName = NSStringFromSelector(selector) ?: @""; row.classMethod = classMethod;
    row.argumentKind = RYGArgumentKindForMethod(method);
    const char *types = method_getTypeEncoding(method); row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    return row;
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
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *raw = _dyld_get_image_name(i); if (!raw) continue;
        NSString *path = [[NSString stringWithUTF8String:raw] stringByStandardizingPath];
        BOOL main = RYGImagePathMatches(path, executable);
        BOOL framework = [path hasPrefix:[frameworks stringByAppendingString:@"/"]];
        BOOL dylib = [path hasPrefix:[bundle stringByAppendingString:@"/"]] && [path.pathExtension.lowercaseString isEqualToString:@"dylib"];
        if (main || framework || dylib) [images addObject:path];
    }
    return [images.array sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL am = RYGImagePathMatches(a, executable), bm = RYGImagePathMatches(b, executable);
        if (am != bm) return am ? NSOrderedAscending : NSOrderedDescending;
        return [[self shortNameForImagePath:a] localizedCaseInsensitiveCompare:[self shortNameForImagePath:b]];
    }];
}
+ (NSString *)shortNameForImagePath:(NSString *)imagePath { return imagePath.lastPathComponent.length ? imagePath.lastPathComponent : @"Image"; }
+ (BOOL)isStructuralNoiseSelectorName:(NSString *)selectorName {
    if (!selectorName.length) return YES;
    static NSSet *noise; static dispatch_once_t once; dispatch_once(&once, ^{ noise = [NSSet setWithArray:@[@"isEqual:",@"hash",@"class",@"self",@"superclass",@"respondsToSelector:",@"isKindOfClass:",@"isMemberOfClass:",@"conformsToProtocol:",@"methodForSelector:",@"description",@"debugDescription",@"retainCount",@"zone"]]; });
    return [noise containsObject:selectorName];
}

+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath {
    if (!imagePath.length) return @[];
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    unsigned int count = 0; const char **direct = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &count);
    if ((!direct || !count) && imagePath.stringByResolvingSymlinksInPath.length) {
        if (direct) free(direct); NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
        direct = objc_copyClassNamesForImage(resolved.fileSystemRepresentation, &count);
    }
    for (unsigned int i = 0; direct && i < count; i++) if (direct[i] && *direct[i]) [names addObject:[NSString stringWithUTF8String:direct[i]]];
    if (direct) free(direct);

    int total = objc_getClassList(NULL, 0);
    if (total > 0 && total < 500000) {
        Class __unsafe_unretained *classes = (Class __unsafe_unretained *)calloc((size_t)total, sizeof(Class));
        int filled = classes ? objc_getClassList(classes, total) : 0;
        for (int i = 0; i < filled; i++) {
            Class cls = classes[i]; NSString *name = cls ? NSStringFromClass(cls) : nil;
            if (name.length && ![names containsObject:name] && RYGClassDefinesOrContributesToImage(cls, imagePath)) [names addObject:name];
        }
        if (classes) free(classes);
    }
    NSArray *ordered = [names.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:ordered.count];
    for (NSString *name in ordered) { RYGRuntimeClassRow *row = [RYGRuntimeClassRow new]; row.imagePath = imagePath; row.className = name; [rows addObject:row]; }
    return rows.copy;
}

+ (NSArray<RYGRuntimeMemberRow *> *)membersForClassName:(NSString *)className imagePath:(NSString *)imagePath {
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    if (!cls || !imagePath.length) return @[];
    const char *rawClassImage = class_getImageName(cls);
    BOOL classDefinedHere = rawClassImage && RYGImagePathMatches([NSString stringWithUTF8String:rawClassImage], imagePath);
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger pass = 0; pass < 2; pass++) {
        BOOL classMember = pass == 1; Class owner = classMember ? object_getClass(cls) : cls;
        unsigned int methodCount = 0; Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
        for (unsigned int i = 0; methods && i < methodCount; i++) {
            Method method = methods[i]; if (!classDefinedHere && !RYGMethodIMPBelongsToImage(method, imagePath)) continue;
            SEL selector = method_getName(method); NSString *name = selector ? NSStringFromSelector(selector) : @"";
            if ([self isStructuralNoiseSelectorName:name]) continue;
            RYGRuntimeMemberRow *row = [RYGRuntimeMemberRow new]; row.imagePath = imagePath; row.className = className; row.name = name;
            row.kind = classMember ? RYGRuntimeMemberClassMethod : RYGRuntimeMemberInstanceMethod;
            const char *types = method_getTypeEncoding(method); row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
            row.hookableBool = RYGMethodHasSupportedBoolABI(method); row.argumentKind = row.hookableBool ? RYGArgumentKindForMethod(method) : RYGRuntimeArgumentNone;
            [rows addObject:row];
        }
        if (methods) free(methods);
        if (classDefinedHere) {
            unsigned int propertyCount = 0; objc_property_t *properties = owner ? class_copyPropertyList(owner, &propertyCount) : NULL;
            for (unsigned int i = 0; properties && i < propertyCount; i++) {
                const char *n = property_getName(properties[i]), *a = property_getAttributes(properties[i]);
                RYGRuntimeMemberRow *row = [RYGRuntimeMemberRow new]; row.imagePath = imagePath; row.className = className;
                row.name = n ? [NSString stringWithUTF8String:n] : @""; row.typeEncoding = a ? [NSString stringWithUTF8String:a] : @"";
                row.kind = classMember ? RYGRuntimeMemberClassProperty : RYGRuntimeMemberInstanceProperty; [rows addObject:row];
            }
            if (properties) free(properties);
        }
    }
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMemberRow *a, RYGRuntimeMemberRow *b) { if (a.kind != b.kind) return a.kind < b.kind ? NSOrderedAscending : NSOrderedDescending; return [a.name localizedCaseInsensitiveCompare:b.name]; }];
    return rows.copy;
}

+ (RYGRuntimeBoolMethod *)boolMethodForMember:(RYGRuntimeMemberRow *)member {
    if (!member.isMethod || !member.isHookableBool || !member.className.length || !member.name.length) return nil;
    Class cls = objc_lookUpClass(member.className.UTF8String); BOOL cm = member.kind == RYGRuntimeMemberClassMethod;
    Class owner = cls ? (cm ? object_getClass(cls) : cls) : Nil; Method method = owner ? class_getInstanceMethod(owner, NSSelectorFromString(member.name)) : NULL;
    return RYGBoolRow(cls, method, cm, member.imagePath);
}
+ (NSArray<RYGRuntimeBoolMethod *> *)boolMethodsForImagePath:(NSString *)imagePath scope:(RYGRuntimeBrowserScope)scope {
    (void)scope; NSMutableArray *out = [NSMutableArray array];
    for (RYGRuntimeClassRow *c in [self classesForImagePath:imagePath]) for (RYGRuntimeMemberRow *m in [self membersForClassName:c.className imagePath:imagePath]) { RYGRuntimeBoolMethod *b = [self boolMethodForMember:m]; if (b) [out addObject:b]; }
    return out.copy;
}

+ (NSInteger)dyldIndexForImagePath:(NSString *)imagePath {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) { const char *raw = _dyld_get_image_name(i); if (raw && RYGImagePathMatches([NSString stringWithUTF8String:raw], imagePath)) return i; }
    return NSNotFound;
}
+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath {
    NSInteger idx = [self dyldIndexForImagePath:imagePath]; if (idx == NSNotFound) return @[];
    const struct mach_header *generic = _dyld_get_image_header((uint32_t)idx); if (!generic || generic->magic != MH_MAGIC_64) return @[];
    const struct mach_header_64 *header = (const struct mach_header_64 *)generic;
    const uint8_t *cursor = (const uint8_t *)header + sizeof(*header); const struct symtab_command *symtab = NULL; const struct segment_command_64 *linkedit = NULL;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *cmd = (const struct load_command *)cursor; if (cmd->cmdsize < sizeof(*cmd)) return @[];
        if (cmd->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)cursor;
        else if (cmd->cmd == LC_SEGMENT_64) { const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor; if (!strncmp(seg->segname, SEG_LINKEDIT, sizeof(seg->segname))) linkedit = seg; }
        cursor += cmd->cmdsize;
    }
    if (!symtab || !linkedit || symtab->nsyms > 2000000) return @[];
    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)idx); uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff); const char *strings = (const char *)(base + symtab->stroff);
    NSMutableArray *out = [NSMutableArray array];
    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        struct nlist_64 e = symbols[i]; if ((e.n_type & N_STAB) || !e.n_un.n_strx || e.n_un.n_strx >= symtab->strsize) continue;
        const char *name = strings + e.n_un.n_strx; size_t remaining = symtab->strsize - e.n_un.n_strx; if (!name || !*name || !memchr(name, 0, remaining)) continue;
        RYGMachOSymbol *row = [RYGMachOSymbol new]; row.name = [NSString stringWithUTF8String:name] ?: @""; row.external = (e.n_type & N_EXT) != 0;
        uint8_t type = e.n_type & N_TYPE; row.kind = type == N_UNDF ? @"undefined" : type == N_ABS ? @"absolute" : type == N_SECT ? @"section" : type == N_INDR ? @"indirect" : @"symbol";
        if (e.n_value) row.address = type == N_ABS ? e.n_value : (uint64_t)((intptr_t)e.n_value + slide); [out addObject:row];
    }
    [out sortUsingComparator:^NSComparisonResult(RYGMachOSymbol *a, RYGMachOSymbol *b) { return [a.name localizedCaseInsensitiveCompare:b.name]; }]; return out.copy;
}

+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method { return [method isKindOfClass:RYGRuntimeBoolMethod.class] && RYGInstallUnifiedBoolHook(method.overrideKey); }
+ (NSNumber *)observedNativeValueForKey:(NSString *)overrideKey { return RYGObservedForKey(overrideKey); }
+ (NSNumber *)overrideForKey:(NSString *)overrideKey { return RYGOverrideForKey(overrideKey); }
+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return;
    if (value && !RYGInstallUnifiedBoolHook(method.overrideKey)) return;
    @synchronized(self) { if (!gRYGOverrides) gRYGOverrides = [NSMutableDictionary dictionary]; if (value) gRYGOverrides[method.overrideKey] = @(value.boolValue); else [gRYGOverrides removeObjectForKey:method.overrideKey]; }
}
+ (void)reinstallPersistedOverrides { }
@end
