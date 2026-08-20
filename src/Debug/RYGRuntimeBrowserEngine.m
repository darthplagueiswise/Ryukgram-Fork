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

static NSMutableDictionary<NSString *, NSNumber *> *gOverrides;
static NSMutableDictionary<NSString *, NSNumber *> *gObserved;
static NSMutableSet<NSString *> *gInstalled;

#pragma mark - Loaded-image identity

static NSString *RYGCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static NSInteger RYGDyldIndexForPath(NSString *path) {
    if (!path.length) return NSNotFound;
    NSString *wanted = RYGCanonicalPath(path);
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw) continue;
        NSString *loaded = [NSString stringWithUTF8String:raw];
        if ([RYGCanonicalPath(loaded) isEqualToString:wanted]) return (NSInteger)index;
    }
    return NSNotFound;
}

static const struct mach_header *RYGHeaderForPath(NSString *path) {
    NSInteger index = RYGDyldIndexForPath(path);
    return index == NSNotFound ? NULL : _dyld_get_image_header((uint32_t)index);
}

static NSString *RYGDyldNameForPath(NSString *path) {
    NSInteger index = RYGDyldIndexForPath(path);
    if (index == NSNotFound) return nil;
    const char *raw = _dyld_get_image_name((uint32_t)index);
    return raw ? [NSString stringWithUTF8String:raw] : nil;
}

static BOOL RYGSameLoadedImage(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    const struct mach_header *a = RYGHeaderForPath(left);
    const struct mach_header *b = RYGHeaderForPath(right);
    if (a && b) return a == b;
    return [RYGCanonicalPath(left) isEqualToString:RYGCanonicalPath(right)];
}

static BOOL RYGMethodBelongsToImage(Method method, NSString *imagePath) {
    IMP imp = method ? method_getImplementation(method) : NULL;
    if (!imp || !imagePath.length) return NO;
    Dl_info info = {0};
    if (!dladdr((const void *)imp, &info)) return NO;
    const struct mach_header *target = RYGHeaderForPath(imagePath);
    if (target && info.dli_fbase) return info.dli_fbase == (const void *)target;
    return info.dli_fname && RYGSameLoadedImage([NSString stringWithUTF8String:info.dli_fname], imagePath);
}

static BOOL RYGClassDefinedInImage(Class cls, NSString *imagePath) {
    const char *raw = cls ? class_getImageName(cls) : NULL;
    return raw && RYGSameLoadedImage([NSString stringWithUTF8String:raw], imagePath);
}

static BOOL RYGClassContributesToImage(Class cls, NSString *imagePath) {
    if (RYGClassDefinedInImage(cls, imagePath)) return YES;
    for (NSUInteger pass = 0; pass < 2; pass++) {
        Class owner = pass ? object_getClass(cls) : cls;
        unsigned int count = 0;
        Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
        BOOL found = NO;
        for (unsigned int index = 0; methods && index < count; index++) {
            if (RYGMethodBelongsToImage(methods[index], imagePath)) {
                found = YES;
                break;
            }
        }
        if (methods) free(methods);
        if (found) return YES;
    }
    return NO;
}

#pragma mark - Objective-C ABI

static const char *RYGUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGIsBoolType(const char *type) {
    type = RYGUnqualified(type);
    return type && *type && strchr("BcC", *type) != NULL;
}

static RYGRuntimeArgumentKind RYGArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;

    char encoded[128] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *type = RYGUnqualified(encoded);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGHookableBoolABI(Method method) {
    if (!method) return NO;
    char returned[64] = {0};
    method_getReturnType(method, returned, sizeof(returned));
    RYGRuntimeArgumentKind kind = RYGArgumentKind(method);
    return RYGIsBoolType(returned) && kind >= RYGRuntimeArgumentNone && kind <= RYGRuntimeArgumentInteger;
}

static NSString *RYGMethodKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
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

#pragma mark - Process-local observation / overrides

static NSNumber *RYGOverride(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { return gOverrides[key]; }
}

static NSNumber *RYGObserved(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { return gObserved[key]; }
}

