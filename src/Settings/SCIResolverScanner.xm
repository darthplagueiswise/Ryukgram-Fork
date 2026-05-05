#import "SCIResolverScanner.h"
#import "SCIResolverSpecifierEntry.h"
#import "../Features/ExpFlags/SCIExpFlags.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <stdio.h>

#pragma mark - Search keys

static NSArray<NSString *> *SCIDogKeys(void) {
    return @[
        @"dogfood", @"dogfooding", @"dogfooder", @"developer", @"internal",
        @"employee", @"override", @"eligibility", @"localexperiment", @"lidexperiment",
        @"fdidexperiment", @"metalocalexperiment", @"quicksnap", @"quick_snap", @"instants"
    ];
}

static NSArray<NSString *> *SCIMCKeys(void) {
    return @[
        @"mobileconfig", @"igmobileconfig", @"fbmobileconfig", @"mcimobileconfig",
        @"mciexperiment", @"metaextensionsexperiment", @"msgcsessionedmobileconfig",
        @"easygating", @"mcqeasygating", @"mcddasmnative", @"internaluse",
        @"donotuseormock", @"getbool", @"configmanager", @"parametertracker",
        @"quicksnap", @"quick_snap", @"instants"
    ];
}

static NSArray<NSString *> *SCISelectorKeys(void) {
    return @[
        @"open", @"config", @"userSession", @"deviceSession", @"logger", @"settings",
        @"section", @"item", @"row", @"builder", @"coordinator", @"route",
        @"developer", @"employee", @"dogfood", @"override", @"eligibility",
        @"quick", @"snap", @"instant", @"getBool", @"withDefault", @"withOptions",
        @"internal", @"mobileConfig", @"experiment", @"force", @"refresh"
    ];
}

static NSArray<NSString *> *SCIExactClasses(void) {
    return @[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController",
        @"IGDogfoodingFirst.DogfoodingFirstCoordinator",
        @"IGDogfoodingFirst.DogfoodingProductionLockoutViewController",
        @"IGDogfoodingSettingsConfig",
        @"IGDogfoodingSettingsItem",
        @"IGDogfoodingSettingsOptions",
        @"IGDogfoodingSettingsOptionsMatcher",
        @"IGDogfoodingSettingsSection",
        @"IGDogfoodingOverride",
        @"IGDogfooderProd",
        @"IGDogfoodingLogger",
        @"DogfoodingEligibilityQueryBuilder",
        @"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs",
        @"MetaLocalExperiment",
        @"FamilyLocalExperiment",
        @"LIDLocalExperiment",
        @"LIDExperimentGenerator",
        @"FDIDExperimentGenerator",
        @"MetaLocalExperimentListViewController",
        @"MetaLocalExperimentDetailViewController",
        @"IGMobileConfigContextManager",
        @"IGMobileConfigUserSessionContextManager",
        @"IGMobileConfigSessionlessContextManager",
        @"FBMobileConfigContextManager"
    ];
}

#pragma mark - Coverage model

