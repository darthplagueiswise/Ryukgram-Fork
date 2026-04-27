#import "SCIResolverScanner.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

static NSArray<NSString *> *SCIResolverDogKeywords(void) {
    return @[
        @"dogfood", @"Dogfood", @"Dogfooding", @"Dogfooder", @"DogfoodingSettings", @"DogfoodingFirst",
        @"ProductionLockout", @"Eligibility", @"DeveloperOptions", @"DeveloperAccount", @"DeveloperTools",
        @"InternalSettings", @"Internal", @"MetaConfig", @"SettingsOverrides", @"Override",
        @"Employee", @"employee", @"Whitehat", @"IGLogoutEntryPointDeveloperTools",
        @"LocalExperiment", @"LIDExperiment", @"FamilyLocalExperiment"
    ];
}

static NSArray<NSString *> *SCIResolverMCKeywords(void) {
    return @[
        @"MobileConfig", @"mobileconfig", @"IGMobileConfig", @"FBMobileConfig",
        @"MCIMobileConfig", @"MCIExperimentCache", @"MCIExtensionExperimentCache",
        @"METAExtensionsExperiment", @"MSGCSessionedMobileConfig", @"EasyGating",
        @"MCQEasyGating", @"MCDDasmNative", @"MCDCoreDasmNative",
        @"MEMMobileConfig", @"MCQMEMMobileConfig", @"FeatureDevConfig",
        @"FeatureCapability", @"ProtocolExperiment", @"PlatformGetBoolean",
        @"InternalUse", @"DoNotUseOrMock", @"getBool", @"getBoolean"
    ];
}

static NSArray<NSString *> *SCIResolverSelectorHints(void) {
    return @[
        @"open", @"openWithConfig", @"initWithConfig", @"userSession", @"deviceSession", @"logger",
        @"settings", @"sections", @"items", @"rows", @"builder", @"coordinator", @"route",
        @"developer", @"employee", @"dogfood", @"override", @"eligibility", @"config"
    ];
}

static NSString *SCIClassName(Class cls) {
    if (!cls) return @"(nil)";
    const char *n = class_getName(cls);
    return n ? [NSString stringWithUTF8String:n] : @"(unknown)";
}

static NSString *SCIImageName(Class cls) {
    if (!cls) return @"";
    const char *n = class_getImageName(cls);
    return n ? [NSString stringWithUTF8String:n] : @"";
}

static BOOL SCIContainsAny(NSString *text, NSArray<NSString *> *keys) {
    if (!text.length) return NO;
    NSString *lower = text.lowercaseString;
    for (NSString *k in keys) {
        if (k.length && [lower containsString:k.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL SCIIsUIViewControllerClass(Class cls) {
    Class vc = NSClassFromString(@"UIViewController");
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        if (c == vc) return YES;
    }
    return NO;
}

static NSArray<NSString *> *SCIMatchingMethods(Class cls, NSArray<NSString *> *keys, NSUInteger max) {
    if (!cls) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableArray<NSString *> *allKeys = [keys mutableCopy];
    [allKeys addObjectsFromArray:SCIResolverSelectorHints()];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (methods) {
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            const char *csel = sel ? sel_getName(sel) : NULL;
            if (!csel) continue;
            NSString *name = [NSString stringWithUTF8String:csel];
            if (!SCIContainsAny(name, allKeys)) continue;
            const char *types = method_getTypeEncoding(methods[i]);
            NSString *type = types ? [NSString stringWithUTF8String:types] : @"";
            [out addObject:[NSString stringWithFormat:@"%@ types=%@", name, type]];
            if (max && out.count >= max) break;
        }
        free(methods);
    }
    return out;
}

static NSArray<NSString *> *SCIMatchingIvars(Class cls, NSArray<NSString *> *keys, NSUInteger max) {
    if (!cls) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableArray<NSString *> *allKeys = [keys mutableCopy];
    [allKeys addObjectsFromArray:SCIResolverSelectorHints()];
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    if (ivars) {
        for (unsigned int i = 0; i < count; i++) {
            const char *cn = ivar_getName(ivars[i]);
            const char *ct = ivar_getTypeEncoding(ivars[i]);
            if (!cn) continue;
            NSString *name = [NSString stringWithUTF8String:cn];
            NSString *type = ct ? [NSString stringWithUTF8String:ct] : @"";
            if (!SCIContainsAny(name, allKeys) && !SCIContainsAny(type, allKeys)) continue;
            [out addObject:[NSString stringWithFormat:@"%@ type=%@", name, type]];
            if (max && out.count >= max) break;
        }
        free(ivars);
    }
    return out;
}

static NSInteger SCIScoreClass(Class cls, NSArray<NSString *> *keys, NSArray<NSString *> **methodsOut, NSArray<NSString *> **ivarsOut) {
    NSString *name = SCIClassName(cls);
    NSArray<NSString *> *methods = SCIMatchingMethods(cls, keys, 16);
    NSArray<NSString *> *ivars = SCIMatchingIvars(cls, keys, 12);
    NSInteger score = 0;
    if (SCIContainsAny(name, keys)) score += 60;
    score += MIN(48, (NSInteger)methods.count * 8);
    score += MIN(24, (NSInteger)ivars.count * 4);
    if (SCIIsUIViewControllerClass(cls)) score += 20;
    if ([name containsString:@"."]) score += 5;
    if ([name containsString:@"Settings"] || [name containsString:@"Controller"] || [name containsString:@"Coordinator"]) score += 10;
    if (methodsOut) *methodsOut = methods;
    if (ivarsOut) *ivarsOut = ivars;
    return score;
}

static NSArray<NSDictionary *> *SCIRankedCandidates(NSArray<NSString *> *keys, NSUInteger limit) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @[];
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    if (!classes) return @[];
    count = objc_getClassList(classes, count);
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSArray *methods = nil;
        NSArray *ivars = nil;
        NSInteger score = SCIScoreClass(cls, keys, &methods, &ivars);
        if (score < 25) continue;
        [results addObject:@{
            @"score": @(score),
            @"name": SCIClassName(cls),
            @"super": SCIClassName(class_getSuperclass(cls)),
            @"image": SCIImageName(cls),
            @"vc": @(SCIIsUIViewControllerClass(cls)),
            @"methods": methods ?: @[],
            @"ivars": ivars ?: @[]
        }];
    }
    free(classes);
    [results sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger sa = [a[@"score"] integerValue];
        NSInteger sb = [b[@"score"] integerValue];
        if (sa > sb) return NSOrderedAscending;
        if (sa < sb) return NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"]];
    }];
    if (limit && results.count > limit) return [results subarrayWithRange:NSMakeRange(0, limit)];
    return results;
}

