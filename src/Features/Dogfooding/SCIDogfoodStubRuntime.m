#import "SCIDogfoodStubRuntime.h"
#import <objc/runtime.h>

static NSArray<NSDictionary *> *sSCIStubCatalog;
static NSTimeInterval sSCIStubCatalogBuiltAt;

static NSString *SCISafeCString(const char *s) { return s ? [NSString stringWithUTF8String:s] ?: @"" : @""; }
static NSString *SCISafeString(id obj) { @try { return obj ? [[obj description] copy] ?: @"" : @""; } @catch (__unused id e) { return @"<exception>"; } }

static BOOL SCIClassNameLooksUseful(NSString *name) {
    NSString *s = name.lowercaseString ?: @"";
    return [s containsString:@"dogfood"] || [s containsString:@"dogfooding"] || [s containsString:@"internal"] ||
           [s containsString:@"settings"] || [s containsString:@"experiment"] || [s containsString:@"launcher"] ||
           [s containsString:@"mobileconfig"] || [s containsString:@"pando"] || [s containsString:@"graphql"] ||
           [s containsString:@"userlauncherset"] || [s containsString:@"autofill"] || [s containsString:@"notes"];
}

static NSArray<NSString *> *SCIMethodNames(Class cls, BOOL meta, NSUInteger limit, NSString *filter) {
    if (!cls) return @[];
    Class target = meta ? object_getClass(cls) : cls;
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSString *q = filter.lowercaseString ?: @"";
    for (Class c = target; c && out.count < limit; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(c, &count);
        for (unsigned int i = 0; methods && i < count && out.count < limit; i++) {
            NSString *n = NSStringFromSelector(method_getName(methods[i]));
            if (!n.length || [seen containsObject:n]) continue;
            if (q.length && ![n.lowercaseString containsString:q]) continue;
            const char *types = method_getTypeEncoding(methods[i]);
            [out addObject:@{ @"name": n, @"types": SCISafeCString(types) }];
            [seen addObject:n];
        }
        if (methods) free(methods);
        if (meta && c == object_getClass(NSObject.class)) break;
    }
    return out.copy;
}

static NSArray<NSDictionary *> *SCIPropertyList(Class cls, NSUInteger limit, NSString *filter) {
    if (!cls) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSString *q = filter.lowercaseString ?: @"";
    for (Class c = cls; c && out.count < limit; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(c, &count);
        for (unsigned int i = 0; props && i < count && out.count < limit; i++) {
            NSString *n = SCISafeCString(property_getName(props[i]));
            if (!n.length || [seen containsObject:n]) continue;
            if (q.length && ![n.lowercaseString containsString:q]) continue;
            [out addObject:@{ @"name": n, @"attrs": SCISafeCString(property_getAttributes(props[i])), @"owner": NSStringFromClass(c) ?: @"" }];
            [seen addObject:n];
        }
        if (props) free(props);
    }
    return out.copy;
}

static NSArray<NSDictionary *> *SCIIvarList(Class cls, NSUInteger limit, NSString *filter) {
    if (!cls) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSString *q = filter.lowercaseString ?: @"";
    for (Class c = cls; c && out.count < limit; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(c, &count);
        for (unsigned int i = 0; ivars && i < count && out.count < limit; i++) {
            NSString *n = SCISafeCString(ivar_getName(ivars[i]));
            if (!n.length || [seen containsObject:n]) continue;
            if (q.length && ![n.lowercaseString containsString:q]) continue;
            [out addObject:@{ @"name": n, @"type": SCISafeCString(ivar_getTypeEncoding(ivars[i])), @"offset": @(ivar_getOffset(ivars[i])), @"owner": NSStringFromClass(c) ?: @"" }];
            [seen addObject:n];
        }
        if (ivars) free(ivars);
    }
    return out.copy;
}

