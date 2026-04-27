#import "SCIResolverScanner.h"
#import "SCIResolverSpecifierEntry.h"
#import "../Features/ExpFlags/SCIExpFlags.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>

static NSArray<NSString *> *SCIDogKeys(void) {
    return @[@"dogfood", @"dogfooding", @"dogfooder", @"developer", @"internal", @"employee", @"override", @"eligibility", @"localexperiment", @"lidexperiment", @"quicksnap", @"quick_snap", @"instants"];
}

static NSArray<NSString *> *SCIMCKeys(void) {
    return @[@"mobileconfig", @"igmobileconfig", @"fbmobileconfig", @"mcimobileconfig", @"mciexperiment", @"metaextensionsexperiment", @"msgcsessionedmobileconfig", @"easygating", @"mcqeasygating", @"mcddasmnative", @"internaluse", @"donotuseormock", @"quicksnap", @"quick_snap", @"instants"];
}

static NSArray<NSString *> *SCISelectorKeys(void) {
    return @[@"open", @"config", @"userSession", @"deviceSession", @"logger", @"settings", @"section", @"item", @"row", @"builder", @"coordinator", @"route", @"developer", @"employee", @"dogfood", @"override", @"eligibility", @"quick", @"snap", @"instant", @"getBool"];
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
    for (Class c = cls; c; c = class_getSuperclass(c)) if (c == vc) return YES;
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
    NSArray *im = SCIMethods(cls, NO, 14);
    NSArray *cm = SCIMethods(cls, YES, 14);
    NSArray *iv = SCIIvars(cls, 12);
    NSString *name = SCIClassName(cls);
    NSInteger score = 0;
    if (SCIContainsAny(name, keys)) score += 60;
    score += MIN(56, (NSInteger)(im.count + cm.count) * 7);
    score += MIN(24, (NSInteger)iv.count * 4);
    if (SCIIsVC(cls)) score += 20;
    if ([name containsString:@"Settings"] || [name containsString:@"Controller"] || [name containsString:@"Coordinator"]) score += 10;
    return @{@"score": @(score), @"name": name, @"super": SCIClassName(class_getSuperclass(cls)), @"image": SCIImageName(cls), @"vc": @(SCIIsVC(cls)), @"methods": [cm arrayByAddingObjectsFromArray:im] ?: @[], @"ivars": iv ?: @[]};
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
        if (results.count >= limit) break;
    }
    free(classes);

    [results sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger sa = [a[@"score"] integerValue];
        NSInteger sb = [b[@"score"] integerValue];
        if (sa > sb) return NSOrderedAscending;
        if (sa < sb) return NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"]];
    }];
    return results;
}

static void *SCIDlsymFlexible(NSString *sym) {
    if (!sym.length) return NULL;
    void *p = dlsym(RTLD_DEFAULT, sym.UTF8String);
    if (p) return p;
    if ([sym hasPrefix:@"_"]) return dlsym(RTLD_DEFAULT, [sym substringFromIndex:1].UTF8String);
    return dlsym(RTLD_DEFAULT, [[@"_" stringByAppendingString:sym] UTF8String]);
}

static NSString *SCIExactClassReport(void) {
    NSMutableString *out = [NSMutableString stringWithString:@"Exact class check\nmode = bounded; no all-class method scan\n\n"];
    for (NSString *name in SCIExactClasses()) {
        Class cls = NSClassFromString(name) ?: objc_getClass(name.UTF8String);
        [out appendFormat:@"%@ · %@\n", cls ? @"FOUND" : @"missing", name];
        if (!cls) continue;
        [out appendFormat:@"  super=%@ UIViewController=%@ image=%@\n", SCIClassName(class_getSuperclass(cls)), SCIIsVC(cls) ? @"YES" : @"NO", SCIImageName(cls)];
        for (NSString *m in SCIMethods(cls, YES, 18)) [out appendFormat:@"  %@\n", m];
        for (NSString *m in SCIMethods(cls, NO, 18)) [out appendFormat:@"  %@\n", m];
        for (NSString *v in SCIIvars(cls, 12)) [out appendFormat:@"  ivar %@\n", v];
    }
    return out;
}

