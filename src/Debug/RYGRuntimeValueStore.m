#import "RYGRuntimeValueStore.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#include <string.h>

NSString *const RYGRuntimeValueOverridesKey = @"ryg_runtime_typed_value_overrides_v2";

static NSString *const kRYGValueClassKey = @"class";
static NSString *const kRYGValueSelectorKey = @"selector";
static NSString *const kRYGValueMetaKey = @"meta";
static NSString *const kRYGValueTypeKey = @"type";
static NSString *const kRYGValuePayloadKey = @"value";
static NSString *const kRYGValueKindKey = @"kind";
static NSString *const kRYGValueArgumentKey = @"argument_kind";
static NSString *const kRYGValueImagePathKey = @"image_path";
static NSString *const kRYGValueImageUUIDKey = @"image_uuid";
static NSString *const kRYGNestedKindKey = @"__ryg_kind";
static NSString *const kRYGNestedValueKey = @"__ryg_value";

@interface RYGRuntimeValueHookDescriptor : NSObject
@property(nonatomic, copy) NSString *uid;
@property(nonatomic, assign) SEL selector;
@property(nonatomic, assign) IMP original;
@property(nonatomic, assign) char returnCode;
@property(nonatomic, assign) RYGRuntimeValueArgumentKind argumentKind;
@end
@implementation RYGRuntimeValueHookDescriptor @end

static NSMutableDictionary<NSString *, NSDictionary *> *gRYGRuntimeValueOverrides;
static NSMutableDictionary<NSString *, RYGRuntimeValueHookDescriptor *> *gRYGRuntimeValueHooks;
static NSMutableDictionary<NSString *, id> *gRYGRuntimeObservedValues;
static NSObject *gRYGRuntimeValueLock;
static dispatch_once_t gRYGRuntimeValueOnce;

static NSString *RYGCanonicalPath(NSString *path) {
    if (!path.length) return @"";
    NSString *standard = path.stringByStandardizingPath;
    NSString *resolved = standard.stringByResolvingSymlinksInPath;
    return resolved.length ? resolved.stringByStandardizingPath : standard;
}

static const struct mach_header *RYGHeaderForPath(NSString *path) {
    NSString *wanted = RYGCanonicalPath(path);
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *loaded = RYGCanonicalPath([NSString stringWithUTF8String:raw]);
        if ([loaded isEqualToString:wanted]) return _dyld_get_image_header(i);
    }
    return NULL;
}

static NSString *RYGUUIDForHeader(const struct mach_header *header) {
    if (!header || (header->magic != MH_MAGIC_64 && header->magic != MH_CIGAM_64)) return nil;
    const struct mach_header_64 *h = (const struct mach_header_64 *)header;
    const uint8_t *cursor = (const uint8_t *)h + sizeof(*h);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc)) break;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uuid = (const struct uuid_command *)lc;
            NSUUID *value = [[NSUUID alloc] initWithUUIDBytes:uuid->uuid];
            return value.UUIDString.uppercaseString;
        }
        cursor += lc->cmdsize;
    }
    return nil;
}

NSString *RYGRuntimeValueImageUUIDForClassName(NSString *className) {
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    const char *raw = cls ? class_getImageName(cls) : NULL;
    NSString *path = raw ? [NSString stringWithUTF8String:raw] : nil;
    return RYGUUIDForHeader(RYGHeaderForPath(path));
}

