#import "../../Utils.h"
#import "../../Settings/SCIResolverScanner.h"
#import "SCIExpFlags.h"
#import "SCIExpMobileConfigDebug.h"
#import "SCIExpMobileConfigMapping.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#include "../../../modules/fishhook/fishhook.h"

static const unsigned long long kIGMCEmployeeSpecifierA = 0x0081030f00000a95ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeSpecifierB = 0x0081030f00010a96ULL; // ig_is_employee
static const unsigned long long kIGMCEmployeeOrTestUserSpecifier = 0x008100b200000161ULL; // ig_is_employee_or_test_user

static BOOL rgEmployeeMasterEnabled(void) { return [SCIUtils getBoolPref:@"igt_employee_master"] || [SCIUtils getBoolPref:@"igt_employee"] || [SCIUtils getBoolPref:@"igt_employee_devoptions_gate"]; }
static BOOL rgEmployeeMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_mc"]; }
static BOOL rgEmployeeOrTestUserMCEnabled(void) { return rgEmployeeMasterEnabled() || [SCIUtils getBoolPref:@"igt_employee_or_test_user_mc"]; }
static BOOL rgInternalObserverEnabled(void) { return [SCIUtils getBoolPref:@"igt_internaluse_observer"] || [SCIUtils getBoolPref:@"sci_exp_flags_enabled"]; }
static BOOL rgQuickSnapEnabled(void) { return [SCIUtils getBoolPref:@"igt_quicksnap"]; }

static BOOL rgHasManualInternalUseOverrides(void) { return [SCIExpFlags allOverriddenInternalUseSpecifiers].count > 0; }

static BOOL rgShouldInstallInternalModeHooks(void) {
    return rgEmployeeMasterEnabled() ||
           rgEmployeeMCEnabled() ||
           rgEmployeeOrTestUserMCEnabled() ||
           rgQuickSnapEnabled() ||
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

static void rgAddQuickSnapSpecifierSymbol(NSMutableDictionary<NSNumber *, NSString *> *nameMap,
                                          NSMutableDictionary<NSNumber *, NSNumber *> *returnMap,
                                          const char *symbol,
                                          NSString *label,
                                          NSUInteger count,
                                          BOOL forcedReturn) {
    unsigned long long *values = (unsigned long long *)rgDLSym(symbol);
    if (!values) return;

    NSUInteger valid = 0;
    for (NSUInteger i = 0; i < count; i++) {
        unsigned long long spec = values[i];
        if (!rgLooksLikeMCSpecifier(spec)) continue;

        NSString *name = count > 1 ? [NSString stringWithFormat:@"%@[%lu]", label, (unsigned long)i] : label;
        nameMap[@(spec)] = name;
        returnMap[@(spec)] = @(forcedReturn);
        valid++;
    }

    if ([SCIUtils getBoolPref:@"igt_internaluse_observer"]) {
        NSLog(@"[RyukGram][QuickSnapMC] loaded %lu/%lu specifiers from %s forced=%d",
              (unsigned long)valid, (unsigned long)count, symbol, forcedReturn);
    }
}

static void rgAddKnownQuickSnapGroups(NSMutableDictionary<NSNumber *, NSString *> *nameMap,
                                      NSMutableDictionary<NSNumber *, NSNumber *> *returnMap) {
    // Static scan of FBSharedFramework(23) / Instagram 426:
    // QuickSnap/Instants are MobileConfig specifier groups, not one direct C function gate like FriendMap.
    // Most groups should be YES; the negative hide gate must be NO.
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_instants_hide", @"ig_instants_hide", 1, NO);

    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap", @"ig_ios_quick_snap", 34, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_nux_v2", @"ig_ios_quick_snap_nux_v2", 7, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_quick_snap_show_peek_in_view_did_appear", @"ig_quick_snap_show_peek_in_view_did_appear", 1, YES);

    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_app_joiner_number", @"ig_ios_quick_snap_app_joiner_number", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_audience", @"ig_ios_quick_snap_audience", 5, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_burst_photos", @"ig_ios_quick_snap_burst_photos", 4, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_camera_capture_animation", @"ig_ios_quick_snap_camera_capture_animation", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_classification", @"ig_ios_quick_snap_classification", 3, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_extend_expiration", @"ig_ios_quick_snap_extend_expiration", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_gallery_send", @"ig_ios_quick_snap_gallery_send", 2, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_moods", @"ig_ios_quick_snap_moods", 6, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_new_audience_picker", @"ig_ios_quick_snap_new_audience_picker", 3, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quick_snap_new_zoom_animation", @"ig_ios_quick_snap_new_zoom_animation", 1, YES);

    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_archive", @"ig_ios_quicksnap_archive", 6, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_audience_picker", @"ig_ios_quicksnap_audience_picker", 3, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_cache_instants", @"ig_ios_quicksnap_cache_instants", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_consumption_button", @"ig_ios_quicksnap_consumption_button", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_consumption_stack_improvements", @"ig_ios_quicksnap_consumption_stack_improvements", 19, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_consumption_v2", @"ig_ios_quicksnap_consumption_v2", 9, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_craft_improvements", @"ig_ios_quicksnap_craft_improvements", 2, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_creation_preview", @"ig_ios_quicksnap_creation_preview", 2, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_dual_camera", @"ig_ios_quicksnap_dual_camera", 4, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_gtm", @"ig_ios_quicksnap_gtm", 5, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_navigation_v3", @"ig_ios_quicksnap_navigation_v3", 9, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_perf_improvements", @"ig_ios_quicksnap_perf_improvements", 7, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_profile", @"ig_ios_quicksnap_profile", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_recap_improvements", @"ig_ios_quicksnap_recap_improvements", 6, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_story_deletion", @"ig_ios_quicksnap_story_deletion", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_undo_toast", @"ig_ios_quicksnap_undo_toast", 2, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_valentines_activation", @"ig_ios_quicksnap_valentines_activation", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_quicksnap_wearables", @"ig_ios_quicksnap_wearables", 2, YES);

    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_instants_infinite_archive", @"ig_ios_instants_infinite_archive", 2, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_instants_tagging", @"ig_ios_instants_tagging", 1, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_instants_to_stories_recap", @"ig_ios_instants_to_stories_recap", 4, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_instants_upleveling_reactions", @"ig_ios_instants_upleveling_reactions", 3, YES);
    rgAddQuickSnapSpecifierSymbol(nameMap, returnMap, "ig_ios_instants_widget", @"ig_ios_instants_widget", 2, YES);
}

