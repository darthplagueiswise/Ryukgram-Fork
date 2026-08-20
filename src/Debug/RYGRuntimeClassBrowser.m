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
        // This UI is an override browser, not a class-dump. Only materialize
        // methods whose exact runtime ABI has a safe BOOL adapter.
        if (!member.method || !member.hookableBool) continue;
        BOOL isClass = member.kind == RYGRuntimeMemberClassMethod;
        if (isClass != classMethods) continue;

        RYGRuntimeMethodRow *method = [RYGRuntimeMethodRow new];
        method.imagePath = member.imagePath ?: @"";
        method.className = member.className ?: @"";
        method.selectorName = member.name ?: @"";
        method.typeEncoding = member.typeEncoding ?: @"";
        method.classMethod = isClass;
        method.hookableBool = YES;
        method.argumentKind = member.argumentKind;
        [result addObject:method];
    }
    return result.copy;
}

+ (NSArray<RYGRuntimePropertyRow *> *)propertiesForClass:(RYGRuntimeClassRow *)row {
    (void)row;
    // A property is only useful here through its getter IMP. Safe BOOL getters
    // already appear once in Instance/Class Methods, where Observe/Force has an
    // exact adapter. Do not duplicate them as non-actionable property rows.
    return @[];
}

+ (RYGRuntimeBoolMethod *)boolDescriptorForMethod:(RYGRuntimeMethodRow *)method {
    if (!method.hookableBool) return nil;
    RYGRuntimeMemberRow *member = [RYGRuntimeMemberRow new];
    member.imagePath = method.imagePath ?: @"";
    member.className = method.className ?: @"";
    member.name = method.selectorName ?: @"";
    member.typeEncoding = method.typeEncoding ?: @"";
    member.kind = method.classMethod ? RYGRuntimeMemberClassMethod : RYGRuntimeMemberInstanceMethod;
    member.hookableBool = YES;
    member.argumentKind = method.argumentKind;
    return [RYGRuntimeBrowserEngine boolMethodForMember:member];
}

+ (BOOL)methodRow:(RYGRuntimeMethodRow *)row matchesSearch:(NSString *)query {
    return RYGRTContainsTokens([NSString stringWithFormat:@"%@ %@ %@", row.className ?: @"", row.selectorName ?: @"", row.typeEncoding ?: @""], query);
}

@end