static void RYGRecordNative(NSString *key, BOOL value) {
    if (!key.length) return;
    BOOL changed = NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gObserved) gObserved = [NSMutableDictionary dictionary];
        NSNumber *previous = gObserved[key];
        if (!previous || previous.boolValue != value) {
            gObserved[key] = @(value);
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

static void RYGUnmarkInstalled(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) { [gInstalled removeObject:key]; }
}

static BOOL RYGInstallBoolTrampoline(NSString *key) {
    if (!key.length) return NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gInstalled) gInstalled = [NSMutableSet set];
        if ([gInstalled containsObject:key]) return YES;
        [gInstalled addObject:key];
    }

    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGParseMethodKey(key, &className, &selectorName, &classMethod)) {
        RYGUnmarkInstalled(key);
        return NO;
    }

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGHookableBoolABI(method)) {
        RYGUnmarkInstalled(key);
        return NO;
    }

    RYGRuntimeArgumentKind kind = RYGArgumentKind(method);
    NSString *capturedKey = key.copy;
    SEL capturedSelector = selector;
    IMP *original = calloc(1, sizeof(IMP));
    if (!original) {
        RYGUnmarkInstalled(key);
        return NO;
    }

    IMP replacement = NULL;
    if (kind == RYGRuntimeArgumentNone) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
            RYGRecordNative(capturedKey, native);
            NSNumber *forced = RYGOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
            RYGRecordNative(capturedKey, native);
            NSNumber *forced = RYGOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
            RYGRecordNative(capturedKey, native);
            NSNumber *forced = RYGOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    }

    if (!replacement) {
        free(original);
        RYGUnmarkInstalled(key);
        return NO;
    }

    MSHookMessageEx(owner, selector, replacement, original);
    if (!*original) {
        imp_removeBlock(replacement);
        free(original);
        RYGUnmarkInstalled(key);
        return NO;
    }
    return YES;
}

#pragma mark - Models

@implementation RYGRuntimeClassRow @end

@implementation RYGRuntimeMemberRow
- (BOOL)method {
    return self.kind == RYGRuntimeMemberInstanceMethod || self.kind == RYGRuntimeMemberClassMethod;
}
- (BOOL)classMember {
    return self.kind == RYGRuntimeMemberClassMethod || self.kind == RYGRuntimeMemberClassProperty;
}
@end

@implementation RYGRuntimeBoolMethod
- (NSString *)overrideKey { return RYGMethodKey(self.className, self.selectorName, self.classMethod); }
- (NSNumber *)overrideValue { return [RYGRuntimeBrowserEngine overrideForKey:self.overrideKey]; }
- (NSNumber *)liveValue { return [RYGRuntimeBrowserEngine observedNativeValueForKey:self.overrideKey]; }
@end

@implementation RYGMachOSymbol @end

