#import "RYGRuntimeSurface.h"
#import "RYGRuntimeValueStore.h"
#import <objc/runtime.h>
#include <stdlib.h>

@implementation RYGRuntimeEntry @end
@implementation RYGRuntimeSurfaceSpec
+ (NSArray<RYGRuntimeSurfaceSpec *> *)allSurfaces { return [RYGRuntimeScanner runtimeImageSurfaces]; }
@end

static BOOL RYGPathLooksInsideApp(NSString *path) {
    if (!path.length) return NO;
    NSString *standard = path.stringByStandardizingPath;
    NSString *bundle = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *resolvedPath = standard.stringByResolvingSymlinksInPath;
    NSString *resolvedBundle = bundle.stringByResolvingSymlinksInPath;
    if (bundle.length && ([standard isEqualToString:bundle] || [standard hasPrefix:[bundle stringByAppendingString:@"/"]])) return YES;
    if (resolvedBundle.length && ([resolvedPath isEqualToString:resolvedBundle] || [resolvedPath hasPrefix:[resolvedBundle stringByAppendingString:@"/"]])) return YES;
    NSString *component = bundle.lastPathComponent.length ? bundle.lastPathComponent : @"Instagram.app";
    if ([standard rangeOfString:[NSString stringWithFormat:@"/%@/", component] options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return [standard rangeOfString:@"/Instagram.app/" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

NSString *RYGRuntimeImageNameForPath(NSString *imagePath) {
    if (!imagePath.length) return @"Runtime";
    NSString *last = imagePath.lastPathComponent ?: @"";
    NSString *exec = NSBundle.mainBundle.executableURL.lastPathComponent ?: @"Instagram";
    if ([last isEqualToString:exec]) return @"Instagram Executable";
    NSArray<NSString *> *parts = imagePath.pathComponents;
    for (NSString *part in parts.reverseObjectEnumerator) if ([part hasSuffix:@".framework"]) return part;
    return last.length ? last : imagePath;
}

static NSArray<NSString *> *RYGRawTokens(NSString *value) {
    if (!value.length) return @[];
    NSMutableString *expanded = [NSMutableString stringWithCapacity:value.length * 2];
    NSCharacterSet *upper = NSCharacterSet.uppercaseLetterCharacterSet;
    NSCharacterSet *lower = NSCharacterSet.lowercaseLetterCharacterSet;
    NSCharacterSet *alnum = NSCharacterSet.alphanumericCharacterSet;
    unichar previous = 0;
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar current = [value characterAtIndex:i];
        if ([upper characterIsMember:current] && previous && [lower characterIsMember:previous]) [expanded appendString:@"_"];
        [expanded appendString:[alnum characterIsMember:current] ? [NSString stringWithCharacters:&current length:1] : @"_"];
        previous = current;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *part in [expanded.lowercaseString componentsSeparatedByString:@"_"]) if (part.length) [out addObject:part];
    return out.copy;
}

static NSSet<NSString *> *RYGStopWords(void) {
    static NSSet *words; static dispatch_once_t once;
    dispatch_once(&once, ^{ words = [NSSet setWithArray:@[
        @"is",@"has",@"have",@"can",@"could",@"should",@"would",@"get",@"set",@"for",@"from",@"with",@"without",@"and",@"or",@"the",@"of",@"to",@"a",@"an",@"value",@"flag",@"feature",@"enabled",@"enable",@"disabled",@"disable",@"active",@"available",@"availability",@"launched",@"launch",@"supported",@"support",@"ios",@"objc",@"impl",@"implementation",@"property",@"properties",@"provider",@"manager"
    ]]; });
    return words;
}

static NSString *RYGDisplayToken(NSString *token) {
    static NSSet *acronyms; static dispatch_once_t once;
    dispatch_once(&once, ^{ acronyms = [NSSet setWithArray:@[@"ai",@"ab",@"mc",@"ui",@"ux",@"api",@"qpl",@"foa",@"ig",@"igds",@"bslds",@"lid",@"fb"]]; });
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
    if (!meaningful.count) for (NSString *token in RYGRawTokens(className)) {
        if (![RYGStopWords() containsObject:token]) [meaningful addObject:token];
        if (meaningful.count == 3) break;
    }
    if (!meaningful.count) return @"Other Runtime";
    NSMutableArray *display = [NSMutableArray arrayWithCapacity:meaningful.count];
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
    for (NSString *group in [(query ?: @"").lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        for (NSString *term in [group componentsSeparatedByString:@"|"]) if (term.length) [terms addObject:term];
    }
    return terms.array;
}

static BOOL RYGMethodIsSupported(Method method, NSString **selectorName, NSString **typeCode) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    NSString *selector = NSStringFromSelector(method_getName(method));
    if (!RYGRuntimeValueSelectorIsSafeGetter(selector)) return NO;
    char raw[64] = {0}; method_getReturnType(method, raw, sizeof(raw));
    NSString *type = [NSString stringWithUTF8String:raw] ?: @"";
    if (!RYGRuntimeValueTypeIsSupported(type)) return NO;
    if (selectorName) *selectorName = selector;
    if (typeCode) *typeCode = type;
    return YES;
}

static void RYGEnumerateAppClasses(void (^block)(Class cls)) {
    if (!block) return;
    int count = objc_getClassList(NULL, 0);
    if (count <= 0 || count > 500000) return;
    Class __unsafe_unretained *classes = (Class __unsafe_unretained *)calloc((size_t)count, sizeof(Class));
    if (!classes) return;
    int filled = objc_getClassList(classes, count);
    for (int i = 0; i < filled; i++) {
        Class cls = classes[i];
        const char *rawPath = cls ? class_getImageName(cls) : NULL;
        NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
        if (RYGPathLooksInsideApp(path)) block(cls);
    }
    free(classes);
}

static NSUInteger RYGSupportedMethodCount(Class cls) {
    NSUInteger total = 0;
    for (NSUInteger meta = 0; meta <= 1; meta++) {
        Class owner = meta ? object_getClass(cls) : cls;
        unsigned int count = 0; Method *methods = owner ? class_copyMethodList(owner, &count) : NULL;
        for (unsigned int i = 0; methods && i < count; i++) if (RYGMethodIsSupported(methods[i], NULL, NULL)) total++;
        if (methods) free(methods);
    }
    return total;
}

static RYGRuntimeSurfaceSpec *RYGSurface(NSString *identifier, NSString *title, NSString *subtitle, NSString *icon) {
    RYGRuntimeSurfaceSpec *s = [RYGRuntimeSurfaceSpec new];
    s.surfaceID = identifier ?: @"runtime"; s.title = title ?: @"Runtime"; s.subtitle = subtitle ?: @""; s.icon = icon ?: @"terminal";
    s.selectorTokens = @[]; s.scanInstanceMethods = YES; s.scanClassMethods = YES; s.scanProperties = YES; s.runtimeGenerated = YES;
    return s;
}

static BOOL RYGAnyTokenMatches(NSArray<NSString *> *tokens, NSString *haystack) {
    if (!tokens.count) return YES;
    NSString *lower = haystack.lowercaseString ?: @"";
    for (NSString *token in tokens) if (token.length && [lower containsString:token.lowercaseString]) return YES;
    return NO;
}

static BOOL RYGClassMatchesSurface(RYGRuntimeSurfaceSpec *spec, Class cls) {
    const char *raw = cls ? class_getImageName(cls) : NULL;
    NSString *path = raw ? [NSString stringWithUTF8String:raw] : @"";
    if (spec.runtimeImagePath.length) return [path isEqualToString:spec.runtimeImagePath];
    return RYGPathLooksInsideApp(path);
}

static void RYGAddEntry(NSMutableArray<RYGRuntimeEntry *> *output, NSMutableSet<NSString *> *seen,
                        RYGRuntimeSurfaceSpec *spec, Class cls, BOOL meta, NSString *selector,
                        BOOL property, NSString *typeCode) {
    if (!selector.length || !typeCode.length) return;
    NSString *className = NSStringFromClass(cls); if (!className.length) return;
    NSString *typeName = RYGRuntimeValueTypeName(typeCode); if (!typeName.length) return;
    const char *rawPath = class_getImageName(cls); NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
    NSString *imageName = RYGRuntimeImageNameForPath(path);
    NSString *family = RYGRuntimeFamilyForSelector(selector, className);
    if (spec.runtimeFamilyKey.length && ![family isEqualToString:spec.runtimeFamilyKey]) return;
    NSString *subcategory = RYGRuntimeSubcategoryForEntry(selector, className, path);
    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", imageName, className, selector, typeName, family, subcategory];
    if (!RYGAnyTokenMatches(spec.selectorTokens, hay)) return;
    NSString *uid = RYGRuntimeValueUID(className, selector, meta); if (!uid.length || [seen containsObject:uid]) return;
    [seen addObject:uid];
    RYGRuntimeEntry *e = [RYGRuntimeEntry new];
    e.surfaceID = spec.surfaceID; e.className = className; e.classMethod = meta; e.property = property; e.selectorName = selector;
    e.displayName = selector; e.returnType = typeName; e.typeCode = RYGRuntimeValueNormalizedType(typeCode); e.typeName = typeName; e.overrideKey = uid;
    e.imagePath = path; e.imageName = imageName; e.runtimeFamily = family; e.runtimeSubcategory = subcategory;
    [output addObject:e];
}

@implementation RYGRuntimeScanner

+ (RYGRuntimeSurfaceSpec *)allAppSurfaceWithTitle:(NSString *)title query:(NSString *)query {
    RYGRuntimeSurfaceSpec *s = RYGSurface(@"runtime:all", title.length ? title : @"Runtime Browser", @"All loaded Instagram-owned Objective-C getters", @"terminal");
    s.selectorTokens = RYGRuntimeQueryTerms(query);
    return s;
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeImageSurfaces {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    RYGEnumerateAppClasses(^(Class cls) {
        NSUInteger methods = RYGSupportedMethodCount(cls); if (!methods) return;
        const char *raw = class_getImageName(cls); NSString *path = raw ? [NSString stringWithUTF8String:raw] : @""; if (!path.length) return;
        NSMutableDictionary *g = groups[path]; if (!g) { g = [@{@"classes":[NSMutableSet set], @"methods":@0} mutableCopy]; groups[path] = g; }
        [(NSMutableSet *)g[@"classes"] addObject:NSStringFromClass(cls) ?: @"Unknown"];
        g[@"methods"] = @([g[@"methods"] unsignedIntegerValue] + methods);
    });
    NSMutableArray *out = [NSMutableArray array];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSMutableDictionary *g, BOOL *stop) {
        (void)stop; NSUInteger cc = [g[@"classes"] count], mc = [g[@"methods"] unsignedIntegerValue]; NSString *name = RYGRuntimeImageNameForPath(path);
        RYGRuntimeSurfaceSpec *s = RYGSurface([NSString stringWithFormat:@"image:%lu", (unsigned long)path.hash], name,
            [NSString stringWithFormat:@"%lu classes · %lu typed getters loaded now", (unsigned long)cc, (unsigned long)mc], [name containsString:@"Executable"] ? @"app.dashed" : @"shippingbox");
        s.runtimeImagePath = path; s.runtimeClassCount = cc; s.runtimeEntryCount = mc; [out addObject:s];
    }];
    [out sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *a, RYGRuntimeSurfaceSpec *b) {
        BOOL ae=[a.title containsString:@"Executable"], be=[b.title containsString:@"Executable"]; if (ae != be) return ae ? NSOrderedAscending : NSOrderedDescending;
        if (a.runtimeEntryCount != b.runtimeEntryCount) return a.runtimeEntryCount > b.runtimeEntryCount ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    return out.copy;
}

+ (NSArray<RYGRuntimeSurfaceSpec *> *)runtimeFamilySurfaces {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    RYGEnumerateAppClasses(^(Class cls) {
        NSString *cn = NSStringFromClass(cls) ?: @"Unknown"; const char *raw = class_getImageName(cls); NSString *path = raw ? [NSString stringWithUTF8String:raw] : @"";
        for (NSUInteger meta=0; meta<=1; meta++) { Class owner = meta ? object_getClass(cls) : cls; unsigned int count=0; Method *methods=class_copyMethodList(owner,&count);
            for (unsigned int i=0; methods && i<count; i++) { NSString *sel=nil; if (!RYGMethodIsSupported(methods[i],&sel,NULL)) continue; NSString *family=RYGRuntimeFamilyForSelector(sel,cn); if (!family.length) continue;
                NSMutableDictionary *g=groups[family]; if (!g) { g=[@{@"classes":[NSMutableSet set],@"images":[NSMutableSet set],@"methods":@0} mutableCopy]; groups[family]=g; }
                [(NSMutableSet *)g[@"classes"] addObject:cn]; if (path.length) [(NSMutableSet *)g[@"images"] addObject:path]; g[@"methods"]=@([g[@"methods"] unsignedIntegerValue]+1); }
            if (methods) free(methods); }
    });
    NSMutableArray *out=[NSMutableArray array];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSString *family, NSMutableDictionary *g, BOOL *stop) { (void)stop; NSUInteger cc=[g[@"classes"] count], ic=[g[@"images"] count], mc=[g[@"methods"] unsignedIntegerValue];
        RYGRuntimeSurfaceSpec *s=RYGSurface([NSString stringWithFormat:@"family:%lu",(unsigned long)family.hash],family,[NSString stringWithFormat:@"%lu getters · %lu classes · %lu loaded images",(unsigned long)mc,(unsigned long)cc,(unsigned long)ic],@"line.3.horizontal.decrease.circle"); s.runtimeFamilyKey=family; s.runtimeClassCount=cc; s.runtimeEntryCount=mc; [out addObject:s]; }];
    [out sortUsingComparator:^NSComparisonResult(RYGRuntimeSurfaceSpec *a, RYGRuntimeSurfaceSpec *b) { if (a.runtimeEntryCount != b.runtimeEntryCount) return a.runtimeEntryCount > b.runtimeEntryCount ? NSOrderedAscending : NSOrderedDescending; return [a.title localizedCaseInsensitiveCompare:b.title]; }];
    return out.copy;
}

+ (NSArray<RYGRuntimeEntry *> *)scanSurface:(RYGRuntimeSurfaceSpec *)spec {
    if (!spec) return @[]; NSMutableArray *output=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    RYGEnumerateAppClasses(^(Class cls) {
        if (!RYGClassMatchesSurface(spec,cls)) return;
        if (spec.scanProperties) { unsigned int count=0; objc_property_t *props=class_copyPropertyList(cls,&count); for (unsigned int i=0; props && i<count; i++) { const char *raw=property_getName(props[i]); if (!raw) continue; NSString *sel=[NSString stringWithUTF8String:raw]; Method m=class_getInstanceMethod(cls,NSSelectorFromString(sel)); NSString *live=nil,*type=nil; if (RYGMethodIsSupported(m,&live,&type)) RYGAddEntry(output,seen,spec,cls,NO,live,YES,type); } if (props) free(props); }
        for (NSUInteger meta=0; meta<=1; meta++) { if ((!meta && !spec.scanInstanceMethods) || (meta && !spec.scanClassMethods)) continue; Class owner=meta?object_getClass(cls):cls; unsigned int count=0; Method *methods=class_copyMethodList(owner,&count);
            for (unsigned int i=0; methods && i<count; i++) { NSString *sel=nil,*type=nil; if (RYGMethodIsSupported(methods[i],&sel,&type)) RYGAddEntry(output,seen,spec,cls,(BOOL)meta,sel,NO,type); } if (methods) free(methods); }
    });
    return [output sortedArrayUsingComparator:^NSComparisonResult(RYGRuntimeEntry *a, RYGRuntimeEntry *b) { NSComparisonResult r=[a.runtimeFamily localizedCaseInsensitiveCompare:b.runtimeFamily]; if (r!=NSOrderedSame) return r; r=[a.imageName localizedCaseInsensitiveCompare:b.imageName]; if (r!=NSOrderedSame) return r; r=[a.className localizedCaseInsensitiveCompare:b.className]; if (r!=NSOrderedSame) return r; r=[a.selectorName localizedCaseInsensitiveCompare:b.selectorName]; if (r!=NSOrderedSame) return r; return a.classMethod==b.classMethod?NSOrderedSame:(a.classMethod?NSOrderedAscending:NSOrderedDescending); }];
}
@end
