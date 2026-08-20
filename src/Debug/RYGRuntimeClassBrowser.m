#import "RYGRuntimeClassBrowser.h"

@implementation RYGRuntimeMethodRow @end
@implementation RYGRuntimePropertyRow @end

static BOOL RYGRTContainsTokens(NSString *haystack, NSString *query) {
    if (!query.length) return YES;
    NSString *lower = haystack.lowercaseString ?: @"";
    for (NSString *token in [query.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (token.length && [lower rangeOfString:token].location == NSNotFound) return NO;
    }
    return YES;
}

@implementation RYGRuntimeClassBrowser

+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath {
    return [RYGRuntimeBrowserEngine classesForImagePath:imagePath] ?: @[];
}

+ (NSArray<RYGRuntimeMethodRow *> *)methodsForClass:(RYGRuntimeClassRow *)row classMethods:(BOOL)classMethods {
    if (!row.className.length || !row.imagePath.length) return @[];
    NSMutableArray<RYGRuntimeMethodRow *> *result = [NSMutableArray array];
    for (RYGRuntimeMemberRow *member in [RYGRuntimeBrowserEngine membersForClassName:row.className imagePath:row.imagePath]) {
        if (!member.method) continue;
        BOOL isClass = member.kind == RYGRuntimeMemberClassMethod;
        if (isClass != classMethods) continue;
        RYGRuntimeMethodRow *method = [RYGRuntimeMethodRow new];
        method.imagePath = member.imagePath ?: @"";
        method.className = member.className ?: @"";
        method.selectorName = member.name ?: @"";
        method.typeEncoding = member.typeEncoding ?: @"";
        method.classMethod = isClass;
        method.hookableBool = member.hookableBool;
        method.argumentKind = member.argumentKind;
        [result addObject:method];
    }
    return result.copy;
}

+ (NSArray<RYGRuntimePropertyRow *> *)propertiesForClass:(RYGRuntimeClassRow *)row {
    if (!row.className.length || !row.imagePath.length) return @[];
    NSMutableArray<RYGRuntimePropertyRow *> *result = [NSMutableArray array];
    for (RYGRuntimeMemberRow *member in [RYGRuntimeBrowserEngine membersForClassName:row.className imagePath:row.imagePath]) {
        if (member.method) continue;
        RYGRuntimePropertyRow *property = [RYGRuntimePropertyRow new];
        property.name = member.name ?: @"";
        property.attributes = member.typeEncoding ?: @"";
        property.classProperty = member.kind == RYGRuntimeMemberClassProperty;
        [result addObject:property];
    }
    return result.copy;
}

+ (RYGRuntimeBoolMethod *)boolDescriptorForMethod:(RYGRuntimeMethodRow *)method {
    if (!method.hookableBool) return nil;
    RYGRuntimeMemberRow *member = [RYGRuntimeMemberRow new];
    member.imagePath = method.imagePath ?: @"";
    member.className = method.className ?: @"";
    member.name = method.selectorName ?: @"";
    member.typeEncoding = method.typeEncoding ?: @"";
    member.kind = method.classMethod ? RYGRuntimeMemberClassMethod : RYGRuntimeMemberInstanceMethod;
    member.hookableBool = method.hookableBool;
    member.argumentKind = method.argumentKind;
    return [RYGRuntimeBrowserEngine boolMethodForMember:member];
}

+ (BOOL)methodRow:(RYGRuntimeMethodRow *)row matchesSearch:(NSString *)query {
    return RYGRTContainsTokens([NSString stringWithFormat:@"%@ %@ %@",
                               row.className ?: @"",
                               row.selectorName ?: @"",
                               row.typeEncoding ?: @""],
                               query);
}

@end
