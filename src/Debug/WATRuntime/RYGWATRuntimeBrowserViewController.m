#import "RYGWATRuntimeBrowserViewController.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdlib.h>
#include <string.h>

static NSString * const kRYGWATOverridesKey = @"RYGWATRuntimeValueOverrides.v1";
static const void *kRYGWATSwitchEntryKey = &kRYGWATSwitchEntryKey;

#pragma mark - Runtime model

@interface RYGWATEntry : NSObject
@property(nonatomic, copy) NSString *imagePath;
@property(nonatomic, copy) NSString *imageName;
@property(nonatomic, copy) NSString *className;
@property(nonatomic, copy) NSString *selectorName;
@property(nonatomic, copy) NSString *typeCode;
@property(nonatomic, copy) NSString *typeName;
@property(nonatomic, copy) NSString *family;
@property(nonatomic, assign) BOOL classMethod;
@end
@implementation RYGWATEntry
@end

@interface RYGWATImage : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) NSUInteger classCount;
@property(nonatomic, assign) NSUInteger entryCount;
@end
@implementation RYGWATImage
@end

@interface RYGWATHookDescriptor : NSObject
@property(nonatomic, copy) NSString *uid;
@property(nonatomic, assign) SEL selector;
@property(nonatomic, assign) IMP original;
@property(nonatomic, assign) char typeCode;
@end
@implementation RYGWATHookDescriptor
@end

static NSMutableDictionary<NSString *, NSDictionary *> *gRYGWATOverrides;
static NSMutableDictionary<NSString *, RYGWATHookDescriptor *> *gRYGWATHooks;
static NSObject *gRYGWATLock;
static dispatch_once_t gRYGWATOnce;

#pragma mark - Type / persistence helpers

static NSString *RYGWATNormalizedType(NSString *typeCode) {
    if (!typeCode.length) return @"";
    const char *cursor = typeCode.UTF8String;
    while (*cursor && strchr("rnNoORV", *cursor)) cursor++;
    return *cursor ? [NSString stringWithFormat:@"%c", *cursor] : @"";
}

static NSString *RYGWATTypeName(NSString *typeCode) {
    NSString *type = RYGWATNormalizedType(typeCode);
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

static BOOL RYGWATTypeSupported(NSString *typeCode) { return RYGWATTypeName(typeCode) != nil; }
static BOOL RYGWATTypeBoolean(NSString *typeCode) {
    NSString *type = RYGWATNormalizedType(typeCode);
    return [type isEqualToString:@"B"] || [type isEqualToString:@"c"];
}
static BOOL RYGWATTypeSigned(NSString *typeCode) {
    NSString *type = RYGWATNormalizedType(typeCode);
    return [@[@"s", @"i", @"l", @"q"] containsObject:type];
}
static BOOL RYGWATTypeUnsigned(NSString *typeCode) {
    NSString *type = RYGWATNormalizedType(typeCode);
    return [@[@"C", @"S", @"I", @"L", @"Q"] containsObject:type];
}
static BOOL RYGWATTypeFloat(NSString *typeCode) {
    NSString *type = RYGWATNormalizedType(typeCode);
    return [type isEqualToString:@"f"] || [type isEqualToString:@"d"];
}
static BOOL RYGWATTypeObject(NSString *typeCode) { return [RYGWATNormalizedType(typeCode) isEqualToString:@"@"]; }

static BOOL RYGWATSelectorSafe(NSString *selectorName) {
    if (!selectorName.length || [selectorName containsString:@":"]) return NO;
    static NSSet<NSString *> *blocked;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        blocked = [NSSet setWithArray:@[
            @"alloc", @"init", @"new", @"dealloc", @"finalize", @"copy", @"mutableCopy",
            @"retain", @"release", @"autorelease", @"retainCount", @"zone", @"class",
            @"superclass", @"self", @"hash", @"description", @"debugDescription", @"isProxy"
        ]];
    });
    return ![blocked containsObject:selectorName];
}

static NSString *RYGWATUID(NSString *className, NSString *selectorName, BOOL classMethod) {
    if (!className.length || !selectorName.length) return @"";
    return [NSString stringWithFormat:@"%@|%@|%@", className, classMethod ? @"class" : @"instance", selectorName];
}

