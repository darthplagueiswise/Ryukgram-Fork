#import <Foundation/Foundation.h>
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

// Revalidated with radare2 6.1.8 (Capstone 5 backend) and Python Capstone
// 5.0.7 against:
//   Instagram         a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa
//   FBSharedFramework 22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc
//
// Instagram VA 0x102c5604c calls the FBShared export with:
//   x0 = deviceSession.mobileConfig
//   x1 = deviceSession.loggedOutNetworker
//   x2 = nil custom hours
//   x3 = completion block
// The FBShared wrapper at VA 0x72da74 is exactly:
//   mov w4, #0
//   b   0x72fee4
// Therefore the public wrapper is four arguments and supplies its private fifth
// argument itself. No synthetic FBMobileConfig context and no manual
// refreshStartupConfigs call are used here.

id SCIEmployeeInternalCapturedDeviceSession(void);
id SCIEmployeeInternalCapturedUserSession(void);

#pragma mark - ABI helpers

static NSString *RRFNormalizedEncoding(const char *encoding) {
    if (!encoding) return @"";
    NSMutableString *result = [NSMutableString string];
    const char *p = encoding;
    while (*p) {
        if (*p != '@') {
            [result appendFormat:@"%c", *p++];
            continue;
        }
        [result appendString:@"@"]; p++;
        if (*p == '"') {
            for (p++; *p && *p != '"'; p++) {}
            if (*p) p++;
        } else if (*p == '?') {
            [result appendString:@"?"]; p++;
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
    return result;
}

static BOOL RRFTypeMatches(Method method, const char *expected) {
    return method && expected &&
        [RRFNormalizedEncoding(method_getTypeEncoding(method))
            isEqualToString:RRFNormalizedEncoding(expected)];
}

static NSString *RRFMethodEncoding(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSString stringWithUTF8String:encoding] : @"missing";
}

static NSString *RRFClassName(id object) {
    return object ? (NSStringFromClass([object class]) ?: @"<unknown>") : @"nil";
}

static id RRFObjectGetter(id receiver, NSString *name, NSString **failure) {
    if (!receiver) {
        if (failure) *failure = [NSString stringWithFormat:@"%@ receiver=nil", name];
        return nil;
    }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([receiver class], selector);
    if (!RRFTypeMatches(method, "@16@0:8")) {
        if (failure) *failure = [NSString stringWithFormat:@"%@.%@ ABI=%@",
            RRFClassName(receiver), name, RRFMethodEncoding(method)];
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
    } @catch (id exception) {
        if (failure) *failure = [NSString stringWithFormat:@"%@.%@ exception=%@",
            RRFClassName(receiver), name, exception];
        return nil;
    }
}

static void *RRFSymbol(NSString *name) {
    if (!name.length) return NULL;
    void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
    if (!symbol) {
        symbol = dlsym(RTLD_DEFAULT,
            [[@"_" stringByAppendingString:name] UTF8String]);
    }
    return symbol;
}

#pragma mark - Device-session-owned sessionless MobileConfig

static id RRFResolveDeviceSession(NSString **source, NSString **failure) {
    id deviceSession = SCIEmployeeInternalCapturedDeviceSession();
    if (deviceSession &&
        [deviceSession respondsToSelector:NSSelectorFromString(@"mobileConfig")] &&
        [deviceSession respondsToSelector:NSSelectorFromString(@"loggedOutNetworker")]) {
        if (source) *source = @"IGBugReportMenuViewController.deviceSession";
        return deviceSession;
    }

    id userSession = SCIEmployeeInternalCapturedUserSession() ?:
        [SCIDogfoodObjectRuntime activeUserSession];
    NSString *stepFailure = nil;
    deviceSession = RRFObjectGetter(userSession, @"deviceSession", &stepFailure);
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
} RRFSessionlessInputs;

static RRFSessionlessInputs RRFResolveSessionlessInputs(void) {
    RRFSessionlessInputs result = {0};
    NSString *source = nil;
    NSString *failure = nil;
    id deviceSession = RRFResolveDeviceSession(&source, &failure);
    if (!deviceSession) {
        result.failure = failure;
        return result;
    }

    NSString *mobileFailure = nil;
    id mobileConfig = RRFObjectGetter(deviceSession, @"mobileConfig", &mobileFailure);
    NSString *networkFailure = nil;
    id networker = RRFObjectGetter(deviceSession, @"loggedOutNetworker", &networkFailure);
    void *symbol = RRFSymbol(@"IGMobileConfigTryUpdateConfigsWithCompletion");

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

static NSString *sRRFLastFetchCompletion;

static NSString *RRFSessionlessStateString(RRFSessionlessInputs inputs) {
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:[NSString stringWithFormat:@"source=%@", inputs.source ?: @"unresolved"]];
    [rows addObject:[NSString stringWithFormat:@"deviceSession=%@", RRFClassName(inputs.deviceSession)]];
    [rows addObject:[NSString stringWithFormat:@"mobileConfig=%@", RRFClassName(inputs.mobileConfig)]];
    [rows addObject:[NSString stringWithFormat:@"loggedOutNetworker=%@", RRFClassName(inputs.networker)]];
    [rows addObject:[NSString stringWithFormat:@"IGMobileConfigTryUpdateConfigsWithCompletion=%@",
        inputs.updateSymbol ? @"resolved (x0,x1,x2,x3; wrapper supplies w4=0)" : @"missing"]];
    if (inputs.failure.length) [rows addObject:[@"blocked=" stringByAppendingString:inputs.failure]];
    @synchronized (SCIDogfoodObjectRuntime.class) {
        if (sRRFLastFetchCompletion.length) {
            [rows addObject:[@"last completion=" stringByAppendingString:sRRFLastFetchCompletion]];
        }
    }
    return [rows componentsJoinedByString:@"\n"];
}

typedef void (*RRFTryUpdateConfigsFn)(id mobileConfig,
                                      id loggedOutNetworker,
                                      id customHours,
                                      void (^completion)(BOOL success));

static NSString *RRFInspectOrFetchSessionless(BOOL fetch) {
    RRFSessionlessInputs inputs = RRFResolveSessionlessInputs();
    NSString *state = RRFSessionlessStateString(inputs);
    if (!fetch || inputs.failure.length) return state;

    union { void *raw; RRFTryUpdateConfigsFn function; } update;
    update.raw = inputs.updateSymbol;
    if (!update.function) {
        return [state stringByAppendingString:@"\nfetch=blocked; invalid function pointer"];
    }

    id mobileConfig = inputs.mobileConfig;
    id networker = inputs.networker;
    NSString *source = inputs.source ?: @"unknown";

    @try {
        update.function(mobileConfig, networker, nil, ^(BOOL success) {
            NSString *completion = [NSString stringWithFormat:@"success=%@ via %@",
                success ? @"YES" : @"NO", source];
            @synchronized (SCIDogfoodObjectRuntime.class) {
                sRRFLastFetchCompletion = completion;
            }
            [SCIDogfoodObjectRuntime noteAction:@"Sessionless MobileConfig OEM completion"
                                          status:success ? @"success" : @"failed"
                                          detail:completion];
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showToastForDuration:2.8
                                         title:success
                                            ? @"MobileConfig fetched"
                                            : @"MobileConfig fetch failed"
                                      subtitle:completion];
            });
            (void)mobileConfig;
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

static id RRFLiveGraphQLDebugProvider(NSString **state) {
    id session = SCIEmployeeInternalCapturedUserSession() ?:
        [SCIDogfoodObjectRuntime activeUserSession];
    if (!session) {
        if (state) *state = @"session=nil; open after login";
        return nil;
    }

    NSString *failure = nil;
    id provider = RRFObjectGetter(session, @"deidentifiedRequestProvider", &failure);
    if (!provider) {
        if (state) *state = failure ?: @"deidentifiedRequestProvider=nil";
        return nil;
    }

    NSString *providerClass = RRFClassName(provider);
    if (![providerClass containsString:@"IGDirectDeidentifiedRequestProvider"]) {
        if (state) *state = [NSString stringWithFormat:@"provider=%@ (unexpected class)", providerClass];
        return nil;
    }

    if (state) *state = [NSString stringWithFormat:@"session=%@; provider=%@ (live)",
        RRFClassName(session), providerClass];
    return provider;
}

static NSString *RRFGraphQLCapabilities(void) {
    NSString *providerState = nil;
    id provider = RRFLiveGraphQLDebugProvider(&providerState);
    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithObjects:
        providerState ?: @"provider state unavailable",
        @"provider construction=disabled; Swift -init is never called", nil];
    if (!provider) {
        [rows addObject:@"runtime usable=NO"];
        return [rows componentsJoinedByString:@"\n"];
    }

    Class cls = [provider class];
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
        BOOL match = RRFTypeMatches(method, [entry[@"abi"] UTF8String]);
        compatible = compatible && match;
        [rows addObject:[NSString stringWithFormat:@"%@ — %@ — %@", name,
            match ? @"live/compatible" : @"missing or ABI mismatch",
            RRFMethodEncoding(method)]];
    }
    [rows addObject:[NSString stringWithFormat:@"runtime usable=%@",
        compatible ? @"YES" : @"NO"]];
    [rows addObject:@"Token/config contents are never displayed."];
    return [rows componentsJoinedByString:@"\n"];
}