static void *SCIDlsymFlexible(NSString *sym) {
    if (!sym.length) return NULL;
    void *p = dlsym(RTLD_DEFAULT, sym.UTF8String);
    if (p) return p;
    if ([sym hasPrefix:@"_"]) return dlsym(RTLD_DEFAULT, [sym substringFromIndex:1].UTF8String);
    NSString *under = [@"_" stringByAppendingString:sym];
    return dlsym(RTLD_DEFAULT, under.UTF8String);
}

static NSString *SCISymbolReport(void) {
    NSArray<NSString *> *symbols = @[
        @"_IGMobileConfigBooleanValueForInternalUse",
        @"_IGMobileConfigSessionlessBooleanValueForInternalUse",
        @"_MCIMobileConfigGetBoolean",
        @"_MCIExperimentCacheGetMobileConfigBoolean",
        @"_MCIExtensionExperimentCacheGetMobileConfigBoolean",
        @"_METAExtensionsExperimentGetBoolean",
        @"_METAExtensionsExperimentGetBooleanWithoutExposure",
        @"_MSGCSessionedMobileConfigGetBoolean",
        @"_EasyGatingPlatformGetBoolean",
        @"_EasyGatingGetBoolean_Internal_DoNotUseOrMock",
        @"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
        @"_MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
        @"_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",
        @"_MCQMEMMobileConfigCqlGetBooleanInternalDoNotUseOrMock",
        @"_MEMMobileConfigFeatureCapabilityGetBoolean_Internal_DoNotUseOrMock",
        @"_MEMMobileConfigFeatureDevConfigGetBoolean_Internal_DoNotUseOrMock",
        @"_MEMMobileConfigPlatformGetBoolean",
        @"_MEMMobileConfigProtocolExperimentGetBoolean_Internal_DoNotUseOrMock",
        @"_ig_is_employee",
        @"_ig_is_employee_or_test_user",
        @"_ig_dogfooding_first_client",
        @"_xav_switcher_ig_ios_test_user_check_fdid",
        @"_kIGDeviceReportFBUserIsEmployeeKey",
        @"_METAAppGroupNameDeveloperAccount",
        @"_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18"
    ];
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"MobileConfig / EasyGating / employee symbol availability\n"];
    [out appendString:@"mode = dlsym(RTLD_DEFAULT), flexible underscore handling\n\n"];
    for (NSString *sym in symbols) {
        void *addr = SCIDlsymFlexible(sym);
        [out appendFormat:@"%@ · %@ · %p\n", addr ? @"FOUND" : @"missing", sym, addr];
    }
    return out;
}

static NSString *SCIFormatCandidates(NSString *title, NSArray<NSDictionary *> *candidates) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"%@\n", title];
    [out appendString:@"mode = view-only; no hooks, no alloc/init, no KVC, no entrypoint invocation\n\n"];
    NSUInteger i = 1;
    for (NSDictionary *e in candidates) {
        [out appendFormat:@"%lu. score=%@ %@\n", (unsigned long)i, e[@"score"], e[@"name"]];
        [out appendFormat:@"   super=%@ UIViewController=%@\n", e[@"super"], [e[@"vc"] boolValue] ? @"YES" : @"NO"];
        [out appendFormat:@"   image=%@\n", e[@"image"]];
        NSArray *methods = e[@"methods"];
        if (methods.count) {
            [out appendString:@"   methods:\n"];
            for (NSString *m in methods) [out appendFormat:@"     - %@\n", m];
        }
        NSArray *ivars = e[@"ivars"];
        if (ivars.count) {
            [out appendString:@"   ivars:\n"];
            for (NSString *v in ivars) [out appendFormat:@"     - %@\n", v];
        }
        [out appendString:@"\n"];
        i++;
    }
    return out;
}

@implementation SCIResolverScanner

+ (NSString *)runDogfoodDeveloperReport {
    @autoreleasepool {
        return SCIFormatCandidates(@"SCI Resolver — Dogfood / Developer / MetaConfig candidates", SCIRankedCandidates(SCIResolverDogKeywords(), 100));
    }
}

+ (NSString *)runMobileConfigSymbolReport {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString stringWithString:SCISymbolReport()];
        [out appendString:@"\nMobileConfig/EasyGating runtime-visible class candidates\n\n"];
        [out appendString:SCIFormatCandidates(@"Class candidates", SCIRankedCandidates(SCIResolverMCKeywords(), 80))];
        return out;
    }
}

+ (NSString *)runFullResolverReport {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendString:[self runDogfoodDeveloperReport]];
        [out appendString:@"\n\n==============================\n\n"];
        [out appendString:[self runMobileConfigSymbolReport]];
        return out;
    }
}

@end