static NSArray<NSString *> *SCIProtocolNames(Class cls, NSUInteger limit) {
    if (!cls) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (Class c = cls; c && out.count < limit; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Protocol *__unsafe_unretained *protocols = class_copyProtocolList(c, &count);
        for (unsigned int i = 0; protocols && i < count && out.count < limit; i++) {
            NSString *n = SCISafeCString(protocol_getName(protocols[i]));
            if (n.length && ![seen containsObject:n]) { [out addObject:n]; [seen addObject:n]; }
        }
        if (protocols) free(protocols);
    }
    return out.copy;
}

static NSArray<NSDictionary *> *SCIBuildCatalog(void) {
    NSMutableArray *out = [NSMutableArray array];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; classes && i < count; i++) {
        Class cls = classes[i];
        NSString *raw = SCISafeCString(class_getName(cls));
        if (!raw.length || !SCIClassNameLooksUseful(raw)) continue;
        [out addObject:@{ @"class": raw, @"display": raw }];
    }
    if (classes) free(classes);
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [[a[@"display"] description] localizedCaseInsensitiveCompare:[b[@"display"] description]];
    }];
    return out.copy;
}

static NSDictionary *SCIStubPreview(NSDictionary *base) {
    NSString *raw = [base[@"class"] description];
    Class cls = NSClassFromString(raw) ?: objc_getClass(raw.UTF8String);
    if (!cls) return base;
    NSArray *inst = SCIMethodNames(cls, NO, 8, nil);
    NSArray *klass = SCIMethodNames(cls, YES, 8, nil);
    NSArray *props = SCIPropertyList(cls, 6, nil);
    NSArray *ivars = SCIIvarList(cls, 6, nil);
    NSMutableDictionary *d = [base mutableCopy];
    d[@"methodCountPreview"] = @(inst.count);
    d[@"classMethodCountPreview"] = @(klass.count);
    d[@"propertyCountPreview"] = @(props.count);
    d[@"ivarCountPreview"] = @(ivars.count);
    d[@"methodsPreview"] = inst;
    d[@"classMethodsPreview"] = klass;
    d[@"propertiesPreview"] = props;
    d[@"ivarsPreview"] = ivars;
    return d.copy;
}

@implementation SCIDogfoodStubRuntime

+ (NSArray<NSDictionary *> *)catalog {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!sSCIStubCatalog || (now - sSCIStubCatalogBuiltAt) > 30.0) {
        sSCIStubCatalog = SCIBuildCatalog();
        sSCIStubCatalogBuiltAt = now;
    }
    return sSCIStubCatalog ?: @[];
}

+ (NSArray<NSDictionary *> *)stubsMatching:(NSString *)query limit:(NSUInteger)limit {
    NSString *q = query.lowercaseString ?: @"";
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in [self catalog]) {
        if (q.length && ![[d description].lowercaseString containsString:q]) continue;
        [out addObject:SCIStubPreview(d)];
        if (limit && out.count >= limit) break;
    }
    return out.copy;
}

+ (NSDictionary *)detailsForClassName:(NSString *)className {
    if (!className.length) return @{};
    Class cls = NSClassFromString(className) ?: objc_getClass(className.UTF8String);
    if (!cls) return @{ @"class": className, @"error": @"class not loaded" };
    NSString *filter = @"";
    return @{
        @"class": className,
        @"superclass": NSStringFromClass(class_getSuperclass(cls)) ?: @"",
        @"methods": SCIMethodNames(cls, NO, 500, filter),
        @"classMethods": SCIMethodNames(cls, YES, 300, filter),
        @"properties": SCIPropertyList(cls, 300, filter),
        @"ivars": SCIIvarList(cls, 300, filter),
        @"protocols": SCIProtocolNames(cls, 100),
        @"note": @"Stub details only. No heap scan, no method invocation, no ivar dereference."
    };
}

+ (void)clearCache { sSCIStubCatalog = nil; sSCIStubCatalogBuiltAt = 0; }

@end