static const char *RYGSkipQualifiers(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

NSString *RYGRuntimeValueNormalizedType(NSString *typeCode) {
    const char *cursor = typeCode.UTF8String;
    cursor = RYGSkipQualifiers(cursor);
    return cursor && *cursor ? [NSString stringWithFormat:@"%c", *cursor] : @"";
}

NSString *RYGRuntimeValueTypeName(NSString *typeCode) {
    NSString *type = RYGRuntimeValueNormalizedType(typeCode);
    if (!type.length) return nil;
    switch ([type characterAtIndex:0]) {
        case 'B': return @"BOOL";
        case 'c': return @"char/BOOL";
        case 'C': return @"uint8";
        case 's': return @"int16";
        case 'S': return @"uint16";
        case 'i': return @"int32";
        case 'I': return @"uint32";
        case 'l': return @"long";
        case 'L': return @"unsigned long";
        case 'q': return @"int64";
        case 'Q': return @"uint64";
        case 'f': return @"float";
        case 'd': return @"double";
        case '@': return @"object";
        default: return nil;
    }
}

BOOL RYGRuntimeValueTypeIsSupported(NSString *typeCode) { return RYGRuntimeValueTypeName(typeCode) != nil; }
BOOL RYGRuntimeValueTypeIsBoolean(NSString *typeCode) {
    NSString *type = RYGRuntimeValueNormalizedType(typeCode);
    return [type isEqualToString:@"B"] || [type isEqualToString:@"c"];
}
BOOL RYGRuntimeValueTypeIsSignedInteger(NSString *typeCode) {
    return [@[@"s", @"i", @"l", @"q"] containsObject:RYGRuntimeValueNormalizedType(typeCode)];
}
BOOL RYGRuntimeValueTypeIsUnsignedInteger(NSString *typeCode) {
    return [@[@"C", @"S", @"I", @"L", @"Q"] containsObject:RYGRuntimeValueNormalizedType(typeCode)];
}
BOOL RYGRuntimeValueTypeIsFloatingPoint(NSString *typeCode) {
    NSString *type = RYGRuntimeValueNormalizedType(typeCode);
    return [type isEqualToString:@"f"] || [type isEqualToString:@"d"];
}
BOOL RYGRuntimeValueTypeIsObject(NSString *typeCode) { return [RYGRuntimeValueNormalizedType(typeCode) isEqualToString:@"@"]; }

BOOL RYGRuntimeValueSelectorIsSafeGetter(NSString *selectorName) {
    if (!selectorName.length) return NO;
    NSUInteger colons = [[selectorName componentsSeparatedByString:@":"] count] - 1;
    if (colons > 1) return NO;
    static NSSet<NSString *> *blocked;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        blocked = [NSSet setWithArray:@[
            @"alloc", @"init", @"new", @"dealloc", @"finalize", @"copy", @"mutableCopy",
            @"retain", @"release", @"autorelease", @"retainCount", @"zone", @"class", @"superclass",
            @"self", @"hash", @"description", @"debugDescription", @"isProxy", @"isEqual:",
            @"respondsToSelector:", @"isKindOfClass:", @"isMemberOfClass:", @"conformsToProtocol:",
            @"methodForSelector:", @"forwardingTargetForSelector:", @"performSelector:"
        ]];
    });
    if ([blocked containsObject:selectorName]) return NO;
    NSString *normalized = [[[selectorName lowercaseString]
        componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
        componentsJoinedByString:@""];
    for (NSString *prefix in @[@"isequal", @"equalto", @"respondstoselector", @"canrespond",
                                @"iskindofclass", @"ismemberofclass", @"conformstoprotocol",
                                @"allowsweakreference", @"retainweakreference"]) {
        if ([normalized hasPrefix:prefix]) return NO;
    }
    return YES;
}

BOOL RYGRuntimeValueClassifyMethod(Method method,
                                   NSString **typeCode,
                                   RYGRuntimeValueArgumentKind *argumentKind) {
    if (typeCode) *typeCode = nil;
    if (argumentKind) *argumentKind = RYGRuntimeValueArgumentUnsupported;
    if (!method) return NO;
    NSString *selector = NSStringFromSelector(method_getName(method));
    if (!RYGRuntimeValueSelectorIsSafeGetter(selector)) return NO;

    char rawReturn[64] = {0};
    method_getReturnType(method, rawReturn, sizeof(rawReturn));
    NSString *normalized = RYGRuntimeValueNormalizedType([NSString stringWithUTF8String:rawReturn] ?: @"");
    unsigned int argc = method_getNumberOfArguments(method);
    if (argc == 2 && RYGRuntimeValueTypeIsSupported(normalized) && ![selector containsString:@":"]) {
        if (typeCode) *typeCode = normalized;
        if (argumentKind) *argumentKind = RYGRuntimeValueArgumentNone;
        return YES;
    }
    if (argc != 3 || ![selector containsString:@":"]) return NO;
    char returnCode = RYGSkipQualifiers(rawReturn)[0];
    if (returnCode != 'B' && returnCode != 'c' && returnCode != 'C') return NO;
    char rawArgument[64] = {0};
    method_getArgumentType(method, 2, rawArgument, sizeof(rawArgument));
    char arg = RYGSkipQualifiers(rawArgument)[0];
    RYGRuntimeValueArgumentKind kind = RYGRuntimeValueArgumentUnsupported;
    if (arg == '@') kind = RYGRuntimeValueArgumentObject;
    else if (arg == 'q' || arg == 'Q') kind = RYGRuntimeValueArgumentInteger;
    if (kind == RYGRuntimeValueArgumentUnsupported) return NO;
    if (typeCode) *typeCode = @"B"; // semantic BOOL row; replacement preserves the concrete B/c/C ABI.
    if (argumentKind) *argumentKind = kind;
    return YES;
}

