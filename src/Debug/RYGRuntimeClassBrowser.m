#import "RYGRuntimeClassBrowser.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

@implementation RYGRuntimeClassRow @end
@implementation RYGRuntimeMethodRow @end
@implementation RYGRuntimePropertyRow @end

static NSString *RYGRTCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static BOOL RYGRTPathEquals(NSString *left, NSString *right) {
    if (!left.length || !right.length) return NO;
    return [RYGRTCanonicalPath(left) isEqualToString:RYGRTCanonicalPath(right)];
}

static const char *RYGRTSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGRTIsBoolType(const char *raw) {
    const char *type = RYGRTSkipQualifiers(raw);
    return type && strchr("BcC", *type) != NULL;
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
    RYGRuntimeArgumentKind kind = RYGRTArgumentKind(method);
    return RYGRTIsBoolType(raw) &&
        kind >= RYGRuntimeArgumentNone && kind <= RYGRuntimeArgumentInteger;
}

static NSArray<RYGRuntimeMethodRow *> *RYGRTMethods(Class cls,
                                                     NSString *imagePath,
                                                     NSString *className,
                                                     BOOL classMethods) {
    Class owner = classMethods ? object_getClass(cls) : cls;
    if (!owner) return @[];

    unsigned int count = 0;
    Method *methods = class_copyMethodList(owner, &count);
    NSMutableArray<RYGRuntimeMethodRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; methods && index < count; index++) {
        Method method = methods[index];
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

    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeMethodRow *left, RYGRuntimeMethodRow *right) {
        return [left.selectorName localizedCaseInsensitiveCompare:right.selectorName];
    }];
    return rows.copy;
}

static void RYGRTAddClassName(NSMutableOrderedSet<NSString *> *names, Class cls, NSString *imagePath) {
    if (!cls || !imagePath.length) return;
    const char *rawImage = class_getImageName(cls);
    if (!rawImage) return;
    NSString *actual = [NSString stringWithUTF8String:rawImage];
    if (!RYGRTPathEquals(actual, imagePath)) return;
    const char *rawName = class_getName(cls);
    if (!rawName || !*rawName) return;
    NSString *name = [NSString stringWithUTF8String:rawName];
    if (name.length) [names addObject:name];
}

@implementation RYGRuntimeClassBrowser

+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath {
    if (!imagePath.length) return @[];
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];

    unsigned int namedCount = 0;
    const char **named = objc_copyClassNamesForImage(imagePath.fileSystemRepresentation, &namedCount);
    if ((!named || namedCount == 0) && imagePath.stringByResolvingSymlinksInPath.length) {
        if (named) free(named);
        NSString *resolved = imagePath.stringByResolvingSymlinksInPath;
        named = objc_copyClassNamesForImage(resolved.fileSystemRepresentation, &namedCount);
    }
    for (unsigned int index = 0; named && index < namedCount; index++) {
        if (!named[index] || !*named[index]) continue;
        Class cls = objc_lookUpClass(named[index]);
        RYGRTAddClassName(names, cls, imagePath);
    }
    if (named) free(named);

    // Some sideloaded executables do not round-trip through
    // objc_copyClassNamesForImage even though class_getImageName is correct.
    // Fall back to a raw C Class buffer; never retain Class objects in NSArray.
    if (names.count == 0) {
        int total = objc_getClassList(NULL, 0);
        if (total > 0 && total < 500000) {
            Class __unsafe_unretained *classes =
                (Class __unsafe_unretained *)calloc((size_t)total, sizeof(Class));
            int filled = classes ? objc_getClassList(classes, total) : 0;
            for (int index = 0; index < filled; index++) {
                RYGRTAddClassName(names, classes[index], imagePath);
            }
            free(classes);
        }
    }

    NSArray<NSString *> *sortedNames = [names.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray<RYGRuntimeClassRow *> *rows = [NSMutableArray arrayWithCapacity:sortedNames.count];
    for (NSString *name in sortedNames) {
        Class cls = name.length ? objc_lookUpClass(name.UTF8String) : Nil;
        if (!cls) continue;

        unsigned int instanceCount = 0;
        Method *instanceMethods = class_copyMethodList(cls, &instanceCount);
        if (instanceMethods) free(instanceMethods);

        unsigned int classCount = 0;
        Class meta = object_getClass(cls);
        Method *classMethods = meta ? class_copyMethodList(meta, &classCount) : NULL;
        if (classMethods) free(classMethods);

        unsigned int propertyCount = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
        if (properties) free(properties);

        RYGRuntimeClassRow *row = [RYGRuntimeClassRow new];
        row.imagePath = imagePath;
        row.className = name;
        row.instanceMethodCount = instanceCount;
        row.classMethodCount = classCount;
        row.propertyCount = propertyCount;
        [rows addObject:row];
    }
    return rows.copy;
}

+ (NSArray<RYGRuntimeMethodRow *> *)methodsForClass:(RYGRuntimeClassRow *)row
                                      classMethods:(BOOL)classMethods {
    if (!row.className.length) return @[];
    Class cls = objc_lookUpClass(row.className.UTF8String);
    return cls ? RYGRTMethods(cls, row.imagePath, row.className, classMethods) : @[];
}

+ (NSArray<RYGRuntimePropertyRow *> *)propertiesForClass:(RYGRuntimeClassRow *)row {
    if (!row.className.length) return @[];
    Class cls = objc_lookUpClass(row.className.UTF8String);
    if (!cls) return @[];

    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    NSMutableArray<RYGRuntimePropertyRow *> *rows = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int index = 0; properties && index < count; index++) {
        const char *rawName = property_getName(properties[index]);
        if (!rawName) continue;
        RYGRuntimePropertyRow *property = [RYGRuntimePropertyRow new];
        property.name = [NSString stringWithUTF8String:rawName] ?: @"";
        const char *attributes = property_getAttributes(properties[index]);
        property.attributes = attributes ? [NSString stringWithUTF8String:attributes] : @"";
        [rows addObject:property];
    }
    if (properties) free(properties);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimePropertyRow *left, RYGRuntimePropertyRow *right) {
        return [left.name localizedCaseInsensitiveCompare:right.name];
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
    if (!query.length) return YES;
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@",
                           row.className ?: @"",
                           row.selectorName ?: @"",
                           row.typeEncoding ?: @""] lowercaseString];
    for (NSString *token in [query.lowercaseString componentsSeparatedByCharactersInSet:
                              NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (token.length && [haystack rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

@end
