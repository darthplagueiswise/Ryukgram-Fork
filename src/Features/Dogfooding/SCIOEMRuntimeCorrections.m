#import "SCIDogfoodObjectRuntime.h"
#import "SCIGraphQLDogfoodDiagnostics.h"
#import "SCIInternalActions.h"
#import "../Gating/SCICRuntimePatchResolver.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>

#define SCIOEMLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] OEMCorrections " fmt, ##__VA_ARGS__)

@interface SCIGraphQLDogfoodDiagnostics (SCIOEMPrivate)
+ (nullable id)graphQLDebugProvider;
@end

#pragma mark - ABI helpers

static NSString *SCIOEMNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *out = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') {
            [out appendFormat:@"%c", *p++];
            continue;
        }
        [out appendString:@"@"];
        p++;
        if (*p == '"') {
            p++;
            while (*p && *p != '"') p++;
            if (*p == '"') p++;
        } else if (*p == '?') {
            [out appendString:@"?"];
            p++;
            if (*p == '<') {
                NSInteger depth = 0;
                do {
                    if (*p == '<') depth++;
                    else if (*p == '>') depth--;
                    p++;
                } while (*p && depth > 0);
            }
        }
    }
    return out;
}

static BOOL SCIOEMMethodMatches(Method method, const char *expected) {
    if (!method || !expected) return NO;
    return [SCIOEMNormalizedEncoding(method_getTypeEncoding(method))
        isEqualToString:SCIOEMNormalizedEncoding(expected)];
}

static NSString *SCIOEMMethodEncoding(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSString stringWithUTF8String:encoding] : @"missing";
}

static NSString *SCIOEMClassName(id object) {
    return object ? (NSStringFromClass([object class]) ?: @"<unknown>") : @"nil";
}

static NSString *SCIOEMAddress(id object) {
    return object ? [NSString stringWithFormat:@"%p", object] : @"nil";
}

static id SCIOEMCallClassObject(Class cls, NSString *selectorName,
                                NSMutableArray<NSString *> *trace,
                                NSMutableArray<NSString *> *failures) {
    if (!cls || !selectorName.length) {
        if (failures) [failures addObject:[NSString stringWithFormat:@"%@ unavailable", selectorName ?: @"class"]];
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getClassMethod(cls, selector);
    if (!SCIOEMMethodMatches(method, "@16@0:8")) {
        if (failures) {
            [failures addObject:[NSString stringWithFormat:@"%@.%@ ABI=%@",
                NSStringFromClass(cls), selectorName, SCIOEMMethodEncoding(method)]];
        }
        return nil;
    }
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
        if (value && trace) {
            [trace addObject:[NSString stringWithFormat:@"%@.%@ → %@",
                NSStringFromClass(cls), selectorName, SCIOEMClassName(value)]];
        }
        return value;
    } @catch (id exception) {
        if (failures) {
            [failures addObject:[NSString stringWithFormat:@"%@.%@ threw %@",
                NSStringFromClass(cls), selectorName, exception]];
        }
        return nil;
    }
}

static id SCIOEMCallInstanceObject(id object, NSString *selectorName,
                                   NSMutableArray<NSString *> *trace,
                                   NSMutableArray<NSString *> *failures) {
    if (!object || !selectorName.length) {
        if (failures) [failures addObject:[NSString stringWithFormat:@"%@ receiver=nil", selectorName ?: @"selector"]];
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod([object class], selector);
    if (!SCIOEMMethodMatches(method, "@16@0:8")) {
        if (failures) {
            [failures addObject:[NSString stringWithFormat:@"%@.%@ ABI=%@",
                SCIOEMClassName(object), selectorName, SCIOEMMethodEncoding(method)]];
        }
        return nil;
    }
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (value && trace) {
            [trace addObject:[NSString stringWithFormat:@"%@.%@ → %@",
                SCIOEMClassName(object), selectorName, SCIOEMClassName(value)]];
        }
        return value;
    } @catch (id exception) {
        if (failures) {
            [failures addObject:[NSString stringWithFormat:@"%@.%@ threw %@",
                SCIOEMClassName(object), selectorName, exception]];
        }
        return nil;
    }
}