static id RYGRuntimeValueEncodeNested(id value);
static id RYGRuntimeValueDecodeNested(id value);

static id RYGRuntimeValueEncodeNested(id value) {
    if (!value || value == NSNull.null) return @{kRYGNestedKindKey:@"nil"};
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return @{kRYGNestedKindKey:@"url", kRYGNestedValueKey:[(NSURL *)value absoluteString] ?: @""};
    if ([value isKindOfClass:NSData.class]) return @{kRYGNestedKindKey:@"data", kRYGNestedValueKey:[(NSData *)value base64EncodedStringWithOptions:0] ?: @""};
    if ([value isKindOfClass:NSDate.class]) return @{kRYGNestedKindKey:@"date", kRYGNestedValueKey:@([(NSDate *)value timeIntervalSince1970])};
    if ([value isKindOfClass:NSSet.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in [(NSSet *)value allObjects]) [out addObject:RYGRuntimeValueEncodeNested(item) ?: @{kRYGNestedKindKey:@"nil"}];
        return @{kRYGNestedKindKey:@"set", kRYGNestedValueKey:out};
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in (NSArray *)value) [out addObject:RYGRuntimeValueEncodeNested(item) ?: @{kRYGNestedKindKey:@"nil"}];
        return out;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
            (void)stop;
            NSString *stringKey = [key isKindOfClass:NSString.class] ? key : [key description];
            if (stringKey.length) out[stringKey] = RYGRuntimeValueEncodeNested(object) ?: @{kRYGNestedKindKey:@"nil"};
        }];
        return out;
    }
    return nil;
}

static id RYGRuntimeValueDecodeNested(id value) {
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in (NSArray *)value) [out addObject:RYGRuntimeValueDecodeNested(item) ?: NSNull.null];
        return out;
    }
    if (![value isKindOfClass:NSDictionary.class]) return value;
    NSString *kind = value[kRYGNestedKindKey];
    id payload = value[kRYGNestedValueKey];
    if ([kind isEqualToString:@"nil"]) return nil;
    if ([kind isEqualToString:@"url"]) return [NSURL URLWithString:[payload description] ?: @""];
    if ([kind isEqualToString:@"data"]) return [[NSData alloc] initWithBase64EncodedString:[payload description] ?: @"" options:0];
    if ([kind isEqualToString:@"date"]) return [NSDate dateWithTimeIntervalSince1970:[payload doubleValue]];
    if ([kind isEqualToString:@"set"]) {
        id decoded = RYGRuntimeValueDecodeNested(payload);
        return [decoded isKindOfClass:NSArray.class] ? [NSSet setWithArray:decoded] : [NSSet set];
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        (void)stop; out[key] = RYGRuntimeValueDecodeNested(object) ?: NSNull.null;
    }];
    return out;
}

static NSDictionary *RYGRuntimeValueEncodedObjectSpec(id value) {
    if (!value || value == NSNull.null) return @{kRYGValueKindKey:@"nil", kRYGValuePayloadKey:@""};
    id encoded = RYGRuntimeValueEncodeNested(value);
    if (!encoded) return nil;
    NSString *kind = @"foundation";
    if ([value isKindOfClass:NSString.class]) kind = @"string";
    else if ([value isKindOfClass:NSNumber.class]) kind = @"number";
    else if ([value isKindOfClass:NSArray.class]) kind = @"array";
    else if ([value isKindOfClass:NSDictionary.class]) kind = @"dictionary";
    else if ([value isKindOfClass:NSSet.class]) kind = @"set";
    else if ([value isKindOfClass:NSURL.class]) kind = @"url";
    else if ([value isKindOfClass:NSData.class]) kind = @"data";
    else if ([value isKindOfClass:NSDate.class]) kind = @"date";
    return @{kRYGValueKindKey:kind, kRYGValuePayloadKey:encoded};
}

