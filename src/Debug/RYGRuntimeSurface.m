#import "RYGRuntimeSurface.h"
#import "RYGRuntimeValueStore.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdlib.h>

@implementation RYGRuntimeEntry
@end

@implementation RYGRuntimeSurfaceSpec
+ (NSArray<RYGRuntimeSurfaceSpec *> *)allSurfaces {
    return [RYGRuntimeScanner runtimeImageSurfaces];
}
@end

#pragma mark - Image ownership / naming

static NSString *RYGCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGPathLooksInsideApp(NSString *path) {
    if (!path.length) return NO;
    NSString *candidate = RYGCanonicalPath(path);
    NSString *bundle = RYGCanonicalPath(NSBundle.mainBundle.bundlePath ?: @"");
    if (bundle.length && ([candidate isEqualToString:bundle] ||
                          [candidate hasPrefix:[bundle stringByAppendingString:@"/"]])) {
        return YES;
    }

    NSString *component = NSBundle.mainBundle.bundleURL.lastPathComponent ?: @"Instagram.app";
    if (component.length &&
        [candidate rangeOfString:[NSString stringWithFormat:@"/%@/", component]
                         options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }
    return [candidate rangeOfString:@"/Instagram.app/"
                            options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL RYGPathsEqual(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    return [RYGCanonicalPath(left) isEqualToString:RYGCanonicalPath(right)];
}

NSString *RYGRuntimeImageNameForPath(NSString *imagePath) {
    if (!imagePath.length) return @"Runtime";
    NSString *last = imagePath.lastPathComponent ?: @"";
    NSString *executable = NSBundle.mainBundle.executablePath ?: @"";
    if (RYGPathsEqual(imagePath, executable) ||
        (last.length && [last isEqualToString:executable.lastPathComponent])) {
        return @"Instagram Executable";
    }
    for (NSString *part in imagePath.pathComponents.reverseObjectEnumerator) {
        if ([part hasSuffix:@".framework"]) return part;
    }
    return last.length ? last : imagePath;
}

static NSArray<NSString *> *RYGLoadedAppImagePaths(void) {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t index = 0; index < imageCount; index++) {
        const char *raw = _dyld_get_image_name(index);
        if (!raw || !*raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        if (!path.length || !RYGPathLooksInsideApp(path)) continue;
        [paths addObject:path];
    }

    NSString *executable = NSBundle.mainBundle.executablePath ?: @"";
    if (executable.length && RYGPathLooksInsideApp(executable)) {
        NSUInteger existing = [paths indexOfObjectPassingTest:^BOOL(NSString *candidate, NSUInteger idx, BOOL *stop) {
            (void)idx;
            if (RYGPathsEqual(candidate, executable)) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];
        if (existing == NSNotFound) [paths insertObject:executable atIndex:0];
    }
    return paths.array ?: @[];
}

#pragma mark - Live class enumeration

static NSUInteger RYGEnumerateClassesForImage(NSString *imagePath, void (^block)(Class cls)) {
    if (!imagePath.length) return 0;
    unsigned int count = 0;
    const char **names = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &count);
    if (!names || !count || count > 500000) {
        if (names) free(names);
        return 0;
    }

    NSUInteger emitted = 0;
    for (unsigned int index = 0; index < count; index++) {
        const char *rawName = names[index];
        if (!rawName || !*rawName) continue;
        Class cls = objc_getClass(rawName);
        if (!cls) continue;
        emitted++;
        if (block) block(cls);
    }
    free(names);
    return emitted;
}

static void RYGEnumerateAppClasses(void (^block)(Class cls)) {
    if (!block) return;
    unsigned int count = 0;
    Class __unsafe_unretained *classes = objc_copyClassList(&count);
    if (!classes || !count || count > 500000) {
        if (classes) free(classes);
        return;
    }
    for (unsigned int index = 0; index < count; index++) {
        Class cls = classes[index];
        const char *rawPath = cls ? class_getImageName(cls) : NULL;
        NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
        if (RYGPathLooksInsideApp(path)) block(cls);
    }
    free(classes);
}

#pragma mark - Live naming / filtering

static NSArray<NSString *> *RYGRawTokens(NSString *value) {
    if (!value.length) return @[];
    NSMutableString *expanded = [NSMutableString stringWithCapacity:value.length * 2];
    NSCharacterSet *upper = NSCharacterSet.uppercaseLetterCharacterSet;
    NSCharacterSet *lower = NSCharacterSet.lowercaseLetterCharacterSet;
    NSCharacterSet *alnum = NSCharacterSet.alphanumericCharacterSet;
    unichar previous = 0;
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar current = [value characterAtIndex:index];
        if ([upper characterIsMember:current] && previous && [lower characterIsMember:previous]) {
            [expanded appendString:@"_"];
        }
        if ([alnum characterIsMember:current]) [expanded appendFormat:@"%C", current];
        else [expanded appendString:@"_"];
        previous = current;
    }
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in [expanded.lowercaseString componentsSeparatedByString:@"_"]) {
        if (part.length) [tokens addObject:part];
    }
    return tokens.copy;
}

static NSSet<NSString *> *RYGStopWords(void) {
    static NSSet<NSString *> *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        words = [NSSet setWithArray:@[
            @"is", @"has", @"have", @"can", @"could", @"should", @"would",
            @"get", @"set", @"for", @"from", @"with", @"without", @"and", @"or",
            @"the", @"of", @"to", @"a", @"an", @"value", @"flag", @"feature",
            @"enabled", @"enable", @"disabled", @"disable", @"active", @"available",
            @"availability", @"launched", @"launch", @"supported", @"support",
            @"ios", @"objc", @"impl", @"implementation", @"property", @"properties",
            @"provider", @"manager"
        ]];
    });
    return words;
}