static NSArray<NSDictionary *> *SCIFunctionCoverageRows(void) {
    return @[
        @{
            @"name": @"IGMobileConfigBooleanValueForInternalUse",
            @"symbol": @"IGMobileConfigBooleanValueForInternalUse",
            @"family": @"IG MobileConfig InternalUse",
            @"hook": @"InternalModeHooks.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"ctx=x0 default=w1 specifier=x2",
            @"notes": @"Known signature; per-specifier override supported."
        },
        @{
            @"name": @"IGMobileConfigSessionlessBooleanValueForInternalUse",
            @"symbol": @"IGMobileConfigSessionlessBooleanValueForInternalUse",
            @"family": @"IG MobileConfig InternalUse",
            @"hook": @"InternalModeHooks.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"ctx=x0 default=w1 specifier=x2",
            @"notes": @"Known signature; per-specifier override supported."
        },
        @{
            @"name": @"MCIMobileConfigGetBoolean",
            @"symbol": @"MCIMobileConfigGetBoolean",
            @"family": @"MCI MobileConfig",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"preferred specifier=x2",
            @"notes": @"Generic bool-return hook; records observed callsites."
        },
        @{
            @"name": @"MCIExperimentCacheGetMobileConfigBoolean",
            @"symbol": @"MCIExperimentCacheGetMobileConfigBoolean",
            @"family": @"MCI Experiment Cache",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"preferred specifier=x2",
            @"notes": @"Generic bool-return hook; records observed callsites."
        },
        @{
            @"name": @"MCIExtensionExperimentCacheGetMobileConfigBoolean",
            @"symbol": @"MCIExtensionExperimentCacheGetMobileConfigBoolean",
            @"family": @"MCI Extension Cache",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"preferred specifier=x2",
            @"notes": @"Generic bool-return hook; records observed callsites."
        },
        @{
            @"name": @"METAExtensionsExperimentGetBoolean",
            @"symbol": @"METAExtensionsExperimentGetBoolean",
            @"family": @"META Extensions Experiment",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"preferred gate=x1 exposure=w4=1",
            @"notes": @"Exported wrapper; internal dispatcher sets exposure logging."
        },
        @{
            @"name": @"METAExtensionsExperimentGetBooleanWithoutExposure",
            @"symbol": @"METAExtensionsExperimentGetBooleanWithoutExposure",
            @"family": @"META Extensions Experiment",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"preferred gate=x1 exposure=w4=0",
            @"notes": @"Exported wrapper; no exposure logging path."
        },
        @{
            @"name": @"MSGCSessionedMobileConfigGetBoolean",
            @"symbol": @"MSGCSessionedMobileConfigGetBoolean",
            @"family": @"MSGC Sessioned MobileConfig",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"preferred gate=x1",
            @"notes": @"Session-aware bool-return hook."
        },
        @{
            @"name": @"EasyGatingPlatformGetBoolean",
            @"symbol": @"EasyGatingPlatformGetBoolean",
            @"family": @"EasyGating",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"preferred gate=x1",
            @"notes": @"Raw gate id may not look like IG MobileConfig specifier."
        },
        @{
            @"name": @"EasyGatingGetBoolean_Internal_DoNotUseOrMock",
            @"symbol": @"EasyGatingGetBoolean_Internal_DoNotUseOrMock",
            @"family": @"EasyGating",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"gate=x0 default=x2",
            @"notes": @"Raw gate id path."
        },
        @{
            @"name": @"EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
            @"symbol": @"EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock",
            @"family": @"EasyGating AuthDataContext",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"gate=x1 default=x2 authDataContext=x3",
            @"notes": @"Auth-data aware raw gate path."
        },
        @{
            @"name": @"MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
            @"symbol": @"MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
            @"family": @"MCQ EasyGating",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"force via out pointer",
            @"safe": @"PARTIAL",
            @"arg": @"gate=w1 default=x3 result=*x4",
            @"notes": @"Preserve status return; force only outValue."
        },
        @{
            @"name": @"MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",
            @"symbol": @"MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter",
            @"family": @"DASM/DVM Adapter",
            @"hook": @"InternalGateObservers.xm",
            @"mode": @"observe-only",
            @"safe": @"NO_DIRECT_FORCE",
            @"arg": @"VM stack adapter",
            @"notes": @"Uses DVM/DASM support stack; direct BOOL return forcing is unsafe."
        },
        @{
            @"name": @"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
            @"symbol": @"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
            @"family": @"Internal Apps Detection",
            @"hook": @"InternalModeHooks.xm",
            @"mode": @"forceable",
            @"safe": @"YES",
            @"arg": @"void -> BOOL",
            @"notes": @"Controlled by internal apps spoof/gate."
        }
    ];
}

#pragma mark - Runtime helpers

static NSString *SCIClassName(Class cls) {
    if (!cls) return @"(nil)";
    const char *n = class_getName(cls);
    return n ? [NSString stringWithUTF8String:n] : @"(unknown)";
}

