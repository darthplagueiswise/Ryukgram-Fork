#import "../../Utils.h"
#import "SCIExpFlags.h"
#import "SCIExpMobileConfigDebug.h"
#import "SCIExpMobileConfigMapping.h"
#import <objc/message.h>
#include "../../../modules/fishhook/fishhook.h"

static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL; // ig_is_employee_or_test_user

static BOOL rgEmployeeMasterEnabled(void) { return [SCIUtils getBoolPref:@"igt_employee"]; }
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

static BOOL specifierMatchesEmployee(unsigned long long specifier) {
    if (specifier == kIGMCEmployeeSpecifierA || specifier == kIGMCEmployeeSpecifierB) return rgEmployeeMCEnabled();
    if (specifier == kIGMCEmployeeOrTestUserSpecifier) return rgEmployeeOrTestUserMCEnabled();
    return NO;
}

static NSString *specifierName(unsigned long long specifier) {
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

static id rgCallNoArgObject(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return nil;
    @try {
        id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        return send(target, sel);
    } @catch (__unused NSException *e) {
        return nil;
    }
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

static NSString *rgResolveWithStartupConfigRuntime(unsigned long long specifier) {
    Class cls = NSClassFromString(@"FBMobileConfigStartupConfigs");
    if (!cls) return nil;

    id startup = rgCallNoArgObject(cls, @"getInstance");
    if (!startup) {
        @try { startup = [[cls alloc] init]; } @catch (__unused NSException *e) { startup = nil; }
    }
    if (!startup) return nil;

    return rgCallStringForSpecifier(startup, @"convertSpecifierToParamName:", specifier);
}

static NSString *rgResolveWithStartupConfigs(unsigned long long specifier) {
    NSString *runtimeName = rgResolveWithStartupConfigRuntime(specifier);
    if (runtimeName.length) return runtimeName;

    NSString *mapped = [SCIExpMobileConfigMapping resolvedNameForSpecifier:specifier];
    if (mapped.length) return mapped;
    return nil;
}

static NSString *rgResolveSpecifierName(id ctx, unsigned long long specifier) {
    NSString *hardcoded = specifierName(specifier);
    if (![hardcoded isEqualToString:@"unknown"]) return hardcoded;

    NSString *mapped = rgResolveWithStartupConfigs(specifier);
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
        NSString *translatedName = rgResolveWithStartupConfigs(translated);
        if (translatedName.length) return [NSString stringWithFormat:@"%@ (translated 0x%016llx)", translatedName, translated];
        NSString *stableTranslated = rgCallStringForSpecifier(ctx, @"getStableIdFromParamSpecifier:", translated);
        if (stableTranslated.length) return [NSString stringWithFormat:@"%@ (translated 0x%016llx)", stableTranslated, translated];
    }

    id launcherSet = rgCallNoArgObject(ctx, @"sessionlessMobileConfig") ?: rgCallNoArgObject(ctx, @"asIGDeviceLauncherSetForMigrationPurposesOnly");
    if (launcherSet) {
        NSString *launcherName = rgCallStringForSpecifier(launcherSet, @"convertSpecifierToParamName:", specifier);
        if (launcherName.length) return launcherName;
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
    if ([SCIUtils getBoolPref:@"igt_internal_apps_gate"]) return YES;
    return orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 ?
        orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18() : NO;
}

%ctor {
    if (!rgShouldInstallInternalModeHooks()) return;

    struct rebinding rebindings[] = {
        {"IGMobileConfigBooleanValueForInternalUse", (void *)hook_IGMobileConfigBooleanValueForInternalUse, (void **)&orig_IGMobileConfigBooleanValueForInternalUse},
        {"IGMobileConfigSessionlessBooleanValueForInternalUse", (void *)hook_IGMobileConfigSessionlessBooleanValueForInternalUse, (void **)&orig_IGMobileConfigSessionlessBooleanValueForInternalUse},
        {"IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18", (void *)hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18, (void **)&orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18},
    };
    int rc = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));
    NSLog(@"[RyukGram][MC] internal-mode fishhook rc=%d bool=%p sessionless=%p internalApps=%p manualOverrides=%lu",
          rc,
          orig_IGMobileConfigBooleanValueForInternalUse,
          orig_IGMobileConfigSessionlessBooleanValueForInternalUse,
          orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18,
          (unsigned long)[SCIExpFlags allOverriddenInternalUseSpecifiers].count);
}