static NSString *RYGDisplayToken(NSString *token) {
    static NSSet<NSString *> *acronyms;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        acronyms = [NSSet setWithArray:@[
            @"ai", @"ab", @"mc", @"ui", @"ux", @"api", @"qpl", @"foa",
            @"ig", @"igds", @"bslds", @"lid", @"fb"
        ]];
    });
    return [acronyms containsObject:token] ? token.uppercaseString : token.localizedCapitalizedString;
}

NSString *RYGRuntimeFamilyForSelector(NSString *selectorName, NSString *className) {
    NSArray<NSString *> *source = RYGRawTokens(selectorName.length ? selectorName : className);
    NSMutableArray<NSString *> *meaningful = [NSMutableArray array];
    NSSet<NSString *> *stop = RYGStopWords();
    for (NSString *token in source) {
        if ([stop containsObject:token]) continue;
        [meaningful addObject:token];
        if (meaningful.count == 3) break;
    }
    if (!meaningful.count && className.length) {
        for (NSString *token in RYGRawTokens(className)) {
            if (![stop containsObject:token]) [meaningful addObject:token];
            if (meaningful.count == 3) break;
        }
    }
    if (!meaningful.count) return @"Other Runtime";
    NSMutableArray<NSString *> *display = [NSMutableArray arrayWithCapacity:meaningful.count];
    for (NSString *token in meaningful) [display addObject:RYGDisplayToken(token)];
    return [display componentsJoinedByString:@" "];
}

NSString *RYGRuntimeSubcategoryForEntry(NSString *selectorName, NSString *className, NSString *imagePath) {
    NSString *family = RYGRuntimeFamilyForSelector(selectorName, className);
    NSString *owner = className.length ? className : RYGRuntimeImageNameForPath(imagePath);
    return owner.length ? [NSString stringWithFormat:@"%@ — %@", owner, family] : family;
}