static BOOL SCIOEMContextHasValidManager(id context, NSString **failure) {
    if (!context) {
        if (failure) *failure = @"context=nil";
        return NO;
    }
    SEL selector = NSSelectorFromString(@"hasValidManager");
    Method method = class_getInstanceMethod([context class], selector);
    if (!SCIOEMMethodMatches(method, "B16@0:8") &&
        !SCIOEMMethodMatches(method, "c16@0:8")) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"%@.hasValidManager ABI=%@",
                SCIOEMClassName(context), SCIOEMMethodEncoding(method)];
        }
        return NO;
    }
    @try {
        BOOL valid = ((BOOL (*)(id, SEL))objc_msgSend)(context, selector);
        if (!valid && failure) {
            *failure = [NSString stringWithFormat:@"%@ manager=invalid", SCIOEMClassName(context)];
        }
        return valid;
    } @catch (id exception) {
        if (failure) *failure = [NSString stringWithFormat:@"hasValidManager threw %@", exception];
        return NO;
    }
}

#pragma mark - OEM sessionless MobileConfig graph

static id SCIOEMResolveSessionlessContext(NSString **source, NSString **failure) {
    NSMutableArray<NSString *> *trace = [NSMutableArray array];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    // Instagram's injected context is not the empty FBShared singleton. It is
    // owned by the FBT global graph and built with initWithManager:.
    Class globalClass = NSClassFromString(@"FBMobileConfigFBTGlobalSessionManager");
    id global = SCIOEMCallClassObject(globalClass, @"sharedInstance", trace, failures);
    id holder = SCIOEMCallInstanceObject(global, @"sessionlessContextManagerHolder", trace, failures);
    id fbtManager = SCIOEMCallInstanceObject(holder, @"mcFbtManager", trace, failures);
    id context = SCIOEMCallInstanceObject(fbtManager, @"mobileconfig", trace, failures);

    NSString *validityFailure = nil;
    if (context && SCIOEMContextHasValidManager(context, &validityFailure)) {
        if (source) *source = [trace componentsJoinedByString:@"\n"];
        return context;
    }
    if (validityFailure.length) [failures addObject:validityFailure];

    // Runtime capture is a fallback only, and is accepted only after manager
    // validation. It can never outrank the real FBT ownership graph.
    id captured = [SCIDogfoodObjectRuntime
        liveInstanceOfClassNameContaining:@"IGMobileConfigSessionlessContextManager"];
    validityFailure = nil;
    if (captured && SCIOEMContextHasValidManager(captured, &validityFailure)) {
        if (source) {
            *source = [NSString stringWithFormat:@"captured live %@ %@",
                SCIOEMClassName(captured), SCIOEMAddress(captured)];
        }
        return captured;
    }
    if (validityFailure.length) [failures addObject:[@"captured: " stringByAppendingString:validityFailure]];

    // Keep the two FBShared factories as last-resort diagnostics. Their normal
    // Instagram result is the manager-less singleton shown in the screenshot;
    // therefore a non-null object is not enough.
    NSArray<NSString *> *factoryClasses = @[
        @"FBMobileConfigContextManager",
        @"FBMobileConfigSessionlessContextManager"
    ];
    for (NSString *className in factoryClasses) {
        Class cls = NSClassFromString(className);
        NSMutableArray<NSString *> *factoryTrace = [NSMutableArray array];
        id candidate = SCIOEMCallClassObject(cls, @"sessionlessContextManager",
                                             factoryTrace, failures);
        validityFailure = nil;
        if (candidate && SCIOEMContextHasValidManager(candidate, &validityFailure)) {
            if (source) *source = [factoryTrace componentsJoinedByString:@"\n"];
            return candidate;
        }
        if (validityFailure.length) {
            [failures addObject:[NSString stringWithFormat:@"%@ factory: %@", className, validityFailure]];
        }
    }

    if (failure) {
        *failure = failures.count
            ? [failures componentsJoinedByString:@"; "]
            : @"no sessionless MobileConfig context is available";
    }
    return nil;
}