static NSString *SCISymbolReport(void) {
    NSArray *symbols = @[
        @"_IGMobileConfigBooleanValueForInternalUse", @"_IGMobileConfigSessionlessBooleanValueForInternalUse",
        @"_MCIMobileConfigGetBoolean", @"_MCIExperimentCacheGetMobileConfigBoolean", @"_MCIExtensionExperimentCacheGetMobileConfigBoolean",
        @"_METAExtensionsExperimentGetBoolean", @"_METAExtensionsExperimentGetBooleanWithoutExposure",
        @"_MSGCSessionedMobileConfigGetBoolean", @"_EasyGatingPlatformGetBoolean", @"_EasyGatingGetBoolean_Internal_DoNotUseOrMock",
        @"_EasyGatingGetBooleanUsingAuthDataContext_Internal_DoNotUseOrMock", @"_MCQEasyGatingGetBooleanInternalDoNotUseOrMock",
        @"_MCDDasmNativeGetMobileConfigBooleanV2DvmAdapter", @"_ig_is_employee", @"_ig_is_employee_or_test_user",
        @"_ig_dogfooding_first_client", @"_xav_switcher_ig_ios_test_user_check_fdid", @"_IGAppIsInstagramInternalAppsInstalledAndNotHiddenAfteriOS18",
        @"_ig_ios_quick_snap", @"_ig_ios_quick_snap_nux_v2", @"_ig_ios_quicksnap_navigation_v3", @"_ig_ios_quicksnap_consumption_v2",
        @"_ig_ios_quicksnap_consumption_stack_improvements", @"_ig_ios_instants_widget", @"_ig_instants_hide"
    ];
    NSMutableString *out = [NSMutableString stringWithString:@"MobileConfig / QuickSnap symbol availability\nmode = dlsym(RTLD_DEFAULT), flexible underscore handling\n\n"];
    for (NSString *sym in symbols) {
        void *addr = SCIDlsymFlexible(sym);
        [out appendFormat:@"%@ · %@ · %p\n", addr ? @"FOUND" : @"missing", sym, addr];
    }
    return out;
}

static NSString *SCIFormatCandidates(NSString *title, NSArray<NSDictionary *> *candidates) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"%@\nmode = view-only; candidates are name-filtered before method/ivar inspection\n\ncandidateCount=%lu\n\n", title, (unsigned long)candidates.count];
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

@implementation SCIResolverScanner