static NSDictionary<NSNumber *, NSNumber *> *rgQuickSnapSpecifierReturnMap(void) {
    static NSDictionary<NSNumber *, NSNumber *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSNumber *, NSString *> *names = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSNumber *, NSNumber *> *returns = [NSMutableDictionary dictionary];
        rgAddKnownQuickSnapGroups(names, returns);
        map = [returns copy];
    });
    return map;
}

static NSDictionary<NSNumber *, NSString *> *rgKnownInternalUseSpecifierMap(void) {
    static NSDictionary<NSNumber *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSNumber *, NSString *> *m = [NSMutableDictionary dictionary];

        rgAddMCSpecifierSymbol(m, "ig_is_employee", @"ig_is_employee", 2);
        rgAddMCSpecifierSymbol(m, "ig_is_employee_or_test_user", @"ig_is_employee_or_test_user", 1);
        rgAddMCSpecifierSymbol(m, "xav_switcher_ig_ios_test_user_check_fdid", @"xav_switcher_ig_ios_test_user_check_fdid", 1);
        rgAddMCSpecifierSymbol(m, "ig_dogfooding_first_client", @"ig_dogfooding_first_client", 1);
        rgAddMCSpecifierSymbol(m, "ig_ios_home_coming_is_dogfooding_option_enabled", @"ig_ios_home_coming_is_dogfooding_option_enabled", 1);

        NSMutableDictionary<NSNumber *, NSNumber *> *quickSnapReturns = [NSMutableDictionary dictionary];
        rgAddKnownQuickSnapGroups(m, quickSnapReturns);

        // Hard fallback for this current FBSharedFramework build, in case dlsym does not expose
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
           [n containsString:@"xav_switcher"];
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

static BOOL specifierMatchesQuickSnap(unsigned long long specifier) {
    return rgQuickSnapSpecifierReturnMap()[@(specifier)] != nil;
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

    if (rgQuickSnapEnabled()) {
        NSNumber *forced = rgQuickSnapSpecifierReturnMap()[@(specifier)];
        if (forced) return forced.boolValue;
    }

    return original;
}

static void recordInternalUseSpecifier(id ctx, NSString *funcName, unsigned long long specifier, BOOL defaultValue, BOOL originalValue, BOOL returnedValue, void *callerAddress) {
    BOOL forced = (returnedValue != originalValue);
    BOOL quickSnapMatch = specifierMatchesQuickSnap(specifier);
    BOOL shouldRecord = rgInternalObserverEnabled() || forced || specifierMatchesEmployee(specifier) || quickSnapMatch || [SCIExpFlags internalUseOverrideForSpecifier:specifier] != SCIExpFlagOverrideOff;
    if (!shouldRecord) return;

    NSString *name = rgResolveSpecifierName(ctx, specifier);
    [SCIExpFlags recordInternalUseSpecifier:specifier
                               functionName:funcName
                              specifierName:name
                               defaultValue:defaultValue
                                resultValue:returnedValue
                                forcedValue:forced
                              callerAddress:callerAddress];

    if ([SCIUtils getBoolPref:@"igt_internaluse_observer"]) {
        NSLog(@"[RyukGram][MC][%@] spec=0x%016llx (%@) default=%d original=%d returned=%d forced=%d employeeMatch=%d quickSnapMatch=%d manual=%ld caller=%p",
              funcName,
              specifier,
              name,
              defaultValue,
              originalValue,
              returnedValue,
              forced,
              specifierMatchesEmployee(specifier),
              quickSnapMatch,
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
    recordInternalUseSpecifier(ctx, @"IG InternalUse", specifier, defaultValue, original, returned, callerAddress);
    return returned;
}

static IGMCBoolInternalFn orig_IGMobileConfigSessionlessBooleanValueForInternalUse = NULL;
static BOOL hook_IGMobileConfigSessionlessBooleanValueForInternalUse(id ctx, BOOL defaultValue, unsigned long long specifier) {
    [SCIExpMobileConfigDebug noteContext:ctx source:@"IG Sessionless InternalUse"];
    void *callerAddress = __builtin_return_address(0);
    BOOL original = orig_IGMobileConfigSessionlessBooleanValueForInternalUse ?
        orig_IGMobileConfigSessionlessBooleanValueForInternalUse(ctx, defaultValue, specifier) : defaultValue;
    BOOL returned = applyInternalUseOverride(specifier, original);
    recordInternalUseSpecifier(ctx, @"IG Sessionless InternalUse", specifier, defaultValue, original, returned, callerAddress);
    return returned;
}

static BOOL (*orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18)(void) = NULL;
static BOOL hook_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18(void) {
    if ([SCIUtils getBoolPref:@"igt_internal_apps_spoof"] || [SCIUtils getBoolPref:@"igt_internal_apps_gate"] || rgEmployeeMasterEnabled()) return YES;
    return orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18 ?
        orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18() : NO;
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

    if (!orig_IGMobileConfigBooleanValueForInternalUse) {
        void *addr = [SCIResolverScanner findMobileConfigFunctionAddress];
        if (addr) {
            orig_IGMobileConfigBooleanValueForInternalUse = (IGMCBoolInternalFn)addr;
            NSLog(@"[RyukGram][MC] IGMobileConfigBooleanValueForInternalUse resolved via pattern scanner: %p", addr);
        } else {
            NSLog(@"[RyukGram][MC] IGMobileConfigBooleanValueForInternalUse not found via fishhook or pattern scanner.");
        }
    }
    NSLog(@"[RyukGram][MC] safe internal-mode fishhook rc=%d bool=%p sessionless=%p internalApps=%p manualOverrides=%lu quickSnap=%d quickSnapSpecs=%lu knownGates={%@}",
          rc,
          orig_IGMobileConfigBooleanValueForInternalUse,
          orig_IGMobileConfigSessionlessBooleanValueForInternalUse,
          orig_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18,
          (unsigned long)[SCIExpFlags allOverriddenInternalUseSpecifiers].count,
          rgQuickSnapEnabled(),
          (unsigned long)rgQuickSnapSpecifierReturnMap().count,
          rgKnownMapLogLine());
}