static id RYGWATEncodeObject(id value) {
    if (!value || value == NSNull.null) return @{ @"kind": @"nil" };
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return @{ @"kind": @"url", @"value": [(NSURL *)value absoluteString] ?: @"" };
    if ([value isKindOfClass:NSData.class]) return @{ @"kind": @"data", @"value": [(NSData *)value base64EncodedStringWithOptions:0] ?: @"" };
    if ([value isKindOfClass:NSDate.class]) return @{ @"kind": @"date", @"value": @([(NSDate *)value timeIntervalSince1970]) };
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in (NSArray *)value) [out addObject:RYGWATEncodeObject(item) ?: NSNull.null];
        return out;
    }
    if ([value isKindOfClass:NSSet.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in [(NSSet *)value allObjects]) [out addObject:RYGWATEncodeObject(item) ?: NSNull.null];
        return @{ @"kind": @"set", @"value": out };
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
            (void)stop;
            NSString *stringKey = [key isKindOfClass:NSString.class] ? key : [key description];
            if (stringKey.length) out[stringKey] = RYGWATEncodeObject(object) ?: NSNull.null;
        }];
        return out;
    }
    return nil;
}

static id RYGWATDecodeObject(id value) {
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in (NSArray *)value) [out addObject:RYGWATDecodeObject(item) ?: NSNull.null];
        return out;
    }
    if (![value isKindOfClass:NSDictionary.class]) return value == NSNull.null ? nil : value;
    NSString *kind = value[@"kind"];
    id payload = value[@"value"];
    if ([kind isEqualToString:@"nil"]) return nil;
    if ([kind isEqualToString:@"url"]) return [NSURL URLWithString:[payload description] ?: @""];
    if ([kind isEqualToString:@"data"]) return [[NSData alloc] initWithBase64EncodedString:[payload description] ?: @"" options:0];
    if ([kind isEqualToString:@"date"]) return [NSDate dateWithTimeIntervalSince1970:[payload doubleValue]];
    if ([kind isEqualToString:@"set"]) {
        id decoded = RYGWATDecodeObject(payload);
        return [decoded isKindOfClass:NSArray.class] ? [NSSet setWithArray:decoded] : [NSSet set];
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        (void)stop;
        id decoded = RYGWATDecodeObject(object);
        out[key] = decoded ?: NSNull.null;
    }];
    return out;
}

static void RYGWATEnsureStore(void) {
    dispatch_once(&gRYGWATOnce, ^{
        gRYGWATLock = [NSObject new];
        gRYGWATHooks = [NSMutableDictionary dictionary];
        NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGWATOverridesKey];
        gRYGWATOverrides = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    });
}

static NSDictionary *RYGWATSpec(NSString *className, NSString *selectorName, BOOL classMethod) {
    RYGWATEnsureStore();
    NSString *uid = RYGWATUID(className, selectorName, classMethod);
    @synchronized (gRYGWATLock) { return uid.length ? gRYGWATOverrides[uid] : nil; }
}

static BOOL RYGWATHasOverride(RYGWATEntry *entry) {
    return RYGWATSpec(entry.className, entry.selectorName, entry.classMethod) != nil;
}

static id RYGWATOverrideValue(RYGWATEntry *entry) {
    NSDictionary *spec = RYGWATSpec(entry.className, entry.selectorName, entry.classMethod);
    if (!spec) return nil;
    NSString *type = spec[@"type"];
    id payload = spec[@"value"];
    return [type isEqualToString:@"@"] ? RYGWATDecodeObject(payload) : payload;
}

