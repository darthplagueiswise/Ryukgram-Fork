#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import <os/log.h>
#import <string.h>

#import "SCIDogfoodObjectRuntime.h"
#import "SCIGraphQLDogfoodDiagnostics.h"
#import "../../Utils.h"

#define RRFLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] ValidatedOEM " fmt, ##__VA_ARGS__)

// Runtime bridge revalidated against:
// Instagram         SHA-256 a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa
// FBSharedFramework SHA-256 22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc
//
// The sessionless startup path in -[IGAppJobsDefaultRunner startupAnalyzerDidEnd]
// calls the exported FBSharedFramework function at three call sites. The
// sessionless call at Instagram VA 0x102c5604c is exactly:
//
//   IGMobileConfigTryUpdateConfigsWithCompletion(
//       [deviceSession mobileConfig],
//       [deviceSession loggedOutNetworker],
//       nil,
//       completion /* receives BOOL in w1 */
//   );
//
// The exported wrapper is at FBSharedFramework VA 0x72da74; it consumes x0-x3
// and supplies its private fifth argument itself. This is the real OEM route.
// The former FBTGlobalSessionManager holder chain is not the owner in this
// runtime: the user's alert proved sessionlessContextManagerHolder=nil.

id SCIEmployeeInternalCapturedDeviceSession(void);
id SCIEmployeeInternalCapturedUserSession(void);

#pragma mark - ABI helpers

static NSString *SCIRRFNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *out = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') { [out appendFormat:@"%c", *p++]; continue; }
        [out appendString:@"@"]; p++;
        if (*p == '"') {
            p++;
            while (*p && *p != '"') p++;
            if (*p == '"') p++;
        } else if (*p == '?') {
            [out appendString:@"?"]; p++;
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

static BOOL SCIRRFTypeMatches(Method method, const char *expected) {
    if (!method || !expected) return NO;
    return [SCIRRFNormalizedEncoding(method_getTypeEncoding(method))
        isEqualToString:SCIRRFNormalizedEncoding(expected)];
}

static NSString *SCIRRFMethodEncoding(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSString stringWithUTF8String:encoding] : @"missing";
}

static NSString *SCIRRFClassName(id object) {
    return object ? (NSStringFromClass(object_getClass(object)) ?: @"<unknown>") : @"nil";
}

static id SCIRRFCallObjectGetter(id receiver, NSString *name, NSString **failure) {
    if (!receiver) {
        if (failure) *failure = [NSString stringWithFormat:@"%@ receiver=nil", name];
        return nil;
    }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(receiver), selector);
    if (!SCIRRFTypeMatches(method, "@16@0:8")) {
        if (failure) *failure = [NSString stringWithFormat:@"%@.%@ ABI=%@",
            SCIRRFClassName(receiver), name, SCIRRFMethodEncoding(method)];
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
    } @catch (id exception) {
        if (failure) *failure = [NSString stringWithFormat:@"%@.%@ exception=%@",
            SCIRRFClassName(receiver), name, exception];
        return nil;
    }
}

static void *SCIRRFSymbol(NSString *name) {
    if (!name.length) return NULL;
    void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
    if (!symbol) {
        symbol = dlsym(RTLD_DEFAULT,
            [[@"_" stringByAppendingString:name] UTF8String]);
    }
    return symbol;
}

#pragma mark - Device-session owned sessionless MobileConfig

static id SCIRRFResolveDeviceSession(NSString **source, NSString **failure) {
    id deviceSession = SCIEmployeeInternalCapturedDeviceSession();
    if (deviceSession &&
        [deviceSession respondsToSelector:NSSelectorFromString(@"mobileConfig")] &&
        [deviceSession respondsToSelector:NSSelectorFromString(@"loggedOutNetworker")]) {
        if (source) *source = @"IGBugReportMenuViewController.deviceSession";
        return deviceSession;
    }

    id userSession = [SCIDogfoodObjectRuntime activeUserSession];
    NSString *stepFailure = nil;
    deviceSession = SCIRRFCallObjectGetter(userSession, @"deviceSession", &stepFailure);
    if (deviceSession &&
        [deviceSession respondsToSelector:NSSelectorFromString(@"mobileConfig")] &&
        [deviceSession respondsToSelector:NSSelectorFromString(@"loggedOutNetworker")]) {
        if (source) *source = @"IGUserSession.deviceSession";
        return deviceSession;
    }

    id candidate = [SCIDogfoodObjectRuntime
        liveInstanceOfClassNameContaining:@"IGDeviceSession"];
    if (candidate &&
        [candidate respondsToSelector:NSSelectorFromString(@"mobileConfig")] &&
        [candidate respondsToSelector:NSSelectorFromString(@"loggedOutNetworker")]) {
        if (source) *source = @"captured runtime IGDeviceSession";
        return candidate;
    }

    if (failure) {
        *failure = stepFailure.length
            ? [NSString stringWithFormat:@"no usable IGDeviceSession; %@", stepFailure]
            : @"no usable IGDeviceSession; open the native Debug Menu once so its deviceSession is captured";
    }
    return nil;
}

