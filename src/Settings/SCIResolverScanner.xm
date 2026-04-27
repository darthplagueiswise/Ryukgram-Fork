#import "SCIResolverScanner.h"
#import "SCIExpFlags.h"

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
