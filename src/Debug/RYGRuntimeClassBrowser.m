#import "RYGRuntimeClassBrowser.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#include <stdlib.h>
#include <string.h>

@implementation RYGRuntimeClassRow @end
@implementation RYGRuntimeMethodRow @end
@implementation RYGRuntimePropertyRow @end

static NSString *RYGRTCanonicalPath(NSString *path) {
    NSString *standard = path.stringByStandardizingPath ?: @"";
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGRTPathEquals(NSString *left, NSString *right) {
    return left.length && right.length && [RYGRTCanonicalPath(left) isEqualToString:RYGRTCanonicalPath(right)];
}

static const char *RYGRTSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGRTArgumentKind(Method method) {
    if (!method) return (RYGRuntimeArgumentKind)-1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return (RYGRuntimeArgumentKind)-1;
    char raw[64] = {0};
    method_getArgumentType(method, 2, raw, sizeof(raw));
    const char *type = RYGRTSkipQualifiers(raw);
    if (!type || !*type) return (RYGRuntimeArgumentKind)-1;
    if (*type == '@' || *type == '#' || *type == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ", *type)) return RYGRuntimeArgumentInteger;
    return (RYGRuntimeArgumentKind)-1;
}

static BOOL RYGRTHookableBool(Method method) {
    if (!method) return NO;
    char raw[32] = {0};
    method_getReturnType(method, raw, sizeof(raw));
    const char *type = RYGRTSkipQualifiers(raw);
    RYGRuntimeArgumentKind kind = RYGRTArgumentKind(method);
    return type && *type == 'B' && kind >= RYGRuntimeArgumentNone && kind <= RYGRuntimeArgumentInteger;
}

static BOOL RYGRTMethodBelongsToImage(Method method, NSString *imagePath) {
    if (!method || !imagePath.length) return NO;
    IMP imp = method_getImplementation(method);
    Dl_info info = {0};
    if (!imp || !dladdr((const void *)imp, &info) || !info.dli_fname) return NO;
    NSString *owner = [NSString stringWithUTF8String:info.dli_fname];
    return RYGRTPathEquals(owner, imagePath);
}

static NSArray<RYGRuntimeMethodRow *> *RYGRTMethods(Class cls, NSString *imagePath, NSString *className, BOOL classMethods) {
    Class owner = classMethods ? object_getClass(cls) : cls;
    if (!owner) return @[];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(owner, &count);
    NSMutableArray<RYGRuntimeMethodRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int i = 0; methods && i < count; i++) {
        Method method = methods[i];
        if (!RYGRTMethodBelongsToImage(method, imagePath)) continue;
        SEL selector = method_getName(method);
        if (!selector) continue;
        RYGRuntimeMethodRow *row = [RYGRuntimeMethodRow new];
        row.imagePath = imagePath ?: @"";
        row.className = className ?: @"";
        row.selectorName = NSStringFromSelector(selector) ?: @"";
        const char *types = method_getTypeEncoding(method);
        row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
        row.classMethod = classMethods;
        row.argumentKind = RYGRTArgumentKind(method);
        row.hookableBool = RYGRTHookableBool(method);
        [rows addObject:row];
    }
    if (methods) free(methods);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMethodRow *a, RYGRuntimeMethodRow *b) {
        return [a.selectorName localizedCaseInsensitiveCompare:b.selectorName];
    }];
    return rows.copy;
}

@implementation RYGRuntimeClassBrowser

