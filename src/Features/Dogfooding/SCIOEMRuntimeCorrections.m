#import "SCIDogfoodObjectRuntime.h"
#import "SCIGraphQLDogfoodDiagnostics.h"
#import "SCIInternalActions.h"
#import "../Gating/SCICRuntimePatchResolver.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>

#define OEMLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] OEMCorrections " fmt, ##__VA_ARGS__)

@interface SCIGraphQLDogfoodDiagnostics (SCIOEMPrivate)
+ (nullable id)graphQLDebugProvider;
@end

#pragma mark - Runtime ABI helpers

static NSString *OEMNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *out = [NSMutableString string];
    for (const char *p = encoding; *p;) {
        if (*p != '@') { [out appendFormat:@"%c", *p++]; continue; }
        [out appendString:@"@"]; p++;
        if (*p == '"') {
            for (p++; *p && *p != '"'; p++) {}
            if (*p) p++;
        } else if (*p == '?') {
            [out appendString:@"?"]; p++;
            if (*p == '<') {
                NSInteger depth = 0;
                do { if (*p == '<') depth++; else if (*p == '>') depth--; p++; }
                while (*p && depth > 0);
            }
        }
    }
    return out;
}

static BOOL OEMMethodMatches(Method method, const char *expected) {
    return method && expected &&
        [OEMNormalizedEncoding(method_getTypeEncoding(method))
            isEqualToString:OEMNormalizedEncoding(expected)];
}

static NSString *OEMEncoding(Method method) {
    const char *value = method ? method_getTypeEncoding(method) : NULL;
    return value ? [NSString stringWithUTF8String:value] : @"missing";
}

static NSString *OEMClass(id object) {
    return object ? (NSStringFromClass([object class]) ?: @"<unknown>") : @"nil";
}

static NSString *OEMAddress(id object) {
    return object ? [NSString stringWithFormat:@"%p", object] : @"nil";
}

static id OEMCallClassObject(Class cls, NSString *name,
                             NSMutableArray<NSString *> *trace,
                             NSMutableArray<NSString *> *failures) {
    if (!cls) { [failures addObject:[NSString stringWithFormat:@"%@ class unavailable", name]]; return nil; }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getClassMethod(cls, selector);
    if (!OEMMethodMatches(method, "@16@0:8")) {
        [failures addObject:[NSString stringWithFormat:@"%@.%@ ABI=%@",
            NSStringFromClass(cls), name, OEMEncoding(method)]];
        return nil;
    }
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(cls, selector);
        if (value) [trace addObject:[NSString stringWithFormat:@"%@.%@ → %@",
            NSStringFromClass(cls), name, OEMClass(value)]];
        return value;
    } @catch (id exception) {
        [failures addObject:[NSString stringWithFormat:@"%@.%@ threw %@",
            NSStringFromClass(cls), name, exception]];
        return nil;
    }
}

static id OEMCallObject(id object, NSString *name,
                        NSMutableArray<NSString *> *trace,
                        NSMutableArray<NSString *> *failures) {
    if (!object) { [failures addObject:[NSString stringWithFormat:@"%@ receiver=nil", name]]; return nil; }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    if (!OEMMethodMatches(method, "@16@0:8")) {
        [failures addObject:[NSString stringWithFormat:@"%@.%@ ABI=%@",
            OEMClass(object), name, OEMEncoding(method)]];
        return nil;
    }
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        if (value) [trace addObject:[NSString stringWithFormat:@"%@.%@ → %@",
            OEMClass(object), name, OEMClass(value)]];
        return value;
    } @catch (id exception) {
        [failures addObject:[NSString stringWithFormat:@"%@.%@ threw %@",
            OEMClass(object), name, exception]];
        return nil;
    }
}

static BOOL OEMHasValidManager(id context, NSString **failure) {
    if (!context) { if (failure) *failure = @"context=nil"; return NO; }
    SEL selector = NSSelectorFromString(@"hasValidManager");
    Method method = class_getInstanceMethod([context class], selector);
    if (!OEMMethodMatches(method, "B16@0:8") && !OEMMethodMatches(method, "c16@0:8")) {
        if (failure) *failure = [NSString stringWithFormat:@"%@.hasValidManager ABI=%@",
            OEMClass(context), OEMEncoding(method)];
        return NO;
    }
    @try {
        BOOL valid = ((BOOL (*)(id, SEL))objc_msgSend)(context, selector);
        if (!valid && failure) *failure = [NSString stringWithFormat:@"%@ manager=invalid", OEMClass(context)];
        return valid;
    } @catch (id exception) {
        if (failure) *failure = [NSString stringWithFormat:@"hasValidManager threw %@", exception];
        return NO;
    }
}

#pragma mark - Sessionless MobileConfig: use Instagram's live FBT graph