#pragma mark - Tweak method replacements

static id (*origRRFSessionlessState)(id, SEL) = NULL;
static id newRRFSessionlessState(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return RRFInspectOrFetchSessionless(NO);
}

static id (*origRRFFetchSessionless)(id, SEL) = NULL;
static id newRRFFetchSessionless(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return RRFInspectOrFetchSessionless(YES);
}

static id (*origRRFGraphQLProvider)(id, SEL) = NULL;
static id newRRFGraphQLProvider(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return RRFLiveGraphQLDebugProvider(NULL);
}

static id (*origRRFGraphQLCapabilities)(id, SEL) = NULL;
static id newRRFGraphQLCapabilities(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return RRFGraphQLCapabilities();
}

static BOOL RRFHookClassMethod(Class cls, SEL selector,
                               const char *expected,
                               IMP replacement,
                               IMP *original) {
    if (!cls || !selector || !expected || !replacement || !original) return NO;
    Method method = class_getClassMethod(cls, selector);
    if (!RRFTypeMatches(method, expected)) {
        RRFLOG("skip +%{public}@.%{public}s ABI=%{public}@",
            NSStringFromClass(cls), sel_getName(selector), RRFMethodEncoding(method));
        return NO;
    }
    MSHookMessageEx(object_getClass(cls), selector, replacement, original);
    return *original != NULL;
}

