#import "SCIDogfoodObjectRuntime.h"
#import "SCIGraphQLDogfoodDiagnostics.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

// Validated runtime resolvers for Instagram 434 / FBSharedFramework 107.
// Binary hashes used for the ABI audit:
// Instagram         a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa
// FBSharedFramework 22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc
//
// This file deliberately replaces the two unsafe assumptions that existed in
// the previous implementation:
//   1. +sessionlessContextManager is a usable Instagram context.
//   2. IGDirectDeidentifiedRequestProvider may be created with -init.
//
// The real objects are resolved from Instagram's live dependency graph.

static BOOL SCIObjectNoArgMethod(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return returnType[0] == '@';
}

static BOOL SCIBoolNoArgMethod(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return returnType[0] == 'B' || returnType[0] == 'c';
}

static BOOL SCIVoidNoArgMethod(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return returnType[0] == 'v';
}

static Method SCIDispatchMethod(id receiver, SEL selector) {
    if (!receiver || !selector) return NULL;
    return class_getInstanceMethod(object_getClass(receiver), selector);
}

static NSString *SCIEncoding(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSString stringWithUTF8String:encoding] : @"missing";
}

static id SCICallObjectGetter(id receiver, NSString *selectorName,
                              NSMutableArray<NSString *> *trace) {
    if (!receiver || !selectorName.length) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = SCIDispatchMethod(receiver, selector);
    if (!SCIObjectNoArgMethod(method)) {
        [trace addObject:[NSString stringWithFormat:@"%@.%@ ABI=%@",
                          NSStringFromClass(object_getClass(receiver)),
                          selectorName, SCIEncoding(method)]];
        return nil;
    }

    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
        [trace addObject:[NSString stringWithFormat:@"%@.%@ -> %@(%p)",
                          NSStringFromClass(object_getClass(receiver)),
                          selectorName,
                          value ? NSStringFromClass(object_getClass(value)) : @"nil",
                          value]];
        return value;
    } @catch (id exception) {
        [trace addObject:[NSString stringWithFormat:@"%@.%@ exception=%@",
                          NSStringFromClass(object_getClass(receiver)),
                          selectorName, exception]];
        return nil;
    }
}

static BOOL SCIContextHasValidManager(id context,
                                      NSMutableArray<NSString *> *trace) {
    SEL selector = NSSelectorFromString(@"hasValidManager");
    Method method = SCIDispatchMethod(context, selector);
    if (!SCIBoolNoArgMethod(method)) {
        [trace addObject:[NSString stringWithFormat:@"%@.hasValidManager ABI=%@",
                          context ? NSStringFromClass(object_getClass(context)) : @"nil",
                          SCIEncoding(method)]];
        return NO;
    }

    @try {
        BOOL valid = ((BOOL (*)(id, SEL))objc_msgSend)(context, selector);
        [trace addObject:[NSString stringWithFormat:@"hasValidManager=%@",
                          valid ? @"YES" : @"NO"]];
        return valid;
    } @catch (id exception) {
        [trace addObject:[NSString stringWithFormat:@"hasValidManager exception=%@",
                          exception]];
        return NO;
    }
}

static id SCIContextRefreshHandler(id context,
                                   NSMutableArray<NSString *> *trace) {
    id handler = SCICallObjectGetter(context, @"customRefreshHandler", trace);
    [trace addObject:[NSString stringWithFormat:@"customRefreshHandler=%@",
                      handler ? NSStringFromClass(object_getClass(handler)) : @"nil"]];
    return handler;
}

static BOOL SCIContextCanTryUpdate(id context,
                                   NSMutableArray<NSString *> *trace) {
    SEL selector = NSSelectorFromString(@"tryUpdateConfigs");
    Method method = SCIDispatchMethod(context, selector);
    BOOL valid = SCIVoidNoArgMethod(method);
    [trace addObject:[NSString stringWithFormat:@"tryUpdateConfigs ABI=%@ valid=%@",
                      SCIEncoding(method), valid ? @"YES" : @"NO"]];
    return valid;
}