static id OEMResolveSessionlessContext(NSString **source, NSString **failure) {
    NSMutableArray<NSString *> *trace = [NSMutableArray array];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    id global = OEMCallClassObject(NSClassFromString(@"FBMobileConfigFBTGlobalSessionManager"),
                                   @"sharedInstance", trace, failures);
    id holder = OEMCallObject(global, @"sessionlessContextManagerHolder", trace, failures);
    id fbtManager = OEMCallObject(holder, @"mcFbtManager", trace, failures);
    id context = OEMCallObject(fbtManager, @"mobileconfig", trace, failures);
    NSString *why = nil;
    if (context && OEMHasValidManager(context, &why)) {
        if (source) *source = [trace componentsJoinedByString:@"\n"];
        return context;
    }
    if (why.length) [failures addObject:why];

    id captured = [SCIDogfoodObjectRuntime
        liveInstanceOfClassNameContaining:@"IGMobileConfigSessionlessContextManager"];
    why = nil;
    if (captured && OEMHasValidManager(captured, &why)) {
        if (source) *source = [NSString stringWithFormat:@"captured live %@ %@",
            OEMClass(captured), OEMAddress(captured)];
        return captured;
    }
    if (why.length) [failures addObject:[@"captured: " stringByAppendingString:why]];

    // FBShared factories are diagnostic fallbacks only. A non-null singleton is
    // rejected unless its manager is actually valid.
    for (NSString *className in @[@"FBMobileConfigContextManager",
                                  @"FBMobileConfigSessionlessContextManager"]) {
        NSMutableArray<NSString *> *factoryTrace = [NSMutableArray array];
        id candidate = OEMCallClassObject(NSClassFromString(className),
            @"sessionlessContextManager", factoryTrace, failures);
        why = nil;
        if (candidate && OEMHasValidManager(candidate, &why)) {
            if (source) *source = [factoryTrace componentsJoinedByString:@"\n"];
            return candidate;
        }
        if (why.length) [failures addObject:[NSString stringWithFormat:@"%@ factory: %@", className, why]];
    }

    if (failure) *failure = failures.count
        ? [failures componentsJoinedByString:@"; "]
        : @"no live sessionless context";
    return nil;
}

static NSString *OEMInspectOrFetchSessionless(BOOL fetch) {
    NSString *source = nil, *failure = nil;
    id context = OEMResolveSessionlessContext(&source, &failure);
    if (!context) return [NSString stringWithFormat:@"context=nil\n%@", failure ?: @"unresolved"];

    SEL handlerSelector = NSSelectorFromString(@"customRefreshHandler");
    Method handlerMethod = class_getInstanceMethod([context class], handlerSelector);
    if (!OEMMethodMatches(handlerMethod, "@16@0:8")) {
        return [NSString stringWithFormat:@"context=%@ %@\nmanager=valid\ncustomRefreshHandler ABI=%@\nsource:\n%@",
            OEMClass(context), OEMAddress(context), OEMEncoding(handlerMethod), source ?: @"unknown"];
    }

    id handler = nil;
    @try { handler = ((id (*)(id, SEL))objc_msgSend)(context, handlerSelector); }
    @catch (id exception) { return [NSString stringWithFormat:@"customRefreshHandler threw %@", exception]; }
    if (!handler) return [NSString stringWithFormat:@"context=%@ %@\nmanager=valid\ncustomRefreshHandler=nil\nsource:\n%@",
        OEMClass(context), OEMAddress(context), source ?: @"unknown"];

    SEL updateSelector = NSSelectorFromString(@"tryUpdateConfigs");
    Method updateMethod = class_getInstanceMethod([context class], updateSelector);
    if (!OEMMethodMatches(updateMethod, "v16@0:8")) {
        return [NSString stringWithFormat:@"context=%@ %@\nmanager=valid\nhandler=%@\ntryUpdateConfigs ABI=%@\nsource:\n%@",
            OEMClass(context), OEMAddress(context), OEMClass(handler), OEMEncoding(updateMethod), source ?: @"unknown"];
    }

    if (fetch) {
        @try { ((void (*)(id, SEL))objc_msgSend)(context, updateSelector); }
        @catch (id exception) { return [NSString stringWithFormat:@"tryUpdateConfigs threw %@", exception]; }
    }
    return [NSString stringWithFormat:@"%@ through OEM context %@ %@\nmanager=valid\nhandler=%@ %@\ntryUpdateConfigs=v16@0:8\nsource:\n%@",
        fetch ? @"requested" : @"resolved", OEMClass(context), OEMAddress(context),
        OEMClass(handler), OEMAddress(handler), source ?: @"unknown"];
}

