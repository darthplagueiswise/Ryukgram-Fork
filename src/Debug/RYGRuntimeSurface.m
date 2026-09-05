#import "RYGRuntimeSurface.h"
#import "RYGRuntimeValueStore.h"
#import <objc/runtime.h>
#include <stdlib.h>

@implementation RYGRuntimeEntry
@end

@implementation RYGRuntimeSurfaceSpec

+ (NSArray<RYGRuntimeSurfaceSpec *> *)allSurfaces {
    return [RYGRuntimeScanner runtimeImageSurfaces];
}

@end

#pragma mark - Live naming

NSString *RYGCleanDisplayName(NSString *name) {
    if (!name.length) return @"";
    NSString *value = [name copy];
    while ([value hasPrefix:@"@property "]) value = [value substringFromIndex:10];
    while ([value hasPrefix:@"- "]) value = [value substringFromIndex:2];
    while ([value hasPrefix:@"+ "]) value = [value substringFromIndex:2];
    return value;
}

static BOOL RYGRuntimePathIsAppOwned(NSString *path) {
    if (!path.length) return NO;
    NSString *bundle = NSBundle.mainBundle.bundlePath ?: @"";
    if (bundle.length && [path hasPrefix:bundle]) return YES;
    return [path rangeOfString:@"/Instagram.app/" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

NSString *RYGRuntimeImageNameForPath(NSString *imagePath) {
    if (!imagePath.length) return @"Runtime";
    if ([imagePath hasSuffix:@"/Instagram"] || [imagePath isEqualToString:@"Instagram"]) {
        return @"Instagram Executable";
    }
    NSArray<NSString *> *parts = imagePath.pathComponents;
    for (NSString *part in [parts reverseObjectEnumerator]) {
        if ([part hasSuffix:@".framework"]) return part;
    }
    NSString *last = imagePath.lastPathComponent;
    return last.length ? last : imagePath;
}

static NSArray<NSString *> *RYGLiveRawTokens(NSString *value) {
    if (!value.length) return @[];
    NSMutableString *expanded = [NSMutableString stringWithCapacity:value.length * 2];
    NSCharacterSet *upper = NSCharacterSet.uppercaseLetterCharacterSet;
    NSCharacterSet *lower = NSCharacterSet.lowercaseLetterCharacterSet;
    NSCharacterSet *alnum = NSCharacterSet.alphanumericCharacterSet;

    unichar previous = 0;
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar current = [value characterAtIndex:index];
        BOOL isUpper = [upper characterIsMember:current];
        BOOL previousLower = previous && [lower characterIsMember:previous];
        if (isUpper && previousLower) [expanded appendString:@"_"];
        if ([alnum characterIsMember:current]) [expanded appendFormat:@"%C", current];
        else [expanded appendString:@"_"];
        previous = current;
    }

    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in [expanded.lowercaseString componentsSeparatedByString:@"_"]) {
        if (part.length) [tokens addObject:part];
    }
    return tokens;
}

static NSSet<NSString *> *RYGLiveStopWords(void) {
    static NSSet<NSString *> *words = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        words = [NSSet setWithArray:@[
            @"is", @"has", @"have", @"can", @"could", @"should", @"would",
            @"get", @"set", @"for", @"from", @"with", @"without", @"and", @"or",
            @"the", @"of", @"to", @"a", @"an", @"value", @"flag", @"feature",
            @"enabled", @"enable", @"disabled", @"disable", @"active", @"available",
            @"availability", @"launched", @"launch", @"supported", @"support",
            @"ios", @"objc", @"impl", @"implementation",
            @"property", @"properties", @"provider", @"manager"
        ]];
    });
    return words;
}

static NSString *RYGLiveDisplayToken(NSString *token) {
    if (!token.length) return @"";
    static NSSet<NSString *> *acronyms = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        acronyms = [NSSet setWithArray:@[
            @"ai", @"ab", @"mc", @"ui", @"ux", @"api", @"qpl", @"foa",
            @"ig", @"igds", @"bslds", @"fb", @"lid", @"m0", @"m1", @"m2"
        ]];
    });
    if ([acronyms containsObject:token]) return token.uppercaseString;
    return token.localizedCapitalizedString;
}