static NSString *SCIImageName(Class cls) {
    const char *n = cls ? class_getImageName(cls) : NULL;
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

static BOOL SCIIsVC(Class cls) {
    Class vc = UIViewController.class;
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        if (c == vc) return YES;
    }
    return NO;
}

static NSArray<NSString *> *SCIMethods(Class cls, BOOL meta, NSUInteger max) {
    if (!cls) return @[];
    NSMutableArray *out = [NSMutableArray array];
    Class scan = meta ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(scan, &count);
    if (methods) {
        for (unsigned int i = 0; i < count; i++) {
            SEL sel = method_getName(methods[i]);
            const char *cs = sel ? sel_getName(sel) : NULL;
            if (!cs) continue;
            NSString *name = [NSString stringWithUTF8String:cs];
            if (!SCIContainsAny(name, SCISelectorKeys())) continue;
            const char *ct = method_getTypeEncoding(methods[i]);
            NSString *type = ct ? [NSString stringWithUTF8String:ct] : @"";
            [out addObject:[NSString stringWithFormat:@"%@%@ types=%@", meta ? @"+" : @"-", name, type]];
            if (max && out.count >= max) break;
        }
        free(methods);
    }
    return out;
}

static NSArray<NSString *> *SCIIvars(Class cls, NSUInteger max) {
    if (!cls) return @[];
    NSMutableArray *out = [NSMutableArray array];
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    if (ivars) {
        for (unsigned int i = 0; i < count; i++) {
            const char *cn = ivar_getName(ivars[i]);
            const char *ct = ivar_getTypeEncoding(ivars[i]);
            NSString *name = cn ? [NSString stringWithUTF8String:cn] : @"";
            NSString *type = ct ? [NSString stringWithUTF8String:ct] : @"";
            NSString *joined = [NSString stringWithFormat:@"%@ %@", name, type];
            if (!SCIContainsAny(joined, SCISelectorKeys())) continue;
            [out addObject:[NSString stringWithFormat:@"%@ type=%@", name, type]];
            if (max && out.count >= max) break;
        }
        free(ivars);
    }
    return out;
}

static NSDictionary *SCIDict(Class cls, NSArray *keys) {
    NSArray *im = SCIMethods(cls, NO, 18);
    NSArray *cm = SCIMethods(cls, YES, 18);
    NSArray *iv = SCIIvars(cls, 14);
    NSString *name = SCIClassName(cls);
    NSInteger score = 0;
    if (SCIContainsAny(name, keys)) score += 60;
    score += MIN(72, (NSInteger)(im.count + cm.count) * 8);
    score += MIN(32, (NSInteger)iv.count * 4);
    if (SCIIsVC(cls)) score += 20;
    if ([name containsString:@"Settings"] || [name containsString:@"Controller"] || [name containsString:@"Coordinator"] || [name containsString:@"Helper"]) score += 10;
    return @{
        @"score": @(score),
        @"name": name,
        @"super": SCIClassName(class_getSuperclass(cls)),
        @"image": SCIImageName(cls),
        @"vc": @(SCIIsVC(cls)),
        @"methods": [cm arrayByAddingObjectsFromArray:im] ?: @[],
        @"ivars": iv ?: @[]
    };
}

static NSArray<NSDictionary *> *SCIRankedCandidates(NSArray<NSString *> *keys, NSUInteger limit) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return @[];
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    if (!classes) return @[];
    count = objc_getClassList(classes, count);

    NSMutableArray *results = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];

    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *name = SCIClassName(cls);
        if (!SCIContainsAny(name, keys)) continue;
        if ([seen containsObject:name]) continue;
        [seen addObject:name];
        [results addObject:SCIDict(cls, keys)];
    }
    free(classes);

    [results sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger sa = [a[@"score"] integerValue];
        NSInteger sb = [b[@"score"] integerValue];
        if (sa > sb) return NSOrderedAscending;
        if (sa < sb) return NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"]];
    }];
    if (limit && results.count > limit) {
        return [results subarrayWithRange:NSMakeRange(0, limit)];
    }
    return results;
}

