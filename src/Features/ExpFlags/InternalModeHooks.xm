#import "../../Utils.h"
#import "SCIExpFlags.h"
#import "SCIExpMobileConfigDebug.h"
#import "SCIExpMobileConfigMapping.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>
#include "../../../modules/fishhook/fishhook.h"

static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL; // ig_is_employee_or_test_user

static BOOL rgEmployeeMasterEnabled(void) { return [SCIUtils getBoolPref:@"igt_employee"] || [SCIUtils getBoolPref:@"igt_employee_devoptions_gate"]; }
static BOOL rgEmployeeMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_mc"]; }
static BOOL rgEmployeeOrTestUserMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"]; }
static BOOL rgInternalObserverEnabled(void) { return [SCIUtils getBoolPref:@"igt_internaluse_observer"]; }

static BOOL rgHasManualInternalUseOverrides(void) { return [SCIExpFlags allOverriddenInternalUseSpecifiers].count > 0; }

static BOOL rgShouldInstallInternalModeHooks(void) {
    return rgEmployeeMasterEnabled() ||
           rgEmployeeMCEnabled() ||
           rgEmployeeOrTestUserMCEnabled() ||
           [SCIUtils getBoolPref:@"igt_internal_apps_gate"] ||
           rgInternalObserverEnabled() ||
           rgHasManualInternalUseOverrides();
}

static void *rgDLSym(const char *symbol) {
    if (!symbol || !symbol[0]) return NULL;
    void *p = dlsym(RTLD_DEFAULT, symbol);
    if (p) return p;
    char underscored[256];
    snprintf(underscored, sizeof(underscored), "_%s", symbol);
    return dlsym(RTLD_DEFAULT, underscored);
}

static BOOL rgLooksLikeMCSpecifier(unsigned long long v) {
    return v != 0 && ((v >> 56) == 0) && ((v >> 48) != 0);
}

static void rgAddMCSpecifierSymbol(NSMutableDictionary<NSNumber *, NSString *> *map,
                                   const char *symbol,
                                   NSString *label,
                                   NSUInteger count) {
    unsigned long long *values = (unsigned long long *)rgDLSym(symbol);
    if (!values) return;
    for (NSUInteger i = 0; i < count; i++) {
        unsigned long long spec = values[i];
        if (!rgLooksLikeMCSpecifier(spec)) continue;
        NSString *name = count > 1 ? [NSString stringWithFormat:@"%@[%lu]", label, (unsigned long)i] : label;
        map[@(spec)] = name;
    }
}

static NSDictionary<NSNumber *, NSString *> *rgKnownInternalUseSpecifierMap(void) {
    static NSDictionary<NSNumber *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSNumber *, NSString *> *m = [NSMutableDictionary dictionary];

        // Exported MC param symbols found in FBSharedFramework(22) by static strings/symbol-name scan.
        // These are the iOS equivalent of the Android/DexKit "golden anchors": resolve the named
        // specifier arrays first, then force only those InternalUse calls when the Employee/DevOptions
        // gate is enabled. Do not globally force every MobileConfig boolean.
        rgAddMCSpecifierSymbol(m, "ig_is_employee", @"ig_is_employee", 2);
        rgAddMCSpecifierSymbol(m, "ig_is_employee_or_test_user", @"ig_is_employee_or_test_user", 1);
        rgAddMCSpecifierSymbol(m, "xav_switcher_ig_ios_test_user_check_fdid", @"xav_switcher_ig_ios_test_user_check_fdid", 1);
        rgAddMCSpecifierSymbol(m, "ig_dogfooding_first_client", @"ig_dogfooding_first_client", 1);
        rgAddMCSpecifierSymbol(m, "ig_ios_home_coming_is_dogfooding_option_enabled", @"ig_ios_home_coming_is_dogfooding_option_enabled", 1);

        // Hard fallback for the current FBSharedFramework build, in case dlsym does not expose
        // the data symbols in a sideloaded image.
        m[@(kIGMCEmployeeSpecifierA)] = @"ig_is_employee[0]";
        m[@(kIGMCEmployeeSpecifierB)] = @"ig_is_employee[1]";
        m[@(kIGMCEmployeeOrTestUserSpecifier)] = @"ig_is_employee_or_test_user";
        map = [m copy];
    });
    return map;
}

static NSString *rgKnownSpecifierName(unsigned long long specifier) {
    return rgKnownInternalUseSpecifierMap()[@(specifier)];
}

