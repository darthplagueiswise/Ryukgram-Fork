#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>

#import "SCIDogfoodObjectRuntime.h"
#import "SCIGraphQLDogfoodDiagnostics.h"
#import "SCIInternalMenusLauncher.h"

// Runtime-only correction layer for the IG/FBSharedFramework build identified by:
// Instagram SHA-256 a562b3626c663eec47b41ed1bca7a7af6aa00cc30bada3293046f7cce1a555aa
// FBSharedFramework SHA-256 22aea16b8485a1f62cde3ae4136b90d0c89504dc0faca366c2c9bf7c9e5420dc
//
// The previous resolver stopped at the first non-nil sessionless factory result.
// In this build that object is the base singleton and can legitimately have no
// injected FBMobileConfigManager. The live Instagram-owned context is reached
// through the FBT global dependency graph instead.

static BOOL SCIRRFExactEncoding(Method method, const char *expected) {
    if (!method || !expected) return NO;
    const char *actual = method_getTypeEncoding(method);
    return actual && strcmp(actual, expected) == 0;
}

static NSString *SCIRRFMethodEncoding(Method method) {
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    return encoding ? [NSString stringWithUTF8String:encoding] : @"missing";
}

// Runtime encodings can preserve quoted Objective-C names and expanded block
// signatures. Normalize those annotations while retaining the ABI shape.
static NSString *SCIRRFNormalizedEncoding(const char *encoding) {
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
            continue;
        }
        if (*p == '?') {
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

static BOOL SCIRRFTypeMatches(Method method, const char *expected) {
    if (!method || !expected) return NO;
    return [SCIRRFNormalizedEncoding(method_getTypeEncoding(method))
        isEqualToString:SCIRRFNormalizedEncoding(expected)];
}

static id SCIRRFCallObjectGetter(id receiver, SEL selector, NSString **failure) {
    if (!receiver) {
        if (failure) *failure = @"receiver=nil";
        return nil;
    }

    Class cls = object_getClass(receiver);
    Method method = class_getInstanceMethod(cls, selector);
    if (!SCIRRFExactEncoding(method, "@16@0:8")) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"%@.%@ ABI=%@",
                        NSStringFromClass(cls), NSStringFromSelector(selector),
                        SCIRRFMethodEncoding(method)];
        }
        return nil;
    }

    @try {
        return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
    } @catch (id exception) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"%@.%@ exception=%@",
                        NSStringFromClass(cls), NSStringFromSelector(selector), exception];
        }
        return nil;
    }
}

static id SCIRRFCallObjectClassGetter(Class cls, SEL selector, NSString **failure) {
    if (!cls) {
        if (failure) *failure = @"class unavailable";
        return nil;
    }

    Method method = class_getClassMethod(cls, selector);
    if (!SCIRRFExactEncoding(method, "@16@0:8")) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"%@.%@ ABI=%@",
                        NSStringFromClass(cls), NSStringFromSelector(selector),
                        SCIRRFMethodEncoding(method)];
        }
        return nil;
    }

    @try {
        return ((id (*)(id, SEL))objc_msgSend)(cls, selector);
    } @catch (id exception) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"%@.%@ exception=%@",
                        NSStringFromClass(cls), NSStringFromSelector(selector), exception];
        }
        return nil;
    }
}

static BOOL SCIRRFReadValidManager(id context, BOOL *validOut, NSString **failure) {
    if (validOut) *validOut = NO;
    if (!context) {
        if (failure) *failure = @"context=nil";
        return NO;
    }

    Class cls = object_getClass(context);
    SEL selector = NSSelectorFromString(@"hasValidManager");
    Method method = class_getInstanceMethod(cls, selector);
    if (!SCIRRFExactEncoding(method, "B16@0:8") &&
        !SCIRRFExactEncoding(method, "c16@0:8")) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"%@.hasValidManager ABI=%@",
                        NSStringFromClass(cls), SCIRRFMethodEncoding(method)];
        }
        return NO;
    }

    @try {
        BOOL valid = ((BOOL (*)(id, SEL))objc_msgSend)(context, selector);
        if (validOut) *validOut = valid;
        return YES;
    } @catch (id exception) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"%@.hasValidManager exception=%@",
                        NSStringFromClass(cls), exception];
        }
        return NO;
    }
}