static void RYGWATPersistLocked(void) {
    [NSUserDefaults.standardUserDefaults setObject:gRYGWATOverrides forKey:kRYGWATOverridesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

static void RYGWATSetOverride(RYGWATEntry *entry, id value) {
    NSString *uid = RYGWATUID(entry.className, entry.selectorName, entry.classMethod);
    NSString *type = RYGWATNormalizedType(entry.typeCode);
    if (!uid.length || !type.length) return;
    id payload = value;
    if ([type isEqualToString:@"@"]) {
        payload = RYGWATEncodeObject(value);
        if (!payload) return;
    } else if (![value isKindOfClass:NSNumber.class]) {
        return;
    }
    NSDictionary *spec = @{ @"class": entry.className, @"selector": entry.selectorName,
                             @"meta": @(entry.classMethod), @"type": type,
                             @"value": payload ?: @{ @"kind": @"nil" } };
    RYGWATEnsureStore();
    @synchronized (gRYGWATLock) { gRYGWATOverrides[uid] = spec; RYGWATPersistLocked(); }
}

static void RYGWATClearOverride(RYGWATEntry *entry) {
    NSString *uid = RYGWATUID(entry.className, entry.selectorName, entry.classMethod);
    RYGWATEnsureStore();
    @synchronized (gRYGWATLock) { [gRYGWATOverrides removeObjectForKey:uid]; RYGWATPersistLocked(); }
}

#pragma mark - Exact typed hook engine

static id RYGWATForcedValue(RYGWATHookDescriptor *descriptor, BOOL *hasOverride) {
    if (hasOverride) *hasOverride = NO;
    RYGWATEnsureStore();
    @synchronized (gRYGWATLock) {
        NSDictionary *spec = gRYGWATOverrides[descriptor.uid];
        if (!spec) return nil;
        if (hasOverride) *hasOverride = YES;
        return [spec[@"type"] isEqualToString:@"@"] ? RYGWATDecodeObject(spec[@"value"]) : spec[@"value"];
    }
}

static IMP RYGWATReplacement(RYGWATHookDescriptor *d) {
    switch (d.typeCode) {
        case 'B': return imp_implementationWithBlock(^BOOL(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v boolValue]:(d.original?((BOOL(*)(id,SEL))d.original)(r,d.selector):NO); });
        case 'c': return imp_implementationWithBlock(^signed char(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?(signed char)[v charValue]:(d.original?((signed char(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'C': return imp_implementationWithBlock(^unsigned char(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?(unsigned char)[v unsignedCharValue]:(d.original?((unsigned char(*)(id,SEL))d.original)(r,d.selector):0); });
        case 's': return imp_implementationWithBlock(^short(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?(short)[v shortValue]:(d.original?((short(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'S': return imp_implementationWithBlock(^unsigned short(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?(unsigned short)[v unsignedShortValue]:(d.original?((unsigned short(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'i': return imp_implementationWithBlock(^int(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v intValue]:(d.original?((int(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'I': return imp_implementationWithBlock(^unsigned int(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v unsignedIntValue]:(d.original?((unsigned int(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'l': return imp_implementationWithBlock(^long(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v longValue]:(d.original?((long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'L': return imp_implementationWithBlock(^unsigned long(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v unsignedLongValue]:(d.original?((unsigned long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'q': return imp_implementationWithBlock(^long long(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v longLongValue]:(d.original?((long long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'Q': return imp_implementationWithBlock(^unsigned long long(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v unsignedLongLongValue]:(d.original?((unsigned long long(*)(id,SEL))d.original)(r,d.selector):0); });
        case 'f': return imp_implementationWithBlock(^float(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v floatValue]:(d.original?((float(*)(id,SEL))d.original)(r,d.selector):0.0f); });
        case 'd': return imp_implementationWithBlock(^double(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?[v doubleValue]:(d.original?((double(*)(id,SEL))d.original)(r,d.selector):0.0); });
        case '@': return imp_implementationWithBlock(^id(id r){ BOOL h=NO; id v=RYGWATForcedValue(d,&h); return h?v:(d.original?((id(*)(id,SEL))d.original)(r,d.selector):nil); });
        default: return NULL;
    }
}

static BOOL RYGWATInstallHook(RYGWATEntry *entry) {
    if (!entry || !RYGWATSelectorSafe(entry.selectorName) || !RYGWATTypeSupported(entry.typeCode)) return NO;
    NSString *uid = RYGWATUID(entry.className, entry.selectorName, entry.classMethod);
    RYGWATEnsureStore();
    @synchronized (gRYGWATLock) { if (gRYGWATHooks[uid]) return YES; }
    Class cls = NSClassFromString(entry.className) ?: objc_getClass(entry.className.UTF8String);
    if (!cls) return NO;
    SEL sel = NSSelectorFromString(entry.selectorName);
    Method method = entry.classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char actual[64] = {0}; method_getReturnType(method, actual, sizeof(actual));
    NSString *actualType = RYGWATNormalizedType([NSString stringWithUTF8String:actual]);
    NSString *wantedType = RYGWATNormalizedType(entry.typeCode);
    if (![actualType isEqualToString:wantedType]) return NO;
    RYGWATHookDescriptor *descriptor = [RYGWATHookDescriptor new];
    descriptor.uid = uid; descriptor.selector = sel; descriptor.typeCode = (char)[wantedType characterAtIndex:0];
    IMP replacement = RYGWATReplacement(descriptor); if (!replacement) return NO;
    IMP original = NULL;
    MSHookMessageEx(entry.classMethod ? object_getClass(cls) : cls, sel, replacement, &original);
    if (!original || original == replacement) return NO;
    descriptor.original = original;
    @synchronized (gRYGWATLock) { gRYGWATHooks[uid] = descriptor; }
    return YES;
}

static BOOL RYGWATHookInstalled(RYGWATEntry *entry) {
    RYGWATEnsureStore();
    NSString *uid = RYGWATUID(entry.className, entry.selectorName, entry.classMethod);
    @synchronized (gRYGWATLock) { return gRYGWATHooks[uid] != nil; }
}

#pragma mark - Live scanner

static BOOL RYGWATPathOwnedByApp(NSString *path) {
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    return path.length && bundlePath.length && [path hasPrefix:bundlePath];
}

static NSString *RYGWATImageName(NSString *path) {
    if ([path isEqualToString:NSBundle.mainBundle.executablePath]) return @"App Executable";
    for (NSString *part in [path.pathComponents reverseObjectEnumerator]) if ([part hasSuffix:@".framework"]) return part;
    return path.lastPathComponent.length ? path.lastPathComponent : @"Runtime";
}

static NSString *RYGWATFamily(NSString *selectorName, NSString *className) {
    NSString *source = selectorName.length ? selectorName : className;
    if (!source.length) return @"Other";
    NSMutableString *expanded = [NSMutableString string];
    for (NSUInteger i=0; i<source.length; i++) {
        unichar c=[source characterAtIndex:i];
        if (i>0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) [expanded appendString:@" "];
        if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) [expanded appendFormat:@"%C",c]; else [expanded appendString:@" "];
    }
    NSSet *stop = [NSSet setWithArray:@[@"is",@"has",@"can",@"get",@"set",@"the",@"a",@"an",@"for",@"with",@"value",@"enabled",@"enable",@"active",@"available",@"manager",@"provider"]];
    NSMutableArray *parts=[NSMutableArray array];
    for (NSString *part in [expanded.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        if (!part.length || [stop containsObject:part]) continue;
        [parts addObject:part.localizedCapitalizedString];
        if (parts.count==3) break;
    }
    return parts.count ? [parts componentsJoinedByString:@" "] : @"Other";
}

static BOOL RYGWATSupportedMethod(Method method, NSString **selectorOut, NSString **typeOut) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    NSString *selectorName = NSStringFromSelector(method_getName(method));
    if (!RYGWATSelectorSafe(selectorName)) return NO;
    char rawType[64] = {0}; method_getReturnType(method, rawType, sizeof(rawType));
    NSString *type = RYGWATNormalizedType([NSString stringWithUTF8String:rawType]);
    if (!RYGWATTypeSupported(type)) return NO;
    if (selectorOut) *selectorOut = selectorName;
    if (typeOut) *typeOut = type;
    return YES;
}

static NSArray<RYGWATImage *> *RYGWATScanImages(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @[];
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    if (!classes) return @[];
    count = objc_getClassList(classes, count);
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups=[NSMutableDictionary dictionary];
    for (int i=0; i<count; i++) {
        Class cls=classes[i]; if (!cls) continue;
        const char *rawPath=class_getImageName(cls); NSString *path=rawPath?[NSString stringWithUTF8String:rawPath]:@"";
        if (!RYGWATPathOwnedByApp(path)) continue;
        NSUInteger supported=0;
        for (NSUInteger meta=0; meta<2; meta++) {
            Class owner=meta?object_getClass(cls):cls; unsigned int methodCount=0; Method *methods=class_copyMethodList(owner,&methodCount);
            for (unsigned int j=0; j<methodCount; j++) if (RYGWATSupportedMethod(methods[j],NULL,NULL)) supported++;
            if (methods) free(methods);
        }
        if (!supported) continue;
        NSMutableDictionary *g=groups[path];
        if (!g) { g=[@{@"classes":@0,@"entries":@0} mutableCopy]; groups[path]=g; }
        g[@"classes"]=@([g[@"classes"] unsignedIntegerValue]+1);
        g[@"entries"]=@([g[@"entries"] unsignedIntegerValue]+supported);
    }
    free(classes);
    NSMutableArray *images=[NSMutableArray array];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSString *path, NSDictionary *g, BOOL *stop){
        (void)stop; RYGWATImage *image=[RYGWATImage new]; image.path=path; image.name=RYGWATImageName(path); image.classCount=[g[@"classes"] unsignedIntegerValue]; image.entryCount=[g[@"entries"] unsignedIntegerValue]; [images addObject:image];
    }];
    [images sortUsingComparator:^NSComparisonResult(RYGWATImage *a, RYGWATImage *b){
        BOOL ae=[a.path isEqualToString:NSBundle.mainBundle.executablePath], be=[b.path isEqualToString:NSBundle.mainBundle.executablePath];
        if (ae!=be) return ae?NSOrderedAscending:NSOrderedDescending;
        if (a.entryCount!=b.entryCount) return a.entryCount>b.entryCount?NSOrderedAscending:NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return images;
}

static NSArray<RYGWATEntry *> *RYGWATScanEntries(NSString *imagePath) {
    int count=objc_getClassList(NULL,0); if (count<=0) return @[];
    Class *classes=(__unsafe_unretained Class *)calloc((size_t)count,sizeof(Class)); if (!classes) return @[];
    count=objc_getClassList(classes,count); NSMutableArray *entries=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for (int i=0; i<count; i++) {
        Class cls=classes[i]; if (!cls) continue; const char *rawPath=class_getImageName(cls); NSString *path=rawPath?[NSString stringWithUTF8String:rawPath]:@"";
        if (![path isEqualToString:imagePath]) continue; NSString *className=NSStringFromClass(cls)?:@"Unknown";
        for (NSUInteger meta=0; meta<2; meta++) {
            Class owner=meta?object_getClass(cls):cls; unsigned int methodCount=0; Method *methods=class_copyMethodList(owner,&methodCount);
            for (unsigned int j=0; j<methodCount; j++) {
                NSString *selectorName=nil,*type=nil; if (!RYGWATSupportedMethod(methods[j],&selectorName,&type)) continue;
                NSString *uid=RYGWATUID(className,selectorName,meta==1); if ([seen containsObject:uid]) continue; [seen addObject:uid];
                RYGWATEntry *e=[RYGWATEntry new]; e.imagePath=path; e.imageName=RYGWATImageName(path); e.className=className; e.selectorName=selectorName; e.typeCode=type; e.typeName=RYGWATTypeName(type)?:type; e.family=RYGWATFamily(selectorName,className); e.classMethod=(meta==1); [entries addObject:e];
            }
            if (methods) free(methods);
        }
    }
    free(classes);
    [entries sortUsingComparator:^NSComparisonResult(RYGWATEntry *a, RYGWATEntry *b){
        NSComparisonResult c=[a.family localizedCaseInsensitiveCompare:b.family]; if (c!=NSOrderedSame) return c;
        c=[a.className localizedCaseInsensitiveCompare:b.className]; if (c!=NSOrderedSame) return c;
        return [a.selectorName localizedCaseInsensitiveCompare:b.selectorName];
    }];
    return entries;
}

#pragma mark - Reading

static id RYGWATSharedReceiver(RYGWATEntry *entry) {
    if (entry.classMethod) return NSClassFromString(entry.className);
    Class cls=NSClassFromString(entry.className); SEL target=NSSelectorFromString(entry.selectorName); if (!cls) return nil;
    for (NSString *factoryName in @[@"shared",@"sharedInstance",@"current",@"defaultInstance",@"defaultManager",@"manager",@"provider",@"properties"]) {
        SEL factory=NSSelectorFromString(factoryName); Method method=class_getClassMethod(cls,factory); if (!method || method_getNumberOfArguments(method)!=2) continue;
        char type[32]={0}; method_getReturnType(method,type,sizeof(type)); if (type[0]!='@') continue;
        @try { id value=((id(*)(id,SEL))objc_msgSend)(cls,factory); if (value && [value isKindOfClass:cls] && [value respondsToSelector:target]) return value; } @catch (__unused NSException *exception) {}
    }
    return nil;
}

static NSString *RYGWATRead(RYGWATEntry *entry, id *rawValue) {
    if (rawValue) *rawValue=nil; id receiver=RYGWATSharedReceiver(entry); if (!receiver) return @"receiver unavailable";
    SEL sel=NSSelectorFromString(entry.selectorName); Method method=entry.classMethod?class_getClassMethod((Class)receiver,sel):class_getInstanceMethod([receiver class],sel); if (!method) return @"method unavailable";
    IMP imp=[receiver methodForSelector:sel]; if (!imp) return @"IMP unavailable"; NSString *type=RYGWATNormalizedType(entry.typeCode);
    @try {
        switch ([type characterAtIndex:0]) {
            case 'B': { BOOL v=((BOOL(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return v?@"YES":@"NO"; }
            case 'c': { signed char v=((signed char(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%d",(int)v]; }
            case 'C': { unsigned char v=((unsigned char(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%u",(unsigned)v]; }
            case 's': { short v=((short(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%d",(int)v]; }
            case 'S': { unsigned short v=((unsigned short(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%u",(unsigned)v]; }
            case 'i': { int v=((int(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%d",v]; }
            case 'I': { unsigned int v=((unsigned int(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%u",v]; }
            case 'l': { long v=((long(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%ld",v]; }
            case 'L': { unsigned long v=((unsigned long(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%lu",v]; }
            case 'q': { long long v=((long long(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%lld",v]; }
            case 'Q': { unsigned long long v=((unsigned long long(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%llu",v]; }
            case 'f': { float v=((float(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%.9g",v]; }
            case 'd': { double v=((double(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=@(v); return [NSString stringWithFormat:@"%.17g",v]; }
            case '@': { id v=((id(*)(id,SEL))imp)(receiver,sel); if(rawValue)*rawValue=v; if(!v)return @"nil"; NSString *d=[v description]?:@""; if(d.length>180)d=[[d substringToIndex:180]stringByAppendingString:@"…"]; return [NSString stringWithFormat:@"%@ · %@",NSStringFromClass([v class]),d]; }
            default: return @"unsupported";
        }
    } @catch (NSException *exception) { return [NSString stringWithFormat:@"exception %@",exception.name?:@"?"]; }
}

#pragma mark - Detail browser

typedef NS_ENUM(NSInteger, RYGWATScope) { RYGWATScopeAll=0, RYGWATScopeBoolean, RYGWATScopeNumeric, RYGWATScopeObject, RYGWATScopeOverrides };

@interface RYGWATImageBrowserViewController : UITableViewController <UISearchResultsUpdating, UISearchBarDelegate>
@property(nonatomic, strong) RYGWATImage *image;
@property(nonatomic, strong) NSArray<RYGWATEntry *> *allEntries;
@property(nonatomic, strong) NSArray<RYGWATEntry *> *visibleEntries;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, assign) BOOL scanning;
- (instancetype)initWithImage:(RYGWATImage *)image;
@end

@implementation RYGWATImageBrowserViewController
- (instancetype)initWithImage:(RYGWATImage *)image { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_image=image;_allEntries=@[];_visibleEntries=@[];self.title=image.name;} return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.tableView.estimatedRowHeight=92; self.tableView.rowHeight=UITableViewAutomaticDimension;
    UISearchController *s=[[UISearchController alloc]initWithSearchResultsController:nil]; s.searchResultsUpdater=self; s.obscuresBackgroundDuringPresentation=NO; s.searchBar.delegate=self; s.searchBar.placeholder=@"Search class, selector, family or type"; s.searchBar.scopeButtonTitles=@[@"All",@"BOOL",@"Numbers",@"Objects",@"Overrides"]; self.navigationItem.searchController=s; self.navigationItem.hidesSearchBarWhenScrolling=NO; self.search=s;
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc]initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(applyOverrides)],[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(scanNow)]];
    [self scanNow];
}
- (void)scanNow { if(self.scanning)return; self.scanning=YES; self.title=@"Reading runtime…"; NSString *path=self.image.path; dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ NSArray *entries=RYGWATScanEntries(path); dispatch_async(dispatch_get_main_queue(),^{ self.scanning=NO; self.allEntries=entries?:@[]; [self applyFilter]; }); }); }
- (BOOL)entry:(RYGWATEntry *)e matchesScope:(RYGWATScope)scope { if(scope==RYGWATScopeBoolean)return RYGWATTypeBoolean(e.typeCode); if(scope==RYGWATScopeNumeric)return RYGWATTypeSigned(e.typeCode)||RYGWATTypeUnsigned(e.typeCode)||RYGWATTypeFloat(e.typeCode); if(scope==RYGWATScopeObject)return RYGWATTypeObject(e.typeCode); if(scope==RYGWATScopeOverrides)return RYGWATHasOverride(e); return YES; }
- (void)applyFilter { NSString *q=self.search.searchBar.text.lowercaseString?:@""; RYGWATScope scope=(RYGWATScope)self.search.searchBar.selectedScopeButtonIndex; NSMutableArray *out=[NSMutableArray array]; for(RYGWATEntry *e in self.allEntries){ if(![self entry:e matchesScope:scope])continue; NSString *h=[NSString stringWithFormat:@"%@ %@ %@ %@",e.family,e.className,e.selectorName,e.typeName].lowercaseString; if(!q.length||[h containsString:q])[out addObject:e]; } self.visibleEntries=out; NSUInteger active=0; for(RYGWATEntry *e in out)if(RYGWATHasOverride(e))active++; self.title=[NSString stringWithFormat:@"%@ (%lu)%@",self.image.name,(unsigned long)out.count,active?[NSString stringWithFormat:@" · %lu active",(unsigned long)active]:@""]; [self.tableView reloadData]; }
- (void)updateSearchResultsForSearchController:(__unused UISearchController *)searchController { [self applyFilter]; }
- (void)searchBar:(__unused UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(__unused NSInteger)selectedScope { [self applyFilter]; }
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section { return self.visibleEntries.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"watEntry"]; if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"watEntry"];
    RYGWATEntry *e=self.visibleEntries[indexPath.row]; id raw=nil; NSString *current=RYGWATRead(e,&raw); BOOL overridden=RYGWATHasOverride(e),installed=overridden&&RYGWATHookInstalled(e); id forced=RYGWATOverrideValue(e);
    cell.textLabel.numberOfLines=0; cell.detailTextLabel.numberOfLines=0; cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; cell.textLabel.text=[NSString stringWithFormat:@"%@ %@",e.classMethod?@"+":@"-",e.selectorName]; NSString *state=overridden?(installed?@"INSTALLED":@"PENDING"):@"ORIGINAL"; NSString *forcedText=overridden?[NSString stringWithFormat:@" · FORCE %@",forced?:@"nil"]:@""; cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@\n%@ · %@\nCurrent: %@%@ · %@",e.family,e.imageName,e.className,e.typeName,current,forcedText,state]; cell.detailTextLabel.textColor=overridden?(installed?UIColor.systemCyanColor:UIColor.systemOrangeColor):UIColor.secondaryLabelColor;
    if(RYGWATTypeBoolean(e.typeCode)){ UISwitch *sw=[cell.accessoryView isKindOfClass:UISwitch.class]?(UISwitch *)cell.accessoryView:[UISwitch new]; if(sw!=cell.accessoryView){[sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=sw;} objc_setAssociatedObject(sw,kRYGWATSwitchEntryKey,e,OBJC_ASSOCIATION_RETAIN_NONATOMIC); sw.on=overridden?[forced boolValue]:[raw boolValue]; cell.accessoryType=UITableViewCellAccessoryNone; } else { cell.accessoryView=nil; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; }
    return cell;
}
- (void)toggleChanged:(UISwitch *)sw { RYGWATEntry *e=objc_getAssociatedObject(sw,kRYGWATSwitchEntryKey); if(!e)return; RYGWATSetOverride(e,@(sw.on)); (void)RYGWATInstallHook(e); [self applyFilter]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; [self editEntry:self.visibleEntries[indexPath.row] source:[tableView cellForRowAtIndexPath:indexPath]]; }
- (void)showError:(NSString *)message { UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Invalid value" message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)promptForEntry:(RYGWATEntry *)e title:(NSString *)title initial:(NSString *)initial keyboard:(UIKeyboardType)keyboard parser:(id(^)(NSString *))parser { UIAlertController *a=[UIAlertController alertControllerWithTitle:e.selectorName message:title preferredStyle:UIAlertControllerStyleAlert]; [a addTextFieldWithConfigurationHandler:^(UITextField *f){f.text=initial;f.keyboardType=keyboard;f.autocorrectionType=UITextAutocorrectionTypeNo;}]; __weak typeof(self) w=self; [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ id value=parser(a.textFields.firstObject.text?:@""); if(!value){[w showError:@"The value could not be parsed for this ABI type."];return;} RYGWATSetOverride(e,value); (void)RYGWATInstallHook(e); [w applyFilter]; }]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)editEntry:(RYGWATEntry *)e source:(UIView *)source {
    id raw=nil; NSString *current=RYGWATRead(e,&raw); BOOL overridden=RYGWATHasOverride(e); id forced=RYGWATOverrideValue(e); UIAlertController *sheet=[UIAlertController alertControllerWithTitle:e.selectorName message:[NSString stringWithFormat:@"%@\n%@ method · %@\nCurrent: %@",e.className,e.classMethod?@"class":@"instance",e.typeName,current] preferredStyle:UIAlertControllerStyleActionSheet]; sheet.popoverPresentationController.sourceView=source?:self.view; sheet.popoverPresentationController.sourceRect=source?source.bounds:self.view.bounds; __weak typeof(self) w=self;
    if(RYGWATTypeBoolean(e.typeCode)){ for(NSNumber *n in @[@YES,@NO]) [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Force %@",n.boolValue?@"YES":@"NO"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){RYGWATSetOverride(e,n);(void)RYGWATInstallHook(e);[w applyFilter];}]]; }
    else if(RYGWATTypeSigned(e.typeCode)){ [sheet addAction:[UIAlertAction actionWithTitle:@"Set signed integer…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ [w promptForEntry:e title:@"Decimal signed integer" initial:[(overridden?forced:raw) description] keyboard:UIKeyboardTypeNumbersAndPunctuation parser:^id(NSString *t){ NSScanner *s=[NSScanner scannerWithString:t]; long long v=0; return ([s scanLongLong:&v]&&s.isAtEnd)?@(v):nil; }]; }]]; }
    else if(RYGWATTypeUnsigned(e.typeCode)){ [sheet addAction:[UIAlertAction actionWithTitle:@"Set unsigned integer…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ [w promptForEntry:e title:@"Decimal unsigned integer" initial:[(overridden?forced:raw) description] keyboard:UIKeyboardTypeNumberPad parser:^id(NSString *t){ if(!t.length||[t hasPrefix:@"-"])return nil; char *end=NULL; unsigned long long v=strtoull(t.UTF8String,&end,10); return(end&&*end=='\0')?@(v):nil; }]; }]]; }
    else if(RYGWATTypeFloat(e.typeCode)){ [sheet addAction:[UIAlertAction actionWithTitle:@"Set decimal…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ [w promptForEntry:e title:@"Floating point number" initial:[(overridden?forced:raw) description] keyboard:UIKeyboardTypeDecimalPad parser:^id(NSString *t){ NSScanner *s=[NSScanner scannerWithString:t]; double v=0; return([s scanDouble:&v]&&s.isAtEnd)?@(v):nil; }]; }]]; }
    else if(RYGWATTypeObject(e.typeCode)){ [sheet addAction:[UIAlertAction actionWithTitle:@"Set Foundation object…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ NSString *initial=[(overridden?forced:raw) isKindOfClass:NSString.class]?(overridden?forced:raw):[(overridden?forced:raw) description]; [w promptForEntry:e title:@"String by default. Prefix JSON with json:, number with number:, URL with url:, or type nil." initial:initial keyboard:UIKeyboardTypeDefault parser:^id(NSString *t){ NSString *trim=[t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if([trim.lowercaseString isEqualToString:@"nil"])return NSNull.null; if([trim.lowercaseString hasPrefix:@"number:"])return [NSDecimalNumber decimalNumberWithString:[trim substringFromIndex:7]]; if([trim.lowercaseString hasPrefix:@"url:"])return [NSURL URLWithString:[trim substringFromIndex:4]]; if([trim.lowercaseString hasPrefix:@"json:"]){NSData *d=[[trim substringFromIndex:5] dataUsingEncoding:NSUTF8StringEncoding];return d?[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingFragmentsAllowed error:nil]:nil;} return t; }]; }]]; [sheet addAction:[UIAlertAction actionWithTitle:@"Force nil" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){RYGWATSetOverride(e,NSNull.null);(void)RYGWATInstallHook(e);[w applyFilter];}]]; }
    if(overridden)[sheet addAction:[UIAlertAction actionWithTitle:@"Use original" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){RYGWATClearOverride(e);[w applyFilter];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy name + value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){UIPasteboard.generalPasteboard.string=[NSString stringWithFormat:@"%@ %@ %@ (%@) = %@",e.classMethod?@"+":@"-",e.className,e.selectorName,e.typeName,current];}]]; [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:sheet animated:YES completion:nil];
}
- (void)applyOverrides { NSUInteger active=0,installed=0; for(RYGWATEntry *e in self.allEntries){if(!RYGWATHasOverride(e))continue;active++;if(RYGWATInstallHook(e))installed++;} UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Apply Runtime" message:[NSString stringWithFormat:@"Overrides in this image: %lu\nExact hooks installed: %lu\nPending: %lu",(unsigned long)active,(unsigned long)installed,(unsigned long)(active-installed)] preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; [self applyFilter]; }
@end

#pragma mark - Image catalog root

@interface RYGWATRuntimeBrowserViewController ()
@property(nonatomic, strong) NSArray<RYGWATImage *> *images;
@property(nonatomic, assign) BOOL scanning;
@property(nonatomic, assign) BOOL didScan;
@end

@implementation RYGWATRuntimeBrowserViewController
- (instancetype)init { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_images=@[];self.title=@"Runtime Browser · WAT Port";} return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(scanNow)]; self.tableView.estimatedRowHeight=72; self.tableView.rowHeight=UITableViewAutomaticDimension; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if(!self.didScan)[self scanNow]; }
- (void)scanNow { if(self.scanning)return; self.scanning=YES; self.didScan=YES; self.title=@"Scanning loaded images…"; self.navigationItem.rightBarButtonItem.enabled=NO; dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSArray *images=RYGWATScanImages(); dispatch_async(dispatch_get_main_queue(),^{self.scanning=NO;self.navigationItem.rightBarButtonItem.enabled=YES;self.images=images?:@[];self.title=[NSString stringWithFormat:@"Runtime Browser · WAT Port (%lu)",(unsigned long)self.images.count];[self.tableView reloadData];});}); }
- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView { return 1; }
- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section { return self.images.count; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(__unused NSInteger)section { return @"Loaded app-owned Mach-O images"; }
- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(__unused NSInteger)section { return @"The catalog is rebuilt only when this screen is opened or refreshed. It scans the currently loaded Objective-C runtime and exposes only zero-argument getters with a supported return ABI. Persisted overrides are never installed automatically at cold start."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"watImage"]; if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"watImage"]; RYGWATImage *image=self.images[indexPath.row]; cell.textLabel.text=image.name; cell.detailTextLabel.text=[NSString stringWithFormat:@"%lu classes · %lu typed getters loaded now",(unsigned long)image.classCount,(unsigned long)image.entryCount]; cell.detailTextLabel.numberOfLines=0; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; RYGWATImageBrowserViewController *vc=[[RYGWATImageBrowserViewController alloc]initWithImage:self.images[indexPath.row]]; [self.navigationController pushViewController:vc animated:YES]; }
@end