static id RYGRuntimeValueDecodeSpec(NSDictionary *spec) {
    if (![spec isKindOfClass:NSDictionary.class]) return nil;
    if (![spec[kRYGValueTypeKey] isEqualToString:@"@"]) return spec[kRYGValuePayloadKey];
    if ([spec[kRYGValueKindKey] isEqualToString:@"nil"]) return nil;
    return RYGRuntimeValueDecodeNested(spec[kRYGValuePayloadKey]);
}

static void RYGRuntimeValueEnsureStorage(void) {
    dispatch_once(&gRYGRuntimeValueOnce, ^{
        gRYGRuntimeValueLock = [NSObject new];
        gRYGRuntimeValueHooks = [NSMutableDictionary dictionary];
        gRYGRuntimeObservedValues = [NSMutableDictionary dictionary];
        NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:RYGRuntimeValueOverridesKey];
        gRYGRuntimeValueOverrides = stored ? stored.mutableCopy : [NSMutableDictionary dictionary];
    });
}

static void RYGRuntimeValuePersistLocked(void) {
    if (gRYGRuntimeValueOverrides.count) [NSUserDefaults.standardUserDefaults setObject:gRYGRuntimeValueOverrides.copy forKey:RYGRuntimeValueOverridesKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:RYGRuntimeValueOverridesKey];
}

NSString *RYGRuntimeValueUID(NSString *className, NSString *selectorName, BOOL classMethod) {
    return className.length && selectorName.length ? [NSString stringWithFormat:@"%@|%@|%@", className, classMethod ? @"class" : @"instance", selectorName] : @"";
}

static NSDictionary *RYGRuntimeValueSpec(NSString *className, NSString *selectorName, BOOL classMethod) {
    RYGRuntimeValueEnsureStorage();
    NSString *uid = RYGRuntimeValueUID(className, selectorName, classMethod);
    @synchronized (gRYGRuntimeValueLock) { return gRYGRuntimeValueOverrides[uid]; }
}

BOOL RYGRuntimeValueHasOverride(NSString *className, NSString *selectorName, BOOL classMethod) { return RYGRuntimeValueSpec(className, selectorName, classMethod) != nil; }
id RYGRuntimeValueOverride(NSString *className, NSString *selectorName, BOOL classMethod) { return RYGRuntimeValueDecodeSpec(RYGRuntimeValueSpec(className, selectorName, classMethod)); }
id RYGRuntimeValueObservedValue(NSString *className, NSString *selectorName, BOOL classMethod) {
    RYGRuntimeValueEnsureStorage();
    NSString *uid = RYGRuntimeValueUID(className, selectorName, classMethod);
    @synchronized (gRYGRuntimeValueLock) { return gRYGRuntimeObservedValues[uid]; }
}

static Method RYGMethodForIdentity(NSString *className, NSString *selectorName, BOOL classMethod, Class *targetOut) {
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class target = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    if (targetOut) *targetOut = target;
    return target && selector ? class_getInstanceMethod(target, selector) : NULL;
}

void RYGRuntimeValueSetOverride(NSString *className, NSString *selectorName, BOOL classMethod,
                                NSString *typeCode, id value) {
    NSString *uid = RYGRuntimeValueUID(className, selectorName, classMethod);
    Class target = Nil;
    Method method = RYGMethodForIdentity(className, selectorName, classMethod, &target);
    NSString *liveType = nil;
    RYGRuntimeValueArgumentKind argKind = RYGRuntimeValueArgumentUnsupported;
    if (!uid.length || !RYGRuntimeValueClassifyMethod(method, &liveType, &argKind)) return;
    NSString *requested = RYGRuntimeValueNormalizedType(typeCode);
    if (![requested isEqualToString:liveType]) return;

    NSMutableDictionary *spec = [@{kRYGValueClassKey:className,
                                   kRYGValueSelectorKey:selectorName,
                                   kRYGValueMetaKey:@(classMethod),
                                   kRYGValueTypeKey:liveType,
                                   kRYGValueArgumentKey:@(argKind)} mutableCopy];
    if ([liveType isEqualToString:@"@"]) {
        NSDictionary *objectSpec = RYGRuntimeValueEncodedObjectSpec(value);
        if (!objectSpec) return;
        [spec addEntriesFromDictionary:objectSpec];
    } else {
        if (![value isKindOfClass:NSNumber.class]) return;
        spec[kRYGValuePayloadKey] = value;
    }
    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    const char *rawPath = cls ? class_getImageName(cls) : NULL;
    NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : @"";
    NSString *uuid = RYGRuntimeValueImageUUIDForClassName(className);
    if (path.length) spec[kRYGValueImagePathKey] = path;
    if (uuid.length) spec[kRYGValueImageUUIDKey] = uuid;

    RYGRuntimeValueEnsureStorage();
    @synchronized (gRYGRuntimeValueLock) {
        gRYGRuntimeValueOverrides[uid] = spec.copy;
        RYGRuntimeValuePersistLocked();
    }
}