+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath {
    if (!imagePath.length) return @[];
    NSMutableOrderedSet<NSString *> *classNames = [NSMutableOrderedSet orderedSet];

    unsigned int namedCount = 0;
    const char **names = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &namedCount);
    if (!names) {
        NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
        if (![resolved isEqualToString:imagePath]) names = objc_copyClassNamesForImage(resolved.fileSystemRepresentation, &namedCount);
    }
    for (unsigned int i = 0; names && i < namedCount; i++) {
        if (names[i] && *names[i]) [classNames addObject:[NSString stringWithUTF8String:names[i]] ?: @""];
    }
    if (names) free(names);

    // Categories can contribute methods to a class whose defining image is not
    // the selected image. Discover those classes from the live runtime by IMP
    // ownership instead of relying on a pre-rendered class table.
    unsigned int runtimeCount = 0;
    Class *runtimeClasses = objc_copyClassList(&runtimeCount);
    for (unsigned int i = 0; runtimeClasses && i < runtimeCount; i++) {
        Class cls = runtimeClasses[i];
        NSString *className = cls ? NSStringFromClass(cls) : @"";
        if (!className.length || [classNames containsObject:className]) continue;
        BOOL contributes = NO;
        for (NSUInteger pass = 0; pass < 2 && !contributes; pass++) {
            Class owner = pass ? object_getClass(cls) : cls;
            unsigned int methodCount = 0;
            Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
            for (unsigned int j = 0; methods && j < methodCount; j++) {
                if (RYGRTMethodBelongsToImage(methods[j], imagePath)) { contributes = YES; break; }
            }
            if (methods) free(methods);
        }
        if (contributes) [classNames addObject:className];
    }
    if (runtimeClasses) free(runtimeClasses);

    NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray arrayWithCapacity:classNames.count];
    for (NSString *name in classNames) {
        Class cls = name.length ? objc_lookUpClass(name.UTF8String) : Nil;
        if (!cls) continue;
        RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
        row.imagePath = imagePath;
        row.className = name;

        unsigned int instanceRaw = 0;
        Method *instanceMethods = class_copyMethodList(cls, &instanceRaw);
        NSUInteger instanceCount = 0;
        for (unsigned int j = 0; instanceMethods && j < instanceRaw; j++) if (RYGRTMethodBelongsToImage(instanceMethods[j], imagePath)) instanceCount++;
        if (instanceMethods) free(instanceMethods);

        Class meta = object_getClass(cls);
        unsigned int classRaw = 0;
        Method *classMethods = meta ? class_copyMethodList(meta, &classRaw) : NULL;
        NSUInteger classCount = 0;
        for (unsigned int j = 0; classMethods && j < classRaw; j++) if (RYGRTMethodBelongsToImage(classMethods[j], imagePath)) classCount++;
        if (classMethods) free(classMethods);

        unsigned int propertyCount = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
        if (properties) free(properties);
        row.instanceMethodCount = instanceCount;
        row.classMethodCount = classCount;
        row.propertyCount = propertyCount;
        [rows addObject:row];
    }

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeClassRow *a, RYGRuntimeClassRow *b) {
        return [a.className localizedCaseInsensitiveCompare:b.className];
    }];
    return rows.copy;
}

+ (NSArray<RYGRuntimeMethodRow *> *)methodsForClass:(RYGRuntimeClassRow *)row classMethods:(BOOL)classMethods {
    if (!row.className.length) return @[];
    Class cls = objc_lookUpClass(row.className.UTF8String);
    return cls ? RYGRTMethods(cls, row.imagePath, row.className, classMethods) : @[];
}

+ (NSArray<RYGRuntimePropertyRow *> *)propertiesForClass:(RYGRuntimeClassRow *)row classProperties:(BOOL)classProperties {
    if (!row.className.length) return @[];
    Class cls = objc_lookUpClass(row.className.UTF8String);
    Class owner = classProperties ? object_getClass(cls) : cls;
    if (!owner) return @[];
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(owner, &count);
    NSMutableArray<RYGRuntimePropertyRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int i = 0; properties && i < count; i++) {
        const char *rawName = property_getName(properties[i]);
        const char *rawAttributes = property_getAttributes(properties[i]);
        if (!rawName) continue;
        RYGRuntimePropertyRow *property = [RYGRuntimePropertyRow new];
        property.name = [NSString stringWithUTF8String:rawName] ?: @"";
        property.attributes = rawAttributes ? [NSString stringWithUTF8String:rawAttributes] : @"";
        property.classProperty = classProperties;
        [rows addObject:property];
    }
    if (properties) free(properties);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimePropertyRow *a, RYGRuntimePropertyRow *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return rows.copy;
}

+ (RYGRuntimeBoolMethod *)boolDescriptorForMethod:(RYGRuntimeMethodRow *)method {
    if (!method.hookableBool) return nil;
    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.imagePath = method.imagePath ?: @"";
    row.className = method.className ?: @"";
    row.selectorName = method.selectorName ?: @"";
    row.typeEncoding = method.typeEncoding ?: @"";
    row.classMethod = method.classMethod;
    row.argumentKind = method.argumentKind;
    return row;
}

+ (BOOL)methodRow:(RYGRuntimeMethodRow *)row matchesSearch:(NSString *)query {
    NSString *needle = query.lowercaseString ?: @"";
    if (!needle.length) return YES;
    NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", row.className ?: @"", row.selectorName ?: @"", row.typeEncoding ?: @""] lowercaseString];
    for (NSString *part in [needle componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (part.length && [hay rangeOfString:part].location == NSNotFound) return NO;
    }
    return YES;
}

@end