static void *SCIDlsymFlexible(NSString *sym) {
    if (!sym.length) return NULL;
    void *p = dlsym(RTLD_DEFAULT, sym.UTF8String);
    if (p) return p;
    if ([sym hasPrefix:@"_"]) return dlsym(RTLD_DEFAULT, [sym substringFromIndex:1].UTF8String);
    return dlsym(RTLD_DEFAULT, [[@"_" stringByAppendingString:sym] UTF8String]);
}

static BOOL SCILooksLikeMCSpecifier(unsigned long long spec) {
    return spec != 0 && ((spec >> 56) == 0) && ((spec >> 48) != 0);
}

#pragma mark - Report formatting

static NSString *SCIExactClassReport(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"Exact class check\nmode = bounded exact-class inspection\n\n"];
    for (NSString *name in SCIExactClasses()) {
        Class cls = NSClassFromString(name) ?: objc_getClass(name.UTF8String);
        [out appendFormat:@"%@ · %@\n", cls ? @"FOUND" : @"missing", name];
        if (!cls) continue;
        [out appendFormat:@"  super=%@ UIViewController=%@ image=%@\n", SCIClassName(class_getSuperclass(cls)), SCIIsVC(cls) ? @"YES" : @"NO", SCIImageName(cls)];
        for (NSString *m in SCIMethods(cls, YES, 24)) [out appendFormat:@"  %@\n", m];
        for (NSString *m in SCIMethods(cls, NO, 24)) [out appendFormat:@"  %@\n", m];
        for (NSString *v in SCIIvars(cls, 16)) [out appendFormat:@"  ivar %@\n", v];
    }
    return out;
}

static NSString *SCIFunctionCoverageReport(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"Function coverage matrix\nmode = dlsym + hook coverage map\n\n"];
    for (NSDictionary *row in SCIFunctionCoverageRows()) {
        NSString *symbol = row[@"symbol"];
        void *addr = SCIDlsymFlexible(symbol);
        [out appendFormat:@"%@ · %@ · %@\n", addr ? @"FOUND" : @"missing", row[@"name"], addr ? [NSString stringWithFormat:@"%p", addr] : @"0x0"];
        [out appendFormat:@"  family=%@\n", row[@"family"]];
        [out appendFormat:@"  hook=%@ mode=%@ safeForce=%@\n", row[@"hook"], row[@"mode"], row[@"safe"]];
        [out appendFormat:@"  args=%@\n", row[@"arg"]];
        [out appendFormat:@"  notes=%@\n", row[@"notes"]];
    }
    return out;
}

static NSString *SCISymbolAvailabilityReport(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"MobileConfig / QuickSnap symbol availability\nmode = dlsym(RTLD_DEFAULT), flexible underscore handling\n\n"];
    for (NSDictionary *row in SCIFunctionCoverageRows()) {
        NSString *sym = row[@"symbol"];
        void *addr = SCIDlsymFlexible(sym);
        [out appendFormat:@"%@ · _%@ · %p\n", addr ? @"FOUND" : @"missing", sym, addr];
    }

    NSArray *dataSymbols = @[
        @"ig_is_employee", @"ig_is_employee_or_test_user", @"ig_dogfooding_first_client", @"xav_switcher_ig_ios_test_user_check_fdid",
        @"ig_ios_home_coming_is_dogfooding_option_enabled",
        @"ig_ios_quick_snap", @"ig_ios_quick_snap_nux_v2", @"ig_ios_quicksnap_navigation_v3", @"ig_ios_quicksnap_consumption_v2",
        @"ig_ios_quicksnap_consumption_stack_improvements", @"ig_ios_instants_widget", @"ig_instants_hide"
    ];
    [out appendString:@"\nKnown data specifier symbols\n\n"];
    for (NSString *sym in dataSymbols) {
        void *addr = SCIDlsymFlexible(sym);
        [out appendFormat:@"%@ · _%@ · %p\n", addr ? @"FOUND" : @"missing", sym, addr];
    }
    return out;
}