void RYGRuntimeValueClearOverride(NSString *className, NSString *selectorName, BOOL classMethod) {
    NSString *uid = RYGRuntimeValueUID(className, selectorName, classMethod);
    if (!uid.length) return;
    RYGRuntimeValueEnsureStorage();
    @synchronized (gRYGRuntimeValueLock) {
        [gRYGRuntimeValueOverrides removeObjectForKey:uid];
        RYGRuntimeValuePersistLocked();
    }
}

NSArray<NSDictionary<NSString *, id> *> *RYGRuntimeValueAllOverrideSpecs(void) {
    RYGRuntimeValueEnsureStorage();
    @synchronized (gRYGRuntimeValueLock) { return gRYGRuntimeValueOverrides.allValues.copy ?: @[]; }
}

static id RYGRuntimeForced(RYGRuntimeValueHookDescriptor *descriptor, BOOL *has) {
    if (has) *has = NO;
    RYGRuntimeValueEnsureStorage();
    @synchronized (gRYGRuntimeValueLock) {
        NSDictionary *spec = gRYGRuntimeValueOverrides[descriptor.uid];
        if (!spec) return nil;
        if (has) *has = YES;
        return RYGRuntimeValueDecodeSpec(spec);
    }
}

static void RYGRememberObserved(RYGRuntimeValueHookDescriptor *descriptor, id value) {
    if (!descriptor.uid.length || !value) return;
    RYGRuntimeValueEnsureStorage();
    @synchronized (gRYGRuntimeValueLock) { gRYGRuntimeObservedValues[descriptor.uid] = value; }
}

