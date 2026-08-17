#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>
#import <substrate.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static NSString *const kRYGCompatOverridesKey = @"ryg_runtime_bool_overrides";
static NSDictionary<NSString *, NSNumber *> *gRYGCompatOverrideCache;
static NSMutableSet<NSString *> *gRYGCompatInstalledKeys;
static NSMutableDictionary<NSString *, NSNumber *> *gRYGCompatObservedValues;

static const char *RYGCompatSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGCompatArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;
    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *arg = RYGCompatSkipQualifiers(encoded);
    if (!arg || !*arg) return -1;
    if (*arg == '@' || *arg == '#' || *arg == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *arg)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGCompatSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGCompatSkipQualifiers(encoded);
    return ret && (*ret == 'B' || *ret == 'c' || *ret == 'C') && RYGCompatArgumentKind(method) >= 0;
}

static NSDictionary<NSString *, NSNumber *> *RYGCompatOverrides(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kRYGCompatOverridesKey];
    if (![value isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [obj isKindOfClass:NSNumber.class]) clean[key] = @([obj boolValue]);
    }];
    return clean.copy;
}

static void RYGCompatRefreshCache(void) {
    @synchronized(RYGRuntimeBrowserEngine.class) {
        gRYGCompatOverrideCache = RYGCompatOverrides();
    }
}

static NSNumber *RYGCompatOverride(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) {
        return gRYGCompatOverrideCache[key];
    }
}

static void RYGCompatRemember(NSString *key, BOOL native) {
    if (!key.length) return;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGCompatObservedValues) gRYGCompatObservedValues = [NSMutableDictionary dictionary];
        gRYGCompatObservedValues[key] = @(native);
    }
}

static NSNumber *RYGCompatObserved(NSString *key) {
    @synchronized(RYGRuntimeBrowserEngine.class) {
        return gRYGCompatObservedValues[key];
    }
}

static NSString *RYGCompatMethodKey(NSString *className, NSString *selectorName, BOOL classMethod) {
    return [NSString stringWithFormat:@"%@%@#%@", classMethod ? @"+" : @"-", className ?: @"", selectorName ?: @""];
}

static BOOL RYGCompatParseKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
    if (key.length < 4) return NO;
    unichar prefix = [key characterAtIndex:0];
    if (prefix != '+' && prefix != '-') return NO;
    NSString *body = [key substringFromIndex:1];
    NSRange separator = [body rangeOfString:@"#"];
    if (separator.location == NSNotFound || separator.location == 0 || NSMaxRange(separator) >= body.length) return NO;
    if (className) *className = [body substringToIndex:separator.location];
    if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(separator)];
    if (classMethod) *classMethod = prefix == '+';
    return YES;
}

static Method RYGCompatDeclaredMethod(Class owner, SEL selector) {
    for (Class cursor = owner; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int index = 0; index < count; index++) {
            if (method_getName(methods[index]) == selector) { found = methods[index]; break; }
        }
        if (methods) free(methods);
        if (found) return found;
    }
    return NULL;
}

static BOOL RYGCompatInstallKey(NSString *key) {
    if (!key.length) return NO;
    @synchronized(RYGRuntimeBrowserEngine.class) {
        if (!gRYGCompatInstalledKeys) gRYGCompatInstalledKeys = [NSMutableSet set];
        if ([gRYGCompatInstalledKeys containsObject:key]) return YES;
    }

    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGCompatParseKey(key, &className, &selectorName, &classMethod)) return NO;
    if ([RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]) return NO;

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = sel_registerName(selectorName.UTF8String);
    Class owner = classMethod ? object_getClass(cls) : cls;
    Method method = owner ? RYGCompatDeclaredMethod(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGCompatSupportedBool(method)) return NO;

    RYGRuntimeArgumentKind kind = RYGCompatArgumentKind(method);
    NSString *capturedKey = key.copy;
    SEL capturedSelector = selector;
    IMP *original = calloc(1, sizeof(IMP));
    if (!original) return NO;

    IMP replacement = NULL;
    if (kind == RYGRuntimeArgumentNone) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
            RYGCompatRemember(capturedKey, native);
            NSNumber *forced = RYGCompatOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
            RYGCompatRemember(capturedKey, native);
            NSNumber *forced = RYGCompatOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    } else if (kind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
            RYGCompatRemember(capturedKey, native);
            NSNumber *forced = RYGCompatOverride(capturedKey);
            return forced ? forced.boolValue : native;
        });
    }
    if (!replacement) { free(original); return NO; }

    @synchronized(RYGRuntimeBrowserEngine.class) {
        if ([gRYGCompatInstalledKeys containsObject:key]) {
            imp_removeBlock(replacement);
            free(original);
            return YES;
        }
        [gRYGCompatInstalledKeys addObject:key];
    }
    MSHookMessageEx(owner, selector, replacement, original);
    if (!*original) {
        @synchronized(RYGRuntimeBrowserEngine.class) { [gRYGCompatInstalledKeys removeObject:key]; }
        imp_removeBlock(replacement);
        free(original);
        return NO;
    }
    return YES;
}

static BOOL RYGCompatRelevant(NSString *className, NSString *selectorName, RYGRuntimeBrowserScope scope) {
    if (scope == RYGRuntimeBrowserScopeAll) return YES;
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@", className ?: @"", selectorName ?: @""] lowercaseString];
    for (NSString *needle in @[@"employee", @"dogfood", @"internal", @"launcher", @"staff", @"metamate"]) {
        if ([haystack containsString:needle]) return YES;
    }
    if (scope == RYGRuntimeBrowserScopeEmployee) return NO;
    for (NSString *needle in @[@"experiment", @"feature", @"gate", @"gating", @"enable", @"available", @"allow", @"support", @"test", @"debug", @"rollout", @"treatment", @"variant", @"config", @"prism", @"glass", @"wordmark"]) {
        if ([haystack containsString:needle]) return YES;
    }
    return NO;
}