NSArray<NSString *> *RYGRuntimeQueryTerms(NSString *query) {
    NSMutableOrderedSet<NSString *> *terms = [NSMutableOrderedSet orderedSet];
    for (NSString *group in [(query ?: @"").lowercaseString
             componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        for (NSString *term in [group componentsSeparatedByString:@"|"]) {
            if (term.length) [terms addObject:term];
        }
    }
    return terms.array;
}

static BOOL RYGMethodIsSupported(Method method, NSString **selectorName, NSString **typeCode) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    NSString *selector = NSStringFromSelector(method_getName(method));
    if (!RYGRuntimeValueSelectorIsSafeGetter(selector)) return NO;
    char raw[64] = {0};
    method_getReturnType(method, raw, sizeof(raw));
    NSString *type = [NSString stringWithUTF8String:raw] ?: @"";
    if (!RYGRuntimeValueTypeIsSupported(type)) return NO;
    if (selectorName) *selectorName = selector;
    if (typeCode) *typeCode = type;
    return YES;
}

static RYGRuntimeSurfaceSpec *RYGSurface(NSString *identifier,
                                         NSString *title,
                                         NSString *subtitle,
                                         NSString *icon) {
    RYGRuntimeSurfaceSpec *surface = [RYGRuntimeSurfaceSpec new];
    surface.surfaceID = identifier ?: @"runtime";
    surface.title = title ?: @"Runtime";
    surface.subtitle = subtitle ?: @"";
    surface.icon = icon ?: @"terminal";
    surface.selectorTokens = @[];
    surface.scanInstanceMethods = YES;
    surface.scanClassMethods = YES;
    surface.scanProperties = YES;
    surface.runtimeGenerated = YES;
    return surface;
}