static IMP RYGRuntimeZeroArgReplacement(RYGRuntimeValueHookDescriptor *d) {
    switch (d.returnCode) {
        case 'B': return imp_implementationWithBlock(^BOOL(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v boolValue]:(d.original?((BOOL(*)(id,SEL))d.original)(r,d.selector):NO); });
        case 'c': return imp_implementationWithBlock(^signed char(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v charValue]:(d.original?((signed char(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'C': return imp_implementationWithBlock(^unsigned char(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v unsignedCharValue]:(d.original?((unsigned char(*)(id,SEL))d.original)(r,d.selector):0); });
        case 's': return imp_implementationWithBlock(^short(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v shortValue]:(d.original?((short(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'S': return imp_implementationWithBlock(^unsigned short(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v unsignedShortValue]:(d.original?((unsigned short(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'i': return imp_implementationWithBlock(^int(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v intValue]:(d.original?((int(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'I': return imp_implementationWithBlock(^unsigned int(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v unsignedIntValue]:(d.original?((unsigned int(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'l': return imp_implementationWithBlock(^long(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v longValue]:(d.original?((long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'L': return imp_implementationWithBlock(^unsigned long(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v unsignedLongValue]:(d.original?((unsigned long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'q': return imp_implementationWithBlock(^long long(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v longLongValue]:(d.original?((long long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'Q': return imp_implementationWithBlock(^unsigned long long(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v unsignedLongLongValue]:(d.original?((unsigned long long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'f': return imp_implementationWithBlock(^float(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v floatValue]:(d.original?((float(*)(id,SEL))d.original)(r,d.selector):0.0f); });
        case 'd': return imp_implementationWithBlock(^double(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v doubleValue]:(d.original?((double(*)(id,SEL))d.original)(r,d.selector):0.0); });
        case '@': return imp_implementationWithBlock(^id(id r){ BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?v:(d.original?((id(*)(id,SEL))d.original)(r,d.selector):nil); });
        default: return NULL;
    }
}

static IMP RYGRuntimeOneArgBoolReplacement(RYGRuntimeValueHookDescriptor *d) {
    if (d.argumentKind == RYGRuntimeValueArgumentObject) {
        switch (d.returnCode) {
            case 'B': return imp_implementationWithBlock(^BOOL(id r,id a){ BOOL n=d.original?((BOOL(*)(id,SEL,id))d.original)(r,d.selector,a):NO; RYGRememberObserved(d,@(n)); BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v boolValue]:n; });
            case 'c': return imp_implementationWithBlock(^signed char(id r,id a){ signed char n=d.original?((signed char(*)(id,SEL,id))d.original)(r,d.selector,a):0; RYGRememberObserved(d,@(n)); BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v charValue]:n; });
            case 'C': return imp_implementationWithBlock(^unsigned char(id r,id a){ unsigned char n=d.original?((unsigned char(*)(id,SEL,id))d.original)(r,d.selector,a):0; RYGRememberObserved(d,@(n)); BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v unsignedCharValue]:n; });
        }
    } else if (d.argumentKind == RYGRuntimeValueArgumentInteger) {
        switch (d.returnCode) {
            case 'B': return imp_implementationWithBlock(^BOOL(id r,uint64_t a){ BOOL n=d.original?((BOOL(*)(id,SEL,uint64_t))d.original)(r,d.selector,a):NO; RYGRememberObserved(d,@(n)); BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v boolValue]:n; });
            case 'c': return imp_implementationWithBlock(^signed char(id r,uint64_t a){ signed char n=d.original?((signed char(*)(id,SEL,uint64_t))d.original)(r,d.selector,a):0; RYGRememberObserved(d,@(n)); BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v charValue]:n; });
            case 'C': return imp_implementationWithBlock(^unsigned char(id r,uint64_t a){ unsigned char n=d.original?((unsigned char(*)(id,SEL,uint64_t))d.original)(r,d.selector,a):0; RYGRememberObserved(d,@(n)); BOOL h=NO; id v=RYGRuntimeForced(d,&h); return h?[v unsignedCharValue]:n; });
        }
    }
    return NULL;
}

static BOOL RYGRuntimeSpecMatchesCurrentImage(NSDictionary *spec) {
    NSString *storedUUID = [spec[kRYGValueImageUUIDKey] isKindOfClass:NSString.class] ? spec[kRYGValueImageUUIDKey] : nil;
    NSString *className = spec[kRYGValueClassKey];
    if (!storedUUID.length) return NO; // v1 specs are kept, but never auto-hooked across an unknown build.
    NSString *current = RYGRuntimeValueImageUUIDForClassName(className);
    return current.length && [current caseInsensitiveCompare:storedUUID] == NSOrderedSame;
}

BOOL RYGRuntimeValueInstallHook(NSString *className, NSString *selectorName, BOOL classMethod,
                                NSString *typeCode) {
    NSString *uid = RYGRuntimeValueUID(className, selectorName, classMethod);
    if (!uid.length) return NO;
    RYGRuntimeValueEnsureStorage();
    @synchronized (gRYGRuntimeValueLock) { if (gRYGRuntimeValueHooks[uid]) return YES; }

    Class target = Nil;
    Method method = RYGMethodForIdentity(className, selectorName, classMethod, &target);
    NSString *liveType = nil;
    RYGRuntimeValueArgumentKind argKind = RYGRuntimeValueArgumentUnsupported;
    if (!method || !target || !RYGRuntimeValueClassifyMethod(method, &liveType, &argKind)) return NO;
    NSString *requested = RYGRuntimeValueNormalizedType(typeCode);
    if (![requested isEqualToString:liveType]) return NO;

    NSDictionary *persisted = RYGRuntimeValueSpec(className, selectorName, classMethod);
    if (persisted && !RYGRuntimeSpecMatchesCurrentImage(persisted)) return NO;

    char rawReturn[64] = {0};
    method_getReturnType(method, rawReturn, sizeof(rawReturn));
    char returnCode = RYGSkipQualifiers(rawReturn)[0];
    RYGRuntimeValueHookDescriptor *d = [RYGRuntimeValueHookDescriptor new];
    d.uid = uid;
    d.selector = NSSelectorFromString(selectorName);
    d.returnCode = returnCode;
    d.argumentKind = argKind;
    IMP replacement = argKind == RYGRuntimeValueArgumentNone ? RYGRuntimeZeroArgReplacement(d) : RYGRuntimeOneArgBoolReplacement(d);
    if (!replacement) return NO;

    IMP original = NULL;
    MSHookMessageEx(target, d.selector, replacement, &original);
    if (!original || original == replacement) return NO;
    d.original = original;
    @synchronized (gRYGRuntimeValueLock) { gRYGRuntimeValueHooks[uid] = d; }
    return YES;
}

BOOL RYGRuntimeValueHookIsInstalled(NSString *className, NSString *selectorName, BOOL classMethod) {
    NSString *uid = RYGRuntimeValueUID(className, selectorName, classMethod);
    RYGRuntimeValueEnsureStorage();
    @synchronized (gRYGRuntimeValueLock) { return gRYGRuntimeValueHooks[uid] != nil; }
}

NSUInteger RYGRuntimeValueReinstallPersistedHooks(void) {
    NSUInteger installed = 0;
    for (NSDictionary *spec in RYGRuntimeValueAllOverrideSpecs()) {
        if (!RYGRuntimeSpecMatchesCurrentImage(spec)) continue;
        NSString *className = spec[kRYGValueClassKey];
        NSString *selector = spec[kRYGValueSelectorKey];
        NSString *type = spec[kRYGValueTypeKey];
        BOOL meta = [spec[kRYGValueMetaKey] boolValue];
        if (RYGRuntimeValueInstallHook(className, selector, meta, type)) installed++;
    }
    return installed;
}

NSString *RYGRuntimeValueRead(NSString *className, NSString *selectorName, BOOL classMethod,
                              id instance, id *rawValue) {
    if (rawValue) *rawValue = nil;
    Class target = Nil;
    Method method = RYGMethodForIdentity(className, selectorName, classMethod, &target);
    NSString *type = nil;
    RYGRuntimeValueArgumentKind argKind = RYGRuntimeValueArgumentUnsupported;
    if (!method || !RYGRuntimeValueClassifyMethod(method, &type, &argKind)) return @"unsupported ABI";

    if (argKind != RYGRuntimeValueArgumentNone) {
        // Never invent an argument. Arm a pass-through observer and wait for the
        // real Instagram call; if an override exists the same hook forces it.
        (void)RYGRuntimeValueInstallHook(className, selectorName, classMethod, type);
        id observed = RYGRuntimeValueObservedValue(className, selectorName, classMethod);
        if (rawValue) *rawValue = observed;
        return observed ? ([observed boolValue] ? @"YES · observed live" : @"NO · observed live")
                        : @"awaiting live invocation · pass-through hook armed";
    }

    Class cls = className.length ? objc_lookUpClass(className.UTF8String) : Nil;
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    id receiver = classMethod ? ([cls respondsToSelector:selector] ? cls : nil)
                              : (instance && [instance isKindOfClass:cls] && [instance respondsToSelector:selector] ? instance : nil);
    if (!receiver) return classMethod ? @"exact receiver unavailable" : @"instance required";
    IMP imp = [receiver methodForSelector:selector];
    if (!imp) return @"method unavailable";
    @try {
        switch ([type characterAtIndex:0]) {
            case 'B': { BOOL v=((BOOL(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return v?@"YES":@"NO"; }
            case 'c': { signed char v=((signed char(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%d",(int)v]; }
            case 'C': { unsigned char v=((unsigned char(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%u",(unsigned)v]; }
            case 's': { short v=((short(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%d",(int)v]; }
            case 'S': { unsigned short v=((unsigned short(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%u",(unsigned)v]; }
            case 'i': { int v=((int(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%d",v]; }
            case 'I': { unsigned int v=((unsigned int(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%u",v]; }
            case 'l': { long v=((long(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%ld",v]; }
            case 'L': { unsigned long v=((unsigned long(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%lu",v]; }
            case 'q': { long long v=((long long(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%lld",v]; }
            case 'Q': { unsigned long long v=((unsigned long long(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%llu",v]; }
            case 'f': { float v=((float(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%.9g",v]; }
            case 'd': { double v=((double(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%.17g",v]; }
            case '@': { id v=((id(*)(id,SEL))imp)(receiver,selector); if(rawValue)*rawValue=v; if(!v)return @"nil"; NSString *d=[v description]?:@""; if(d.length>500)d=[[d substringToIndex:500]stringByAppendingString:@"…"]; return [NSString stringWithFormat:@"%@ · %@",NSStringFromClass([v class]),d]; }
            default: return @"unsupported ABI";
        }
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"exception %@: %@", exception.name ?: @"?", exception.reason ?: @"?"];
    }
}