static NSString *SCIRuntimeObservationReport(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"Runtime observed gates\nmode = merged from SCIExpFlags live InternalUse observations\n\n"];
    NSArray<SCIExpInternalUseObservation *> *obs = [SCIExpFlags allInternalUseObservations];
    if (!obs.count) {
        [out appendString:@"No runtime gates observed yet. Enable Flags Browser or Verbose Gate Logging, browse IG, then reopen this report.\n"];
        return out;
    }
    for (SCIExpInternalUseObservation *o in obs) {
        SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:o.specifier];
        NSString *ovStr = ov == SCIExpFlagOverrideTrue ? @"FORCED ON" : ov == SCIExpFlagOverrideFalse ? @"FORCED OFF" : @"no override";
        [out appendFormat:@"%@ · %@ · spec=0x%016llx\n", o.functionName ?: @"Gate", o.specifierName ?: @"unknown", o.specifier];
        [out appendFormat:@"  default=%d result=%d forced=%d hits=%lu recent=%lu override=%@\n", o.defaultValue, o.resultValue, o.forcedValue, (unsigned long)o.hitCount, (unsigned long)o.lastSeenOrder, ovStr];
        if (o.callerDescription.length) [out appendFormat:@"  caller=%@\n", o.callerDescription];
    }
    return out;
}

static NSString *SCIFormatCandidates(NSString *title, NSArray<NSDictionary *> *candidates) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"%@\nmode = focused runtime class scan; name-filtered before method/ivar inspection\n\ncandidateCount=%lu\n\n", title, (unsigned long)candidates.count];
    NSUInteger i = 1;
    for (NSDictionary *e in candidates) {
        [out appendFormat:@"%lu. score=%@ %@\n", (unsigned long)i++, e[@"score"], e[@"name"]];
        [out appendFormat:@"   super=%@ UIViewController=%@\n", e[@"super"], [e[@"vc"] boolValue] ? @"YES" : @"NO"];
        [out appendFormat:@"   image=%@\n", e[@"image"]];
        for (NSString *m in e[@"methods"]) [out appendFormat:@"   %@\n", m];
        for (NSString *v in e[@"ivars"]) [out appendFormat:@"   ivar %@\n", v];
        [out appendString:@"\n"];
    }
    return out;
}

#pragma mark - Entry builder

static void SCIAddEntry(NSMutableDictionary<NSNumber *, SCIResolverSpecifierEntry *> *map,
                        unsigned long long spec,
                        NSString *name,
                        NSString *src,
                        BOOL suggested) {
    if (!spec) return;
    SCIResolverSpecifierEntry *e = [SCIResolverSpecifierEntry new];
    e.specifier = spec;
    e.name = name.length ? name : [NSString stringWithFormat:@"unknown 0x%016llx", spec];
    e.source = src.length ? src : @"resolver";
    e.suggestedValue = suggested;

    SCIResolverSpecifierEntry *existing = map[@(spec)];
    if (existing) {
        BOOL existingIsUnknown = !existing.name.length || [existing.name.lowercaseString containsString:@"unknown"];
        BOOL newIsKnown = e.name.length && ![e.name.lowercaseString containsString:@"unknown"];
        if (existingIsUnknown && newIsKnown) {
            map[@(spec)] = e;
        } else {
            NSString *mergedSource = [NSString stringWithFormat:@"%@ + %@", existing.source ?: @"", e.source ?: @""];
            existing.source = mergedSource;
        }
        return;
    }
    map[@(spec)] = e;
}