static BOOL RYGAnyTokenMatches(NSArray<NSString *> *tokens, NSString *haystack) {
    if (!tokens.count) return YES;
    NSString *lower = haystack.lowercaseString ?: @"";
    for (NSString *token in tokens) {
        if (token.length && [lower containsString:token.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL RYGClassMatchesSurface(RYGRuntimeSurfaceSpec *spec, Class cls) {
    const char *raw = cls ? class_getImageName(cls) : NULL;
    NSString *path = raw ? [NSString stringWithUTF8String:raw] : @"";
    if (spec.runtimeImagePath.length) return RYGPathsEqual(path, spec.runtimeImagePath);
    return RYGPathLooksInsideApp(path);
}

static void RYGAddEntry(NSMutableArray<RYGRuntimeEntry *> *output,
                        NSMutableSet<NSString *> *seen,
                        RYGRuntimeSurfaceSpec *spec,
                        Class cls,
                        BOOL meta,
                        NSString *selector,
                        BOOL property,
                        NSString *typeCode) {
    if (!selector.length || !typeCode.length) return;
    NSString *className = NSStringFromClass(cls);
    if (!className.length) return;
    NSString *typeName = RYGRuntimeValueTypeName(typeCode);
    if (!typeName.length) return;

    const char *rawPath = class_getImageName(cls);
    NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
    NSString *imageName = RYGRuntimeImageNameForPath(path);
    NSString *family = RYGRuntimeFamilyForSelector(selector, className);
    if (spec.runtimeFamilyKey.length && ![family isEqualToString:spec.runtimeFamilyKey]) return;
    NSString *subcategory = RYGRuntimeSubcategoryForEntry(selector, className, path);
    NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@",
        imageName ?: @"", className, selector, typeName, family ?: @"", subcategory ?: @""];
    if (!RYGAnyTokenMatches(spec.selectorTokens, haystack)) return;

    NSString *uid = RYGRuntimeValueUID(className, selector, meta);
    if (!uid.length || [seen containsObject:uid]) return;
    [seen addObject:uid];

    RYGRuntimeEntry *entry = [RYGRuntimeEntry new];
    entry.surfaceID = spec.surfaceID;
    entry.className = className;
    entry.classMethod = meta;
    entry.property = property;
    entry.selectorName = selector;
    entry.displayName = selector;
    entry.returnType = typeName;
    entry.typeCode = RYGRuntimeValueNormalizedType(typeCode);
    entry.typeName = typeName;
    entry.overrideKey = uid;
    entry.imagePath = path;
    entry.imageName = imageName;
    entry.runtimeFamily = family;
    entry.runtimeSubcategory = subcategory;
    [output addObject:entry];
}

static void RYGScanClass(RYGRuntimeSurfaceSpec *spec,
                         Class cls,
                         NSMutableArray<RYGRuntimeEntry *> *output,
                         NSMutableSet<NSString *> *seen) {
    if (!spec || !cls || !RYGClassMatchesSurface(spec, cls)) return;

    if (spec.scanProperties) {
        unsigned int propertyCount = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
        for (unsigned int index = 0; properties && index < propertyCount; index++) {
            const char *rawName = property_getName(properties[index]);
            if (!rawName) continue;
            NSString *selector = [NSString stringWithUTF8String:rawName] ?: @"";
            Method method = class_getInstanceMethod(cls, NSSelectorFromString(selector));
            NSString *liveSelector = nil;
            NSString *typeCode = nil;
            if (RYGMethodIsSupported(method, &liveSelector, &typeCode)) {
                RYGAddEntry(output, seen, spec, cls, NO, liveSelector, YES, typeCode);
            }
        }
        if (properties) free(properties);
    }

    for (NSUInteger meta = 0; meta <= 1; meta++) {
        if ((!meta && !spec.scanInstanceMethods) || (meta && !spec.scanClassMethods)) continue;
        Class owner = meta ? object_getClass(cls) : cls;
        unsigned int methodCount = 0;
        Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
        for (unsigned int index = 0; methods && index < methodCount; index++) {
            NSString *selector = nil;
            NSString *typeCode = nil;
            if (RYGMethodIsSupported(methods[index], &selector, &typeCode)) {
                RYGAddEntry(output, seen, spec, cls, (BOOL)meta, selector, NO, typeCode);
            }
        }
        if (methods) free(methods);
    }
}

@implementation RYGRuntimeScanner

+ (RYGRuntimeSurfaceSpec *)allAppSurfaceWithTitle:(NSString *)title query:(NSString *)query {
    RYGRuntimeSurfaceSpec *surface = RYGSurface(@"runtime:all",
        title.length ? title : @"Runtime Browser",
        @"All loaded Instagram-owned Objective-C getters",
        @"terminal");
    surface.selectorTokens = RYGRuntimeQueryTerms(query);
    return surface;
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeImageSurfaces {
    // WAT dogfood2 semantics, adapted to Instagram scale: enumerate loaded Mach-O
    // images first and ask libobjc only for class names in each image. Getter
    // enumeration is intentionally deferred until that surface is opened.
    NSMutableArray<RYGRuntimeSurfaceSpec *> *surfaces = [NSMutableArray array];
    NSString *mainExecutable = NSBundle.mainBundle.executablePath ?: @"";

    for (NSString *path in RYGLoadedAppImagePaths()) {
        NSUInteger classCount = RYGEnumerateClassesForImage(path, nil);
        if (!classCount) continue;
        NSString *name = RYGRuntimeImageNameForPath(path);
        BOOL executable = RYGPathsEqual(path, mainExecutable);
        RYGRuntimeSurfaceSpec *surface = RYGSurface(
            [NSString stringWithFormat:@"image:%lu", (unsigned long)RYGCanonicalPath(path).hash],
            name,
            [NSString stringWithFormat:@"%lu Objective-C classes · typed getters scan on open",
                                       (unsigned long)classCount],
            executable ? @"app.dashed" : @"shippingbox");
        surface.runtimeImagePath = path;
        surface.runtimeClassCount = classCount;
        surface.runtimeEntryCount = 0; // unknown until the selected image is scanned
        [surfaces addObject:surface];
    }

    [surfaces sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *left,
                                                       RYGRuntimeSurfaceSpec *right) {
        BOOL leftExec = RYGPathsEqual(left.runtimeImagePath, mainExecutable);
        BOOL rightExec = RYGPathsEqual(right.runtimeImagePath, mainExecutable);
        if (leftExec != rightExec) return leftExec ? NSOrderedAscending : NSOrderedDescending;
        if (left.runtimeClassCount != right.runtimeClassCount) {
            return left.runtimeClassCount > right.runtimeClassCount ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.title localizedCaseInsensitiveCompare:right.title];
    }];
    return surfaces.copy;
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeFamilySurfaces {
    // Family inventory is explicitly expensive and therefore remains on-demand.
    RYGRuntimeSurfaceSpec *all = [self allAppSurfaceWithTitle:@"Runtime" query:@""];
    NSArray<RYGRuntimeEntry *> *entries = [self scanSurface:all];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];

    for (RYGRuntimeEntry *entry in entries) {
        NSString *family = entry.runtimeFamily.length ? entry.runtimeFamily : @"Other Runtime";
        NSMutableDictionary *group = groups[family];
        if (!group) {
            group = [@{ @"classes": [NSMutableSet set],
                        @"images": [NSMutableSet set],
                        @"entries": @0 } mutableCopy];
            groups[family] = group;
        }
        if (entry.className.length) [(NSMutableSet *)group[@"classes"] addObject:entry.className];
        if (entry.imagePath.length) [(NSMutableSet *)group[@"images"] addObject:entry.imagePath];
        group[@"entries"] = @([group[@"entries"] unsignedIntegerValue] + 1);
    }

    NSMutableArray<RYGRuntimeSurfaceSpec *> *surfaces = [NSMutableArray array];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSString *family, NSMutableDictionary *group, BOOL *stop) {
        (void)stop;
        NSUInteger classCount = [(NSMutableSet *)group[@"classes"] count];
        NSUInteger imageCount = [(NSMutableSet *)group[@"images"] count];
        NSUInteger entryCount = [group[@"entries"] unsignedIntegerValue];
        RYGRuntimeSurfaceSpec *surface = RYGSurface(
            [NSString stringWithFormat:@"family:%lu", (unsigned long)family.hash],
            family,
            [NSString stringWithFormat:@"%lu getters · %lu classes · %lu loaded images",
                                       (unsigned long)entryCount,
                                       (unsigned long)classCount,
                                       (unsigned long)imageCount],
            @"line.3.horizontal.decrease.circle");
        surface.runtimeFamilyKey = family;
        surface.runtimeClassCount = classCount;
        surface.runtimeEntryCount = entryCount;
        [surfaces addObject:surface];
    }];

    [surfaces sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *left,
                                                       RYGRuntimeSurfaceSpec *right) {
        if (left.runtimeEntryCount != right.runtimeEntryCount) {
            return left.runtimeEntryCount > right.runtimeEntryCount ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.title localizedCaseInsensitiveCompare:right.title];
    }];
    return surfaces.copy;
}