@implementation RYGRuntimeBrowserEngine (RYGABICompatibility)

+ (NSArray<RYGRuntimeBoolMethod *> *)ryg_abi_boolMethodsForImagePath:(NSString *)imagePath scope:(RYGRuntimeBrowserScope)scope {
    NSString *wanted = imagePath.stringByStandardizingPath;
    if (!wanted.length) return @[];
    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(wanted.fileSystemRepresentation, &classCount);
    if (!classNames) return @[];
    NSMutableArray *rows = [NSMutableArray array];

    for (unsigned int classIndex = 0; classIndex < classCount; classIndex++) {
        const char *rawName = classNames[classIndex];
        if (!rawName || !*rawName) continue;
        Class cls = objc_lookUpClass(rawName);
        if (!cls) continue;
        NSString *className = [NSString stringWithUTF8String:rawName];
        if (!className.length) continue;

        for (NSInteger pass = 0; pass < 2; pass++) {
            BOOL classMethod = pass == 1;
            Class owner = classMethod ? object_getClass(cls) : cls;
            unsigned int methodCount = 0;
            Method *methods = owner ? class_copyMethodList(owner, &methodCount) : NULL;
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                Method method = methods[methodIndex];
                if (!RYGCompatSupportedBool(method)) continue;
                SEL selector = method_getName(method);
                NSString *selectorName = selector ? NSStringFromSelector(selector) : nil;
                if (!selectorName.length || [selectorName hasPrefix:@"set"] || [selectorName hasPrefix:@"init"] ||
                    [self isStructuralNoiseSelectorName:selectorName] || !RYGCompatRelevant(className, selectorName, scope)) continue;

                RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
                row.imagePath = wanted;
                row.className = className;
                row.selectorName = selectorName;
                row.classMethod = classMethod;
                row.argumentKind = RYGCompatArgumentKind(method);
                row.typeEncoding = [NSString stringWithUTF8String:method_getTypeEncoding(method) ?: ""];
                [rows addObject:row];
            }
            if (methods) free(methods);
        }
    }
    free(classNames);
    [rows sortUsingComparator:^NSComparisonResult(RYGRuntimeBoolMethod *a, RYGRuntimeBoolMethod *b) {
        NSComparisonResult classOrder = [a.className localizedCaseInsensitiveCompare:b.className];
        return classOrder == NSOrderedSame ? [a.selectorName localizedCaseInsensitiveCompare:b.selectorName] : classOrder;
    }];
    return rows.copy;
}

+ (NSNumber *)ryg_abi_overrideForKey:(NSString *)overrideKey {
    return RYGCompatOverride(overrideKey);
}

+ (void)ryg_abi_setOverride:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method {
    if (!method.overrideKey.length) return;
    NSMutableDictionary *overrides = [RYGCompatOverrides() mutableCopy];
    if (value) overrides[method.overrideKey] = @([value boolValue]);
    else [overrides removeObjectForKey:method.overrideKey];
    [NSUserDefaults.standardUserDefaults setObject:overrides.copy forKey:kRYGCompatOverridesKey];
    RYGCompatRefreshCache();
    if (value) RYGCompatInstallKey(method.overrideKey);
}

+ (void)ryg_abi_reinstallPersistedOverrides {
    RYGCompatRefreshCache();
    for (NSString *key in gRYGCompatOverrideCache) RYGCompatInstallKey(key);
}

@end

@implementation RYGRuntimeBoolMethod (RYGABICompatibility)
- (NSNumber *)ryg_abi_liveValue {
    NSNumber *compat = RYGCompatObserved(self.overrideKey);
    return compat ?: [self ryg_abi_liveValue];
}
@end

static void RYGSwapClassMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Class meta = object_getClass(cls);
    Method original = class_getInstanceMethod(meta, originalSelector);
    Method replacement = class_getInstanceMethod(meta, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

__attribute__((constructor(110))) static void RYGInstallRuntimeABICompatibility(void) {
    @autoreleasepool {
        RYGCompatRefreshCache();
        RYGSwapClassMethod(RYGRuntimeBrowserEngine.class,
                           @selector(boolMethodsForImagePath:scope:),
                           @selector(ryg_abi_boolMethodsForImagePath:scope:));
        RYGSwapClassMethod(RYGRuntimeBrowserEngine.class,
                           @selector(overrideForKey:),
                           @selector(ryg_abi_overrideForKey:));
        RYGSwapClassMethod(RYGRuntimeBrowserEngine.class,
                           @selector(setOverride:forMethod:),
                           @selector(ryg_abi_setOverride:forMethod:));
        RYGSwapClassMethod(RYGRuntimeBrowserEngine.class,
                           @selector(reinstallPersistedOverrides),
                           @selector(ryg_abi_reinstallPersistedOverrides));

        Method originalLive = class_getInstanceMethod(RYGRuntimeBoolMethod.class, @selector(liveValue));
        Method replacementLive = class_getInstanceMethod(RYGRuntimeBoolMethod.class, @selector(ryg_abi_liveValue));
        if (originalLive && replacementLive) method_exchangeImplementations(originalLive, replacementLive);
    }
}