static id SCIResolveOEMSessionlessContext(NSMutableArray<NSString *> *trace) {
    // Native Instagram graph proven in the executable:
    // FBMobileConfigFBTGlobalSessionManager.sharedInstance
    //   -> sessionlessContextManagerHolder
    //   -> mcFbtManager
    //   -> mobileconfig
    Class globalClass = NSClassFromString(@"FBMobileConfigFBTGlobalSessionManager");
    if (!globalClass) {
        [trace addObject:@"FBMobileConfigFBTGlobalSessionManager unavailable"];
        return nil;
    }

    id global = SCICallObjectGetter(globalClass, @"sharedInstance", trace);
    id holder = SCICallObjectGetter(global, @"sessionlessContextManagerHolder", trace);
    id fbtManager = SCICallObjectGetter(holder, @"mcFbtManager", trace);
    id mobileconfig = SCICallObjectGetter(fbtManager, @"mobileconfig", trace);

    if (mobileconfig && SCIContextHasValidManager(mobileconfig, trace)) {
        [trace addObject:@"source=OEM FBT global graph"];
        return mobileconfig;
    }

    // The initializer hook is only a fallback for a context already constructed
    // by Instagram. It is never used to manufacture one and the empty framework
    // singleton is intentionally not considered a usable candidate.
    id captured = [SCIDogfoodObjectRuntime
        liveInstanceOfClassNameContaining:@"IGMobileConfigSessionlessContextManager"];
    if (captured && captured != mobileconfig &&
        SCIContextHasValidManager(captured, trace)) {
        [trace addObject:@"source=captured Instagram sessionless context"];
        return captured;
    }

    [trace addObject:@"framework +sessionlessContextManager intentionally ignored: it is the empty base singleton in this build"];
    return nil;
}

static NSString *SCIValidatedSessionlessResult(BOOL fetch) {
    NSMutableArray<NSString *> *trace = [NSMutableArray array];
    id context = SCIResolveOEMSessionlessContext(trace);
    if (!context) {
        [trace insertObject:@"BLOCKED: no live sessionless context with a valid manager" atIndex:0];
        return [trace componentsJoinedByString:@"\n"];
    }

    id handler = SCIContextRefreshHandler(context, trace);
    if (!handler) {
        [trace insertObject:@"BLOCKED: OEM context has no custom refresh handler" atIndex:0];
        return [trace componentsJoinedByString:@"\n"];
    }
    if (!SCIContextCanTryUpdate(context, trace)) {
        [trace insertObject:@"BLOCKED: tryUpdateConfigs ABI changed" atIndex:0];
        return [trace componentsJoinedByString:@"\n"];
    }

    if (!fetch) {
        [trace insertObject:[NSString stringWithFormat:
            @"READY: %@(%p), manager valid, handler %@(%p)",
            NSStringFromClass(object_getClass(context)), context,
            NSStringFromClass(object_getClass(handler)), handler]
                    atIndex:0];
        return [trace componentsJoinedByString:@"\n"];
    }

    @try {
        ((void (*)(id, SEL))objc_msgSend)(context,
            NSSelectorFromString(@"tryUpdateConfigs"));
        [trace insertObject:[NSString stringWithFormat:
            @"REQUESTED: OEM tryUpdateConfigs on %@(%p)",
            NSStringFromClass(object_getClass(context)), context]
                    atIndex:0];
    } @catch (id exception) {
        [trace insertObject:[NSString stringWithFormat:
            @"FAILED: tryUpdateConfigs exception=%@", exception]
                    atIndex:0];
    }
    return [trace componentsJoinedByString:@"\n"];
}

static NSString *SCIValidatedSessionlessState(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    NSString *result = SCIValidatedSessionlessResult(NO);
    [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig state"
                                  status:[result hasPrefix:@"READY:"] ? @"ready" : @"blocked"
                                  detail:result];
    return result;
}

static NSString *SCIValidatedSessionlessFetch(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    NSString *result = SCIValidatedSessionlessResult(YES);
    [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig OEM fetch"
                                  status:[result hasPrefix:@"REQUESTED:"] ? @"requested" : @"blocked"
                                  detail:result];
    return result;
}

static id SCIResolveLiveGraphQLDebugProvider(NSMutableArray<NSString *> *trace) {
    id session = [SCIDogfoodObjectRuntime activeUserSession];
    if (!session) {
        [trace addObject:@"activeUserSession=nil"];
        return nil;
    }
    [trace addObject:[NSString stringWithFormat:@"userSession=%@(%p)",
                      NSStringFromClass(object_getClass(session)), session]];

    id provider = SCICallObjectGetter(session, @"deidentifiedRequestProvider", trace);
    if (!provider) return nil;

    Class expected = objc_getClass(
        "_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider");
    if (expected && ![provider isKindOfClass:expected]) {
        [trace addObject:[NSString stringWithFormat:
            @"provider class mismatch: expected %@, got %@",
            NSStringFromClass(expected), NSStringFromClass(object_getClass(provider))]];
        return nil;
    }
    [trace addObject:@"source=IGUserSession.deidentifiedRequestProvider"];
    return provider;
}

