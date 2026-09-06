#import "RYGRuntimeSurface.h"
#import "RYGRuntimeValueStore.h"
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#include <stdlib.h>

@implementation RYGRuntimeEntry @end
@implementation RYGRuntimeSurfaceSpec
+ (NSArray<RYGRuntimeSurfaceSpec *> *)allSurfaces { return [RYGRuntimeScanner runtimeImageSurfaces]; }
@end

static NSString *RYGCanonicalRuntimePath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGRuntimePathsEqual(NSString *left, NSString *right) {
    return left.length && right.length && [RYGCanonicalRuntimePath(left) isEqualToString:RYGCanonicalRuntimePath(right)];
}

static BOOL RYGRuntimePathIsAppOwned(NSString *path) {
    if (!path.length) return NO;
    NSString *bundle = NSBundle.mainBundle.bundlePath ?: @"";
    if (bundle.length && [RYGCanonicalRuntimePath(path) hasPrefix:[RYGCanonicalRuntimePath(bundle) stringByAppendingString:@"/"]]) return YES;
    return [path rangeOfString:@"/Instagram.app/" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [path hasSuffix:@"/Instagram"];
}

NSString *RYGRuntimeImageNameForPath(NSString *imagePath) {
    if (!imagePath.length) return @"Runtime";
    if ([imagePath hasSuffix:@"/Instagram"] || [imagePath isEqualToString:@"Instagram"]) return @"Instagram Executable";
    for (NSString *part in [imagePath.pathComponents reverseObjectEnumerator]) if ([part hasSuffix:@".framework"]) return part;
    return imagePath.lastPathComponent.length ? imagePath.lastPathComponent : imagePath;
}

static NSArray<NSString *> *RYGRawTokens(NSString *value) {
    if (!value.length) return @[];
    NSMutableString *expanded = [NSMutableString string];
    NSCharacterSet *upper = NSCharacterSet.uppercaseLetterCharacterSet;
    NSCharacterSet *lower = NSCharacterSet.lowercaseLetterCharacterSet;
    NSCharacterSet *alnum = NSCharacterSet.alphanumericCharacterSet;
    unichar previous = 0;
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if ([upper characterIsMember:c] && previous && [lower characterIsMember:previous]) [expanded appendString:@"_"];
        [expanded appendFormat:[alnum characterIsMember:c] ? @"%C" : @"_", c];
        previous = c;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *part in [expanded.lowercaseString componentsSeparatedByString:@"_"]) if (part.length) [out addObject:part];
    return out.copy;
}

static NSSet<NSString *> *RYGStopWords(void) {
    static NSSet *set; static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSSet setWithArray:@[
        @"is",@"has",@"have",@"can",@"could",@"should",@"would",@"get",@"set",@"for",@"from",@"with",@"without",
        @"and",@"or",@"the",@"of",@"to",@"a",@"an",@"value",@"flag",@"feature",@"enabled",@"enable",@"disabled",@"disable",
        @"active",@"available",@"availability",@"launched",@"launch",@"supported",@"support",@"ios",@"objc",@"impl",@"implementation",
        @"property",@"properties",@"provider",@"manager"
    ]]; });
    return set;
}

static NSString *RYGDisplayToken(NSString *token) {
    static NSSet *acronyms; static dispatch_once_t once;
    dispatch_once(&once, ^{ acronyms = [NSSet setWithArray:@[@"ai",@"ab",@"mc",@"ui",@"ux",@"api",@"qpl",@"foa",@"ig",@"igds",@"bslds",@"fb",@"lid"]]; });
    return [acronyms containsObject:token] ? token.uppercaseString : token.localizedCapitalizedString;
}

NSString *RYGRuntimeFamilyForSelector(NSString *selectorName, NSString *className) {
    NSArray *source = RYGRawTokens(selectorName.length ? selectorName : className);
    NSMutableArray *meaningful = [NSMutableArray array];
    for (NSString *token in source) {
        if ([RYGStopWords() containsObject:token]) continue;
        [meaningful addObject:token];
        if (meaningful.count == 3) break;
    }
    if (!meaningful.count && className.length) {
        for (NSString *token in RYGRawTokens(className)) {
            if (![RYGStopWords() containsObject:token]) [meaningful addObject:token];
            if (meaningful.count == 3) break;
        }
    }
    if (!meaningful.count) return @"Other Runtime";
    NSMutableArray *display = [NSMutableArray array];
    for (NSString *token in meaningful) [display addObject:RYGDisplayToken(token)];
    return [display componentsJoinedByString:@" "];
}

NSString *RYGRuntimeSubcategoryForEntry(NSString *selectorName, NSString *className, NSString *imagePath) {
    NSString *family = RYGRuntimeFamilyForSelector(selectorName, className);
    NSString *owner = className.length ? className : RYGRuntimeImageNameForPath(imagePath);
    return owner.length ? [NSString stringWithFormat:@"%@ — %@", owner, family] : family;
}