NSString *RYGRuntimeFamilyForSelector(NSString *selectorName, NSString *className) {
    NSArray<NSString *> *source = RYGLiveRawTokens(selectorName.length ? selectorName : className);
    NSMutableArray<NSString *> *meaningful = [NSMutableArray array];
    NSSet<NSString *> *stop = RYGLiveStopWords();
    for (NSString *token in source) {
        if ([stop containsObject:token]) continue;
        if ([token rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound &&
            [token rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location == NSNotFound) continue;
        [meaningful addObject:token];
        if (meaningful.count == 3) break;
    }
    if (!meaningful.count) {
        for (NSString *token in source) {
            if (token.length) { [meaningful addObject:token]; break; }
        }
    }
    if (!meaningful.count && className.length) {
        NSArray *classTokens = RYGLiveRawTokens(className);
        for (NSString *token in classTokens) {
            if (![stop containsObject:token]) [meaningful addObject:token];
            if (meaningful.count == 3) break;
        }
    }
    if (!meaningful.count) return @"Other Runtime";

    NSMutableArray<NSString *> *display = [NSMutableArray arrayWithCapacity:meaningful.count];
    for (NSString *token in meaningful) [display addObject:RYGLiveDisplayToken(token)];
    return [display componentsJoinedByString:@" "];
}

NSString *RYGRuntimeSubcategoryForEntry(NSString *selectorName,
                                        NSString *className,
                                        NSString *imagePath) {
    NSString *family = RYGRuntimeFamilyForSelector(selectorName, className);
    NSString *owner = className.length ? className : RYGRuntimeImageNameForPath(imagePath);
    if (!owner.length) return family;
    return [NSString stringWithFormat:@"%@ — %@", owner, family];
}

NSString *RYGCategoryForSelector(NSString *selectorName) {
    return RYGRuntimeFamilyForSelector(selectorName, nil);
}

#pragma mark - Snapshot helpers

static NSArray<NSString *> *RYGLiveAppClassNames(void) {
    unsigned int count = 0;
    Class __unsafe_unretained *list = objc_copyClassList(&count);
    if (!list || !count) {
        if (list) free(list);
        return @[];
    }
    NSMutableArray<NSString *> *classNames = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; index < count; index++) {
        Class cls = list[index];
        const char *rawPath = cls ? class_getImageName(cls) : NULL;
        NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
        if (!RYGRuntimePathIsAppOwned(path)) continue;
        const char *rawName = cls ? class_getName(cls) : NULL;
        if (!rawName || !*rawName) continue;
        NSString *name = [NSString stringWithUTF8String:rawName];
        if (name.length) [classNames addObject:name];
    }
    free(list);
    return classNames;
}

static BOOL RYGLiveMethodIsSupported(Method method, NSString **selectorName, NSString **typeCode) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    NSString *selector = NSStringFromSelector(method_getName(method));
    if (!selector.length || [selector containsString:@":"]) return NO;
    char rawType[64] = {0};
    method_getReturnType(method, rawType, sizeof(rawType));
    NSString *type = [NSString stringWithUTF8String:rawType] ?: @"";
    if (!RYGRuntimeValueTypeIsSupported(type)) return NO;
    if (selectorName) *selectorName = selector;
    if (typeCode) *typeCode = type;
    return YES;
}

static NSUInteger RYGLiveSupportedMethodCount(Class cls) {
    if (!cls) return 0;
    NSUInteger total = 0;
    for (NSUInteger meta = 0; meta <= 1; meta++) {
        Class owner = meta ? object_getClass(cls) : cls;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(owner, &count);
        if (!methods) continue;
        for (unsigned int index = 0; index < count; index++) {
            if (RYGLiveMethodIsSupported(methods[index], NULL, NULL)) total++;
        }
        free(methods);
    }
    return total;
}

static RYGRuntimeSurfaceSpec *RYGLiveSurface(NSString *identifier,
                                             NSString *title,
                                             NSString *subtitle,
                                             NSString *icon) {
    RYGRuntimeSurfaceSpec *surface = [RYGRuntimeSurfaceSpec new];
    surface.surfaceID = identifier ?: @"runtime";
    surface.title = title ?: @"Runtime";
    surface.subtitle = subtitle ?: @"";
    surface.icon = icon ?: @"circle";
    surface.classNames = @[];
    surface.classNameFragments = @[];
    surface.selectorTokens = @[];
    surface.categoryAllowList = @[];
    surface.scanInstanceMethods = YES;
    surface.scanClassMethods = YES;
    surface.scanProperties = YES;
    surface.advancedOnly = YES;
    surface.runtimeGenerated = YES;
    return surface;
}

