#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import <string.h>

#define DGBLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] GraphQLDynamicBridge " fmt, ##__VA_ARGS__)

extern NSUInteger SCIRefreshGraphQLDogfoodDynamicStatusHooks(void);

static NSString *(*orig_SCIGraphQLInstallObservers)(id, SEL) = NULL;
static id (*orig_SCIDogfoodEligibilityBuilder)(id, SEL, id) = NULL;

static NSString *SCIGraphQLInstallObservers(id self, SEL _cmd) {
    NSUInteger dynamicCount = SCIRefreshGraphQLDogfoodDynamicStatusHooks();
    NSString *base = orig_SCIGraphQLInstallObservers
        ? orig_SCIGraphQLInstallObservers(self, _cmd)
        : @"observer installer unavailable";
    return [NSString stringWithFormat:@"Dynamic eligibility roots installed: %lu\n\n%@",
            (unsigned long)dynamicCount, base ?: @""];
}

static id SCIDogfoodEligibilityBuilder(id self, SEL _cmd, id lookbackDays) {
    id builder = orig_SCIDogfoodEligibilityBuilder
        ? orig_SCIDogfoodEligibilityBuilder(self, _cmd, lookbackDays)
        : nil;

    // This runs only when Instagram actually builds DogfoodingEligibilityQuery,
    // never during launch. Generated Pando response classes are loaded by then,
    // so resolve the concrete root/status model without a ctor-wide scan.
    NSUInteger count = SCIRefreshGraphQLDogfoodDynamicStatusHooks();
    DGBLOG("query built; dynamic roots installed=%lu", (unsigned long)count);
    return builder;
}

void SCIInstallGraphQLDogfoodQueryBridgeIfNeeded(void) {
    static BOOL installed = NO;
    if (installed) return;

    Class cls = objc_getClass("DogfoodingEligibilityQueryBuilder");
    SEL selector = NSSelectorFromString(@"builderWithLookbackDays:");
    Class meta = cls ? object_getClass(cls) : Nil;
    Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !encoding || strcmp(encoding, "@24@0:8@16") != 0) {
        if (method) DGBLOG("skip query bridge ABI=%{public}s", encoding ?: "(null)");
        return;
    }

    MSHookMessageEx(meta, selector,
                    (IMP)SCIDogfoodEligibilityBuilder,
                    (IMP *)&orig_SCIDogfoodEligibilityBuilder);
    installed = (orig_SCIDogfoodEligibilityBuilder != NULL);
}

%ctor {
    @autoreleasepool {
        Class cls = objc_getClass("SCIGraphQLDogfoodDiagnostics");
        SEL selector = NSSelectorFromString(@"installObservers");
        Class meta = cls ? object_getClass(cls) : Nil;
        Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
        if (method) {
            MSHookMessageEx(meta, selector,
                            (IMP)SCIGraphQLInstallObservers,
                            (IMP *)&orig_SCIGraphQLInstallObservers);
        }
    }
}