static NSString *SCIOEMInspectOrFetchSessionless(BOOL fetch) {
    NSString *source = nil;
    NSString *failure = nil;
    id context = SCIOEMResolveSessionlessContext(&source, &failure);
    if (!context) {
        return [NSString stringWithFormat:@"context=nil\n%@", failure ?: @"unresolved"];
    }

    SEL handlerSelector = NSSelectorFromString(@"customRefreshHandler");
    Method handlerMethod = class_getInstanceMethod([context class], handlerSelector);
    if (!SCIOEMMethodMatches(handlerMethod, "@16@0:8")) {
        return [NSString stringWithFormat:
            @"context=%@ %@\nmanager=valid\ncustomRefreshHandler ABI=%@\nsource:\n%@",
            SCIOEMClassName(context), SCIOEMAddress(context),
            SCIOEMMethodEncoding(handlerMethod), source ?: @"unknown"];
    }

    id handler = nil;
    @try {
        handler = ((id (*)(id, SEL))objc_msgSend)(context, handlerSelector);
    } @catch (id exception) {
        return [NSString stringWithFormat:@"context=%@\ncustomRefreshHandler threw %@",
            SCIOEMClassName(context), exception];
    }
    if (!handler) {
        return [NSString stringWithFormat:
            @"context=%@ %@\nmanager=valid\ncustomRefreshHandler=nil\nsource:\n%@",
            SCIOEMClassName(context), SCIOEMAddress(context), source ?: @"unknown"];
    }

    SEL updateSelector = NSSelectorFromString(@"tryUpdateConfigs");
    Method updateMethod = class_getInstanceMethod([context class], updateSelector);
    if (!SCIOEMMethodMatches(updateMethod, "v16@0:8")) {
        return [NSString stringWithFormat:
            @"context=%@ %@\nmanager=valid\nhandler=%@\ntryUpdateConfigs ABI=%@\nsource:\n%@",
            SCIOEMClassName(context), SCIOEMAddress(context),
            SCIOEMClassName(handler), SCIOEMMethodEncoding(updateMethod),
            source ?: @"unknown"];
    }

    if (!fetch) {
        return [NSString stringWithFormat:
            @"context=%@ %@\nmanager=valid\nhandler=%@ %@\ntryUpdateConfigs=v16@0:8\nsource:\n%@",
            SCIOEMClassName(context), SCIOEMAddress(context),
            SCIOEMClassName(handler), SCIOEMAddress(handler), source ?: @"unknown"];
    }

    @try {
        ((void (*)(id, SEL))objc_msgSend)(context, updateSelector);
    } @catch (id exception) {
        return [NSString stringWithFormat:@"context=%@\ntryUpdateConfigs threw %@",
            SCIOEMClassName(context), exception];
    }

    return [NSString stringWithFormat:
        @"requested through OEM context %@ %@\nmanager=valid\nhandler=%@ %@\nsource:\n%@",
        SCIOEMClassName(context), SCIOEMAddress(context),
        SCIOEMClassName(handler), SCIOEMAddress(handler), source ?: @"unknown"];
}

static NSString *(*sOrigSessionlessState)(id, SEL) = NULL;
static NSString *SCIOEMSessionlessState(id self, SEL _cmd) {
    NSString *result = SCIOEMInspectOrFetchSessionless(NO);
    [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig state"
                                  status:@"inspected" detail:result];
    return result;
}

static NSString *(*sOrigSessionlessFetch)(id, SEL) = NULL;
static NSString *SCIOEMSessionlessFetch(id self, SEL _cmd) {
    NSString *result = SCIOEMInspectOrFetchSessionless(YES);
    NSString *status = [result hasPrefix:@"requested through OEM"] ? @"requested" : @"blocked";
    [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig OEM fetch"
                                  status:status detail:result];
    return result;
}

#pragma mark - Live GraphQL Debug provider

static id SCIOEMLiveGraphQLProvider(NSString **diagnostic) {
    id session = [SCIInternalActions liveUserSession];
    if (!session) {
        if (diagnostic) *diagnostic = @"live IGUserSession=nil";
        return nil;
    }

    SEL selector = NSSelectorFromString(@"deidentifiedRequestProvider");
    Method method = class_getInstanceMethod([session class], selector);
    if (!SCIOEMMethodMatches(method, "@16@0:8")) {
        if (diagnostic) {
            *diagnostic = [NSString stringWithFormat:@"%@.deidentifiedRequestProvider ABI=%@",
                SCIOEMClassName(session), SCIOEMMethodEncoding(method)];
        }
        return nil;
    }

    id provider = nil;
    @try {
        provider = ((id (*)(id, SEL))objc_msgSend)(session, selector);
    } @catch (id exception) {
        if (diagnostic) *diagnostic = [NSString stringWithFormat:@"provider getter threw %@", exception];
        return nil;
    }

    if (!provider) {
        if (diagnostic) *diagnostic = @"deidentifiedRequestProvider returned nil";
        return nil;
    }

    Class expected = NSClassFromString(
        @"_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider"
    );
    if (expected && ![provider isKindOfClass:expected]) {
        if (diagnostic) {
            *diagnostic = [NSString stringWithFormat:@"provider class mismatch: %@",
                SCIOEMClassName(provider)];
        }
        return nil;
    }

    if (diagnostic) {
        *diagnostic = [NSString stringWithFormat:
            @"session=%@ %@\ngetter=deidentifiedRequestProvider @16@0:8\nprovider=%@ %@",
            SCIOEMClassName(session), SCIOEMAddress(session),
            SCIOEMClassName(provider), SCIOEMAddress(provider)];
    }
    return provider;
}

