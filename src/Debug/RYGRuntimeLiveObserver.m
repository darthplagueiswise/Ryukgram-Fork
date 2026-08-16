#import "RYGRuntimeLiveObserver.h"
#import "RYGRuntimeBrowserEngine.h"
#import "RYGRuntimeBrowserViewController.h"
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

// Unlike class_getInstanceMethod(), this does not ask the Objective-C runtime
// to dynamically resolve a missing selector. It only walks already-declared
// method lists, which is important for Pando/GraphQL classes with custom
// +resolveInstanceMethod: implementations.
static Method RYGLiveDeclaredMethodInHierarchy(Class owner, SEL selector) {
    for (Class cursor = owner; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(methods[i]) == selector) { found = methods[i]; break; }
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

    Class cls = NSClassFromString(row.className);
    SEL selector = NSSelectorFromString(row.selectorName);
    Class owner = row.classMethod ? object_getClass(cls) : cls;
    Method method = owner ? RYGLiveDeclaredMethodInHierarchy(owner, selector) : NULL;
    if (!cls || !owner || !selector || !RYGLiveMethodMatchesRow(method, row)) {
        [gRYGLiveLock lock]; [gRYGLiveInstalledKeys removeObject:row.overrideKey]; [gRYGLiveLock unlock];
        return;
    }

    NSString *key = row.overrideKey.copy;
    SEL capturedSelector = selector;
    IMP *original = calloc(1, sizeof(IMP));
    if (!original) {
        [gRYGLiveLock lock]; [gRYGLiveInstalledKeys removeObject:key]; [gRYGLiveLock unlock];
        return;
    }

    IMP replacement = NULL;
    switch (row.argumentKind) {
        case RYGRuntimeArgumentNone: {
            replacement = imp_implementationWithBlock(^BOOL(id receiver) {
                BOOL native = *original ? ((BOOL (*)(id, SEL))*original)(receiver, capturedSelector) : NO;
                RYGLiveRecord(key, native);
                return native;
            });
            break;
        }
        case RYGRuntimeArgumentObject: {
            replacement = imp_implementationWithBlock(^BOOL(id receiver, id argument) {
                BOOL native = *original ? ((BOOL (*)(id, SEL, id))*original)(receiver, capturedSelector, argument) : NO;
                RYGLiveRecord(key, native);
                return native;
            });
            break;
        }
        case RYGRuntimeArgumentInteger: {
            replacement = imp_implementationWithBlock(^BOOL(id receiver, uint64_t argument) {
                BOOL native = *original ? ((BOOL (*)(id, SEL, uint64_t))*original)(receiver, capturedSelector, argument) : NO;
                RYGLiveRecord(key, native);
                return native;
            });
            break;
        }
    }
    if (!replacement) {
        free(original);
        [gRYGLiveLock lock]; [gRYGLiveInstalledKeys removeObject:key]; [gRYGLiveLock unlock];
        return;
    }
    MSHookMessageEx(owner, selector, replacement, original);
    if (!*original) {
        imp_removeBlock(replacement);
        free(original);
        [gRYGLiveLock lock]; [gRYGLiveInstalledKeys removeObject:key]; [gRYGLiveLock unlock];
    }
}

void RYGRuntimeBeginLiveObservation(NSArray<RYGRuntimeBoolMethod *> *methods) {
    if (!methods.count) return;
    for (id candidate in methods) {
        if (![candidate isKindOfClass:RYGRuntimeBoolMethod.class]) continue;
        RYGLiveObserveMethod((RYGRuntimeBoolMethod *)candidate);
    }
}

#pragma mark - Integrate with the existing browser without a preloaded table

@implementation RYGRuntimeBoolMethod (RYGLiveObservation)
- (NSNumber *)ryg_live_nativeValue {
    // If the force hook already observed its true native IMP, that is the most
    // authoritative value. Otherwise use the pass-through observer.
    NSNumber *engineValue = [self ryg_live_nativeValue];
    return engineValue ?: RYGRuntimeObservedNativeValue(self.overrideKey);
}
@end

@implementation RYGRuntimeBrowserViewController (RYGLiveObservation)
- (void)ryg_live_setBoolRows:(NSArray<RYGRuntimeBoolMethod *> *)rows {
    [self ryg_live_setBoolRows:rows];
    RYGRuntimeBeginLiveObservation(rows);
}
- (void)ryg_live_viewDidLoad {
    [self ryg_live_viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(ryg_live_valueChanged:)
                                               name:RYGRuntimeNativeValueDidChangeNotification
                                             object:nil];
}
- (void)ryg_live_valueChanged:(NSNotification *)note {
    UITableView *table = nil;
    @try { table = [self valueForKey:@"tableView"]; } @catch (__unused NSException *e) {}
    NSArray<NSIndexPath *> *visible = table.indexPathsForVisibleRows;
    if (visible.count) [table reloadRowsAtIndexPaths:visible withRowAnimation:UITableViewRowAnimationNone];
}
- (UITableViewCell *)ryg_live_tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self ryg_live_tableView:tableView cellForRowAtIndexPath:indexPath];
    UISegmentedControl *mode = nil;
    NSArray *rows = nil;
    @try {
        mode = [self valueForKey:@"modeControl"];
        rows = [self valueForKey:@"visibleRows"];
    } @catch (__unused NSException *e) {}
    if (mode.selectedSegmentIndex != 0 || indexPath.row >= (NSInteger)rows.count) return cell;
    id item = rows[indexPath.row];
    if (![item isKindOfClass:RYGRuntimeBoolMethod.class]) return cell;
    RYGRuntimeBoolMethod *row = item;
    NSNumber *native = row.liveValue;
    NSNumber *forced = row.overrideValue;
    NSString *nativeText = native ? (native.boolValue ? @"true" : @"false") : @"not observed yet";
    NSString *outputText = forced ? (forced.boolValue ? @"forced true" : @"forced false") : @"native";
    NSString *argument = row.argumentKind == RYGRuntimeArgumentNone ? @"no args" : (row.argumentKind == RYGRuntimeArgumentObject ? @"object arg" : @"integer arg");
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · native %@ · output %@", row.className, argument, nativeText, outputText];
    return cell;
}
@end

static void RYGSwizzleInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor)) static void RYGRuntimeLiveObservationBootstrap(void) {
    @autoreleasepool {
        RYGLiveEnsureStorage();
        RYGSwizzleInstanceMethod(RYGRuntimeBoolMethod.class, @selector(liveValue), @selector(ryg_live_nativeValue));
        RYGSwizzleInstanceMethod(RYGRuntimeBrowserViewController.class, NSSelectorFromString(@"setBoolRows:"), @selector(ryg_live_setBoolRows:));
        RYGSwizzleInstanceMethod(RYGRuntimeBrowserViewController.class, @selector(viewDidLoad), @selector(ryg_live_viewDidLoad));
        RYGSwizzleInstanceMethod(RYGRuntimeBrowserViewController.class, @selector(tableView:cellForRowAtIndexPath:), @selector(ryg_live_tableView:cellForRowAtIndexPath:));
    }
}