#pragma mark - Engine

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
        BOOL main = RYGSameLoadedImage(path, executable);
        BOOL framework = [path hasPrefix:[frameworks stringByAppendingString:@"/"]];
        BOOL bundledDylib = [path hasPrefix:[bundle stringByAppendingString:@"/"]] && [path.pathExtension.lowercaseString isEqualToString:@"dylib"];
        if (main || framework || bundledDylib) [images addObject:path];
    }

    return [images.array sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        BOOL leftMain = RYGSameLoadedImage(left, executable);
        BOOL rightMain = RYGSameLoadedImage(right, executable);
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
    if (!imagePath.length || !RYGHeaderForPath(imagePath)) return @[];

    NSMutableSet<NSString *> *names = [NSMutableSet set];
    NSString *runtimeName = RYGDyldNameForPath(imagePath) ?: imagePath;
    unsigned int directCount = 0;
    const char **direct = objc_copyClassNamesForImage(runtimeName.fileSystemRepresentation, &directCount);
    for (unsigned int index = 0; direct && index < directCount; index++) {
        if (!direct[index] || !*direct[index]) continue;
        NSString *name = [NSString stringWithUTF8String:direct[index]];
        if (name.length) [names addObject:name];
    }
    if (direct) free(direct);

    // Complete the per-image view without ever retaining Class as an Objective-C
    // object. This also catches categories whose owning class was born elsewhere.
    int total = objc_getClassList(NULL, 0);
    if (total > 0 && total < 500000) {
        Class __unsafe_unretained *classes = (Class __unsafe_unretained *)calloc((size_t)total, sizeof(Class));
        int filled = classes ? objc_getClassList(classes, total) : 0;
        for (int index = 0; index < filled; index++) {
            Class cls = classes[index];
            if (!cls || !RYGClassContributesToImage(cls, imagePath)) continue;
            const char *rawName = class_getName(cls);
            if (!rawName || !*rawName) continue;
            NSString *name = [NSString stringWithUTF8String:rawName];
            if (name.length) [names addObject:name];
        }
        if (classes) free(classes);
    }

    NSArray<NSString *> *ordered = [names.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray arrayWithCapacity:ordered.count];
    for (NSString *name in ordered) {
        Class cls = objc_lookUpClass(name.UTF8String);
        if (!cls) continue;
        RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
        row.imagePath = imagePath;
        row.className = name;

        BOOL classDefinedHere = RYGClassDefinedInImage(cls, imagePath);
        NSUInteger counts[2] = {0, 0};
        NSUInteger properties = 0;
        for (NSUInteger pass = 0; pass < 2; pass++) {
            Class owner = pass ? object_getClass(cls) : cls;
            unsigned int methodCount = 0;
            Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
            for (unsigned int index = 0; methods && index < methodCount; index++) {
                if (classDefinedHere || RYGMethodBelongsToImage(methods[index], imagePath)) counts[pass]++;
            }
            if (methods) free(methods);
            if (classDefinedHere) {
                unsigned int propertyCount = 0;
                objc_property_t *list = owner ? class_copyPropertyList(owner, &propertyCount) : NULL;
                properties += propertyCount;
                if (list) free(list);
            }
        }
        row.instanceMethodCount = counts[0];
        row.classMethodCount = counts[1];
        row.propertyCount = properties;
        [rows addObject:row];
    }
    return rows.copy;
}