static void SCIAddSpecifierSymbol(NSMutableDictionary<NSNumber *, SCIResolverSpecifierEntry *> *map,
                                  const char *symbol,
                                  NSString *label,
                                  NSUInteger count,
                                  BOOL suggested) {
    unsigned long long *values = (unsigned long long *)dlsym(RTLD_DEFAULT, symbol);
    if (!values) {
        char underscored[256];
        snprintf(underscored, sizeof(underscored), "_%s", symbol);
        values = (unsigned long long *)dlsym(RTLD_DEFAULT, underscored);
    }
    if (!values) return;
    for (NSUInteger i = 0; i < count; i++) {
        unsigned long long spec = values[i];
        if (!SCILooksLikeMCSpecifier(spec)) continue;
        NSString *name = count > 1 ? [NSString stringWithFormat:@"%@[%lu]", label, (unsigned long)i] : label;
        SCIAddEntry(map, spec, name, @"dlsym data symbol", suggested);
    }
}

@implementation SCIResolverScanner

+ (NSArray<SCIResolverSpecifierEntry *> *)allKnownSpecifierEntries {
    NSMutableDictionary<NSNumber *, SCIResolverSpecifierEntry *> *map = [NSMutableDictionary dictionary];

    // Basic Employee / dogfood gates.
    SCIAddSpecifierSymbol(map, "ig_is_employee", @"ig_is_employee", 2, YES);
    SCIAddSpecifierSymbol(map, "ig_is_employee_or_test_user", @"ig_is_employee_or_test_user", 1, YES);
    SCIAddSpecifierSymbol(map, "xav_switcher_ig_ios_test_user_check_fdid", @"xav_switcher_ig_ios_test_user_check_fdid", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_dogfooding_first_client", @"ig_dogfooding_first_client", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_home_coming_is_dogfooding_option_enabled", @"ig_ios_home_coming_is_dogfooding_option_enabled", 1, YES);

    // QuickSnap / Instants data specifier groups.
    SCIAddSpecifierSymbol(map, "ig_instants_hide", @"ig_instants_hide", 1, NO);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap", @"ig_ios_quick_snap", 34, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_nux_v2", @"ig_ios_quick_snap_nux_v2", 7, YES);
    SCIAddSpecifierSymbol(map, "ig_quick_snap_show_peek_in_view_did_appear", @"ig_quick_snap_show_peek_in_view_did_appear", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_app_joiner_number", @"ig_ios_quick_snap_app_joiner_number", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_audience", @"ig_ios_quick_snap_audience", 5, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_burst_photos", @"ig_ios_quick_snap_burst_photos", 4, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_camera_capture_animation", @"ig_ios_quick_snap_camera_capture_animation", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_classification", @"ig_ios_quick_snap_classification", 3, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_extend_expiration", @"ig_ios_quick_snap_extend_expiration", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_gallery_send", @"ig_ios_quick_snap_gallery_send", 2, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_moods", @"ig_ios_quick_snap_moods", 6, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_new_audience_picker", @"ig_ios_quick_snap_new_audience_picker", 3, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quick_snap_new_zoom_animation", @"ig_ios_quick_snap_new_zoom_animation", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_archive", @"ig_ios_quicksnap_archive", 6, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_audience_picker", @"ig_ios_quicksnap_audience_picker", 3, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_cache_instants", @"ig_ios_quicksnap_cache_instants", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_consumption_button", @"ig_ios_quicksnap_consumption_button", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_consumption_stack_improvements", @"ig_ios_quicksnap_consumption_stack_improvements", 19, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_consumption_v2", @"ig_ios_quicksnap_consumption_v2", 9, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_craft_improvements", @"ig_ios_quicksnap_craft_improvements", 2, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_creation_preview", @"ig_ios_quicksnap_creation_preview", 2, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_dual_camera", @"ig_ios_quicksnap_dual_camera", 4, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_gtm", @"ig_ios_quicksnap_gtm", 5, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_navigation_v3", @"ig_ios_quicksnap_navigation_v3", 9, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_perf_improvements", @"ig_ios_quicksnap_perf_improvements", 7, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_profile", @"ig_ios_quicksnap_profile", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_recap_improvements", @"ig_ios_quicksnap_recap_improvements", 6, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_story_deletion", @"ig_ios_quicksnap_story_deletion", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_undo_toast", @"ig_ios_quicksnap_undo_toast", 2, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_valentines_activation", @"ig_ios_quicksnap_valentines_activation", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_quicksnap_wearables", @"ig_ios_quicksnap_wearables", 2, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_instants_infinite_archive", @"ig_ios_instants_infinite_archive", 2, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_instants_tagging", @"ig_ios_instants_tagging", 1, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_instants_to_stories_recap", @"ig_ios_instants_to_stories_recap", 4, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_instants_upleveling_reactions", @"ig_ios_instants_upleveling_reactions", 3, YES);
    SCIAddSpecifierSymbol(map, "ig_ios_instants_widget", @"ig_ios_instants_widget", 2, YES);

    // Stable fallbacks for current FBSharedFramework builds.
    SCIAddEntry(map, 0x0081030f00000a95ULL, @"ig_is_employee[0]", @"hardcoded fallback", YES);
    SCIAddEntry(map, 0x0081030f00010a96ULL, @"ig_is_employee[1]", @"hardcoded fallback", YES);
    SCIAddEntry(map, 0x008100b200000161ULL, @"ig_is_employee_or_test_user", @"hardcoded fallback", YES);

    // Merge runtime-observed gates from the Experimental Flags Browser pipeline.
    // This is what makes SCI Resolver cover names discovered only after browsing the app.
    for (SCIExpInternalUseObservation *o in [SCIExpFlags allInternalUseObservations]) {
        if (!o.specifier) continue;
        NSString *name = o.specifierName.length ? o.specifierName : [NSString stringWithFormat:@"%@ 0x%016llx", o.functionName ?: @"runtime gate", o.specifier];
        NSString *source = [NSString stringWithFormat:@"runtime %@ ×%lu", o.functionName ?: @"Gate", (unsigned long)o.hitCount];
        SCIAddEntry(map, o.specifier, name, source, o.resultValue);
    }

    // Preserve manual overrides even if the gate has not appeared in runtime observations yet.
    for (NSNumber *n in [SCIExpFlags allOverriddenInternalUseSpecifiers]) {
        unsigned long long spec = n.unsignedLongLongValue;
        SCIExpFlagOverride ov = [SCIExpFlags internalUseOverrideForSpecifier:spec];
        NSString *name = [NSString stringWithFormat:@"manual override 0x%016llx", spec];
        SCIAddEntry(map, spec, name, @"manual override", ov != SCIExpFlagOverrideFalse);
    }

    NSArray *entries = [[map allValues] sortedArrayUsingComparator:^NSComparisonResult(SCIResolverSpecifierEntry *a, SCIResolverSpecifierEntry *b) {
        NSString *as = a.source ?: @"";
        NSString *bs = b.source ?: @"";
        BOOL ar = [as containsString:@"runtime"];
        BOOL br = [bs containsString:@"runtime"];
        if (ar != br) return ar ? NSOrderedAscending : NSOrderedDescending;
        return [a.name compare:b.name];
    }];
    return entries;
}