static id (*sOrigGraphQLDebugProvider)(id, SEL) = NULL;
static id SCIOEMGraphQLDebugProvider(id self, SEL _cmd) {
    // Never call the original implementation: it performs [[provider alloc] init],
    // while this Swift class's public -init is an unavailable/fatal stub.
    return SCIOEMLiveGraphQLProvider(NULL);
}

static NSString *(*sOrigGraphQLCapabilities)(id, SEL) = NULL;
static NSString *SCIOEMGraphQLCapabilities(id self, SEL _cmd) {
    NSString *providerDiagnostic = nil;
    id provider = SCIOEMLiveGraphQLProvider(&providerDiagnostic);
    Class providerClass = NSClassFromString(
        @"_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider"
    );

    NSArray<NSString *> *selectors = @[
        @"getStoredOHAIConfig",
        @"warmupForGraphQLDebugWithCompletionHandler:",
        @"retrieveACSTokenForGraphQLDebugWithCompletionHandler:",
        @"retrieveACSTokenAndOHAIConfigForGraphQLDebugWithCompletionHandler:"
    ];
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[NSString stringWithFormat:@"Provider ready: %@", provider ? @"YES" : @"NO"]];
    [rows addObject:providerDiagnostic ?: @"provider diagnostic unavailable"];
    [rows addObject:@""];

    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        Method method = providerClass ? class_getInstanceMethod(providerClass, selector) : NULL;
        [rows addObject:[NSString stringWithFormat:@"%@ — %@ — %@",
            name, method ? @"present" : @"absent", SCIOEMMethodEncoding(method)]];
    }
    [rows addObject:@"\nMethods alone are not readiness. Warmup/ACS actions are enabled only when the live IGUserSession returns the injected provider. Credential contents remain redacted."];
    return [rows componentsJoinedByString:@"\n"];
}

#pragma mark - Generic DATA patch safety

static BOOL SCIOEMSectionIsMutableData(NSString *section) {
    NSString *value = [section stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    return [value hasPrefix:@"__DATA,"] || [value hasPrefix:@"__DATA_DIRTY,"];
}

static void SCIOEMDisableUnsafeDataPlan(SCICRuntimePatchPlan *plan) {
    if (!plan || plan.strategy != SCICRuntimePatchStrategyDataPatchBytes) return;
    if (SCIOEMSectionIsMutableData(plan.section)) return;

    NSString *section = plan.section.length ? plan.section : @"unknown section";
    plan.strategy = SCICRuntimePatchStrategyNone;
    plan.strategyName = @"none (read-only Mach-O data)";
    plan.shortStrategyName = @"resolve only";
    plan.reason = [NSString stringWithFormat:
        @"%@ is not mutable __DATA/__DATA_DIRTY. Generic byte patch is blocked; resolve and hook the typed consumer/reader instead.",
        section];
    plan.inlineToggleSafe = NO;
    plan.safeAtLaunch = NO;
    plan.requiresPromptValue = NO;
    plan.requiresConfirmedConsumer = YES;
}

static SCICRuntimePatchPlan *(*sOrigResolvePlan)(id, SEL, NSDictionary *, NSArray *) = NULL;
static SCICRuntimePatchPlan *SCIOEMResolvePlan(id self, SEL _cmd,
                                               NSDictionary *entryInfo,
                                               NSArray *xrefHits) {
    SCICRuntimePatchPlan *plan = sOrigResolvePlan
        ? sOrigResolvePlan(self, _cmd, entryInfo, xrefHits)
        : nil;
    SCIOEMDisableUnsafeDataPlan(plan);
    return plan;
}

static BOOL (*sOrigApplyPlan)(id, SEL, SCICRuntimePatchPlan *, id, NSError **) = NULL;
static BOOL SCIOEMApplyPlan(id self, SEL _cmd, SCICRuntimePatchPlan *plan,
                            id value, NSError **error) {
    if (plan.strategy == SCICRuntimePatchStrategyDataPatchBytes &&
        !SCIOEMSectionIsMutableData(plan.section)) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCICRuntimePatchResolver"
                                         code:31
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Refused byte patch in read-only/constant section %@.",
                    plan.section ?: @"unknown"]}];
        }
        return NO;
    }
    return sOrigApplyPlan ? sOrigApplyPlan(self, _cmd, plan, value, error) : NO;
}

