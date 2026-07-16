#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

extern NSUInteger SCIRefreshGraphQLDogfoodDynamicStatusHooks(void);

static NSString *(*orig_SCIGraphQLInstallObservers)(id, SEL) = NULL;

static NSString *SCIGraphQLInstallObservers(id self, SEL _cmd) {
    NSUInteger dynamicCount = SCIRefreshGraphQLDogfoodDynamicStatusHooks();
    NSString *base = orig_SCIGraphQLInstallObservers
        ? orig_SCIGraphQLInstallObservers(self, _cmd)
        : @"observer installer unavailable";
    return [NSString stringWithFormat:@"Dynamic eligibility roots installed: %lu\n\n%@",
            (unsigned long)dynamicCount, base ?: @""];
}

%ctor {
    @autoreleasepool {
        Class cls = objc_getClass("SCIGraphQLDogfoodDiagnostics");
        SEL selector = NSSelectorFromString(@"installObservers");
        Class meta = cls ? object_getClass(cls) : Nil;
        Method method = meta ? class_getInstanceMethod(meta, selector) : NULL;
        if (!method) return;
        MSHookMessageEx(meta, selector,
                        (IMP)SCIGraphQLInstallObservers,
                        (IMP *)&orig_SCIGraphQLInstallObservers);
    }
}
