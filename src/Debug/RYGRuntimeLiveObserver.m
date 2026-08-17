#import "RYGRuntimeLiveObserver.h"
#import "RYGRuntimeBrowserEngine.h"
#import <objc/runtime.h>
#import <substrate.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

NSString *const RYGRuntimeNativeValueDidChangeNotification = @"RYGRuntimeNativeValueDidChangeNotification";
NSString *const RYGRuntimeNativeValueKeyUserInfoKey = @"overrideKey";

static NSMutableDictionary<NSString *, NSNumber *> *gRYGLiveNativeValues;
static NSMutableSet<NSString *> *gRYGLiveInstalledKeys;
static NSLock *gRYGLiveLock;

static void RYGLiveEnsureStorage(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gRYGLiveNativeValues = [NSMutableDictionary dictionary];
        gRYGLiveInstalledKeys = [NSMutableSet set];
        gRYGLiveLock = [NSLock new];
    });
}

NSNumber *RYGRuntimeObservedNativeValue(NSString *overrideKey) {
    if (!overrideKey.length) return nil;
    RYGLiveEnsureStorage();
    [gRYGLiveLock lock];
    NSNumber *value = gRYGLiveNativeValues[overrideKey];
    [gRYGLiveLock unlock];
    return value;
}

static void RYGLiveRecord(NSString *key, BOOL native) {
    if (!key.length) return;
    RYGLiveEnsureStorage();
    NSNumber *next = @(native);
    BOOL changed = NO;
    [gRYGLiveLock lock];
    NSNumber *old = gRYGLiveNativeValues[key];
    if (!old || old.boolValue != native) {
        gRYGLiveNativeValues[key] = next;
        changed = YES;
    }
    [gRYGLiveLock unlock];
    if (!changed) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeNativeValueDidChangeNotification
                                                          object:nil
                                                        userInfo:@{RYGRuntimeNativeValueKeyUserInfoKey:key}];
    });
}

static Class RYGLiveResolveClass(NSString *className) {
    if (!className.length) return Nil;
    Class cls = NSClassFromString(className);
    if (!cls) cls = objc_lookUpClass(className.UTF8String);
    return cls;
}

// Do not ask the Objective-C runtime to resolve missing methods. Pando and
// GraphQL classes use custom resolution paths; walking declared lists avoids
// invoking them while the developer browser is merely inspecting metadata.
static Method RYGLiveDeclaredMethodInHierarchy(Class owner, SEL selector) {
    for (Class cursor = owner; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(methods[i]) == selector) {
                found = methods[i];
                break;
            }
        }
        if (methods) free(methods);
        if (found) return found;
    }
    return NULL;
}

static const char *RYGLiveSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGLiveMethodMatchesRow(Method method, RYGRuntimeBoolMethod *row) {
    if (!method || !row) return NO;
    char encoded[32] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGLiveSkipQualifiers(encoded);
    if (!ret || *ret != 'B') return NO;

    unsigned int args = method_getNumberOfArguments(method);
    if (row.argumentKind == RYGRuntimeArgumentNone) return args == 2;
    if (args != 3) return NO;

    memset(encoded, 0, sizeof(encoded));
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *arg = RYGLiveSkipQualifiers(encoded);
    if (!arg || !*arg) return NO;
    if (row.argumentKind == RYGRuntimeArgumentObject) return *arg == '@' || *arg == '#' || *arg == ':';
    return strchr("BcCsSiIlLqQ^*", *arg) != NULL;
}

static void RYGLiveObserveMethod(RYGRuntimeBoolMethod *row) {
    if (!row.overrideKey.length || !row.className.length || !row.selectorName.length) return;
    if ([RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:row.selectorName]) return;
    RYGLiveEnsureStorage();

    [gRYGLiveLock lock];
    BOOL installed = [gRYGLiveInstalledKeys containsObject:row.overrideKey];
    if (!installed) [gRYGLiveInstalledKeys addObject:row.overrideKey];
    [gRYGLiveLock unlock];
    if (installed) return;

    Class cls = RYGLiveResolveClass(row.className);
    SEL selector = NSSelectorFromString(row.selectorName);
    Class owner = row.classMethod ? object_getClass(cls) : cls;
    Method method = owner ? RYGLiveDeclaredMethodInHierarchy(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGLiveMethodMatchesRow(method, row)) {
        [gRYGLiveLock lock];
        [gRYGLiveInstalledKeys removeObject:row.overrideKey];
        [gRYGLiveLock unlock];
        return;
    }

    NSString *key = row.overrideKey.copy;
    SEL capturedSelector = selector;
    IMP *original = calloc(1, sizeof(IMP));
    if (!original) {
        [gRYGLiveLock lock];
        [gRYGLiveInstalledKeys removeObject:key];
        [gRYGLiveLock unlock];
        return;
    }

    IMP replacement = NULL;
    if (row.argumentKind == RYGRuntimeArgumentNone) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver) {
            BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
            RYGLiveRecord(key, native);
            return native;
        });
    } else if (row.argumentKind == RYGRuntimeArgumentObject) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
            RYGLiveRecord(key, native);
            return native;
        });
    } else if (row.argumentKind == RYGRuntimeArgumentInteger) {
        replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
            BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
            RYGLiveRecord(key, native);
            return native;
        });
    }

    if (!replacement) {
        free(original);
        [gRYGLiveLock lock];
        [gRYGLiveInstalledKeys removeObject:key];
        [gRYGLiveLock unlock];
        return;
    }

    MSHookMessageEx(owner, selector, replacement, original);
    if (!*original) {
        imp_removeBlock(replacement);
        free(original);
        [gRYGLiveLock lock];
        [gRYGLiveInstalledKeys removeObject:key];
        [gRYGLiveLock unlock];
    }
}

void RYGRuntimeBeginLiveObservation(NSArray<RYGRuntimeBoolMethod *> *methods) {
    if (!methods.count) return;
    NSArray<RYGRuntimeBoolMethod *> *rows = [methods copy];
    void (^install)(void) = ^{
        // Observation is intentionally explicit. Never fan out an automatic
        // hook across an entire executable just because a screen was opened.
        // The UI currently calls this with one selected row at a time.
        NSUInteger limit = MIN(rows.count, (NSUInteger)64);
        for (NSUInteger i = 0; i < limit; i++) {
            id candidate = rows[i];
            if ([candidate isKindOfClass:RYGRuntimeBoolMethod.class]) {
                RYGLiveObserveMethod((RYGRuntimeBoolMethod *)candidate);
            }
        }
    };
    if (NSThread.isMainThread) install();
    else dispatch_async(dispatch_get_main_queue(), install);
}

// Keep the public model's liveValue property aware of explicit pass-through
// observations without swizzling any view controller or property setter.
@implementation RYGRuntimeBoolMethod (RYGLiveObservation)
- (NSNumber *)ryg_live_nativeValue {
    NSNumber *engineValue = [self ryg_live_nativeValue];
    return engineValue ?: RYGRuntimeObservedNativeValue(self.overrideKey);
}
@end

__attribute__((constructor)) static void RYGRuntimeLiveObservationBootstrap(void) {
    @autoreleasepool {
        RYGLiveEnsureStorage();
        Method original = class_getInstanceMethod(RYGRuntimeBoolMethod.class, @selector(liveValue));
        Method replacement = class_getInstanceMethod(RYGRuntimeBoolMethod.class, @selector(ryg_live_nativeValue));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
