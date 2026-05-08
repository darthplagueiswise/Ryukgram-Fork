#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "SCIMobileConfigBrokerStore.h"

static NSDictionary *(*SCIOrigResolvedMetadataForOverrideKey)(Class, SEL, NSString *) = NULL;

static NSString *SCIStringValue(id obj) {
    return [obj isKindOfClass:NSString.class] ? (NSString *)obj : @"";
}

static BOOL SCIBoolValue(id obj) {
    return [obj respondsToSelector:@selector(boolValue)] ? [obj boolValue] : NO;
}

static NSString *SCIIDTitleFromMetadata(NSDictionary *metadata) {
    NSString *rawPrefixed = SCIStringValue(metadata[@"rawValuePrefixed"]);
    if (rawPrefixed.length) return rawPrefixed;

    NSString *normalized = SCIStringValue(metadata[@"normalizedValue"]);
    if (normalized.length) return normalized;

    NSString *normalizedKey = SCIStringValue(metadata[@"normalizedKey"]);
    if (normalizedKey.length) return normalizedKey;

    NSString *raw = SCIStringValue(metadata[@"rawValue"]);
    if (raw.length) return [raw hasPrefix:@"0x"] ? raw : [@"0x" stringByAppendingString:raw];

    NSString *rawKey = SCIStringValue(metadata[@"rawKey"]);
    if (rawKey.length) return rawKey;

    return @"";
}

static NSDictionary *SCIResolvedMetadataForOverrideKeyNormalized(Class cls, SEL sel, NSString *overrideKey) {
    NSDictionary *base = SCIOrigResolvedMetadataForOverrideKey ? SCIOrigResolvedMetadataForOverrideKey(cls, sel, overrideKey) : @{};
    if (![base isKindOfClass:NSDictionary.class] || base.count == 0) return base;

    NSString *source = SCIStringValue(base[@"source"]);
    BOOL resolved = SCIBoolValue(base[@"resolved"]);
    BOOL hasExactName = SCIStringValue(base[@"resolvedName"]).length > 0 || SCIStringValue(base[@"name"]).length > 0;

    if (resolved || hasExactName || ![source isEqualToString:@"runtime-callsite"]) {
        return base;
    }

    NSMutableDictionary *out = [base mutableCopy];
    NSString *callerSymbol = SCIStringValue(base[@"callerSymbol"]);
    NSString *currentTitle = SCIStringValue(base[@"title"]);
    NSString *idTitle = SCIIDTitleFromMetadata(base);

    if (callerSymbol.length) out[@"callsiteTitle"] = callerSymbol;
    if (idTitle.length && (!currentTitle.length || [currentTitle isEqualToString:callerSymbol] || ![currentTitle hasPrefix:@"0x"])) {
        out[@"title"] = idTitle;
    }

    out[@"resolvedName"] = @"";
    out[@"name"] = @"";
    out[@"resolved"] = @NO;
    out[@"runtimeObserved"] = @YES;
    out[@"displayHint"] = @"unresolved runtime callsite; title kept as MC id, caller kept separately";

    return [out copy];
}

__attribute__((constructor))
static void SCIInstallMCBrokerDisplayNormalizer(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"SCIMobileConfigBrokerStore");
        if (!cls) return;

        Method method = class_getClassMethod(cls, @selector(resolvedMetadataForOverrideKey:));
        if (!method) return;

        IMP oldImp = method_getImplementation(method);
        if (!oldImp || oldImp == (IMP)SCIResolvedMetadataForOverrideKeyNormalized) return;

        SCIOrigResolvedMetadataForOverrideKey = (NSDictionary *(*)(Class, SEL, NSString *))oldImp;
        method_setImplementation(method, (IMP)SCIResolvedMetadataForOverrideKeyNormalized);
    }
}