// Direct backend port from WATweaks dogfood2/src/Runtime/WAGRSurface.m
// (archive commit 0466dffcd0f20054eac60f482a04b479c421eb87).
// The discovery contract is intentionally preserved: both the image list and
// the selected-image detail scan are derived from the SAME objc_copyClassList
// snapshot model + class_getImageName + identical typed-getter predicate.
// Instagram-specific adaptation is limited to app ownership/naming and labels.

NSArray<NSString *> *RYGRuntimeQueryTerms(NSString *query) {
    NSMutableOrderedSet<NSString *> *terms = [NSMutableOrderedSet orderedSet];
    for (NSString *group in [(query ?: @"").lowercaseString
             componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        for (NSString *term in [group componentsSeparatedByString:@"|"]) {
            if (term.length) [terms addObject:term];
        }
    }
    return terms.array ?: @[];
}

@implementation RYGRuntimeScanner

+ (RYGRuntimeSurfaceSpec *)allAppSurfaceWithTitle:(NSString *)title query:(NSString *)query {
    RYGRuntimeSurfaceSpec *surface = RYGLiveSurface(@"runtime:all",
        title.length ? title : @"Runtime Browser",
        @"All loaded Instagram-owned Objective-C typed getters",
        @"terminal");
    surface.selectorTokens = RYGRuntimeQueryTerms(query);
    return surface;
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeImageSurfaces {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    for (NSString *liveClassName in RYGLiveAppClassNames()) {
        Class cls = objc_lookUpClass(liveClassName.UTF8String);
        if (!cls) continue;
        NSUInteger methods = RYGLiveSupportedMethodCount(cls);
        if (!methods) continue;
        const char *rawPath = class_getImageName(cls);
        NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
        if (!path.length) continue;
        NSMutableDictionary *group = groups[path];
        if (!group) {
            group = [@{ @"classes": [NSMutableSet set], @"methods": @0 } mutableCopy];
            groups[path] = group;
        }
        [group[@"classes"] addObject:NSStringFromClass(cls) ?: @"Unknown"];
        group[@"methods"] = @([group[@"methods"] unsignedIntegerValue] + methods);
    }

    NSMutableArray<RYGRuntimeSurfaceSpec *> *surfaces = [NSMutableArray array];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSMutableDictionary *group, BOOL *stop) {
        (void)stop;
        NSUInteger classCount = [group[@"classes"] count];
        NSUInteger methodCount = [group[@"methods"] unsignedIntegerValue];
        NSString *name = RYGRuntimeImageNameForPath(path);
        NSString *subtitle = [NSString stringWithFormat:@"%lu classes · %lu typed getters loaded now",
            (unsigned long)classCount, (unsigned long)methodCount];
        NSString *identifier = [NSString stringWithFormat:@"image:%lu", (unsigned long)path.hash];
        NSString *icon = [name containsString:@"Executable"] ? @"app.dashed" : @"shippingbox";
        RYGRuntimeSurfaceSpec *surface = RYGLiveSurface(identifier, name, subtitle, icon);
        surface.runtimeImagePath = path;
        surface.runtimeClassCount = classCount;
        surface.runtimeEntryCount = methodCount;
        [surfaces addObject:surface];
    }];

    [surfaces sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *left, RYGRuntimeSurfaceSpec *right) {
        BOOL leftExec = [left.title containsString:@"Executable"];
        BOOL rightExec = [right.title containsString:@"Executable"];
        if (leftExec != rightExec) return leftExec ? NSOrderedAscending : NSOrderedDescending;
        if (left.runtimeEntryCount != right.runtimeEntryCount) {
            return left.runtimeEntryCount > right.runtimeEntryCount ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.title localizedCaseInsensitiveCompare:right.title];
    }];
    return surfaces;
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeFamilySurfaces {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    for (NSString *liveClassName in RYGLiveAppClassNames()) {
        Class cls = objc_lookUpClass(liveClassName.UTF8String);
        if (!cls) continue;
        NSString *className = NSStringFromClass(cls) ?: @"Unknown";
        const char *rawPath = class_getImageName(cls);
        NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
        for (NSUInteger meta = 0; meta <= 1; meta++) {
            Class owner = meta ? object_getClass(cls) : cls;
            unsigned int count = 0;
            Method *methods = class_copyMethodList(owner, &count);
            if (!methods) continue;
            for (unsigned int index = 0; index < count; index++) {
                NSString *selector = nil;
                if (!RYGLiveMethodIsSupported(methods[index], &selector, NULL)) continue;
                NSString *family = RYGRuntimeFamilyForSelector(selector, className);
                if (!family.length) continue;
                NSMutableDictionary *group = groups[family];
                if (!group) {
                    group = [@{ @"classes": [NSMutableSet set], @"images": [NSMutableSet set], @"methods": @0 } mutableCopy];
                    groups[family] = group;
                }
                [group[@"classes"] addObject:className];
                if (path.length) [group[@"images"] addObject:path];
                group[@"methods"] = @([group[@"methods"] unsignedIntegerValue] + 1);
            }
            free(methods);
        }
    }

    NSMutableArray<RYGRuntimeSurfaceSpec *> *surfaces = [NSMutableArray array];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSString *family, NSMutableDictionary *group, BOOL *stop) {
        (void)stop;
        NSUInteger classCount = [group[@"classes"] count];
        NSUInteger imageCount = [group[@"images"] count];
        NSUInteger methodCount = [group[@"methods"] unsignedIntegerValue];
        NSString *subtitle = [NSString stringWithFormat:@"%lu getters · %lu classes · %lu loaded images",
            (unsigned long)methodCount, (unsigned long)classCount, (unsigned long)imageCount];
        NSString *identifier = [NSString stringWithFormat:@"family:%lu", (unsigned long)family.hash];
        RYGRuntimeSurfaceSpec *surface = RYGLiveSurface(identifier, family, subtitle,
                                                   @"line.3.horizontal.decrease.circle");
        surface.runtimeFamilyKey = family;
        surface.runtimeClassCount = classCount;
        surface.runtimeEntryCount = methodCount;
        [surfaces addObject:surface];
    }];

    [surfaces sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *left, RYGRuntimeSurfaceSpec *right) {
        if (left.runtimeEntryCount != right.runtimeEntryCount) {
            return left.runtimeEntryCount > right.runtimeEntryCount ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.title localizedCaseInsensitiveCompare:right.title];
    }];
    return surfaces;
}