static void SCIOEMScrubUnsafePersistedPlans(void) {
    NSDictionary<NSString *, NSDictionary<NSString *, id> *> *plans =
        [SCICRuntimePatchResolver persistedPatchPlans];
    for (NSString *symbol in plans.allKeys.copy) {
        NSDictionary *entry = plans[symbol];
        NSString *strategy = [entry[@"strategy"] isKindOfClass:NSString.class]
            ? entry[@"strategy"] : @"";
        NSString *section = [entry[@"section"] isKindOfClass:NSString.class]
            ? entry[@"section"] : @"";
        if ([strategy isEqualToString:@"data.patch.bytes"] &&
            !SCIOEMSectionIsMutableData(section)) {
            [SCICRuntimePatchResolver forgetPatchPlanForSymbol:symbol];
            SCIOEMLOG("removed unsafe persisted DATA plan %{public}@ (%{public}@)", symbol, section);
        }
    }
}

static void (*sOrigReinstallPlans)(id, SEL) = NULL;
static void SCIOEMReinstallPlans(id self, SEL _cmd) {
    SCIOEMScrubUnsafePersistedPlans();
    if (sOrigReinstallPlans) sOrigReinstallPlans(self, _cmd);
}

#pragma mark - Installation

static BOOL SCIOEMHookClassMethod(Class cls, NSString *selectorName,
                                  IMP replacement, IMP *original) {
    if (!cls || !selectorName.length || !replacement || !original) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getClassMethod(cls, selector);
    if (!method) {
        SCIOEMLOG("missing class method %{public}@.%{public}@",
                  NSStringFromClass(cls), selectorName);
        return NO;
    }
    Class meta = object_getClass(cls);
    if (!meta) return NO;
    MSHookMessageEx(meta, selector, replacement, original);
    return *original != NULL;
}

__attribute__((constructor))
static void SCIOEMRuntimeCorrectionsCtor(void) {
    @autoreleasepool {
        BOOL stateHook = SCIOEMHookClassMethod(
            SCIDogfoodObjectRuntime.class, @"sessionlessMobileConfigState",
            (IMP)SCIOEMSessionlessState, (IMP *)&sOrigSessionlessState);
        BOOL fetchHook = SCIOEMHookClassMethod(
            SCIDogfoodObjectRuntime.class, @"tryFetchSessionlessMobileConfig",
            (IMP)SCIOEMSessionlessFetch, (IMP *)&sOrigSessionlessFetch);

        BOOL providerHook = SCIOEMHookClassMethod(
            SCIGraphQLDogfoodDiagnostics.class, @"graphQLDebugProvider",
            (IMP)SCIOEMGraphQLDebugProvider, (IMP *)&sOrigGraphQLDebugProvider);
        BOOL capabilitiesHook = SCIOEMHookClassMethod(
            SCIGraphQLDogfoodDiagnostics.class, @"graphQLDebugCapabilities",
            (IMP)SCIOEMGraphQLCapabilities, (IMP *)&sOrigGraphQLCapabilities);

        BOOL resolverHook = SCIOEMHookClassMethod(
            SCICRuntimePatchResolver.class, @"resolvePlanForEntryInfo:xrefHits:",
            (IMP)SCIOEMResolvePlan, (IMP *)&sOrigResolvePlan);
        BOOL applyHook = SCIOEMHookClassMethod(
            SCICRuntimePatchResolver.class, @"applyPlan:value:error:",
            (IMP)SCIOEMApplyPlan, (IMP *)&sOrigApplyPlan);
        BOOL reinstallHook = SCIOEMHookClassMethod(
            SCICRuntimePatchResolver.class, @"reinstallSafePersistedPatchPlansAtLaunch",
            (IMP)SCIOEMReinstallPlans, (IMP *)&sOrigReinstallPlans);

        SCIOEMScrubUnsafePersistedPlans();
        SCIOEMLOG("installed sessionless=%d/%d graphql=%d/%d DATA=%d/%d/%d",
                  stateHook, fetchHook, providerHook, capabilitiesHook,
                  resolverHook, applyHook, reinstallHook);
    }
}