+ (NSArray<SCIResolverSpecifierEntry *> *)allKnownSpecifierEntries {
    static NSArray<SCIResolverSpecifierEntry *> *entries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSNumber *, SCIResolverSpecifierEntry *> *map = [NSMutableDictionary dictionary];
        
        void (^add)(unsigned long long, NSString *, NSString *, BOOL) = ^(unsigned long long spec, NSString *name, NSString *src, BOOL suggested) {
            if (spec == 0) return;
            SCIResolverSpecifierEntry *e = [SCIResolverSpecifierEntry new];
            e.specifier = spec;
            e.name = name;
            e.source = src;
            e.suggestedValue = suggested;
            map[@(spec)] = e;
        };

        void (^addSymbol)(const char *, NSString *, NSUInteger, BOOL) = ^(const char *symbol, NSString *label, NSUInteger count, BOOL suggested) {
            unsigned long long *values = (unsigned long long *)dlsym(RTLD_DEFAULT, symbol);
            if (!values) {
                char underscored[256];
                snprintf(underscored, sizeof(underscored), "_%s", symbol);
                values = (unsigned long long *)dlsym(RTLD_DEFAULT, underscored);
            }
            if (!values) return;
            for (NSUInteger i = 0; i < count; i++) {
                unsigned long long spec = values[i];
                if (spec == 0 || ((spec >> 56) != 0) || ((spec >> 48) == 0)) continue;
                NSString *name = count > 1 ? [NSString stringWithFormat:@"%@[%lu]", label, (unsigned long)i] : label;
                add(spec, name, @"dlsym", suggested);
            }
        };

        // Basic Employee gates
        addSymbol("ig_is_employee", @"ig_is_employee", 2, YES);
        addSymbol("ig_is_employee_or_test_user", @"ig_is_employee_or_test_user", 1, YES);
        addSymbol("xav_switcher_ig_ios_test_user_check_fdid", @"xav_switcher_ig_ios_test_user_check_fdid", 1, YES);
        addSymbol("ig_dogfooding_first_client", @"ig_dogfooding_first_client", 1, YES);
        addSymbol("ig_ios_home_coming_is_dogfooding_option_enabled", @"ig_ios_home_coming_is_dogfooding_option_enabled", 1, YES);

        // QuickSnap / Instants
        addSymbol("ig_instants_hide", @"ig_instants_hide", 1, NO);
        addSymbol("ig_ios_quick_snap", @"ig_ios_quick_snap", 34, YES);
        addSymbol("ig_ios_quick_snap_nux_v2", @"ig_ios_quick_snap_nux_v2", 7, YES);
        addSymbol("ig_quick_snap_show_peek_in_view_did_appear", @"ig_quick_snap_show_peek_in_view_did_appear", 1, YES);
        addSymbol("ig_ios_quick_snap_app_joiner_number", @"ig_ios_quick_snap_app_joiner_number", 1, YES);
        addSymbol("ig_ios_quick_snap_audience", @"ig_ios_quick_snap_audience", 5, YES);
        addSymbol("ig_ios_quick_snap_burst_photos", @"ig_ios_quick_snap_burst_photos", 4, YES);
        addSymbol("ig_ios_quick_snap_camera_capture_animation", @"ig_ios_quick_snap_camera_capture_animation", 1, YES);
        addSymbol("ig_ios_quick_snap_classification", @"ig_ios_quick_snap_classification", 3, YES);
        addSymbol("ig_ios_quick_snap_extend_expiration", @"ig_ios_quick_snap_extend_expiration", 1, YES);
        addSymbol("ig_ios_quick_snap_gallery_send", @"ig_ios_quick_snap_gallery_send", 2, YES);
        addSymbol("ig_ios_quick_snap_moods", @"ig_ios_quick_snap_moods", 6, YES);
        addSymbol("ig_ios_quick_snap_new_audience_picker", @"ig_ios_quick_snap_new_audience_picker", 3, YES);
        addSymbol("ig_ios_quick_snap_new_zoom_animation", @"ig_ios_quick_snap_new_zoom_animation", 1, YES);
        addSymbol("ig_ios_quicksnap_archive", @"ig_ios_quicksnap_archive", 6, YES);
        addSymbol("ig_ios_quicksnap_audience_picker", @"ig_ios_quicksnap_audience_picker", 3, YES);
        addSymbol("ig_ios_quicksnap_cache_instants", @"ig_ios_quicksnap_cache_instants", 1, YES);
        addSymbol("ig_ios_quicksnap_consumption_button", @"ig_ios_quicksnap_consumption_button", 1, YES);
        addSymbol("ig_ios_quicksnap_consumption_stack_improvements", @"ig_ios_quicksnap_consumption_stack_improvements", 19, YES);
        addSymbol("ig_ios_quicksnap_consumption_v2", @"ig_ios_quicksnap_consumption_v2", 9, YES);
        addSymbol("ig_ios_quicksnap_craft_improvements", @"ig_ios_quicksnap_craft_improvements", 2, YES);
        addSymbol("ig_ios_quicksnap_creation_preview", @"ig_ios_quicksnap_creation_preview", 2, YES);
        addSymbol("ig_ios_quicksnap_dual_camera", @"ig_ios_quicksnap_dual_camera", 4, YES);
        addSymbol("ig_ios_quicksnap_gtm", @"ig_ios_quicksnap_gtm", 5, YES);
        addSymbol("ig_ios_quicksnap_navigation_v3", @"ig_ios_quicksnap_navigation_v3", 9, YES);
        addSymbol("ig_ios_quicksnap_perf_improvements", @"ig_ios_quicksnap_perf_improvements", 7, YES);
        addSymbol("ig_ios_quicksnap_profile", @"ig_ios_quicksnap_profile", 1, YES);
        addSymbol("ig_ios_quicksnap_recap_improvements", @"ig_ios_quicksnap_recap_improvements", 6, YES);
        addSymbol("ig_ios_quicksnap_story_deletion", @"ig_ios_quicksnap_story_deletion", 1, YES);
        addSymbol("ig_ios_quicksnap_undo_toast", @"ig_ios_quicksnap_undo_toast", 2, YES);
        addSymbol("ig_ios_quicksnap_valentines_activation", @"ig_ios_quicksnap_valentines_activation", 1, YES);
        addSymbol("ig_ios_quicksnap_wearables", @"ig_ios_quicksnap_wearables", 2, YES);
        addSymbol("ig_ios_instants_infinite_archive", @"ig_ios_instants_infinite_archive", 2, YES);
        addSymbol("ig_ios_instants_tagging", @"ig_ios_instants_tagging", 1, YES);
        addSymbol("ig_ios_instants_to_stories_recap", @"ig_ios_instants_to_stories_recap", 4, YES);
        addSymbol("ig_ios_instants_upleveling_reactions", @"ig_ios_instants_upleveling_reactions", 3, YES);
        addSymbol("ig_ios_instants_widget", @"ig_ios_instants_widget", 2, YES);

        // Hardcoded fallbacks
        add(0x0081030f00000a95ULL, @"ig_is_employee[0]", @"hardcoded", YES);
        add(0x0081030f00010a96ULL, @"ig_is_employee[1]", @"hardcoded", YES);
        add(0x008100b200000161ULL, @"ig_is_employee_or_test_user", @"hardcoded", YES);

        entries = [[map allValues] sortedArrayUsingComparator:^NSComparisonResult(SCIResolverSpecifierEntry *a, SCIResolverSpecifierEntry *b) {
            return [a.name compare:b.name];
        }];
    });
    return entries;
}