NSArray<NSString *> *RYGRuntimeQueryTerms(NSString *query) {
    NSMutableOrderedSet *terms = [NSMutableOrderedSet orderedSet];
    for (NSString *part in [(query ?: @"").lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
        for (NSString *token in [part componentsSeparatedByString:@"|"]) if (token.length) [terms addObject:token];
    return terms.array ?: @[];
}

static NSArray<NSString *> *RYGAppClassNames(void) {
    unsigned int count = 0;
    Class __unsafe_unretained *list = objc_copyClassList(&count);
    if (!list) return @[];
    NSMutableArray *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        Class cls = list[i];
        const char *rawPath = cls ? class_getImageName(cls) : NULL;
        NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
        if (!RYGRuntimePathIsAppOwned(path)) continue;
        const char *rawName = class_getName(cls);
        if (rawName && *rawName) [names addObject:[NSString stringWithUTF8String:rawName]];
    }
    free(list);
    return names.copy;
}

static NSString *RYGMethodImagePath(Method method, Class fallbackClass) {
    IMP imp = method ? method_getImplementation(method) : NULL;
    Dl_info info = {0};
    if (imp && dladdr((const void *)imp, &info) && info.dli_fname) return [NSString stringWithUTF8String:info.dli_fname] ?: @"";
    const char *raw = fallbackClass ? class_getImageName(fallbackClass) : NULL;
    return raw ? [NSString stringWithUTF8String:raw] : @"";
}

static RYGRuntimeSurfaceSpec *RYGSurface(NSString *identifier, NSString *title, NSString *subtitle, NSString *icon) {
    RYGRuntimeSurfaceSpec *s = [RYGRuntimeSurfaceSpec new];
    s.surfaceID = identifier ?: @"runtime"; s.title = title ?: @"Runtime"; s.subtitle = subtitle ?: @""; s.icon = icon ?: @"circle";
    s.classNames=@[]; s.classNameFragments=@[]; s.selectorTokens=@[]; s.categoryAllowList=@[];
    s.scanInstanceMethods=YES; s.scanClassMethods=YES; s.scanProperties=YES; s.advancedOnly=YES; s.runtimeGenerated=YES;
    return s;
}

static BOOL RYGClassNameMatchesStaticSpec(RYGRuntimeSurfaceSpec *spec, NSString *className) {
    if (!spec.classNames.count && !spec.classNameFragments.count) return YES;
    for (NSString *name in spec.classNames) if ([className isEqualToString:name]) return YES;
    for (NSString *fragment in spec.classNameFragments)
        if (fragment.length && [className rangeOfString:fragment options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

static void RYGAddMethodEntry(NSMutableArray *output, NSMutableSet *seen, RYGRuntimeSurfaceSpec *spec,
                              Class cls, BOOL meta, Method method, BOOL property) {
    NSString *typeCode = nil;
    RYGRuntimeValueArgumentKind argKind = RYGRuntimeValueArgumentUnsupported;
    if (!RYGRuntimeValueClassifyMethod(method, &typeCode, &argKind)) return;
    NSString *selector = NSStringFromSelector(method_getName(method));
    NSString *className = NSStringFromClass(cls);
    if (!selector.length || !className.length) return;
    NSString *imagePath = RYGMethodImagePath(method, cls);
    if (!RYGRuntimePathIsAppOwned(imagePath)) return;
    if (spec.runtimeImagePath.length && !RYGRuntimePathsEqual(imagePath, spec.runtimeImagePath)) return;

    NSString *family = RYGRuntimeFamilyForSelector(selector, className);
    if (spec.runtimeFamilyKey.length && ![family isEqualToString:spec.runtimeFamilyKey]) return;
    NSString *uid = RYGRuntimeValueUID(className, selector, meta);
    if (!uid.length || [seen containsObject:uid]) return;
    [seen addObject:uid];

    RYGRuntimeEntry *entry = [RYGRuntimeEntry new];
    entry.surfaceID = spec.surfaceID ?: @"runtime";
    entry.className = className;
    entry.classMethod = meta;
    entry.property = property;
    entry.selectorName = selector;
    entry.displayName = selector;
    entry.typeCode = typeCode;
    entry.typeName = argKind == RYGRuntimeValueArgumentNone ? (RYGRuntimeValueTypeName(typeCode) ?: typeCode) : @"BOOL · 1 arg";
    entry.returnType = entry.typeName;
    entry.overrideKey = uid;
    entry.imagePath = imagePath;
    entry.imageName = RYGRuntimeImageNameForPath(imagePath);
    entry.runtimeFamily = family;
    entry.runtimeSubcategory = RYGRuntimeSubcategoryForEntry(selector, className, imagePath);
    [output addObject:entry];
}

@implementation RYGRuntimeScanner

+ (RYGRuntimeSurfaceSpec *)allAppSurfaceWithTitle:(NSString *)title query:(NSString *)query {
    (void)query; // presentation filter only; never constrain discovery.
    return RYGSurface(@"runtime:whole-host", title.length ? title : @"Runtime Browser",
                      @"Whole-host Instagram Objective-C runtime · filters apply after discovery", @"terminal");
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeImageSurfaces {
    NSMutableDictionary<NSString *, NSNumber *> *classCounts = [NSMutableDictionary dictionary];
    for (NSString *name in RYGAppClassNames()) {
        Class cls = objc_lookUpClass(name.UTF8String);
        const char *raw = cls ? class_getImageName(cls) : NULL;
        NSString *path = raw ? [NSString stringWithUTF8String:raw] : @"";
        if (!path.length) continue;
        NSString *key = RYGCanonicalRuntimePath(path);
        classCounts[key] = @([classCounts[key] unsignedIntegerValue] + 1);
    }

    NSMutableArray *surfaces = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        if (!RYGRuntimePathIsAppOwned(path)) continue;
        NSString *canonical = RYGCanonicalRuntimePath(path);
        if ([seen containsObject:canonical]) continue;
        [seen addObject:canonical];
        NSString *name = RYGRuntimeImageNameForPath(path);
        NSUInteger classes = [classCounts[canonical] unsignedIntegerValue];
        RYGRuntimeSurfaceSpec *surface = RYGSurface([NSString stringWithFormat:@"image:%lu",(unsigned long)canonical.hash],
                                                    name,
                                                    [NSString stringWithFormat:@"%lu classes · ObjC/C deep scan on open",(unsigned long)classes],
                                                    [name containsString:@"Executable"] ? @"app.dashed" : @"shippingbox");
        surface.runtimeImagePath = path;
        surface.runtimeClassCount = classes;
        [surfaces addObject:surface];
    }
    [surfaces sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *a, RYGRuntimeSurfaceSpec *b) {
        BOOL ae=[a.title containsString:@"Executable"], be=[b.title containsString:@"Executable"];
        if (ae != be) return ae ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    return surfaces.copy;
}

+ (NSArray<RYGRuntimeEntry *> *)scanSurface:(RYGRuntimeSurfaceSpec *)spec {
    if (!spec) return @[];
    NSMutableArray *output = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *name in RYGAppClassNames()) {
        Class cls = objc_lookUpClass(name.UTF8String);
        if (!cls || !RYGClassNameMatchesStaticSpec(spec, name)) continue;

        if (spec.scanProperties) {
            unsigned int count = 0;
            objc_property_t *properties = class_copyPropertyList(cls, &count);
            for (unsigned int i=0; properties && i<count; i++) {
                const char *rawName = property_getName(properties[i]);
                NSString *selector = rawName ? [NSString stringWithUTF8String:rawName] : @"";
                Method method = selector.length ? class_getInstanceMethod(cls, NSSelectorFromString(selector)) : NULL;
                if (method) RYGAddMethodEntry(output, seen, spec, cls, NO, method, YES);
            }
            if (properties) free(properties);
        }

        for (NSUInteger meta=0; meta<=1; meta++) {
            if ((!meta && !spec.scanInstanceMethods) || (meta && !spec.scanClassMethods)) continue;
            Class owner = meta ? object_getClass(cls) : cls;
            unsigned int count = 0;
            Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
            for (unsigned int i=0; methods && i<count; i++) RYGAddMethodEntry(output, seen, spec, cls, (BOOL)meta, methods[i], NO);
            if (methods) free(methods);
        }
    }
    [output sortUsingComparator:^NSComparisonResult(RYGRuntimeEntry *a, RYGRuntimeEntry *b) {
        NSComparisonResult r=[a.runtimeFamily localizedCaseInsensitiveCompare:b.runtimeFamily]; if(r!=NSOrderedSame)return r;
        r=[a.imageName localizedCaseInsensitiveCompare:b.imageName]; if(r!=NSOrderedSame)return r;
        r=[a.className localizedCaseInsensitiveCompare:b.className]; if(r!=NSOrderedSame)return r;
        return [a.selectorName localizedCaseInsensitiveCompare:b.selectorName];
    }];
    return output.copy;
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeFamilySurfaces {
    RYGRuntimeSurfaceSpec *whole = [self allAppSurfaceWithTitle:@"Runtime" query:@""];
    NSArray<RYGRuntimeEntry *> *entries = [self scanSurface:whole];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *classes = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (RYGRuntimeEntry *entry in entries) {
        NSString *family = entry.runtimeFamily.length ? entry.runtimeFamily : @"Other Runtime";
        if (!classes[family]) classes[family] = [NSMutableSet set];
        [classes[family] addObject:entry.className ?: @""];
        counts[family] = @([counts[family] unsignedIntegerValue] + 1);
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *family in counts) {
        RYGRuntimeSurfaceSpec *s = RYGSurface([NSString stringWithFormat:@"family:%lu",(unsigned long)family.hash], family,
                                              [NSString stringWithFormat:@"%lu members · %lu classes",(unsigned long)[counts[family] unsignedIntegerValue],(unsigned long)classes[family].count],
                                              @"line.3.horizontal.decrease.circle");
        s.runtimeFamilyKey = family;
        s.runtimeClassCount = classes[family].count;
        s.runtimeEntryCount = [counts[family] unsignedIntegerValue];
        [out addObject:s];
    }
    [out sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *a, RYGRuntimeSurfaceSpec *b){ return [a.title localizedCaseInsensitiveCompare:b.title]; }];
    return out.copy;
}

@end
