#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <stdlib.h>

#define DGDSLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] GraphQLDynamicStatus " fmt, ##__VA_ARGS__)

static volatile BOOL sDGDynamicForceEnabled = NO;
static const void *kDGEligibilityNestedMarker = &kDGEligibilityNestedMarker;
static NSMutableSet<NSString *> *sDGRootHookedClasses;
static NSMutableSet<NSString *> *sDGStatusHookedClasses;

typedef struct {
    SEL selector;
    IMP original;
} DGDDescriptor;

void SCIRefreshGraphQLDogfoodDynamicForceEnabled(void) {
    sDGDynamicForceEnabled = [SCIUtils getBoolPref:@"sci_employee_internal"];
}

static inline BOOL DGDForceOn(void) {
    return sDGDynamicForceEnabled;
}

static void DGDEnsureState(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sDGRootHookedClasses = [NSMutableSet set];
        sDGStatusHookedClasses = [NSMutableSet set];
    });
}

static BOOL DGDObjectGetter(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == '@';
}

static Method DGDDirectMethod(Class cls, SEL selector) {
    unsigned count = 0;
    Method result = NULL;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            result = methods[i];
            break;
        }
    }
    free(methods);
    return result;
}

static void DGDInstallStatusHook(id nested) {
    if (!nested) return;
    DGDEnsureState();

    Class cls = [nested class];
    NSString *name = NSStringFromClass(cls) ?: @"";
    @synchronized (sDGStatusHookedClasses) {
        if ([sDGStatusHookedClasses containsObject:name]) return;
        [sDGStatusHookedClasses addObject:name];
    }

    SEL selector = NSSelectorFromString(@"status");
    Method method = class_getInstanceMethod(cls, selector);
    if (!DGDObjectGetter(method)) {
        @synchronized (sDGStatusHookedClasses) { [sDGStatusHookedClasses removeObject:name]; }
        return;
    }

    DGDDescriptor *descriptor = calloc(1, sizeof(*descriptor));
    descriptor->selector = selector;
    IMP replacement = imp_implementationWithBlock(^id(id receiver) {
        BOOL exactNested = [objc_getAssociatedObject(receiver, kDGEligibilityNestedMarker) boolValue];
        if (exactNested && DGDForceOn()) return @YES;
        return descriptor->original
            ? ((id (*)(id, SEL))descriptor->original)(receiver, descriptor->selector)
            : nil;
    });

    MSHookMessageEx(cls, selector, replacement, &descriptor->original);
    if (!descriptor->original) {
        @synchronized (sDGStatusHookedClasses) { [sDGStatusHookedClasses removeObject:name]; }
        free(descriptor);
        return;
    }
    DGDSLOG("status hooked on concrete nested class %{public}@", name);
}

static BOOL DGDInstallRootHook(Class cls, SEL selector, Method method) {
    if (!cls || !DGDObjectGetter(method)) return NO;
    DGDEnsureState();

    NSString *name = NSStringFromClass(cls) ?: @"";
    @synchronized (sDGRootHookedClasses) {
        if ([sDGRootHookedClasses containsObject:name]) return NO;
        [sDGRootHookedClasses addObject:name];
    }

    DGDDescriptor *descriptor = calloc(1, sizeof(*descriptor));
    descriptor->selector = selector;
    IMP replacement = imp_implementationWithBlock(^id(id receiver) {
        id nested = descriptor->original
            ? ((id (*)(id, SEL))descriptor->original)(receiver, descriptor->selector)
            : nil;
        if (nested) {
            objc_setAssociatedObject(nested, kDGEligibilityNestedMarker, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DGDInstallStatusHook(nested);
        }
        return nested;
    });

    MSHookMessageEx(cls, selector, replacement, &descriptor->original);
    if (!descriptor->original) {
        @synchronized (sDGRootHookedClasses) { [sDGRootHookedClasses removeObject:name]; }
        free(descriptor);
        return NO;
    }
    DGDSLOG("eligibility root accessor hooked on %{public}@", name);
    return YES;
}

NSUInteger SCIRefreshGraphQLDogfoodDynamicStatusHooks(void) {
    SCIRefreshGraphQLDogfoodDynamicForceEnabled();
    DGDEnsureState();

    SEL rootSelector = NSSelectorFromString(@"xdtApi_V1_Dogfooding_EligibilityStatus");
    NSUInteger installed = 0;
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return 0;

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        Method direct = DGDDirectMethod(cls, rootSelector);
        if (direct) {
            installed += DGDInstallRootHook(cls, rootSelector, direct) ? 1 : 0;
            continue;
        }

        NSString *name = [NSStringFromClass(cls) lowercaseString];
        if ([name containsString:@"gql"] || [name containsString:@"graphql"] ||
            [name containsString:@"pando"]) {
            Method inherited = class_getInstanceMethod(cls, rootSelector);
            if (inherited) installed += DGDInstallRootHook(cls, rootSelector, inherited) ? 1 : 0;
        }
    }
    free(classes);
    return installed;
}