typedef struct {
    __unsafe_unretained id deviceSession;
    __unsafe_unretained id mobileConfig;
    __unsafe_unretained id networker;
    __unsafe_unretained NSString *source;
    __unsafe_unretained NSString *failure;
    void *updateSymbol;
} SCIRRFSessionlessInputs;

static SCIRRFSessionlessInputs SCIRRFResolveSessionlessInputs(void) {
    SCIRRFSessionlessInputs result = {0};
    NSString *source = nil;
    NSString *failure = nil;
    id deviceSession = SCIRRFResolveDeviceSession(&source, &failure);
    if (!deviceSession) {
        result.failure = failure;
        return result;
    }

    NSString *mobileFailure = nil;
    id mobileConfig = SCIRRFCallObjectGetter(deviceSession, @"mobileConfig", &mobileFailure);
    NSString *networkFailure = nil;
    id networker = SCIRRFCallObjectGetter(deviceSession, @"loggedOutNetworker", &networkFailure);
    void *symbol = SCIRRFSymbol(@"IGMobileConfigTryUpdateConfigsWithCompletion");

    result.deviceSession = deviceSession;
    result.mobileConfig = mobileConfig;
    result.networker = networker;
    result.source = source;
    result.updateSymbol = symbol;

    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    if (!mobileConfig) [failures addObject:mobileFailure ?: @"deviceSession.mobileConfig=nil"];
    if (!networker) [failures addObject:networkFailure ?: @"deviceSession.loggedOutNetworker=nil"];
    if (!symbol) [failures addObject:@"IGMobileConfigTryUpdateConfigsWithCompletion symbol unavailable"];
    result.failure = failures.count ? [failures componentsJoinedByString:@"; "] : nil;
    return result;
}

static NSString *sSCIRRFLastFetchCompletion;

static NSString *SCIRRFSessionlessStateString(SCIRRFSessionlessInputs inputs) {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[NSString stringWithFormat:@"source=%@", inputs.source ?: @"unresolved"]];
    [rows addObject:[NSString stringWithFormat:@"deviceSession=%@", SCIRRFClassName(inputs.deviceSession)]];
    [rows addObject:[NSString stringWithFormat:@"mobileConfig=%@", SCIRRFClassName(inputs.mobileConfig)]];
    [rows addObject:[NSString stringWithFormat:@"loggedOutNetworker=%@", SCIRRFClassName(inputs.networker)]];
    [rows addObject:[NSString stringWithFormat:@"IGMobileConfigTryUpdateConfigsWithCompletion=%@",
        inputs.updateSymbol ? @"resolved (x0,x1,x2,x3; completion BOOL in w1)" : @"missing"]];
    if (inputs.failure.length) [rows addObject:[@"blocked=" stringByAppendingString:inputs.failure]];
    @synchronized (SCIDogfoodObjectRuntime.class) {
        if (sSCIRRFLastFetchCompletion.length) {
            [rows addObject:[@"last completion=" stringByAppendingString:sSCIRRFLastFetchCompletion]];
        }
    }
    return [rows componentsJoinedByString:@"\n"];
}

typedef void (*SCIRRFTryUpdateConfigsFn)(id mobileConfig,
                                         id networker,
                                         id customHours,
                                         void (^completion)(BOOL success));
typedef void (*SCIRRFRefreshStartupConfigsFn)(id mobileConfig,
                                              id launcherSet,
                                              id options);