static BOOL rgKnownNameLooksLikeEmployeeGate(NSString *name) {
    NSString *n = name.lowercaseString ?: @"";
    return [n containsString:@"employee"] ||
           [n containsString:@"test_user"] ||
           [n containsString:@"dogfood"] ||
           [n containsString:@"dogfooding"] ||
           [n containsString:@"xav_switcher"] ||
           [n containsString:@"developer"] ||
           [n containsString:@"internalsettings"];
}

static BOOL specifierMatchesEmployee(unsigned long long specifier) {
    NSString *known = rgKnownSpecifierName(specifier);
    if (rgEmployeeMasterEnabled() && rgKnownNameLooksLikeEmployeeGate(known)) return YES;
    if ((specifier == kIGMCEmployeeSpecifierA || specifier == kIGMCEmployeeSpecifierB) && rgEmployeeMCEnabled()) return YES;
    if (specifier == kIGMCEmployeeOrTestUserSpecifier && rgEmployeeOrTestUserMCEnabled()) return YES;
    if ([known containsString:@"ig_is_employee"] && rgEmployeeMCEnabled()) return YES;
    if ([known containsString:@"ig_is_employee_or_test_user"] && rgEmployeeOrTestUserMCEnabled()) return YES;
    return NO;
}

static NSString *specifierName(unsigned long long specifier) {
    NSString *known = rgKnownSpecifierName(specifier);
    if (known.length) return known;
    if (specifier == kIGMCEmployeeSpecifierA || specifier == kIGMCEmployeeSpecifierB) return @"ig_is_employee";
    if (specifier == kIGMCEmployeeOrTestUserSpecifier) return @"ig_is_employee_or_test_user";
    return @"unknown";
}

static NSString *rgTrimmedUsefulString(id obj) {
    if (!obj) return nil;
    NSString *s = nil;
    if ([obj isKindOfClass:[NSString class]]) s = (NSString *)obj;
    else if ([obj respondsToSelector:@selector(description)]) s = [obj description];
    if (!s.length) return nil;
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length || [s isEqualToString:@"(null)"] || [s isEqualToString:@"null"] || [s isEqualToString:@"0"]) return nil;
    return s;
}