+ (NSArray<RYGRuntimeEntry *> *)scanSurface:(RYGRuntimeSurfaceSpec *)spec {
    if (!spec) return @[];
    NSMutableArray<RYGRuntimeEntry *> *output = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    if (spec.runtimeImagePath.length) {
        NSUInteger directCount = RYGEnumerateClassesForImage(spec.runtimeImagePath, ^(Class cls) {
            RYGScanClass(spec, cls, output, seen);
        });
        if (!directCount) {
            // Path spelling can differ across sideload/symlink environments.
            // Fall back to the WAT-style global list, but still require exact
            // canonical image identity before touching the class methods.
            RYGEnumerateAppClasses(^(Class cls) {
                RYGScanClass(spec, cls, output, seen);
            });
        }
    } else {
        RYGEnumerateAppClasses(^(Class cls) {
            RYGScanClass(spec, cls, output, seen);
        });
    }

    return [output sortedArrayUsingComparator:^NSComparisonResult(RYGRuntimeEntry *left,
                                                                   RYGRuntimeEntry *right) {
        NSComparisonResult result = [left.runtimeFamily localizedCaseInsensitiveCompare:right.runtimeFamily];
        if (result != NSOrderedSame) return result;
        result = [left.imageName localizedCaseInsensitiveCompare:right.imageName];
        if (result != NSOrderedSame) return result;
        result = [left.className localizedCaseInsensitiveCompare:right.className];
        if (result != NSOrderedSame) return result;
        result = [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
        if (result != NSOrderedSame) return result;
        if (left.classMethod == right.classMethod) return NSOrderedSame;
        return left.classMethod ? NSOrderedAscending : NSOrderedDescending;
    }];
}

@end