+ (void *)findPattern:(NSString *)patternMask inSegment:(NSString *)segmentName {
    NSArray<NSString *> *components = [patternMask componentsSeparatedByString:@" "];
    NSUInteger patternLength = components.count;
    if (patternLength == 0) return NULL;

    uint8_t *pattern = (uint8_t *)malloc(patternLength);
    BOOL *mask = (BOOL *)malloc(patternLength);
    if (!pattern || !mask) {
        if (pattern) free(pattern);
        if (mask) free(mask);
        return NULL;
    }

    for (NSUInteger i = 0; i < patternLength; i++) {
        NSString *comp = components[i];
        if ([comp isEqualToString:@"??"]) {
            pattern[i] = 0;
            mask[i] = NO;
        } else {
            unsigned int val = 0;
            NSScanner *scanner = [NSScanner scannerWithString:comp];
            [scanner scanHexInt:&val];
            pattern[i] = (uint8_t)val;
            mask[i] = YES;
        }
    }

    void *foundAddress = NULL;
    uint32_t imageCount = _dyld_image_count();

    for (uint32_t i = 0; i < imageCount; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (!imageName) continue;
        NSString *imageNameStr = [NSString stringWithUTF8String:imageName];
        if (![imageNameStr containsString:@"Instagram"] && ![imageNameStr containsString:@"FBSharedFramework"]) continue;

        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64) continue;

        unsigned long size = 0;
        uint8_t *data = getsectiondata(header, "__TEXT", segmentName.UTF8String, &size);
        if (!data || size < patternLength) continue;

        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        uint8_t *searchBase = data + slide;

        for (unsigned long j = 0; j <= size - patternLength; j++) {
            BOOL match = YES;
            for (NSUInteger k = 0; k < patternLength; k++) {
                if (mask[k] && searchBase[j + k] != pattern[k]) {
                    match = NO;
                    break;
                }
            }
            if (match) {
                foundAddress = searchBase + j;
                break;
            }
        }
        if (foundAddress) break;
    }

    free(pattern);
    free(mask);
    return foundAddress;
}