static NSString *rgCallStringForSpecifier(id target, NSString *selectorName, unsigned long long specifier) {
    if (!target || !selectorName.length) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return nil;
    @try {
        id (*send)(id, SEL, unsigned long long) = (id (*)(id, SEL, unsigned long long))objc_msgSend;
        return rgTrimmedUsefulString(send(target, sel, specifier));
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static unsigned long long rgCallUInt64ForSpecifier(id target, NSString *selectorName, unsigned long long specifier) {
    if (!target || !selectorName.length) return 0;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return 0;
    @try {
        unsigned long long (*send)(id, SEL, unsigned long long) = (unsigned long long (*)(id, SEL, unsigned long long))objc_msgSend;
        return send(target, sel, specifier);
    } @catch (__unused NSException *e) {
        return 0;
    }
}

static NSString *rgResolveWithMappingFile(unsigned long long specifier) {
    NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:specifier];
    if (mapped.length) return mapped;
    return nil;
}

static NSString *rgResolveSpecifierName(id ctx, unsigned long long specifier) {
    NSString *hardcoded = specifierName(specifier);
    if (![hardcoded isEqualToString:@"unknown"]) return hardcoded;

    NSString *mapped = rgResolveWithMappingFile(specifier);
    if (mapped.length) return mapped;

    NSString *stable = rgCallStringForSpecifier(ctx, @"getStableIdFromParamSpecifier:", specifier);
    if (stable.length) return stable;

    NSString *latestLogging = rgCallStringForSpecifier(ctx, @"getLatestLoggingID:", specifier);
    if (latestLogging.length) return [@"loggingID:" stringByAppendingString:latestLogging];

    NSString *logging = rgCallStringForSpecifier(ctx, @"getLoggingID:", specifier);
    if (logging.length) return [@"loggingID:" stringByAppendingString:logging];

    unsigned long long translated = rgCallUInt64ForSpecifier(ctx, @"getTranslatedSpecifier:", specifier);
    if (!translated) translated = rgCallUInt64ForSpecifier(ctx, @"_getTranslatedSpecifier:", specifier);
    if (translated && translated != specifier) {
        NSString *translatedName = rgResolveWithMappingFile(translated);
        if (translatedName.length) return [NSString stringWithFormat:@"%@ (translated 0x%016llx)", translatedName, translated];
        NSString *stableTranslated = rgCallStringForSpecifier(ctx, @"getStableIdFromParamSpecifier:", translated);
        if (stableTranslated.length) return [NSString stringWithFormat:@"%@ (translated 0x%016llx)", stableTranslated, translated];
    }

    return @"unknown";
}

static BOOL applyInternalUseOverride(unsigned long long specifier, BOOL original) {
    SCIExpFlagOverride manual = [SCIExpFlags internalUseOverrideForSpecifier:specifier];
    if (manual == SCIExpFlagOverrideTrue) return YES;
    if (manual == SCIExpFlagOverrideFalse) return NO;
    if (specifierMatchesEmployee(specifier)) return YES;
    return original;
}

static void recordInternalUseSpecifier(id ctx, NSString *funcName, unsigned long long specifier, BOOL defaultValue, BOOL originalValue, BOOL returnedValue, void *callerAddress) {
    BOOL forced = (returnedValue != originalValue);
    BOOL shouldRecord = rgInternalObserverEnabled() || forced || specifierMatchesEmployee(specifier) || [SCIExpFlags internalUseOverrideForSpecifier:specifier] != SCIExpFlagOverrideOff;
    if (!shouldRecord) return;

    NSString *name = rgResolveSpecifierName(ctx, specifier);
    [SCIExpFlags recordInternalUseSpecifier:specifier
                               functionName:funcName
                              specifierName:name
                               defaultValue:defaultValue
                                resultValue:returnedValue
                                forcedValue:forced
                              callerAddress:callerAddress];

    if (rgInternalObserverEnabled()) {
        NSLog(@"[RyukGram][MC][%@] spec=0x%016llx (%@) default=%d original=%d returned=%d forced=%d employeeMatch=%d manual=%ld caller=%p",
              funcName,
              specifier,
              name,
              defaultValue,
              originalValue,
              returnedValue,
              forced,
              specifierMatchesEmployee(specifier),
              (long)[SCIExpFlags internalUseOverrideForSpecifier:specifier],
              callerAddress);
    }
}

typedef BOOL (*IGMCBoolInternalFn)(id, BOOL, unsigned long long);
static IGMCBoolInternalFn orig_IGMobileConfigBooleanValueForInternalUse = NULL;
static BOOL hook_IGMobileConfigBooleanValueForInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    [SCIExpMobileConfigDebug noteContext:ctx source:@"IGMobileConfigBooleanValueForInternalUse"];
    void *callerAddress = __builtin_return_address(0);
    BOOL original = orig_IGMobileConfigBooleanValueForInternalUse ?
        orig_IGMobileConfigBooleanValueForInternalUse(ctx, defaultValue, specifier) : defaultValue;
    BOOL returned = applyInternalUseOverride(specifier, original);
    recordInternalUseSpecifier(ctx, @"IGMobileConfigBooleanValueForInternalUse", specifier, defaultValue, original, returned, callerAddress);
    return returned;
}

static IGMCBoolInternalFn orig_IGMobileConfigSessionlessBooleanValueForInternalUse = NULL;
static BOOL hook_IGMobileConfigSessionlessBooleanValueForInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    [SCIExpMobileConfigDebug noteContext:ctx source:@"IGMobileConfigSessionlessBooleanValueForInternalUse"];
    void *callerAddress = __builtin_return_address(0);
    BOOL original = orig_IGMobileConfigSessionlessBooleanValueForInternalUse ?
        orig_IGMobileConfigSessionlessBooleanValueForInternalUse(ctx, defaultValue, specifier) : defaultValue;
    BOOL returned = applyInternalUseOverride(specifier, original);
    recordInternalUseSpecifier(ctx, @"IGMobileConfigSessionlessBooleanValueForInternalUse", specifier, defaultValue, original, returned, callerAddress);
    return returned;
}

static BOOL (*orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18)(void) = NULL;
static BOOL hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18(void) {
    if ([SCIUtils getBoolPref:@"igt_internal_apps_gate"] || rgEmployeeMasterEnabled()) return YES;
    return orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 ?
        orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18() : NO;
}

typedef void (*IGAppStateStartLoggingFn)(id, SEL, id, id, BOOL, id, id, BOOL);
static IGAppStateStartLoggingFn orig_IGApplicationStateLogger_startLogging = NULL;
static void hook_IGApplicationStateLogger_startLogging(id self, SEL _cmd, id application, id launchOptions, BOOL isEmployee, id userPk, id logNotificationWithLaunch, BOOL wrapNotifSettingLoggingIntoBackgroundTask) {
    BOOL returnedEmployee = rgEmployeeMasterEnabled() ? YES : isEmployee;
    if (rgInternalObserverEnabled() || returnedEmployee != isEmployee) {
        NSLog(@"[RyukGram][DogfoodGate] IGApplicationStateLogger startLogging isEmployee=%d -> %d userPk=%@", isEmployee, returnedEmployee, userPk);
    }
    if (orig_IGApplicationStateLogger_startLogging) {
        orig_IGApplicationStateLogger_startLogging(self, _cmd, application, launchOptions, returnedEmployee, userPk, logNotificationWithLaunch, wrapNotifSettingLoggingIntoBackgroundTask);
    }
}