static id SCIRRFOEMSessionlessContext(NSMutableArray<NSString *> *trace,
                                      NSString **source,
                                      NSString **failure) {
    Class globalClass = NSClassFromString(@"FBMobileConfigFBTGlobalSessionManager");
    NSString *stepFailure = nil;
    id global = SCIRRFCallObjectClassGetter(globalClass,
                                            NSSelectorFromString(@"sharedInstance"),
                                            &stepFailure);
    if (!global) {
        if (failure) *failure = stepFailure ?: @"FBT global session manager unavailable";
        return nil;
    }
    [trace addObject:[NSString stringWithFormat:@"global=%@", NSStringFromClass(object_getClass(global))]];

    id holder = SCIRRFCallObjectGetter(global,
                                       NSSelectorFromString(@"sessionlessContextManagerHolder"),
                                       &stepFailure);
    if (!holder) {
        if (failure) *failure = stepFailure ?: @"sessionlessContextManagerHolder=nil";
        return nil;
    }
    [trace addObject:[NSString stringWithFormat:@"holder=%@", NSStringFromClass(object_getClass(holder))]];

    id fbtManager = SCIRRFCallObjectGetter(holder,
                                           NSSelectorFromString(@"mcFbtManager"),
                                           &stepFailure);
    if (!fbtManager) {
        if (failure) *failure = stepFailure ?: @"mcFbtManager=nil";
        return nil;
    }
    [trace addObject:[NSString stringWithFormat:@"fbtManager=%@", NSStringFromClass(object_getClass(fbtManager))]];

    id context = SCIRRFCallObjectGetter(fbtManager,
                                        NSSelectorFromString(@"mobileconfig"),
                                        &stepFailure);
    if (!context) {
        if (failure) *failure = stepFailure ?: @"mobileconfig=nil";
        return nil;
    }

    BOOL valid = NO;
    if (!SCIRRFReadValidManager(context, &valid, &stepFailure)) {
        if (failure) *failure = stepFailure;
        return nil;
    }
    if (!valid) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"OEM mobileconfig=%@ but manager=invalid",
                        NSStringFromClass(object_getClass(context))];
        }
        return nil;
    }

    [trace addObject:[NSString stringWithFormat:@"mobileconfig=%@; manager=valid",
                      NSStringFromClass(object_getClass(context))]];
    if (source) {
        *source = @"FBMobileConfigFBTGlobalSessionManager.sharedInstance → sessionlessContextManagerHolder → mcFbtManager → mobileconfig";
    }
    return context;
}

static id SCIRRFLiveCapturedSessionlessContext(NSMutableArray<NSString *> *trace,
                                               NSString **source,
                                               NSString **failure) {
    id context = [SCIDogfoodObjectRuntime
        liveInstanceOfClassNameContaining:@"IGMobileConfigSessionlessContextManager"];
    if (!context) {
        if (failure) *failure = @"no captured IGMobileConfigSessionlessContextManager";
        return nil;
    }

    BOOL valid = NO;
    NSString *validFailure = nil;
    if (!SCIRRFReadValidManager(context, &valid, &validFailure)) {
        if (failure) *failure = validFailure;
        return nil;
    }
    if (!valid) {
        if (failure) {
            *failure = [NSString stringWithFormat:@"captured %@ manager=invalid",
                        NSStringFromClass(object_getClass(context))];
        }
        return nil;
    }

    [trace addObject:[NSString stringWithFormat:@"captured=%@; manager=valid",
                      NSStringFromClass(object_getClass(context))]];
    if (source) *source = @"captured live IGMobileConfigSessionlessContextManager";
    return context;
}