+ (void *)findMobileConfigFunctionAddress {
    void *p = SCIDlsymFlexible(@"IGMobileConfigBooleanValueForInternalUse");
    if (p) return p;
    NSString *pattern = @"ff 43 01 d1 fd 7b 01 a9 fd 43 00 91 ?? ?? ?? ?? ?? ?? ?? ??";
    return [self findPattern:pattern inSegment:@"__text"];
}

+ (NSString *)runDogfoodDeveloperReport {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendString:SCIExactClassReport()];
        [out appendString:@"\n==============================\n\n"];
        [out appendString:SCIFormatCandidates(@"SCI Resolver — Dogfood / Developer / MetaConfig candidates", SCIRankedCandidates(SCIDogKeys(), 220))];
        return out;
    }
}

+ (NSString *)runMobileConfigSymbolReport {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendString:SCIFunctionCoverageReport()];
        [out appendString:@"\n==============================\n\n"];
        [out appendString:SCISymbolAvailabilityReport()];
        [out appendString:@"\n==============================\n\n"];
        [out appendString:SCIRuntimeObservationReport()];
        [out appendString:@"\n==============================\n\n"];
        [out appendString:SCIFormatCandidates(@"MobileConfig/EasyGating runtime-visible class candidates", SCIRankedCandidates(SCIMCKeys(), 260))];
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

+ (void)applyOverrideForSpecifier:(unsigned long long)specifier value:(BOOL)value {
    [SCIExpFlags setInternalUseOverride:(value ? SCIExpFlagOverrideTrue : SCIExpFlagOverrideFalse) forSpecifier:specifier];
}

+ (BOOL)applyOverrideForSpecifier:(unsigned long long)specifier defaultValue:(BOOL)defaultValue {
    SCIExpFlagOverride o = [SCIExpFlags internalUseOverrideForSpecifier:specifier];
    if (o == SCIExpFlagOverrideTrue) return YES;
    if (o == SCIExpFlagOverrideFalse) return NO;
    return defaultValue;
}

+ (void)removeOverrideForSpecifier:(unsigned long long)specifier {
    [SCIExpFlags setInternalUseOverride:SCIExpFlagOverrideOff forSpecifier:specifier];
}

+ (NSDictionary<NSNumber *, NSNumber *> *)allResolverOverrides {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSNumber *spec in [SCIExpFlags allOverriddenInternalUseSpecifiers]) {
        SCIExpFlagOverride o = [SCIExpFlags internalUseOverrideForSpecifier:spec.unsignedLongLongValue];
        if (o == SCIExpFlagOverrideTrue) out[spec] = @YES;
        else if (o == SCIExpFlagOverrideFalse) out[spec] = @NO;
    }
    return out;
}

+ (void)clearAllResolverOverrides {
    [SCIExpFlags resetAllInternalUseOverrides];
}

@end