static NSString *(*origSessionlessState)(id, SEL) = NULL;
static NSString *OEMSessionlessState(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    NSString *result = OEMInspectOrFetchSessionless(NO);
    [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig state" status:@"inspected" detail:result];
    return result;
}

static NSString *(*origSessionlessFetch)(id, SEL) = NULL;
static NSString *OEMSessionlessFetch(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    NSString *result = OEMInspectOrFetchSessionless(YES);
    [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig OEM fetch"
                                  status:[result hasPrefix:@"requested"] ? @"requested" : @"blocked"
                                  detail:result];
    return result;
}

#pragma mark - GraphQL Debug: use IGUserSession's injected provider

static id OEMLiveGraphQLProvider(NSString **diagnostic) {
    id session = [SCIInternalActions liveUserSession];
    if (!session) { if (diagnostic) *diagnostic = @"live IGUserSession=nil"; return nil; }

    SEL selector = NSSelectorFromString(@"deidentifiedRequestProvider");
    Method method = class_getInstanceMethod([session class], selector);
    if (!OEMMethodMatches(method, "@16@0:8")) {
        if (diagnostic) *diagnostic = [NSString stringWithFormat:@"%@.deidentifiedRequestProvider ABI=%@",
            OEMClass(session), OEMEncoding(method)];
        return nil;
    }

    id provider = nil;
    @try { provider = ((id (*)(id, SEL))objc_msgSend)(session, selector); }
    @catch (id exception) { if (diagnostic) *diagnostic = [NSString stringWithFormat:@"provider getter threw %@", exception]; return nil; }
    if (!provider) { if (diagnostic) *diagnostic = @"deidentifiedRequestProvider returned nil"; return nil; }

    Class expected = NSClassFromString(@"_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider");
    if (expected && ![provider isKindOfClass:expected]) {
        if (diagnostic) *diagnostic = [NSString stringWithFormat:@"provider class mismatch: %@", OEMClass(provider)];
        return nil;
    }
    if (diagnostic) *diagnostic = [NSString stringWithFormat:
        @"session=%@ %@\ngetter=deidentifiedRequestProvider @16@0:8\nprovider=%@ %@",
        OEMClass(session), OEMAddress(session), OEMClass(provider), OEMAddress(provider)];
    return provider;
}

static id (*origGraphQLProvider)(id, SEL) = NULL;
static id OEMGraphQLProvider(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    // Do not call the original [[provider alloc] init] path: Swift -init is an
    // unavailable/fatal stub in this binary.
    return OEMLiveGraphQLProvider(NULL);
}

static NSString *(*origGraphQLCapabilities)(id, SEL) = NULL;
static NSString *OEMGraphQLCapabilities(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    NSString *diagnostic = nil;
    id provider = OEMLiveGraphQLProvider(&diagnostic);
    Class cls = NSClassFromString(@"_TtC38IGDirectDeidentifiedRequestProviderKit35IGDirectDeidentifiedRequestProvider");
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[NSString stringWithFormat:@"Provider ready: %@", provider ? @"YES" : @"NO"]];
    [rows addObject:diagnostic ?: @"provider diagnostic unavailable"];
    [rows addObject:@""];
    for (NSString *name in @[@"getStoredOHAIConfig",
                              @"warmupForGraphQLDebugWithCompletionHandler:",
                              @"retrieveACSTokenForGraphQLDebugWithCompletionHandler:",
                              @"retrieveACSTokenAndOHAIConfigForGraphQLDebugWithCompletionHandler:"]) {
        Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(name)) : NULL;
        [rows addObject:[NSString stringWithFormat:@"%@ — %@ — %@",
            name, method ? @"present" : @"absent", OEMEncoding(method)]];
    }
    [rows addObject:@"\nSelector presence is not readiness. Warmup/ACS uses only the live provider returned by IGUserSession; credential contents stay redacted."];
    return [rows componentsJoinedByString:@"\n"];
}

#pragma mark - Runtime browser: never byte-patch constant/read-only sections