static NSString *SCIRRFInspectOrFetchSessionless(BOOL fetch) {
    NSMutableArray<NSString *> *trace = [NSMutableArray array];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];
    NSString *source = nil;
    NSString *failure = nil;

    id context = SCIRRFOEMSessionlessContext(trace, &source, &failure);
    if (!context && failure.length) [failures addObject:[@"OEM chain: " stringByAppendingString:failure]];

    if (!context) {
        failure = nil;
        context = SCIRRFLiveCapturedSessionlessContext(trace, &source, &failure);
        if (!context && failure.length) [failures addObject:[@"captured fallback: " stringByAppendingString:failure]];
    }

    if (!context) {
        // Deliberately do not call +sessionlessContextManager here. In this build
        // that factory can return a non-nil base singleton with manager=invalid,
        // which was the false-positive shown by the runtime alert.
        [failures addObject:@"base +sessionlessContextManager factory skipped (known empty singleton candidate)"];
        return [NSString stringWithFormat:@"No usable sessionless MobileConfig context.\n%@",
                [failures componentsJoinedByString:@"\n"]];
    }

    Class contextClass = object_getClass(context);
    SEL handlerSelector = NSSelectorFromString(@"customRefreshHandler");
    Method handlerMethod = class_getInstanceMethod(contextClass, handlerSelector);
    if (!SCIRRFExactEncoding(handlerMethod, "@16@0:8")) {
        return [NSString stringWithFormat:@"source=%@\ncontext=%@\ncustomRefreshHandler ABI=%@",
                source ?: @"unknown", NSStringFromClass(contextClass),
                SCIRRFMethodEncoding(handlerMethod)];
    }

    id handler = nil;
    @try {
        handler = ((id (*)(id, SEL))objc_msgSend)(context, handlerSelector);
    } @catch (id exception) {
        return [NSString stringWithFormat:@"source=%@\ncontext=%@\ncustomRefreshHandler exception=%@",
                source ?: @"unknown", NSStringFromClass(contextClass), exception];
    }
    if (!handler) {
        return [NSString stringWithFormat:@"source=%@\ncontext=%@\nmanager=valid\ncustomRefreshHandler=nil",
                source ?: @"unknown", NSStringFromClass(contextClass)];
    }

    SEL updateSelector = NSSelectorFromString(@"tryUpdateConfigs");
    Method updateMethod = class_getInstanceMethod(contextClass, updateSelector);
    if (!SCIRRFExactEncoding(updateMethod, "v16@0:8")) {
        return [NSString stringWithFormat:@"source=%@\ncontext=%@\nmanager=valid\nhandler=%@\ntryUpdateConfigs ABI=%@",
                source ?: @"unknown", NSStringFromClass(contextClass),
                NSStringFromClass(object_getClass(handler)),
                SCIRRFMethodEncoding(updateMethod)];
    }

    NSString *state = [NSString stringWithFormat:
        @"source=%@\ncontext=%@\nmanager=valid\nhandler=%@\ntryUpdateConfigs=v16@0:8\ntrace=%@",
        source ?: @"unknown", NSStringFromClass(contextClass),
        NSStringFromClass(object_getClass(handler)),
        [trace componentsJoinedByString:@" → "]];

    if (!fetch) return state;

    @try {
        ((void (*)(id, SEL))objc_msgSend)(context, updateSelector);
    } @catch (id exception) {
        return [NSString stringWithFormat:@"%@\nfetch exception=%@", state, exception];
    }
    return [NSString stringWithFormat:@"%@\nfetch=requested through OEM context manager", state];
}

#pragma mark - GraphQL Debug provider from live IGUserSession

static id SCIRRFLiveGraphQLDebugProvider(NSString **state) {
    id session = [SCIDogfoodObjectRuntime activeUserSession];
    if (!session) {
        if (state) *state = @"session=nil; open after login";
        return nil;
    }

    Class sessionClass = object_getClass(session);
    SEL getter = NSSelectorFromString(@"deidentifiedRequestProvider");
    Method getterMethod = class_getInstanceMethod(sessionClass, getter);
    if (!SCIRRFExactEncoding(getterMethod, "@16@0:8")) {
        if (state) {
            *state = [NSString stringWithFormat:@"session=%@; deidentifiedRequestProvider ABI=%@",
                      NSStringFromClass(sessionClass), SCIRRFMethodEncoding(getterMethod)];
        }
        return nil;
    }

    id provider = nil;
    @try {
        provider = ((id (*)(id, SEL))objc_msgSend)(session, getter);
    } @catch (id exception) {
        if (state) {
            *state = [NSString stringWithFormat:@"session=%@; deidentifiedRequestProvider exception=%@",
                      NSStringFromClass(sessionClass), exception];
        }
        return nil;
    }

    if (!provider) {
        if (state) {
            *state = [NSString stringWithFormat:@"session=%@; deidentifiedRequestProvider=nil",
                      NSStringFromClass(sessionClass)];
        }
        return nil;
    }

    NSString *providerClass = NSStringFromClass(object_getClass(provider));
    if (![providerClass containsString:@"IGDirectDeidentifiedRequestProvider"]) {
        if (state) {
            *state = [NSString stringWithFormat:@"session=%@; provider=%@ (unexpected class)",
                      NSStringFromClass(sessionClass), providerClass];
        }
        return nil;
    }

    if (state) {
        *state = [NSString stringWithFormat:@"session=%@; getter=@16@0:8; provider=%@ (live)",
                  NSStringFromClass(sessionClass), providerClass];
    }
    return provider;
}