static NSString *SCIRRFInspectOrFetchSessionless(BOOL fetch) {
    SCIRRFSessionlessInputs inputs = SCIRRFResolveSessionlessInputs();
    NSString *state = SCIRRFSessionlessStateString(inputs);
    if (!fetch || inputs.failure.length) return state;

    union { void *raw; SCIRRFTryUpdateConfigsFn function; } update;
    update.raw = inputs.updateSymbol;
    if (!update.function) return [state stringByAppendingString:@"\nfetch=blocked; invalid function pointer"];

    // Strong local captures intentionally keep the exact OEM dependencies alive
    // until FBSharedFramework invokes completion.
    id mobileConfig = inputs.mobileConfig;
    id networker = inputs.networker;
    NSString *source = inputs.source ?: @"unknown";
    void *refreshRaw = SCIRRFSymbol(@"refreshStartupConfigs");

    @try {
        update.function(mobileConfig, networker, nil, ^(BOOL success) {
            if (refreshRaw) {
                union { void *raw; SCIRRFRefreshStartupConfigsFn function; } refresh;
                refresh.raw = refreshRaw;
                // The audited shared completion refreshes startup configs after
                // the update callbacks drain, regardless of the individual BOOL.
                // For this single sessionless request launcherSet/options are nil.
                refresh.function(mobileConfig, nil, nil);
            }
            NSString *completion = [NSString stringWithFormat:@"success=%@ via %@",
                success ? @"YES" : @"NO", source];
            @synchronized (SCIDogfoodObjectRuntime.class) {
                sSCIRRFLastFetchCompletion = completion;
            }
            [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig OEM completion"
                                          status:success ? @"success" : @"failed"
                                          detail:completion];
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showToastForDuration:2.8
                                         title:success ? @"MobileConfig fetched" : @"MobileConfig fetch failed"
                                      subtitle:completion];
            });
            (void)networker;
        });
    } @catch (id exception) {
        return [NSString stringWithFormat:@"%@\nfetch exception=%@", state, exception];
    }

    [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig OEM fetch"
                                  status:@"requested"
                                  detail:state];
    return [NSString stringWithFormat:@"%@\nfetch=requested through OEM C bridge", state];
}

#pragma mark - GraphQL Debug provider from live IGUserSession

static id SCIRRFLiveGraphQLDebugProvider(NSString **state) {
    id session = [SCIDogfoodObjectRuntime activeUserSession];
    if (!session) {
        if (state) *state = @"session=nil; open after login";
        return nil;
    }

    NSString *failure = nil;
    id provider = SCIRRFCallObjectGetter(session, @"deidentifiedRequestProvider", &failure);
    if (!provider) {
        if (state) *state = failure ?: @"deidentifiedRequestProvider=nil";
        return nil;
    }

    NSString *providerClass = SCIRRFClassName(provider);
    if (![providerClass containsString:@"IGDirectDeidentifiedRequestProvider"]) {
        if (state) *state = [NSString stringWithFormat:@"provider=%@ (unexpected class)", providerClass];
        return nil;
    }

    if (state) *state = [NSString stringWithFormat:@"session=%@; provider=%@ (live)",
        SCIRRFClassName(session), providerClass];
    return provider;
}

static NSString *SCIRRFGraphQLCapabilities(void) {
    NSString *providerState = nil;
    id provider = SCIRRFLiveGraphQLDebugProvider(&providerState);
    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithObjects:
        providerState ?: @"provider state unavailable",
        @"provider construction=disabled; Swift -init is never called", nil];
    if (!provider) {
        [rows addObject:@"runtime usable=NO"];
        return [rows componentsJoinedByString:@"\n"];
    }

    Class cls = object_getClass(provider);
    NSArray<NSDictionary *> *methods = @[
        @{ @"name": @"getStoredOHAIConfig", @"abi": @"@16@0:8" },
        @{ @"name": @"warmupForGraphQLDebugWithCompletionHandler:", @"abi": @"v24@0:8@?16" },
        @{ @"name": @"retrieveACSTokenForGraphQLDebugWithCompletionHandler:", @"abi": @"v24@0:8@?16" },
        @{ @"name": @"retrieveACSTokenAndOHAIConfigForGraphQLDebugWithCompletionHandler:", @"abi": @"v24@0:8@?16" }
    ];
    BOOL compatible = YES;
    for (NSDictionary *entry in methods) {
        NSString *name = entry[@"name"];
        Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
        BOOL match = SCIRRFTypeMatches(method, [entry[@"abi"] UTF8String]);
        compatible &= match;
        [rows addObject:[NSString stringWithFormat:@"%@ — %@ — %@", name,
            match ? @"live/compatible" : @"missing or ABI mismatch",
            SCIRRFMethodEncoding(method)]];
    }
    [rows addObject:[NSString stringWithFormat:@"runtime usable=%@", compatible ? @"YES" : @"NO"]];
    [rows addObject:@"Token/config contents are never displayed."];
    return [rows componentsJoinedByString:@"\n"];
}

#pragma mark - Tweak method replacements

static id (*orig_SCIRRFSessionlessState)(id, SEL) = NULL;
static id new_SCIRRFSessionlessState(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return SCIRRFInspectOrFetchSessionless(NO);
}

static id (*orig_SCIRRFFetchSessionless)(id, SEL) = NULL;
static id new_SCIRRFFetchSessionless(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return SCIRRFInspectOrFetchSessionless(YES);
}