static BOOL OEMMutableDataSection(NSString *section) {
    NSString *value = [section stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    return [value hasPrefix:@"__DATA,"] || [value hasPrefix:@"__DATA_DIRTY,"];
}

static void OEMSanitizePlan(SCICRuntimePatchPlan *plan) {
    if (!plan || plan.strategy != SCICRuntimePatchStrategyDataPatchBytes || OEMMutableDataSection(plan.section)) return;
    NSString *section = plan.section.length ? plan.section : @"unknown section";
    plan.strategy = SCICRuntimePatchStrategyNone;
    plan.strategyName = @"none (read-only Mach-O data)";
    plan.shortStrategyName = @"resolve only";
    plan.reason = [NSString stringWithFormat:
        @"%@ is not mutable __DATA/__DATA_DIRTY. Resolve and hook the typed consumer/reader instead.", section];
    plan.inlineToggleSafe = NO;
    plan.safeAtLaunch = NO;
    plan.requiresPromptValue = NO;
    plan.requiresConfirmedConsumer = YES;
}

static SCICRuntimePatchPlan *(*origResolvePlan)(id, SEL, NSDictionary *, NSArray *) = NULL;
static SCICRuntimePatchPlan *OEMResolvePlan(id self, SEL _cmd, NSDictionary *info, NSArray *hits) {
    SCICRuntimePatchPlan *plan = origResolvePlan ? origResolvePlan(self, _cmd, info, hits) : nil;
    OEMSanitizePlan(plan);
    return plan;
}

static BOOL (*origApplyPlan)(id, SEL, SCICRuntimePatchPlan *, id, NSError **) = NULL;
static BOOL OEMApplyPlan(id self, SEL _cmd, SCICRuntimePatchPlan *plan, id value, NSError **error) {
    if (plan.strategy == SCICRuntimePatchStrategyDataPatchBytes && !OEMMutableDataSection(plan.section)) {
        if (error) *error = [NSError errorWithDomain:@"SCICRuntimePatchResolver" code:31
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:
                @"Refused byte patch in read-only/constant section %@.", plan.section ?: @"unknown"]}];
        return NO;
    }
    return origApplyPlan ? origApplyPlan(self, _cmd, plan, value, error) : NO;
}

static void OEMScrubPersistedPlans(void) {
    NSDictionary *plans = [SCICRuntimePatchResolver persistedPatchPlans];
    for (NSString *symbol in plans.allKeys.copy) {
        NSDictionary *entry = plans[symbol];
        NSString *strategy = [entry[@"strategy"] isKindOfClass:NSString.class] ? entry[@"strategy"] : @"";
        NSString *section = [entry[@"section"] isKindOfClass:NSString.class] ? entry[@"section"] : @"";
        if ([strategy isEqualToString:@"data.patch.bytes"] && !OEMMutableDataSection(section)) {
            [SCICRuntimePatchResolver forgetPatchPlanForSymbol:symbol];
            OEMLOG("removed unsafe persisted DATA plan %{public}@ (%{public}@)", symbol, section);
        }
    }
}

static void (*origReinstallPlans)(id, SEL) = NULL;
static void OEMReinstallPlans(id self, SEL _cmd) {
    OEMScrubPersistedPlans();
    if (origReinstallPlans) origReinstallPlans(self, _cmd);
}

#pragma mark - Install corrections on tweak-owned class methods

static BOOL OEMHookClassMethod(Class cls, NSString *name, IMP replacement, IMP *original) {
    if (!cls || !name.length || !replacement || !original) return NO;
    SEL selector = NSSelectorFromString(name);
    if (!class_getClassMethod(cls, selector)) return NO;
    MSHookMessageEx(object_getClass(cls), selector, replacement, original);
    return *original != NULL;
}

__attribute__((constructor))
static void SCIOEMRuntimeCorrectionsCtor(void) {
    @autoreleasepool {
        BOOL a = OEMHookClassMethod(SCIDogfoodObjectRuntime.class, @"sessionlessMobileConfigState",
                                    (IMP)OEMSessionlessState, (IMP *)&origSessionlessState);
        BOOL b = OEMHookClassMethod(SCIDogfoodObjectRuntime.class, @"tryFetchSessionlessMobileConfig",
                                    (IMP)OEMSessionlessFetch, (IMP *)&origSessionlessFetch);
        BOOL c = OEMHookClassMethod(SCIGraphQLDogfoodDiagnostics.class, @"graphQLDebugProvider",
                                    (IMP)OEMGraphQLProvider, (IMP *)&origGraphQLProvider);
        BOOL d = OEMHookClassMethod(SCIGraphQLDogfoodDiagnostics.class, @"graphQLDebugCapabilities",
                                    (IMP)OEMGraphQLCapabilities, (IMP *)&origGraphQLCapabilities);
        BOOL e = OEMHookClassMethod(SCICRuntimePatchResolver.class, @"resolvePlanForEntryInfo:xrefHits:",
                                    (IMP)OEMResolvePlan, (IMP *)&origResolvePlan);
        BOOL f = OEMHookClassMethod(SCICRuntimePatchResolver.class, @"applyPlan:value:error:",
                                    (IMP)OEMApplyPlan, (IMP *)&origApplyPlan);
        BOOL g = OEMHookClassMethod(SCICRuntimePatchResolver.class, @"reinstallSafePersistedPatchPlansAtLaunch",
                                    (IMP)OEMReinstallPlans, (IMP *)&origReinstallPlans);
        OEMScrubPersistedPlans();
        OEMLOG("installed sessionless=%d/%d graphql=%d/%d DATA=%d/%d/%d", a, b, c, d, e, f, g);
    }
}