void SCIInstallValidatedOEMResolvers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        BOOL state = RRFHookClassMethod(NSClassFromString(@"SCIDogfoodObjectRuntime"),
            NSSelectorFromString(@"sessionlessMobileConfigState"), "@16@0:8",
            (IMP)newRRFSessionlessState, (IMP *)&origRRFSessionlessState);
        BOOL fetch = RRFHookClassMethod(NSClassFromString(@"SCIDogfoodObjectRuntime"),
            NSSelectorFromString(@"tryFetchSessionlessMobileConfig"), "@16@0:8",
            (IMP)newRRFFetchSessionless, (IMP *)&origRRFFetchSessionless);
        BOOL provider = RRFHookClassMethod(NSClassFromString(@"SCIGraphQLDogfoodDiagnostics"),
            NSSelectorFromString(@"graphQLDebugProvider"), "@16@0:8",
            (IMP)newRRFGraphQLProvider, (IMP *)&origRRFGraphQLProvider);
        BOOL capabilities = RRFHookClassMethod(NSClassFromString(@"SCIGraphQLDogfoodDiagnostics"),
            NSSelectorFromString(@"graphQLDebugCapabilities"), "@16@0:8",
            (IMP)newRRFGraphQLCapabilities, (IMP *)&origRRFGraphQLCapabilities);
        RRFLOG("installed state=%d fetch=%d provider=%d capabilities=%d",
            state, fetch, provider, capabilities);
    });
}