static id (*orig_SCIRRFGraphQLProvider)(id, SEL) = NULL;
static id new_SCIRRFGraphQLProvider(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return SCIRRFLiveGraphQLDebugProvider(NULL);
}

static id (*orig_SCIRRFGraphQLCapabilities)(id, SEL) = NULL;
static id new_SCIRRFGraphQLCapabilities(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return SCIRRFGraphQLCapabilities();
}

#pragma mark - Replace only the native logged-out Force Fetch action

typedef id (*SCIRRFUIAlertActionFactoryIMP)(id, SEL, NSString *, NSInteger, id);
static SCIRRFUIAlertActionFactoryIMP orig_SCIRRFUIAlertActionFactory = NULL;

static BOOL SCIRRFIsForceFetchTitle(NSString *title) {
    NSString *lower = title.lowercaseString ?: @"";
    return [lower containsString:@"mobileconfig"] &&
           [lower containsString:@"fetch"] &&
           ([lower containsString:@"force"] || [lower containsString:@"re-fetch"]);
}

static id new_SCIRRFUIAlertActionFactory(id cls, SEL _cmd,
                                         NSString *title,
                                         NSInteger style,
                                         id handler) {
    if (!SCIRRFIsForceFetchTitle(title)) {
        return orig_SCIRRFUIAlertActionFactory
            ? orig_SCIRRFUIAlertActionFactory(cls, _cmd, title, style, handler)
            : nil;
    }

    void (^replacement)(UIAlertAction *) = ^(__unused UIAlertAction *action) {
        NSString *result = SCIRRFInspectOrFetchSessionless(YES);
        BOOL requested = [result containsString:@"fetch=requested"];
        [SCIUtils showToastForDuration:3.0
                                 title:requested ? @"MobileConfig fetch requested" : @"MobileConfig fetch blocked"
                              subtitle:result];
    };
    RRFLOG("replaced native logged-out Force MobileConfig re-fetch handler");
    return orig_SCIRRFUIAlertActionFactory
        ? orig_SCIRRFUIAlertActionFactory(cls, _cmd, title, style, replacement)
        : nil;
}

static BOOL SCIRRFHookClassMethod(Class cls, SEL selector,
                                  const char *expected,
                                  IMP replacement,
                                  IMP *original) {
    if (!cls || !selector || !expected || !replacement || !original) return NO;
    Method method = class_getClassMethod(cls, selector);
    if (!SCIRRFTypeMatches(method, expected)) {
        RRFLOG("skip +%{public}@.%{public}s ABI=%{public}@",
            NSStringFromClass(cls), sel_getName(selector), SCIRRFMethodEncoding(method));
        return NO;
    }
    MSHookMessageEx(object_getClass(cls), selector, replacement, original);
    return *original != NULL;
}

static void SCIRRFInstall(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL state = SCIRRFHookClassMethod(NSClassFromString(@"SCIDogfoodObjectRuntime"),
            NSSelectorFromString(@"sessionlessMobileConfigState"), "@16@0:8",
            (IMP)new_SCIRRFSessionlessState, (IMP *)&orig_SCIRRFSessionlessState);
        BOOL fetch = SCIRRFHookClassMethod(NSClassFromString(@"SCIDogfoodObjectRuntime"),
            NSSelectorFromString(@"tryFetchSessionlessMobileConfig"), "@16@0:8",
            (IMP)new_SCIRRFFetchSessionless, (IMP *)&orig_SCIRRFFetchSessionless);
        BOOL provider = SCIRRFHookClassMethod(NSClassFromString(@"SCIGraphQLDogfoodDiagnostics"),
            NSSelectorFromString(@"graphQLDebugProvider"), "@16@0:8",
            (IMP)new_SCIRRFGraphQLProvider, (IMP *)&orig_SCIRRFGraphQLProvider);
        BOOL capabilities = SCIRRFHookClassMethod(NSClassFromString(@"SCIGraphQLDogfoodDiagnostics"),
            NSSelectorFromString(@"graphQLDebugCapabilities"), "@16@0:8",
            (IMP)new_SCIRRFGraphQLCapabilities, (IMP *)&orig_SCIRRFGraphQLCapabilities);
        BOOL alert = SCIRRFHookClassMethod(UIAlertAction.class,
            @selector(actionWithTitle:style:handler:), "@40@0:8@16q24@?32",
            (IMP)new_SCIRRFUIAlertActionFactory,
            (IMP *)&orig_SCIRRFUIAlertActionFactory);
        RRFLOG("installed state=%d fetch=%d provider=%d capabilities=%d alert=%d",
            state, fetch, provider, capabilities, alert);
    });
}

__attribute__((constructor))
static void SCIRRFValidatedResolversCtor(void) {
    @autoreleasepool { SCIRRFInstall(); }
}