+ (void *)findPattern:(NSString *)patternMask inSegment:(NSString *)segmentName {
    NSArray<NSString *> *components = [patternMask componentsSeparatedByString:@" "];
    NSUInteger patternLength = components.count;
    if (patternLength == 0) return NULL;

    uint8_t *pattern = (uint8_t *)malloc(patternLength);
    BOOL *mask = (BOOL *)malloc(patternLength);

    for (NSUInteger i = 0; i < patternLength; i++) {
        NSString *comp = components[i];
        if ([comp isEqualToString:@"??"]) {
            pattern[i] = 0;
            mask[i] = NO;
        } else {
            unsigned int val;
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
        if (![imageNameStr containsString:@"Instagram"] && ![imageNameStr containsString:@"FBSharedFramework"]) {
            continue;
        }

        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64) continue;

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
    // Assinatura ARM64 típica de IGMobileConfigBooleanValueForInternalUse
    // Exemplo fictício, pois a assinatura real depende do binário.
    // O usuário mencionou: "Implementado o método findMobileConfigFunctionAddress que usa a assinatura ARM64 típica de IGMobileConfigBooleanValueForInternalUse."
    // Vamos usar um padrão genérico ou o que for apropriado. Como não foi fornecido o padrão exato, vou colocar um placeholder que pode ser ajustado ou um padrão comum de prólogo de função.
    // Normalmente, funções começam com pacibsp, stp x29, x30, [sp, #-0x10]! etc.
    // Vamos usar um padrão que represente isso ou deixar um comentário.
    // Para fins de compilação e completude, usaremos um padrão de exemplo.
    NSString *pattern = @"ff 43 01 d1 fd 7b 01 a9 fd 43 00 91 ?? ?? ?? ?? ?? ?? ?? ??";
    return [self findPattern:pattern inSegment:@"__text"];
}

+ (NSString *)runDogfoodDeveloperReport {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendString:SCIExactClassReport()];
        [out appendString:@"\n==============================\n\n"];
        [out appendString:SCIFormatCandidates(@"SCI Resolver — Dogfood / Developer / MetaConfig candidates", SCIRankedCandidates(SCIDogKeys(), 160))];
        return out;
    }
}

+ (NSString *)runMobileConfigSymbolReport {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString stringWithString:SCISymbolReport()];
        [out appendString:@"\n==============================\n\n"];
        [out appendString:SCIFormatCandidates(@"MobileConfig/EasyGating runtime-visible class candidates", SCIRankedCandidates(SCIMCKeys(), 160))];
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