+ (NSArray<RYGRuntimeMemberRow *> *)membersForClassName:(NSString *)className imagePath:(NSString *)imagePath {
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    if (!cls || !imagePath.length || !RYGHeaderForPath(imagePath)) return @[];

    BOOL classDefinedHere = RYGClassDefinedInImage(cls, imagePath);
    NSMutableArray<RYGRuntimeMemberRow *> *rows = [NSMutableArray array];
    for (NSUInteger pass = 0; pass < 2; pass++) {
        BOOL classMember = pass == 1;
        Class owner = classMember ? object_getClass(cls) : cls;

        unsigned int methodCount = 0;
        Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
        for (unsigned int index = 0; methods && index < methodCount; index++) {
            Method method = methods[index];
            if (!classDefinedHere && !RYGMethodBelongsToImage(method, imagePath)) continue;
            SEL selector = method_getName(method);
            NSString *name = selector ? NSStringFromSelector(selector) : @"";
            if ([self isStructuralNoiseSelectorName:name]) continue;

            RYGRuntimeMemberRow *row = [RYGRuntimeMemberRow new];
            row.imagePath = imagePath;
            row.className = className;
            row.name = name;
            row.kind = classMember ? RYGRuntimeMemberClassMethod : RYGRuntimeMemberInstanceMethod;
            const char *types = method_getTypeEncoding(method);
            row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
            row.hookableBool = RYGHookableBoolABI(method);
            row.argumentKind = row.hookableBool ? RYGArgumentKind(method) : RYGRuntimeArgumentNone;
            [rows addObject:row];
        }
        if (methods) free(methods);

        if (classDefinedHere) {
            unsigned int propertyCount = 0;
            objc_property_t *properties = owner ? class_copyPropertyList(owner, &propertyCount) : NULL;
            for (unsigned int index = 0; properties && index < propertyCount; index++) {
                const char *rawName = property_getName(properties[index]);
                const char *rawAttributes = property_getAttributes(properties[index]);
                RYGRuntimeMemberRow *row = [RYGRuntimeMemberRow new];
                row.imagePath = imagePath;
                row.className = className;
                row.name = rawName ? [NSString stringWithUTF8String:rawName] : @"";
                row.typeEncoding = rawAttributes ? [NSString stringWithUTF8String:rawAttributes] : @"";
                row.kind = classMember ? RYGRuntimeMemberClassProperty : RYGRuntimeMemberInstanceProperty;
                [rows addObject:row];
            }
            if (properties) free(properties);
        }
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMemberRow *left, RYGRuntimeMemberRow *right) {
        if (left.kind != right.kind) return left.kind < right.kind ? NSOrderedAscending : NSOrderedDescending;
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return rows.copy;
}

+ (RYGRuntimeBoolMethod *)boolMethodForMember:(RYGRuntimeMemberRow *)member {
    if (!member.method || !member.hookableBool || !member.className.length || !member.name.length) return nil;
    Class cls = objc_lookUpClass(member.className.UTF8String);
    BOOL classMethod = member.kind == RYGRuntimeMemberClassMethod;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner ? class_getInstanceMethod(owner, NSSelectorFromString(member.name)) : NULL;
    if (!method || !RYGHookableBoolABI(method)) return nil;

    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.imagePath = member.imagePath ?: @"";
    row.className = member.className ?: @"";
    row.selectorName = member.name ?: @"";
    row.typeEncoding = member.typeEncoding ?: @"";
    row.classMethod = classMethod;
    row.argumentKind = RYGArgumentKind(method);
    return row;
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

+ (NSArray<RYGMachOSymbol *> *)machOSymbolsForImagePath:(NSString *)imagePath {
    NSInteger imageIndex = RYGDyldIndexForPath(imagePath);
    if (imageIndex == NSNotFound) return @[];
    const struct mach_header *generic = _dyld_get_image_header((uint32_t)imageIndex);
    if (!generic || generic->magic != MH_MAGIC_64) return @[];
    const struct mach_header_64 *header = (const struct mach_header_64 *)generic;
    if (!header->sizeofcmds || header->sizeofcmds > 64 * 1024 * 1024 || header->ncmds > 65535) return @[];

    const uint8_t *cursor = (const uint8_t *)header + sizeof(*header);
    const uint8_t *end = cursor + header->sizeofcmds;
    const struct symtab_command *symtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    for (uint32_t index = 0; index < header->ncmds; index++) {
        if (cursor + sizeof(struct load_command) > end) return @[];
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) return @[];
        if (command->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)cursor;
        else if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)cursor;
            if (!strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname))) linkedit = segment;
        }
        cursor += command->cmdsize;
    }
    if (!symtab || !linkedit || symtab->nsyms > 2000000 || symtab->strsize > 512 * 1024 * 1024) return @[];

    intptr_t slide = _dyld_get_image_vmaddr_slide((uint32_t)imageIndex);
    uintptr_t base = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
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
        row.kind = type == N_UNDF ? @"undefined" : type == N_ABS ? @"absolute" : type == N_SECT ? @"section" : type == N_INDR ? @"indirect" : @"symbol";
        if (entry.n_value) row.address = type == N_ABS ? entry.n_value : (uint64_t)((intptr_t)entry.n_value + slide);
        [rows addObject:row];
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGMachOSymbol *left, RYGMachOSymbol *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
    }];
    return rows.copy;
}

+ (BOOL)observeMethod:(RYGRuntimeBoolMethod *)method {
    return [method isKindOfClass:RYGRuntimeBoolMethod.class] && RYGInstallBoolTrampoline(method.overrideKey);
}

+ (NSNumber *)observedNativeValueForKey:(NSString *)overrideKey {
    return RYGObserved(overrideKey);
}

+ (NSNumber *)overrideForKey:(NSString *)overrideKey {
    return RYGOverride(overrideKey);
}

+ (void)setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (![method isKindOfClass:RYGRuntimeBoolMethod.class] || !method.overrideKey.length) return;
    if (value && !RYGInstallBoolTrampoline(method.overrideKey)) return;
    @synchronized(self) {
        if (!gOverrides) gOverrides = [NSMutableDictionary dictionary];
        if (value) gOverrides[method.overrideKey] = @(value.boolValue);
        else [gOverrides removeObjectForKey:method.overrideKey];
    }
}

+ (void)reinstallPersistedOverrides { }

@end