static id SCIValidatedGraphQLDebugProvider(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    NSMutableArray<NSString *> *trace = [NSMutableArray array];
    return SCIResolveLiveGraphQLDebugProvider(trace);
}

static NSString *SCIValidatedGraphQLCapabilities(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    id provider = SCIResolveLiveGraphQLDebugProvider(rows);
    if (!provider) {
        [rows insertObject:@"BLOCKED: no live GraphQL Debug provider. No object was allocated manually."
                   atIndex:0];
        return [rows componentsJoinedByString:@"\n"];
    }

    [rows insertObject:[NSString stringWithFormat:@"READY: provider=%@(%p)",
                        NSStringFromClass(object_getClass(provider)), provider]
                 atIndex:0];

    NSArray<NSString *> *selectors = @[
        @"getStoredOHAIConfig",
        @"warmupForGraphQLDebugWithCompletionHandler:",
        @"retrieveACSTokenForGraphQLDebugWithCompletionHandler:",
        @"retrieveACSTokenAndOHAIConfigForGraphQLDebugWithCompletionHandler:"
    ];
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(object_getClass(provider), selector);
        [rows addObject:[NSString stringWithFormat:@"%@ — %@ — ABI %@",
                         name, method ? @"present" : @"absent",
                         SCIEncoding(method)]];
    }

    SEL storedSelector = NSSelectorFromString(@"getStoredOHAIConfig");
    Method storedMethod = class_getInstanceMethod(object_getClass(provider), storedSelector);
    if (SCIObjectNoArgMethod(storedMethod)) {
        @try {
            id config = ((id (*)(id, SEL))objc_msgSend)(provider, storedSelector);
            [rows addObject:[NSString stringWithFormat:
                @"Stored OHAI config: %@; class=%@",
                config ? @"present" : @"absent",
                config ? NSStringFromClass(object_getClass(config)) : @"nil"]];
        } @catch (id exception) {
            [rows addObject:[NSString stringWithFormat:
                @"Stored OHAI config getter exception=%@", exception]];
        }
    }

    [rows addObject:@"ACS/OHAI contents are never printed; actions report only presence, runtime class and errors."];
    return [rows componentsJoinedByString:@"\n"];
}

static void SCIInstallValidatedOEMResolvers(void) {
    Class runtimeClass = NSClassFromString(@"SCIDogfoodObjectRuntime");
    Class diagnosticsClass = NSClassFromString(@"SCIGraphQLDogfoodDiagnostics");

    if (runtimeClass) {
        Class meta = object_getClass(runtimeClass);
        Method state = class_getInstanceMethod(meta,
            NSSelectorFromString(@"sessionlessMobileConfigState"));
        Method fetch = class_getInstanceMethod(meta,
            NSSelectorFromString(@"tryFetchSessionlessMobileConfig"));
        if (SCIObjectNoArgMethod(state)) {
            MSHookMessageEx(meta,
                NSSelectorFromString(@"sessionlessMobileConfigState"),
                (IMP)SCIValidatedSessionlessState, NULL);
        }
        if (SCIObjectNoArgMethod(fetch)) {
            MSHookMessageEx(meta,
                NSSelectorFromString(@"tryFetchSessionlessMobileConfig"),
                (IMP)SCIValidatedSessionlessFetch, NULL);
        }
    }

    if (diagnosticsClass) {
        Class meta = object_getClass(diagnosticsClass);
        Method provider = class_getInstanceMethod(meta,
            NSSelectorFromString(@"graphQLDebugProvider"));
        Method capabilities = class_getInstanceMethod(meta,
            NSSelectorFromString(@"graphQLDebugCapabilities"));
        if (SCIObjectNoArgMethod(provider)) {
            MSHookMessageEx(meta,
                NSSelectorFromString(@"graphQLDebugProvider"),
                (IMP)SCIValidatedGraphQLDebugProvider, NULL);
        }
        if (SCIObjectNoArgMethod(capabilities)) {
            MSHookMessageEx(meta,
                NSSelectorFromString(@"graphQLDebugCapabilities"),
                (IMP)SCIValidatedGraphQLCapabilities, NULL);
        }
    }
}

__attribute__((constructor))
static void SCIValidatedOEMResolversCtor(void) {
    @autoreleasepool {
        SCIInstallValidatedOEMResolvers();
    }
}