static BOOL RYGTokenMatch(NSArray<NSString *> *tokens, NSString *haystack) {
    if (!tokens.count) return YES;
    NSString *lower = haystack.lowercaseString ?: @"";
    for (NSString *token in tokens) {
        if (token.length && [lower containsString:token.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL RYGClassMatchesSurface(RYGRuntimeSurfaceSpec *spec, Class cls) {
    if (!spec || !cls) return NO;
    NSString *className = NSStringFromClass(cls) ?: @"";
    const char *rawPath = class_getImageName(cls);
    NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";

    if (spec.runtimeImagePath.length) return [path isEqualToString:spec.runtimeImagePath];
    if (spec.runtimeFamilyKey.length) return RYGRuntimePathIsAppOwned(path);

    for (NSString *name in spec.classNames) {
        if ([className isEqualToString:name]) return YES;
    }
    for (NSString *fragment in spec.classNameFragments) {
        if (fragment.length && [className rangeOfString:fragment options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return !spec.classNames.count && !spec.classNameFragments.count && RYGRuntimePathIsAppOwned(path);
}

static void RYGAddEntry(NSMutableArray<RYGRuntimeEntry *> *output,
                        NSMutableSet<NSString *> *seen,
                        RYGRuntimeSurfaceSpec *spec,
                        Class cls,
                        BOOL meta,
                        NSString *selector,
                        BOOL property,
                        NSString *typeCode) {
    if (!selector.length || [selector containsString:@":"] || !typeCode.length) return;
    NSString *typeName = RYGRuntimeValueTypeName(typeCode);
    if (!typeName.length) return;
    NSString *className = NSStringFromClass(cls);
    if (!className.length) return;
    const char *rawPath = class_getImageName(cls);
    NSString *imagePath = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
    NSString *imageName = RYGRuntimeImageNameForPath(imagePath);
    NSString *family = RYGRuntimeFamilyForSelector(selector, className);
    if (spec.runtimeFamilyKey.length && ![family isEqualToString:spec.runtimeFamilyKey]) return;

    NSString *display = RYGCleanDisplayName(selector);
    NSString *subcategory = RYGRuntimeSubcategoryForEntry(selector, className, imagePath);
    NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@",
        imageName, className, selector, display, typeName, family, subcategory];
    if (!RYGTokenMatch(spec.selectorTokens, haystack)) return;
    if (spec.categoryAllowList.count && !RYGTokenMatch(spec.categoryAllowList, haystack)) return;

    NSString *uid = RYGRuntimeValueUID(className, selector, meta);
    if (!uid.length || [seen containsObject:uid]) return;
    [seen addObject:uid];

    RYGRuntimeEntry *entry = [RYGRuntimeEntry new];
    entry.surfaceID = spec.surfaceID ?: @"runtime";
    entry.className = className;
    entry.classMethod = meta;
    entry.property = property;
    entry.selectorName = selector;
    entry.displayName = display.length ? display : selector;
    entry.returnType = typeName;
    entry.typeCode = typeCode;
    entry.typeName = typeName;
    entry.overrideKey = uid;
    entry.imagePath = imagePath;
    entry.imageName = imageName;
    entry.runtimeFamily = family;
    entry.runtimeSubcategory = subcategory;
    [output addObject:entry];
}

+ (NSArray<RYGRuntimeEntry *> *)scanSurface:(RYGRuntimeSurfaceSpec *)spec {
    if (!spec) return @[];
    NSMutableArray<RYGRuntimeEntry *> *output = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *liveClassName in RYGLiveAppClassNames()) {
        Class cls = objc_lookUpClass(liveClassName.UTF8String);
        if (!cls) continue;
        if (!RYGClassMatchesSurface(spec, cls)) continue;

        if (spec.scanProperties) {
            unsigned int propertyCount = 0;
            objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
            if (properties) {
                for (unsigned int index = 0; index < propertyCount; index++) {
                    const char *rawName = property_getName(properties[index]);
                    if (!rawName) continue;
                    NSString *selector = [NSString stringWithUTF8String:rawName];
                    Method method = class_getInstanceMethod(cls, NSSelectorFromString(selector));
                    NSString *liveSelector = nil;
                    NSString *typeCode = nil;
                    if (!RYGLiveMethodIsSupported(method, &liveSelector, &typeCode)) continue;
                    RYGAddEntry(output, seen, spec, cls, NO, liveSelector, YES, typeCode);
                }
                free(properties);
            }
        }

        for (NSUInteger meta = 0; meta <= 1; meta++) {
            if (meta == 0 && !spec.scanInstanceMethods) continue;
            if (meta == 1 && !spec.scanClassMethods) continue;
            Class owner = meta ? object_getClass(cls) : cls;
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(owner, &methodCount);
            if (!methods) continue;
            for (unsigned int index = 0; index < methodCount; index++) {
                NSString *selector = nil;
                NSString *typeCode = nil;
                if (!RYGLiveMethodIsSupported(methods[index], &selector, &typeCode)) continue;
                RYGAddEntry(output, seen, spec, cls, (BOOL)meta, selector, NO, typeCode);
            }
            free(methods);
        }
    }

    return [output sortedArrayUsingComparator:^NSComparisonResult(RYGRuntimeEntry *left, RYGRuntimeEntry *right) {
        NSComparisonResult result = [left.runtimeFamily localizedCaseInsensitiveCompare:right.runtimeFamily];
        if (result != NSOrderedSame) return result;
        result = [left.imageName localizedCaseInsensitiveCompare:right.imageName];
        if (result != NSOrderedSame) return result;
        result = [left.className localizedCaseInsensitiveCompare:right.className];
        if (result != NSOrderedSame) return result;
        result = [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
        if (result != NSOrderedSame) return result;
        return left.classMethod == right.classMethod ? NSOrderedSame
            : (left.classMethod ? NSOrderedAscending : NSOrderedDescending);
    }];
}

@end