static BOOL (*orig_NSUserDefaults_boolForKey)(id, SEL, NSString *) = NULL;
static BOOL hook_NSUserDefaults_boolForKey(id self, SEL _cmd, NSString *key) {
    NSString *k = [key isKindOfClass:[NSString class]] ? key : @"";
    BOOL isEmployeeKey = [k containsString:@"FBUserIsEmployeeKey"] || [k containsString:@"DeviceReportFBUserIsEmployeeKey"] || [k isEqualToString:@"isEmployee"];
    if (rgEmployeeMasterEnabled() && isEmployeeKey) {
        if (rgInternalObserverEnabled()) NSLog(@"[RyukGram][DogfoodGate] NSUserDefaults boolForKey:%@ -> YES", k);
        return YES;
    }
    return orig_NSUserDefaults_boolForKey ? orig_NSUserDefaults_boolForKey(self, _cmd, key) : NO;
}

static void rgInstallObjCGateHooks(void) {
    if (!rgEmployeeMasterEnabled() && !rgInternalObserverEnabled()) return;

    Class loggerClass = NSClassFromString(@"IGApplicationStateLogger");
    Class loggerMeta = loggerClass ? object_getClass(loggerClass) : Nil;
    SEL startSel = NSSelectorFromString(@"startLoggingForApplication:launchOptions:isEmployee:userPk:logNotificationWithLaunch:wrapNotifSettingLoggingIntoBackgroundTask:");
    if (loggerMeta && class_getInstanceMethod(loggerMeta, startSel)) {
        MSHookMessageEx(loggerMeta, startSel, (IMP)hook_IGApplicationStateLogger_startLogging, (IMP *)&orig_IGApplicationStateLogger_startLogging);
        NSLog(@"[RyukGram][DogfoodGate] hooked IGApplicationStateLogger startLoggingForApplication:...isEmployee...");
    } else if (rgInternalObserverEnabled()) {
        NSLog(@"[RyukGram][DogfoodGate] IGApplicationStateLogger startLogging selector not found");
    }

    if (rgEmployeeMasterEnabled()) {
        Class defaultsClass = [NSUserDefaults class];
        SEL boolSel = @selector(boolForKey:);
        if (defaultsClass && class_getInstanceMethod(defaultsClass, boolSel)) {
            MSHookMessageEx(defaultsClass, boolSel, (IMP)hook_NSUserDefaults_boolForKey, (IMP *)&orig_NSUserDefaults_boolForKey);
            NSLog(@"[RyukGram][DogfoodGate] hooked NSUserDefaults employee bool keys");
        }
    }
}

static NSString *rgKnownMapLogLine(void) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSDictionary<NSNumber *, NSString *> *m = rgKnownInternalUseSpecifierMap();
    for (NSNumber *n in [[m allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"%@=0x%016llx", m[n], n.unsignedLongLongValue]];
    }
    return [parts componentsJoinedByString:@", "];
}

%ctor {
    if (!rgShouldInstallInternalModeHooks()) return;

    struct rebinding rebindings[] = {
        {"IGMobileConfigBooleanValueForInternalUse", (void *)hook_IGMobileConfigBooleanValueForInternalUse, (void **)&orig_IGMobileConfigBooleanValueForInternalUse},
        {"IGMobileConfigSessionlessBooleanValueForInternalUse", (void *)hook_IGMobileConfigSessionlessBooleanValueForInternalUse, (void **)&orig_IGMobileConfigSessionlessBooleanValueForInternalUse},
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18, (void **)&orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    rgInstallObjCGateHooks();
    NSLog(@"[RyukGram][MC] internal-mode fishhook rc=%d bool=%p sessionless=%p internalApps=%p appStateLogger=%p userDefaultsBool=%p manualOverrides=%lu knownGates={%@}",
          rc,
          orig_IGMobileConfigBooleanValueForInternalUse,
          orig_IGMobileConfigSessionlessBooleanValueForInternalUse,
          orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18,
          orig_IGApplicationStateLogger_startLogging,
          orig_NSUserDefaults_boolForKey,
          (unsigned long)[SCIExpFlags allOverriddenInternalUseSpecifiers].count,
          rgKnownMapLogLine());
}