static NSString *SCIRRFGraphQLCapabilities(void) {
    NSString *providerState = nil;
    id provider = SCIRRFLiveGraphQLDebugProvider(&providerState);
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    [rows addObject:providerState ?: @"provider state unavailable"];
    [rows addObject:@"provider construction=disabled; Swift -init is not called"];

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

    BOOL allCompatible = YES;
    for (NSDictionary *entry in methods) {
        NSString *name = entry[@"name"];
        NSString *expectedString = entry[@"abi"];
        const char *expected = expectedString.UTF8String;
        Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
        BOOL compatible = SCIRRFTypeMatches(method, expected);
        allCompatible = allCompatible && compatible;
        [rows addObject:[NSString stringWithFormat:@"%@ — %@ — %@",
                         name, compatible ? @"live/compatible" : @"missing or ABI mismatch",
                         SCIRRFMethodEncoding(method)]];
    }

    SEL storedSelector = NSSelectorFromString(@"getStoredOHAIConfig");
    Method storedMethod = class_getInstanceMethod(cls, storedSelector);
    if (SCIRRFExactEncoding(storedMethod, "@16@0:8")) {
        @try {
            id config = ((id (*)(id, SEL))objc_msgSend)(provider, storedSelector);
            [rows addObject:[NSString stringWithFormat:@"stored OHAI config=%@; class=%@",
                             config ? @"present" : @"nil",
                             config ? NSStringFromClass(object_getClass(config)) : @"nil"]];
        } @catch (id exception) {
            [rows addObject:[NSString stringWithFormat:@"stored OHAI getter exception=%@", exception]];
            allCompatible = NO;
        }
    }

    [rows addObject:[NSString stringWithFormat:@"runtime usable=%@", allCompatible ? @"YES" : @"NO"]];
    [rows addObject:@"Token/config contents are never displayed."];
    return [rows componentsJoinedByString:@"\n"];
}

#pragma mark - Explicit method replacements

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

static id (*orig_SCIRRFOpenDogfoodingSettings)(id, SEL) = NULL;
static id new_SCIRRFOpenDogfoodingSettings(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    BOOL opened = [SCIDogfoodObjectRuntime tryOpenNativeDogfoodSettings];
    if (opened) return @"opened native Dogfooding Settings with live provider/config";

    NSDictionary *state = [SCIDogfoodObjectRuntime dogfoodNativeState];
    return [NSString stringWithFormat:
        @"native Dogfooding Assistant config unavailable; synthetic Swift init, socket-as-id scan and DirectNotes fallback are disabled\n%@",
        state ?: @{}];
}

static void SCIRRFHookClassMethod(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !selector || !replacement || !original) return;
    Method method = class_getClassMethod(cls, selector);
    if (!SCIRRFExactEncoding(method, "@16@0:8")) return;
    MSHookMessageEx(object_getClass(cls), selector, replacement, original);
}

static void SCIRRFInstall(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIRRFHookClassMethod(NSClassFromString(@"SCIDogfoodObjectRuntime"),
                             NSSelectorFromString(@"sessionlessMobileConfigState"),
                             (IMP)new_SCIRRFSessionlessState,
                             (IMP *)&orig_SCIRRFSessionlessState);
        SCIRRFHookClassMethod(NSClassFromString(@"SCIDogfoodObjectRuntime"),
                             NSSelectorFromString(@"tryFetchSessionlessMobileConfig"),
                             (IMP)new_SCIRRFFetchSessionless,
                             (IMP *)&orig_SCIRRFFetchSessionless);
        SCIRRFHookClassMethod(NSClassFromString(@"SCIGraphQLDogfoodDiagnostics"),
                             NSSelectorFromString(@"graphQLDebugProvider"),
                             (IMP)new_SCIRRFGraphQLProvider,
                             (IMP *)&orig_SCIRRFGraphQLProvider);
        SCIRRFHookClassMethod(NSClassFromString(@"SCIGraphQLDogfoodDiagnostics"),
                             NSSelectorFromString(@"graphQLDebugCapabilities"),
                             (IMP)new_SCIRRFGraphQLCapabilities,
                             (IMP *)&orig_SCIRRFGraphQLCapabilities);
        SCIRRFHookClassMethod(NSClassFromString(@"SCIInternalMenusLauncher"),
                             NSSelectorFromString(@"openDogfoodingSettingsVC"),
                             (IMP)new_SCIRRFOpenDogfoodingSettings,
                             (IMP *)&orig_SCIRRFOpenDogfoodingSettings);
    });
}

__attribute__((constructor))
static void SCIRRFValidatedResolversCtor(void) {
    @autoreleasepool {
        // These are methods on RyukGram's own classes, so replacement is safe at
        // dylib load. Instagram/FBShared objects are resolved only when the user
        // taps a diagnostic/action row; no global scan, timer or launch-time fetch.
        SCIRRFInstall();
    }
}
